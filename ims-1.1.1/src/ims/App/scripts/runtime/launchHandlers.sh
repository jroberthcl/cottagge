#!/bin/bash
# -------------------------------------------------------------------------------
# init.sh
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

#
# Main
#

export TZ="Europe/Paris"


# Launch audit handler if needed

if [ $(2>/dev/null find /var/opt/SIU/audit -maxdepth 1 -type f | grep -e ".audit$" -e ".sql$" | wc -l) -gt 0 ]; then
    echo "[INF] Pending audit files found. Launching Audit Handler..."
    flock -n /var/opt/SIU/ctrl/auditHandler.lock -c "/var/opt/bits/App/scripts/handlers/auditHandler.sh &"
else
    echo "[INF] No pending audit files found. Audit Handler not launched."
fi

