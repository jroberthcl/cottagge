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


# Handle soft stop

while true; do
    if [ -f /var/opt/SIU/ctrl/flag.softstop ] || [ -f /var/opt/SIU/ctrl/flag.softstop.completed ]; then
        echo "Soft stop procedure ongoing or completed. Waiting for flag files removal to continue."
        sleep 10
    else
        break
    fi
done


# Launch handlers

/var/opt/bits/App/scripts/runtime/launchHandlers.sh

exit 0
