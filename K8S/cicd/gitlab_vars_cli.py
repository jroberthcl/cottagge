#!/usr/bin/python3

"""
CLI para gestionar variables CI/CD de GitLab por entorno y proyecto:
- Lista variables y genera .txt por entorno (paginación completa)
- (Opcional) Exporta también variables heredadas de grupo
- Crea/actualiza variables (interactivo)
- Sincroniza cambios desde un .txt
- Elimina variables por entorno|key
- Clona variables de un entorno origen a otro destino (opción 6)

Requisitos: Python 3.6+ y 'requests' instalado.
"""

import os
import sys
import argparse
import requests
from typing import List, Dict, Any
from pathlib import Path

DEF_OUT_DIR = "./gitlab_vars"
TIMEOUT = 20


# ---------- Utilidades ----------
def env_or_arg(name: str, val: str, required=True) -> str:
    v = val or os.getenv(name)
    if required and not v:
        print(f"ERROR: falta {name}. Pasa --{name.lower().replace('_','-')} o exporta {name}")
        sys.exit(2)
    return v


def parse_bool(s: str, default=False) -> bool:
    if s is None or s == "":
        return default
    return str(s).strip().lower() in ("1", "true", "t", "yes", "y", "si", "s")


def normalize_entry(fields: List[str]) -> Dict[str, Any]:
    # formato: <entorno>|<key>|<value>|<masked>|<protected>|<variable_type>|<description>
    while len(fields) < 7:
        fields.append("")
    env, key, value, masked, protected, vtype, desc = [f.strip() for f in fields]
    if not env or not key:
        raise ValueError("entorno y key son obligatorios")
    return {
        "environment_scope": env or "*",
        "key": key,
        "value": value,
        "masked": parse_bool(masked, False),
        "protected": parse_bool(protected, False),
        "variable_type": (vtype or "env_var").lower(),
        "description": desc or None,
        "raw": False,  # por defecto: expand variables
    }


def normalize_scope_input(s: str) -> str:
    """Admite 'GLOBAL' o '*' y devuelve '*' para el scope global."""
    if not s:
        return "*"
    s2 = s.strip()
    if s2.lower() in ("global", "*"):
        return "*"
    return s2


# ---------- API GitLab ----------
class GitLabAPI:
    """
    Implementa llamadas al REST API v4 de GitLab:
    - /projects/:id/variables        (listar, crear, actualizar, borrar)
    - /groups/:id/variables          (listar)
    """
    def __init__(self, host: str, token: str):
        self.host = host.rstrip("/")
        self.base = f"{self.host}/api/v4"
        self.hdr = {"PRIVATE-TOKEN": token}

    def _check(self, r: requests.Response):
        if not r.ok:
            raise RuntimeError(f"HTTP {r.status_code}: {r.text}")

    # ---- Helpers de paginación ----
    def _get_all_pages(self, url: str, params=None) -> List[Dict[str, Any]]:
        params = dict(params or {})
        per_page = params.get("per_page") or 100
        params["per_page"] = per_page
        out, page = [], 1
        while True:
            params["page"] = page
            r = requests.get(url, headers=self.hdr, params=params, timeout=TIMEOUT)
            self._check(r)
            data = r.json()
            if not isinstance(data, list):  # si el endpoint devolviera objeto
                return data
            if not data:
                break
            out.extend(data)
            page += 1
        return out

    # ---- Proyecto ----
    def list_project_vars(self, project_id: str) -> List[Dict[str, Any]]:
        url = f"{self.base}/projects/{requests.utils.quote(project_id, safe='')}/variables"
        return self._get_all_pages(url)

    def get_project_var(self, project_id: str, key: str, environment_scope: str = None):
        url = f"{self.base}/projects/{requests.utils.quote(project_id, safe='')}/variables/{key}"
        params = {}
        if environment_scope:
            params["filter[environment_scope]"] = environment_scope
        r = requests.get(url, headers=self.hdr, params=params, timeout=TIMEOUT)
        if r.status_code == 404:
            # Fallback: listar todas y filtrar por entorno
            for v in self.list_project_vars(project_id):
                if v.get("key") == key and (environment_scope is None or v.get("environment_scope") == environment_scope):
                    return v
            return None
        self._check(r)
        return r.json()

    def create_project_var(self, project_id: str, payload: Dict[str, Any]):
        url = f"{self.base}/projects/{requests.utils.quote(project_id, safe='')}/variables"
        r = requests.post(url, headers=self.hdr, data=payload, timeout=TIMEOUT)
        self._check(r)
        return r.json()

    def update_project_var(self, project_id: str, key: str, payload: Dict[str, Any]):
        env = payload.get("environment_scope")
        params = {}
        if env:
            params["filter[environment_scope]"] = env
        url = f"{self.base}/projects/{requests.utils.quote(project_id, safe='')}/variables/{key}"
        r = requests.put(url, headers=self.hdr, params=params, data=payload, timeout=TIMEOUT)
        self._check(r)
        return r.json()

    def delete_project_var(self, project_id: str, key: str, environment_scope: str = None):
        url = f"{self.base}/projects/{requests.utils.quote(project_id, safe='')}/variables/{key}"
        params = {}
        if environment_scope:
            params["filter[environment_scope]"] = environment_scope
        r = requests.delete(url, headers=self.hdr, params=params, timeout=TIMEOUT)
        self._check(r)

    # ---- Grupo (opcional, variables heredadas) ----
    def list_group_vars(self, group_id: str) -> List[Dict[str, Any]]:
        url = f"{self.base}/groups/{requests.utils.quote(group_id, safe='')}/variables"
        return self._get_all_pages(url)


