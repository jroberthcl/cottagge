#!/bin/bash
# -------------------------------------------------------------------------------
# oam-podSoftStop.sh
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
    echo "  IMS  : oam-podSoftStop.sh [--context ims-dev|ims-int|ims-prod]    --group imsr7|imsr10|l1|l2|all           --action exec|execNoFlag|reset"
    echo "         oam-podSoftStop.sh [--context ims-dev|ims-int|ims-prod]    --pods <pod_name_1>[,<pod_name_2>[,...]] --action exec|execNoFlag|reset"
    echo "  DMOB : oam-podSoftStop.sh [--context dmob-dev|dmob-int|dmob-prod] --group epdgnk|l1|l2|all                 --action exec|execNoFlag|reset"
    echo "         oam-podSoftStop.sh [--context dmob-dev|dmob-int|dmob-prod] --pods <pod_name_1>[,<pod_name_2>[,...]] --action exec|execNoFlag|reset"
    echo ""
    echo "Arguments:"
    echo "  --group  Specifies the pod group to be soft stopped"
    echo "  --pods   Specifies a comma-separated list of pod names to be soft stopped."
    echo ""
    echo "  --action Specifies the soft stop ACTION:"
    echo "             exec       - Executes the soft stop operation."
    echo "             execNoFlag - Executes the soft stop operation without creating the flag file."
    echo "             reset      - Deletes the soft stop flag files."
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
STATEFUL_SET_LIST=none


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
    "exec" | "execNoFlag" | "reset")
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
        logWarning "You are about to perform soft stop operation in the PRODUCTION environment!!!!"
        while true; do
            read -p "Are you sure you want to proceed? (y/n): " RESPONSE
            case $RESPONSE in
                y)
                    break
                    ;;
                n)
                    logInfo "Soft stop operation cancelled."
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
                STATEFUL_SET_LIST="imsl1-imsr7"
                ;;
            "imsr10")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^imsl1-imsr10" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="imsl1-imsr10"
                ;;
            "l1")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^imsl1-imsr7" -e "^imsl1-imsr10" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="imsl1-imsr7,imsl1-imsr10"
                ;;
            "l2")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^imsl2-imsmutua" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="imsl2-imsmutua"
                ;;
            "all")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^imsl1-imsr7" -e "^imsl1-imsr10" -e "^imsl2-imsmutua" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//')
                STATEFUL_SET_LIST="imsl1-imsr7,imsl1-imsr10,imsl2-imsmutua"
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
                STATEFUL_SET_LIST="dmobl1-epdgnk"
                ;;
            "l1")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^dmobl1-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="dmobl1-epdgnk"
                ;;
            "l2")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep "^dmobl2-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="dmobl2-datamutua"
                ;;
            "all")
                POD_LIST=$(kubectl --context $K8S_CONTEXT get pods | grep -e "^dmobl1-" -e "^dmobl2-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//')
                STATEFUL_SET_LIST="dmobl1-epdgnk,dmobl2-datamutua"
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

echo "List of pods to be soft stopped in context '$K8S_CONTEXT': $POD_LIST"

while true; do
    read -p "Are you sure you want to proceed with soft stop (action: $ACTION) for these pods? (y/n): " RESPONSE
    case $RESPONSE in
        y)
            break
            ;;
        n)
            logInfo "Soft stop operation cancelled."
            exit
            ;;
        * )
            logError "Please answer 'y' or 'n'"
            ;;
    esac
done

case "$ACTION" in
    "reset")
        for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
            logInfo "Resetting soft stop flags for pod: $POD_NAME in context: '$K8S_CONTEXT'"
            kubectl --context $K8S_CONTEXT exec $POD_NAME -- /bin/bash -c "rm -f /var/opt/SIU/ctrl/flag.softstop /var/opt/SIU/ctrl/flag.softstop.completed /var/opt/SIU/ctrl/flag.softstop.acknowledged"
        done
        logInfo "Pod soft stop operation with action '$ACTION' completed."
        exit 0
        ;;
    "exec")
        for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
            logInfo "Creating soft stop flag for pod: $POD_NAME in context: $K8S_CONTEXT"
            kubectl --context $K8S_CONTEXT exec $POD_NAME -- /bin/bash -c "touch /var/opt/SIU/ctrl/flag.softstop"
        done
        ;;
esac

NUM_PODS=$(echo $POD_LIST | tr ',' '\n' | wc -l | tr -d ' ')

> /tmp/oam-podSoftStop-pods_ready_to_stop

while true; do
    logInfo "Waiting for pods to be ready to stop"

    for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
        if [[ $(grep -c "^$POD_NAME$" /tmp/oam-podSoftStop-pods_ready_to_stop) -eq 1 ]]; then
            continue
        fi

        SOFTSTOP_STATUS=$(kubectl --context $K8S_CONTEXT exec $POD_NAME -- /var/opt/bits/App/scripts/runtime/softstop-getStatus.sh)

        case "$SOFTSTOP_STATUS" in
            SOFTSTOP_COMPLETED)
                logInfo "Pod '$POD_NAME' is ready to stop."
                echo "$POD_NAME" >> /tmp/oam-podSoftStop-pods_ready_to_stop
                ;;
            SOFTSTOP_ACKNOWLEDGED)
                logInfo "Pod '$POD_NAME' has acknowledged the soft stop request but is still in processing/transferring data."
                ;;
            SOFTSTOP_NOT_REQUESTED)
                logError "Pod '$POD_NAME' has not received a soft stop request."
                exit 1
                ;;
            SOFTSTOP_NOT_ACKNOWLEDGED)
                logInfo "Pod '$POD_NAME' has not yet acknowledged the soft stop request."
                ;;
            *)
                logError "Pod '$POD_NAME' returned unknown status: $SOFTSTOP_STATUS"
                exit 1
                ;;
        esac

        sleep 10
    done

    if [ $(wc -l < /tmp/oam-podSoftStop-pods_ready_to_stop) -eq $NUM_PODS ]; then
        break
    fi
done

if [ "$POD_GROUP" != "none" ]; then
    while true; do
        read -p "All pods are ready to stop. Do you want to proceed with scaling down the stateful sets? (y/n): " RESPONSE
        case $RESPONSE in
            y)
                break
                ;;
            n)
                logInfo "Scaling down for soft stop operation cancelled."
                exit
                ;;
            * )
                logError "Please answer 'y' or 'n'"
                ;;
        esac
    done

    for STATEFUL_SET in $(echo $STATEFUL_SET_LIST | tr ',' ' '); do
        logInfo "Scaling down stateful set: $STATEFUL_SET in context: $K8S_CONTEXT"
        kubectl --context $K8S_CONTEXT scale statefulset $STATEFUL_SET --replicas=0
    done
else
    while true; do
        read -p "All pods are ready to stop. Do you want to proceed with deleting the pods? (y/n): " RESPONSE
        case $RESPONSE in
            y)
                break
                ;;
            n)
                logInfo "Pod deletion for soft stop operation cancelled."
                exit
                ;;
            * )
                logError "Please answer 'y' or 'n'"
                ;;
        esac
    done

    for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
        logInfo "Deleting pod: $POD_NAME in context: $K8S_CONTEXT"
        kubectl --context $K8S_CONTEXT delete pod $POD_NAME
    done
fi

logInfo "Pod soft stop operation with action '$ACTION' completed."
