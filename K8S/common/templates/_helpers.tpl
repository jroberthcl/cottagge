
{{/*
Expand the name of the chart.
*/}}
{{- define "container.name" -}}
{{- default .Chart.Name .Values.container.serverName | camelcase | lower | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "container.fullname" -}}
{{- $name := default .Chart.Name .Values.container.serverName | camelcase | lower | trunc 63 | trimSuffix "-" }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "container.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "eiumserver.labels" -}}
helm.sh/chart: {{ include "container.chart" . }}
{{ include "container.selectorLabels" . }}
{{ include "container.metricsLabels" . }}
{{ include "container.networkPolicyLabels" . }}
{{ include "container.istioLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "container.selectorLabels" -}}
app.kubernetes.io/name: {{ include "container.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Metrics  labels
*/}}
{{- define "container.metricsLabels" -}}
host: {{ .Values.container.hostName }}
server: {{ .Values.container.serverName }}
app.kubernetes.io/instance: {{ .Release.Name }}
release: {{ .Release.Name }}
{{- end }}


{{/*
NetworkPolicy  labels
*/}}
{{- define "container.networkPolicyLabels" -}}
{{- if .Values.container.udsfAccess }}
udsfAccess: {{ .Values.container.udsfAccess | quote }}
{{- end }}
{{- end }}

{{/*
Istio labels
*/}}
{{- define "container.istioLabels" -}}
sidecar.istio.io/inject: {{ .Values.global.istio | quote }} 
{{- end }}


{{/*
Create the name of the service account to use
*/}}
{{- define "global.serviceAccountName" -}}
  {{- if .Values.global.serviceAccount.create }}
{{- default (include "container.fullname" .) .Values.global.serviceAccount.name }}
  {{- else }}
{{- default "default" .Values.global.serviceAccount.name }}
  {{- end }}
{{- end }}


{{- define "container.replicas" -}}
  {{- if .Values.global.replicas }}
  {{- $servername:= .Values.container.serverName -}}
{{ printf "%d" (tpl (printf "{{ .Values.global.replicas.%s }}" $servername) . | int ) -}} 
  {{- else -}}
{{- printf "%s" 0 }}
  {{- end }}
{{- end }}


{{- define "container.env" -}}
{{- $envname:= . }}
{{- $servername:= .Values.container.serverName -}}
{{- $serverenv:= (tpl (printf "{{ .Values.container.env.%s }}" $envname) . ) -}}
{{- $globalenv:= (tpl (printf "{{ .Values.global.env.%s }}" $envname) . ) -}}
{{- if $serverenv }}
  {{- printf "%s" (tpl (printf "%s" $serverenv ) . ) -}}
{{- else if $globalenv }}
  {{- printf "%s" (tpl (printf "%s" $globalenv ) . ) -}}
{{- else }}
  {{- printf "%s #: %s" "undefined-variable" $envname -}}
{{- end }}
{{- end }}


{{- define "container.getImage" -}}
  {{- $debug:= default false .Values.global.helmDebug }}
  {{- $repository:= .Values.global.images.repository }}
  {{- $iname:= .imagename }}
  {{- range $repository }}
    {{- $root := . }}
    {{- $name :=( index $root 0 ) }}
    {{- $regi :=( index $root 1 ) }}
    {{- $imag :=( index $root 2 ) }}
    {{- $itag :=( index $root 3 ) }}
    {{- $pupo :=( index $root 4 ) }}
    {{- if eq $name $iname }}
image: {{ $regi }}/{{ $imag }}:{{ $itag }}
      {{- if $debug }}
#INFO: imagen found : image: {{ $regi }}/{{ $imag }}:{{ $itag }}@{{ $name }}@{{ $iname }}@debug={{ $debug }}
      {{- end }}
    {{- else }}
      {{- if $debug }}
#DEBUG: imagen not found : image: {{ $regi }}/{{ $imag }}:{{ $itag }}@{{ $name }}@{{ $iname }}@debug={{ $debug }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}


{{- define "container.getImagePullPolicy" -}}
  {{- $debug:= default false .Values.global.helmDebug }}
  {{- $repository:= .Values.global.images.repository }}
  {{- $iname:= .imagename }}
  {{- range $repository }}
    {{- $root := . }}
    {{- $name :=( index $root 0 ) }}
    {{- $regi :=( index $root 1 ) }}
    {{- $imag :=( index $root 2 ) }}
    {{- $itag :=( index $root 3 ) }}
    {{- $pupo :=( index $root 4 ) }}
    {{- if eq $name $iname }}
imagePullPolicy: {{ $pupo }}
        {{- if $debug }}
#INFO: image found : imagePullPolicy: {{ $pupo }} INFO: {{ $regi }}/{{ $imag }}:{{ $itag }}@{{ $name }}@{{ $iname }}@debug={{ $debug }}
        {{- end }}
    {{- else }}
        {{- if $debug }}
#DEBUG: image not found : imagePullPolicy: {{ $pupo }} INFO: {{ $regi }}/{{ $imag }}:{{ $itag }}@{{ $name }}@{{ $iname }}@debug={{ $debug }}
        {{- end }}
    {{- end }}
  {{- end }}
{{- end }}



{{- define "container.testServiceCommand" -}}
  {{- $debug:= default false .Values.global.helmDebug }}
  {{- $values:= .Values }}
  {{- $releasename:= .Release.Name }}
  {{- $releasenamespace:= .Release.Namespace }}
  {{- $servername:= $values.container.serverName | camelcase | lower }}
  {{- if $values.global.clusterdomain }}
    {{- $clusterdomain:= $values.global.clusterdomain }}
    {{- $servicename:= (printf "%s-%s.%s.svc.%s" $releasename $servername $releasenamespace $clusterdomain) }}

    {{- if $values.container.service }}
      {{- if $values.container.service.porttest }}
        {{- $pathtest:="" }}
        {{- $porttest:=$values.container.service.porttest }}
        {{- if $values.container.service.pathtest }}
          {{- $pathtest:=$values.container.service.pathtest }}
command: ['wget']
args: ['{{ $servicename }}:{{ $values.container.service.porttest }}/{{ $values.container.service.pathtest }}']
        {{- else }}
command: ['nc']
args: ['-z', '-w1', '{{ $servicename }}', '{{ $values.container.service.porttest }}']
        {{- end }}
      {{- else if .Values.container.service.ports }}
        {{- if .Values.container.service.ports.metrics }}
command: ['wget']
args: ['{{ $servicename }}:{{ $values.container.service.ports.metrics.port }}/metrics']
        {{- end }}
      {{- else }}
command: ['echo']
args:  ['@Todo: test for this type of non-eIUM components']
      {{- end }}
    {{- end }}

  {{- else }}

    {{- $clusterdomain:= "cluster.local" }}
    {{- $servicename:= (printf "%s-%s.%s.svc.%s" $releasename $servername $releasenamespace $clusterdomain) }}

    {{- if $values.container.service }}
      {{- if $values.container.service.porttest }}
        {{- $pathtest:="" }}
        {{- $porttest:=$values.container.service.porttest }}
        {{- if $values.container.service.pathtest }}
          {{- $pathtest:=$values.container.service.pathtest }}
command: ['wget']
args: ['{{ $servicename }}:{{ $values.container.service.porttest }}/{{ $values.container.service.pathtest }}']
        {{- else }}
command: ['nc']
args: ['-z', '-w1', '{{ $servicename }}', '{{ $values.container.service.porttest }}']
        {{- end }}
      {{- else if .Values.container.service.ports }}
        {{- if .Values.container.service.ports.metrics }}
command: ['wget']
args: ['{{ $servicename }}:{{ $values.container.service.ports.metrics.port }}/metrics']
        {{- end }}
      {{- else }}
command: ['echo']
args:  ['@Todo: test for this type of non-eIUM components']
      {{- end }}

    {{- end }}

  {{- end }}

{{- end }}



{{- define "container.waitServiceCommand" -}}
  {{- $debug:= default false $.Values.global.helmDebug }}
  {{- $values:= $.Values }}
  {{- $releasename:= .Release.Name }}
  {{- $releasenamespace:= .Release.Namespace }}
  {{- $servername := $.Values.container.serverName }}
  {{- $clusterdomain:= $.Values.global.clusterdomain }}
  {{- $initialdelay:= $.Values.global.initContainers.initialDelay }}
  {{- $delay:= $.Values.global.initContainers.delay }}

  {{- range $values.global.initContainers.dependServices }}
    {{- $root:= . }}
    {{- $service:=(index $root 0 ) }}
    {{- $servicedep:=( index $root 1 | camelcase | lower ) }}
    {{- $porttest:=( index $root 2 ) }}
    {{- $pathtest:=( index $root 3 ) }}
    
    {{- $servicedepfull:= (printf "%s-%s.%s.svc.%s" $releasename $servicedep $releasenamespace $clusterdomain) }}

    {{- $servicetestnc:= (printf "nc -z -w1 %s %s" $servicedepfull $porttest) }}
    {{- $servicetestwget:= (printf "wget %s %s/%s" $servicedepfull $porttest $pathtest) }}

    {{- $initialdelay:= 1 }}
    {{- $delay:= 1 }}

    {{- if $values.container.service }}
      {{- if eq $service $servername }}
        {{- if eq $pathtest "" }}
command: [ 'sh', '-c', "echo Waiting for {{ $servicedepfull }}; until nslookup {{ $servicedepfull }} >/dev/null; do printf 'o'; sleep {{ $delay }}; done; sleep {{ $initialdelay }}; until {{ $servicetestnc }}; do printf '.'; sleep {{ $delay }}; done; " ]
          {{- if $debug }}
#DEBUG01 command: porttest=$porttest servicetest=$servicetest 
          {{- end }}
        {{- else }}
command: [ 'sh', '-c', "echo Waiting for {{ $servicedepfull }}; until nslookup {{ $servicedepfull }} >/dev/null; do printf 'o'; sleep {{ $delay }}; done; sleep {{ $initialdelay }}; until {{ $servicetestwget }}; do printf '.'; sleep {{ $delay }}; done; " ]
          {{- if $debug }}
#DEBUG02 command: porttest=$porttest pathtest=$pathtest servicetest=$servicetest 
          {{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
    
  {{- end }}
{{- end }}

{{- define "container.ActionCommand" -}}
  {{- $debug:= default false $.Values.global.helmDebug }}
  {{- $values:= $.Values }}
  {{- $releasename:= .Release.Name }}
  {{- $releasenamespace:= .Release.Namespace }}
  {{- $servername := $.Values.container.serverName }}
  {{- $clusterdomain:= $.Values.global.clusterdomain }}
  {{- $initialdelay:= $.Values.global.initContainers.initialDelay }}
  {{- $delay:= $.Values.global.initContainers.delay }}

  {{- range $values.global.initContainers.actions }}
    {{- $root:= . }}
    {{- $numb:=(index $root 0 ) }}
    {{- $service:=(index $root 1 ) }}
    {{- $cmd:=( index $root 2 ) }}

    {{- if $values.container.service }}
      {{- if eq $service $servername }}
command: [ 'sh', '-c', "{{ $cmd }}" ]
          {{- if $debug }}
#DEBUG01 command: numb={{ $numb }},service={{ $service }},cmd={{ $cmd }}
          {{- end }}
      {{- end }}
    {{- end }}

  {{- end }}
{{- end }}



{{/*
Define values dynamically based on servicename. 
*/}}
{{- define "container.getValue" -}}
{{- $service:=  .service }}
{{- $value:=  .value }}
{{- $valuename:= (printf "{{ .Values.%s.%s }}" $service $value) }}
{{ tpl (printf "{{ .Values.%s.%s }}" $service $value) $ }}
{{- end }}


{{/*
Define values resolved as Tpl 
*/}}
{{- define "container.getTplValue" -}}
{{- $value:=  .value }}
{{- if contains "{{" $value }}
{{ tpl $value $  }}"
{{- else }}
{{ $value }}"
{{- end }}
{{- end }}


{{/*
Define values entities to create 
*/}}
{{- define "global.creation" -}}
  {{- $name:= .name | lower }}
  {{- $create:= .Values.global.create | lower }}
  {{- if or (eq $name $create) (eq $create "all") }}
true
  {{- else }}
false
  {{- end }}
{{- end }}


{{/*
Define values entities to create2
*/}}
{{- define "global.creation2" -}}
  {{- $name:= .name | lower }}
  {{- $create:= .Values.global.create | lower }}
  {{- if or (eq $name $create) (eq $create "all") }}
"true"
  {{- else }}
"false"
  {{- end }}
{{- end }}