# ---------- Exportación a TXT ----------
def write_txt(vars_list: List[Dict[str, Any]], out_dir: Path, project_id: str, prefix: str = ""):
    """
    Genera un fichero por entorno:
      vars_<project>_<ENV>.txt
      - si env == '*' -> nombre 'GLOBAL'
      - contenido mantiene el entorno original (e.g. '*', 'prod/appli01', etc.)
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    for v in vars_list:
        env = v.get("environment_scope") or "*"
        grouped.setdefault(env, []).append(v)

    for env, items in grouped.items():
        env_for_name = "GLOBAL" if env == "*" else env
        fname = out_dir / f"vars_{project_id}_{prefix}{env_for_name.replace('/', '_')}.txt"
        with open(fname, "w", encoding="utf-8") as f:
            f.write("# formato: entorno|key|value|masked|protected|variable_type|description\n")
            for v in items:
                line = "|".join([
                    v.get("environment_scope") or "*",
                    v.get("key") or "",
                    str(v.get("value") or ""),
                    str(v.get("masked", False)).lower(),
                    str(v.get("protected", False)).lower(),
                    v.get("variable_type") or "env_var",
                    (v.get("description") or "") if v.get("description") is not None else ""
                ])
                f.write(line + "\n")
        print(f"➡️  Generado: {fname}")


def read_txt(txt_path: Path) -> List[Dict[str, Any]]:
    entries = []
    with open(txt_path, "r", encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            entries.append(normalize_entry(ln.split("|")))
    return entries


def sync_txt(api: GitLabAPI, project_id: str, txt_path: Path):
    entries = read_txt(txt_path)
    print(f"Aplicando {len(entries)} entradas desde {txt_path} ...")
    for e in entries:
        existing = api.get_project_var(project_id, e["key"], e["environment_scope"])
        if existing:
            print(f"  - UPDATE {e['environment_scope']}|{e['key']}")
            api.update_project_var(project_id, e["key"], e)
        else:
            print(f"  - CREATE {e['environment_scope']}|{e['key']}")
            api.create_project_var(project_id, e)
    print("✅ Sincronización completada.")


# ---------- Clonado entre entornos ----------
def clone_env_vars(api: GitLabAPI, project_id: str, src_env: str, dst_env: str, overwrite: bool = False):
    src_env = normalize_scope_input(src_env)
    dst_env = normalize_scope_input(dst_env)

    if src_env == dst_env:
        print("⚠️  Origen y destino son iguales. No hay nada que clonar.")
        return

    all_vars = api.list_project_vars(project_id)
    src_vars = [v for v in all_vars if (v.get("environment_scope") or "*") == src_env]

    if not src_vars:
        print(f"⚠️  No se encontraron variables en el entorno origen '{src_env}'.")
        return

    created = updated = skipped = 0
    print(f"Clonando {len(src_vars)} variables: {src_env} → {dst_env} (overwrite={str(overwrite).lower()})")

    for v in src_vars:
        payload = {
            "environment_scope": dst_env,
            "key": v.get("key"),
            "value": v.get("value") or "",
            "masked": v.get("masked", False),
            "protected": v.get("protected", False),
            "variable_type": v.get("variable_type", "env_var"),
            "description": v.get("description"),
            "raw": False,
        }
        key = payload["key"]
        existing = api.get_project_var(project_id, key, dst_env)
        if existing:
            if overwrite:
                api.update_project_var(project_id, key, payload)
                updated += 1
                print(f"  - UPDATE {dst_env}|{key}")
            else:
                skipped += 1
                print(f"  - SKIP   {dst_env}|{key} (ya existe)")
        else:
            api.create_project_var(project_id, payload)
            created += 1
            print(f"  - CREATE {dst_env}|{key}")

    print(f"✅ Clonado terminado. Resumen: created={created}, updated={updated}, skipped={skipped}")


# ---------- Menú ----------
def menu(api: GitLabAPI, project_id: str, out_dir: Path, group_id: str = None):
    while True:
        print("\n=== GitLab CI/CD Variables CLI ===")
        print("1) Listar variables y generar .txt por entorno (proyecto)")
        print("2) Crear/actualizar variable (interactivo)")
        print("3) Sincronizar cambios desde un .txt a GitLab (proyecto)")
        print("4) Eliminar variable (proyecto)")
        print("5) Salir")
        if group_id:
            print("   (extra) Exportar variables de GRUPO → añade ficheros vars_<project>_GROUP_*.txt")
        print("6) Clonar variables entre entornos (proyecto)")

        choice = input("Elige opción [1-6]: ").strip()

        if choice == "1":
            vars_list = api.list_project_vars(project_id)
            write_txt(vars_list, out_dir, project_id)

            if group_id:
                try:
                    g_vars = api.list_group_vars(group_id)
                    write_txt(g_vars, out_dir, project_id, prefix="GROUP_")
                except Exception as e:
                    print(f"⚠️  No se pudieron exportar variables de GRUPO ({group_id}): {e}. "
                          f"Continúo solo con proyecto.")

        elif choice == "2":
            env = input("Entorno (environment_scope, p.ej. DEV/INT/VAL/PP o *): ").strip() or "*"
            key = input("Key (A-Z, a-z, 0-9, _): ").strip()
            value = input("Valor: ").strip()
            masked = parse_bool(input("Masked [true/false] (def false): ").strip(), False)
            protected = parse_bool(input("Protected [true/false] (def false): ").strip(), False)
            vtype = (input("Tipo [env_var/file] (def env_var): ").strip() or "env_var").lower()
            desc = input("Descripción (opcional): ").strip() or None
            if not key:
                print("ERROR: key es obligatoria")
                continue
            payload = {"environment_scope": env, "key": key, "value": value, "masked": masked,
                       "protected": protected, "variable_type": vtype, "description": desc, "raw": False}
            existing = api.get_project_var(project_id, key, env)
            if existing:
                print(f"Actualizando {env}|{key} ...")
                api.update_project_var(project_id, key, payload)
            else:
                print(f"Creando {env}|{key} ...")
                api.create_project_var(project_id, payload)
            print("✅ Hecho.")

        elif choice == "3":
            p = input(f"Ruta del .txt (def {DEF_OUT_DIR}/vars_{project_id}_<entorno>.txt): ").strip()
            if not p:
                print("Por favor, indica el path del archivo a sincronizar.")
                continue
            txt_path = Path(p)
            if not txt_path.exists():
                print(f"ERROR: no existe {txt_path}")
                continue
            ans = input(f"¿Aplicar cambios de {txt_path} a proyecto {project_id}? [s/N]: ").strip().lower()
            if ans.startswith("s"):
                sync_txt(api, project_id, txt_path)

        elif choice == "4":
            env = input("Entorno (environment_scope): ").strip() or "*"
            key = input("Key: ").strip()
            if not key:
                print("ERROR: key es obligatoria")
                continue
            ans = input(f"¿Eliminar variable {env}|{key}? [s/N]: ").strip().lower()
            if ans.startswith("s"):
                api.delete_project_var(project_id, key, env)
                print("🗑️  Eliminada.")

        elif choice == "5":
            print("Bye!")
            break

        elif choice == "6":
            src = input("Entorno ORIGEN (e.g. GLOBAL, DEV, pack/appli01/integ, prod/appli01, *): ").strip()
            dst = input("Entorno DESTINO (e.g. GLOBAL, INT, pack/appli01/staging, prod/appli01, *): ").strip()
            overwrite = parse_bool(input("Sobrescribir si ya existe en destino? [true/false] (def false): ").strip(), False)
            clone_env_vars(api, project_id, src, dst, overwrite)

        else:
            print("Opción inválida.")


# ---------- Entrypoint ----------
def main():
    parser = argparse.ArgumentParser(description="CLI gestión de variables CI/CD en GitLab.")
    parser.add_argument("--host", help="URL base de GitLab (e.g. --)")
    parser.add_argument("--token", help="Token de acceso (PAT/Project/Group)")
    parser.add_argument("--project-id", help="ID o path del proyecto (e.g. 12341 o group/project)")
    parser.add_argument("--group-id", help="(Opcional) ID o path del grupo para exportar variables heredadas")
    parser.add_argument("--out-dir", default=DEF_OUT_DIR, help=f"Directorio salida (def {DEF_OUT_DIR})")
    args = parser.parse_args()

    host = env_or_arg("GITLAB_HOST", args.host)
    token = env_or_arg("GITLAB_TOKEN", args.token)
    project_id = env_or_arg("GITLAB_PROJECT_ID", args.project_id)
    group_id = os.getenv("GITLAB_GROUP_ID") or args.group_id
    out_dir = Path(args.out_dir)

    api = GitLabAPI(host, token)
    menu(api, project_id, out_dir, group_id)


if __name__ == "__main__":
    main()

