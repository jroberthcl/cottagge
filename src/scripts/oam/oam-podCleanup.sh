#!/bin/bash
# -------------------------------------------------------------------------------
# oam-podCleanup.sh
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

function log() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S %Z")
    echo "$TIMESTAMP $1"
}

function logError() {
    log "[ERR] $1"
}

function logInfo() {
    log "[INF] $1"
}

function logWarning() {
    log "[WRN] $1"
}

function showUsage() {
    echo "----"
    echo "Usage:"
    echo "  IMS  : oam-podCleanup.sh [--context ims-dev|ims-int|ims-prod]    --group imsr7|imsr10|l1|l2|all           --action resetEIUM|resetFull|maintenance"
    echo "         oam-podCleanup.sh [--context ims-dev|ims-int|ims-prod]    --pods <pod_name_1>[,<pod_name_2>[,...]] --action resetEIUM|resetFull|maintenance"
    echo "  DMOB : oam-podCleanup.sh [--context dmob-dev|dmob-int|dmob-prod] --group epdgnk|l1|l2|all                 --action resetEIUM|resetFull|maintenance"
    echo "         oam-podCleanup.sh [--context dmob-dev|dmob-int|dmob-prod] --pods <pod_name_1>[,<pod_name_2>[,...]] --action resetEIUM|resetFull|maintenance"
    echo ""
    echo "Arguments:"
    echo "  --group Specifies the pod group to be cleaned up"
    echo "  --pods  Specifies a comma-separated list of pod names to be cleaned up."
    echo ""
    echo "  --ACTION  Specifies the cleanup ACTION:"
    echo "            resetEIUM   - Resets eIUM data only."
    echo "            resetFull   - Resets eIUM data and cleans all specified directories."
    echo "            maintenance - Cleans files in specified directories based on retention policies."
    echo ""
    echo "Expected environment variable if argument '--context <context>' is not specified:"
    echo "  K8S_CONTEXT : Specifies the Kubernetes context in the format <project>-<env>"
    echo "                where <project> is 'ims' or 'dmob' and <env> is 'dev', 'int', or 'prod'."
    echo "----"
}


#
# Variables
#

CONTEXT=none
ACTION=none
POD_GROUP=none
POD_LIST=none


#
# Main
#

while [[ $# -gt 0 ]]
do
    case "$1" in
        "--action")
            ACTION="$2"
            shift
            ;;
        "--context")
            CONTEXT="$2"
            shift
            ;;
        "--group")
            POD_GROUP="$2"
            shift
            ;;
        "--pods")
            POD_LIST="$2"
            shift
            ;;
        *)
            logError "Unknown argument: $1"
            showUsage
            exit 1
            ;;
    esac
    shift
done

case "$ACTION" in
    "resetEIUM" | "resetFull" | "maintenance")
        ;;
    *)
        logError "Invalid ACTION specified: $ACTION"
        showUsage
        exit 1
        ;;
esac

if [[ "$POD_GROUP" != "none" ]] && [[ "$POD_LIST" != "none" ]]; then
    logError "Both pod group and pod list cannot be specified at the same time."
    showUsage
    exit 1
fi

if [[ "$CONTEXT" = "none" ]]; then
    if [[ -z "$K8S_CONTEXT" ]]; then
        logError "K8S_CONTEXT environment variable is not set while argument '--context <context>' is not specified."
        showUsage
        exit 1
    else
        case "$CONTEXT" in
            "ims-dev" | "ims-int" | "ims-prod" | "dmob-dev" | "dmob-int" | "dmob-prod")
                K8S_CONTEXT="CONTEXT"
                ;;
            *)
                logError "Invalid context specified: $CONTEXT"
                showUsage
                exit 1
                ;;
        esac
    fi
else
    if [[ ! -z "$K8S_CONTEXT" ]] && [[ "$CONTEXT" != "$K8S_CONTEXT" ]]; then
        logWarning "Both argument '--context <context>' and environment variable K8S_CONTEXT are set with different values."
        while true; do
            read -p "Are you sure you want to override the K8S_CONTEXT environment variable with the argument value? (y/n) " RESPONSE
            case $RESPONSE in
                y)
                    K8S_CONTEXT="$CONTEXT"
                    break
                    ;;
                n)
                    break
                    ;;
                *)
                    logError "Please answer 'y' or 'n'"
                    ;;
            esac
        done
    fi
fi

ENV=$(echo "$K8S_CONTEXT" | cut -d'-' -f2)

case "$ENV" in
    "dev" | "int")
        ;;
    "prod")
        logWarning "You are about to perform cleanup operations in the PROD environment!!!!"
        while true; do
            read -p "Are you sure you want to proceed? (y/n): " RESPONSE
            case $RESPONSE in
                y)
                    break
                    ;;
                n)
                    logInfo "Cleanup operation cancelled."
                    exit
                    ;;
                * )
                    logError "Please answer 'y' or 'n'"
                    ;;
            esac
        done
        ;;
    *)
        logError "Invalid environment specified: $ENV"
        showUsage
        exit 1
        ;;
esac

PROJECT=$(echo "$K8S_CONTEXT" | cut -d'-' -f1)

case "$PROJECT" in
    "ims")
        case "$POD_GROUP" in
            "imsr7")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^imsl1-imsr7" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                ;;
            "imsr10")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^imsl1-imsr10" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                ;;
            "l1")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^imsl1-imsr7" -e "^imsl1-imsr10" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                ;;
            "l2")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^imsl2-imsmutua" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                ;;
            "all")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^imsl1-imsr7" -e "^imsl1-imsr10" -e "^imsl2-imsmutua" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//')
                ;;
            "none")
                if [[ "$POD_LIST" = "none" ]]; then
                    logError "Either group or pods must be specified."
                    showUsage
                    exit 1
                fi
                ;;
            *)
                logError "Invalid group specified: $POD_GROUP"
                showUsage
                exit 1
                ;;
        esac
        ;;
    "dmob" )
        case "$POD_GROUP" in
            "epdgnk")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^dmobl1-epdgnk" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                ;;
            "l1")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^dmobl1-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                ;;
            "l2")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^dmobl2-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                ;;
            "all")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^dmobl1-" -e "^dmobl2-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//')
                ;;
            "none")
                if [[ "$POD_LIST" = "none" ]]; then
                    logError "Either group or pods must be specified."
                    showUsage
                    exit 1
                fi
                ;;
            *)
                logError "Invalid group specified: $POD_GROUP"
                showUsage
                exit 1
                ;;
        esac
        ;;
    * )
        logError "Invalid project specified: $PROJECT"
        showUsage
        exit 1
esac

POD_LIST=$(printf "%s" "$POD_LIST" | sed 's/^,*//; s/,*$//; s/,,*/,/g')

echo "List of pods to be cleaned up in context '$K8S_CONTEXT': $POD_LIST"

while true; do
    read -p "Are you sure you want to proceed with cleanup (action: $ACTION) for these pods? (y/n): " RESPONSE
    case $RESPONSE in
        y)
            break
            ;;
        n)
            logInfo "Cleanup operation cancelled."
            exit
            ;;
        * )
            logError "Please answer 'y' or 'n'"
            ;;
    esac
done

for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
    logInfo "Cleaning up pod: $POD_NAME in context: '$K8S_CONTEXT'"
    kubectl --context $K8S_CONTEXT exec $POD_NAME -- /var/opt/bits/App/scripts/oam/cleanup/cleanup.sh --ACTION $ACTION
done

logInfo "Pod cleanup completed."
