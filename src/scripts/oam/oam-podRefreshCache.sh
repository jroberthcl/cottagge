#!/bin/bash
# -------------------------------------------------------------------------------
# oam-porRefreshCache.sh - Handle soft stopping for pods
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

#
# Functions
#

function showUsage() {
    echo "Usage: oam-podRefreshCache.sh --env dev|int|prod --all"
    echo "Usage: oam-podRefreshCache.sh --env dev|int|prod --pod <pod_name_1>[,<pod_name_2>[,...]]"
    echo ""
}


#
# Variables
#

POD_LIST=none
NAME_SPACE=none

#
# Main
#

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            POD_LIST=$(kubectl --namespace $NAME_SPACE get pods | grep "^imsl2-imsmutua" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//')
            shift
            ;;
        --env)
            case "$2" in
                dev | int | prod)
                    NAME_SPACE="collecte-voix-fixe-v2-$2"
                    ;;
                *)
                    echo "Invalid environment specified: $2"
                    showUsage
                    exit 1
                    ;;
            esac
            shift
            ;;
        --pod)
            POD_LIST="$2"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            showUsage
            exit 1
            ;;
    esac
    shift
done

if [ "$NAME_SPACE" == "none" ]; then
    echo "Error: Could not determine namespace."
    echo ""
    showUsage
    exit 1
fi

if [ "$POD_LIST" == "none" ]; then
    echo "Error: No pods specified for cache refresh."
    echo ""
    showUsage
    exit 1
fi

echo "List of pods to be refreshed: $(echo $POD_LIST | tr ',' ' ')"

for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
    if [[ ! "$POD_NAME" =~ ^imsl2-imsmutua ]]; then
        echo "Warning: Refresh cache not supported for pod '$POD_NAME'. Skipping."
        continue
    fi
    echo "Refreshing cache for pod: $POD_NAME in namespace: $NAME_SPACE"
    kubectl --namespace $NAME_SPACE exec $POD_NAME -- /opt/SIU/bin/refreshcache -ip 127.0.0.1 -port 17010
done

exit 0
