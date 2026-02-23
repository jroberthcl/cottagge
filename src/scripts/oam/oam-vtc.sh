#!/bin/bash
# -------------------------------------------------------------------------------
# oam-ims.sh
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

#
# Variables
#

CHARTS=none
CONTEXT=none
MODE=maintenance
OPERATION=none
POD_GROUP=none
POD_LIST=none
STATEFUL_SET_LIST=none


#
# Functions
#

function log() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S %Z")

    case "$1" in
        ERR)
            shift
            echo "$TIMESTAMP ($K8S_CONTEXT) [ERR] $@"
            ;;
        INF)
            shift
            echo "$TIMESTAMP ($K8S_CONTEXT) [INF] $@"
            ;;
        WRN)
            shift
            echo "$TIMESTAMP ($K8S_CONTEXT) [WRN] $@"
            ;;
        * )
            echo "$TIMESTAMP ($K8S_CONTEXT) $1"
            ;;
    esac
}

function logError() {
    log ERR "$@"
}

function logInfo() {
    log INF "$@"
}

function logWarning() {
    log WRN "$@"
}

function kubectlWrapper() {
    for i in {1..3}; do
        logInfo "Executing kubectl command (attempt $i): kubectl $@"
        kubectl "$@"
        if [[ $? -eq 0 ]]; then
            return 0
        else
            logWarning "kubectl command failed on attempt $i."
            sleep 5
        fi
    done
    logInfo "Executing kubectl command (attempt $i): kubectl $@"
    kubectl "$@"
    if [[ $? -ne 0 ]]; then
        logError "kubectl command executed with errors."
        exit 1
    fi
}

function kubectlWrapperSilent() {
    for i in {1..3}; do
        kubectl "$@"
        if [[ $? -eq 0 ]]; then
            return 0
        else
            sleep 5
        fi
    done
    kubectl "$@"
    if [[ $? -ne 0 ]]; then
        logError "kubectl command executed with errors."
        exit 1
    fi
}

function operationCleanup() {
    logInfo "operationCleanup(): BEGIN"

    for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
        logInfo "Executing OAM operation '$OPERATION_LABEL' on pod: '$POD_NAME'"

        kubectlWrapper --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT exec $POD_NAME -- /var/opt/bits/App/scripts/oam/cleanup/cleanup.sh --mode $MODE
        if [[ $? -ne 0 ]]; then
            logWarning "Operation executed with errors."
        else
            logInfo "Operation completed successfully."
        fi
    done

    logInfo "operationCleanup(): END"
}

function operationHelmDelete() {
    logInfo "operationHelmDelete(): BEGIN"

    for CHART in $(echo $CHARTS | tr ',' ' '); do
        logInfo "Executing OAM operation '$OPERATION_LABEL' on chart: '$CHART'"

        helm --kubeconfig=$HOME/K8S/kube.oidc.config --kube-context $K8S_CONTEXT delete $CHART
        if [[ $? -ne 0 ]]; then
            logWarning "Operation executed with errors."
        else
            logInfo "Operation completed successfully."
        fi
    done

    logInfo "operationHelmDelete(): END"
}

function operationRefreshCache() {
    logInfo "operationRefreshCache(): BEGIN"

    for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
        logInfo "Executing OAM operation '$OPERATION_LABEL' on pod: '$POD_NAME'"

        kubectlWrapper --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT exec $POD_NAME -- /opt/SIU/bin/refreshcache -ip 127.0.0.1 -port 17010
        if [[ $? -ne 0 ]]; then
            logWarning "Operation executed with errors."
        else
            logInfo "Operation completed successfully."
        fi
    done

    logInfo "operationRefreshCache(): END"
}

function operationSoftStop() {
    logInfo "operationSoftStop(): BEGIN"

    case "$MODE" in
        "reset")
            for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
                logInfo "Resetting soft stop flags for pod: '$POD_NAME'"

                kubectlWrapper --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT exec $POD_NAME -- /bin/bash -c "rm -f /var/opt/SIU/ctrl/flag.softstop /var/opt/SIU/ctrl/flag.softstop.completed /var/opt/SIU/ctrl/flag.softstop.acknowledged"
                if [[ $? -ne 0 ]]; then
                    logWarning "Operation executed with errors."
                else
                    logInfo "Operation completed successfully."
                fi
            done
            ;;
        "exec")
            for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
                logInfo "Creating soft stop flag for pod: '$POD_NAME'"
                kubectlWrapper --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT exec $POD_NAME -- /bin/bash -c "touch /var/opt/SIU/ctrl/flag.softstop"
            done
            ;;
    esac

    case "$MODE" in
        "exec" | "execNoFlag")
            NUM_PODS=$(echo $POD_LIST | tr ',' '\n' | wc -l | tr -d ' ')

            > /tmp/oam-podSoftStop-pods_ready_to_stop

            while true; do
                logInfo "Waiting for pods to be ready to stop"

                for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
                    if [[ $(grep -c "^$POD_NAME$" /tmp/oam-podSoftStop-pods_ready_to_stop) -eq 1 ]]; then
                        continue
                    fi

                    SOFTSTOP_STATUS=$(kubectlWrapper --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT exec $POD_NAME -- /var/opt/bits/App/scripts/runtime/softstop-getStatus.sh)

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
                            logError "Pod '$POD_NAME' returned unknown status: '$SOFTSTOP_STATUS'"
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
                    logInfo "Scaling down stateful set: '$STATEFUL_SET'"
                    kubectlWrapper --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT scale statefulset $STATEFUL_SET --replicas=0
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
                    logInfo "Deleting pod: '$POD_NAME'"
                    kubectlWrapper --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT delete pod $POD_NAME
                done
            fi
            ;;
    esac

    logInfo "operationSoftStop(): END"
}

function showUsage() {
    echo ""
    echo "Usage:"
    echo "  oam-ims.sh [--context ims-dev|ims-int|ims-prod] --operation <operation> [--mode <mode>] --pods <pod_list>|--group <pod_group>"
    echo ""
    echo "Note:"
    echo "  If '--context <context>' is not specified, the script will use the value of the K8S_CONTEXT environment variable that must be defined."
    echo ""
    echo "Supported values for argument <operation>:"
    echo "  cleanup      : Performs cleanup operations inside the specified pods"
    echo "  helmDelete   : Deletes the Helm release for IMS in the specified context"
    echo "  refreshCache : Refreshes the IMS configuration cache inside the specified pods"
    echo "  softStop     : Performs a soft stop of IMS services inside the specified pods"
    echo
    echo "Supported values for argument <mode>"
    echo "  With operation 'cleanup':"
    echo "    resetEIUM    : Performs eIUM cleanup (collector related files and DB tables)"
    echo "    resetFull    : Performs full cleanup (eIUM + all files in other configured directories)"
    echo "    maintenance  : Performs file cleanup based on configured retention policies (no eIUM cleanup). This is the default mode if not specified."
    echo "  With operation 'softStop':"
    echo "    exec         : Launch the soft stop operation, starting from the flag file creation"
    echo "    execNoFlag   : Launch the soft stop operation, without the flag file creation"
    echo "    reset        : Delete the soft stop flag files"
    echo ""
    echo "Supported values for argument <pod_list> (comma-separated list of pod names)"
    echo "  With operation 'cleanup', 'softStop':"
    echo "    ims-r7-x,ims-r10-x,mu-ims-proc-x"
    echo "  With operation 'refreshCache':"
    echo "    mu-ims-proc-x"
    echo "  Not supported with operation 'helmDelete'."
    echo
    echo "Supported values for argument <pod_group>"
    echo "  With operation: 'cleanup', 'softStop':"
    echo "    r7  : all IMS R7 pods"
    echo "    r10 : all IMS R10 pods"
    echo "    l1  : all IMS L1 pods"
    echo "    l2  : all IMS L2 pods"
    echo "    all : all IMS pods"
    echo "  With operation: 'helmDelete':"
    echo "    l1  : L1 chart"
    echo "    l2  : L2 chart"
    echo "    all : L1 and L2 charts"
    echo "  With operation: 'refreshCache':"
    echo "    l2  : L2 pods"
    echo ""
    echo "----"
}


#
# Main
#

while [[ $# -gt 0 ]]
do
    case "$1" in
        "--context")
            CONTEXT="$2"
            shift
            ;;
        "--group")
            POD_GROUP="$2"
            shift
            ;;
        "--mode")
            MODE="$2"
            shift
            ;;
        "--operation")
            OPERATION="$2"
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

case "$OPERATION" in
    "cleanup")
        case "$MODE" in
            "resetEIUM" | "resetFull" | "maintenance")
                ;;
            *)
                logError "Invalid MODE specified: '$MODE'"
                showUsage
                exit 1
                ;;
        esac
        OPERATION_LABEL="$OPERATION (mode: $MODE)"
        ;;
    "helmDelete")
        if [ "$POD_LIST" != "none" ]; then
            logError "For operation 'helmDelete', only pod group can be specified."
            showUsage
            exit 1
        fi

        case "$POD_GROUP" in
            "l1")
                CHARTS="ims"
                ;;
            "l2")
                CHARTS="mu-ims"
                ;;
            "all")
                CHARTS="ims,mu-ims"
                ;;
            "none" )
                logError "For operation 'helmDelete', pod group must be specified."
                showUsage
                exit 1
                ;;
            *)
                logError "Invalid group specified for operation 'helmDelete': $POD_GROUP"
                showUsage
                exit 1
                ;;
        esac
        OPERATION_LABEL="$OPERATION"
        ;;
    "refreshCache")
        case "$POD_GROUP" in
            "l2" )
                ;;
            "none" )
                ;;
            *)
                logError "For operation 'refreshCache', only group 'l2' is supported."
                showUsage
                exit 1
                ;;
        esac

        if [ "$POD_LIST" != "none" ]; then
            for POD_NAME in $(echo $POD_LIST | tr ',' ' '); do
                if [[ ! "$POD_NAME" =~ ^imsl2- ]]; then
                    logError "For operation 'refreshCache', only L2 pods are supported."
                    showUsage
                    exit 1
                fi
            done
        fi

        OPERATION_LABEL="$OPERATION"
        ;;
    "softStop")
        case "$MODE" in
            "exec" | "execNoFlag" | "reset")
                ;;
            *)
                logError "Invalid MODE specified: $MODE"
                showUsage
                exit 1
                ;;
        esac
        OPERATION_LABEL="$OPERATION"
        ;;
    "none")
        logError "No OPERATION specified."
        showUsage
        exit 1
        ;;
    *)
        logError "Invalid OPERATION specified: '$OPERATION'"
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
            "ims-dev" | "ims-int" | "ims-prod")
                K8S_CONTEXT="CONTEXT"
                ;;
            *)
                logError "Invalid context specified: '$CONTEXT'"
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
        FINAL_RESPONSE=n
        while true; do
            logWarning "You are about to perform an OAM operation in the PRODUCTION environment!!!!"
            while true; do
                read -p "Are you sure you want to proceed ? (y/n): " RESPONSE1
                case ${RESPONSE1} in
                    y)
                        read -p "Are you really sure ? (y/n): " RESPONSE2
                        case ${RESPONSE2} in
                            y)
                                FINAL_RESPONSE=y
                                ;;
                            n)
                                logInfo "OAM operation cancelled."
                                exit
                                ;;
                        esac
                        ;;
                    n)
                        logInfo "OAM operation cancelled."
                        exit
                        ;;
                    * )
                        logError "Please answer 'y' or 'n'"
                        ;;
                esac

                if [[ "$FINAL_RESPONSE" = "y" ]]; then
                    break
                fi
            done

            if [[ "$FINAL_RESPONSE" = "y" ]]; then
                break
            fi
        done
        ;;
    *)
        logError "Invalid environment specified: '$ENV'"
        showUsage
        exit 1
        ;;
esac

PROJECT=$(echo "$K8S_CONTEXT" | cut -d'-' -f1)

case "$PROJECT" in
    "ims")
        case "$POD_GROUP" in
            "r7")
                POD_LIST=$(kubectlWrapperSilent --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT get pods | grep "^ims-r7" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="ims-r7"
                ;;
            "imsr10")
                POD_LIST=$(kubectlWrapperSilent --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT get pods | grep "^ims-r10" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="ims-r10"
                ;;
            "l1")
                POD_LIST=$(kubectlWrapperSilent --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT get pods | grep -e "^ims-r7" -e "^ims-r10" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="ims-r7,ims-r10"
                ;;
            "l2")
                POD_LIST=$(kubectlWrapperSilent --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT get pods | grep "^mu-ims-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//' )
                STATEFUL_SET_LIST="mu-ims-"
                ;;
            "all")
                POD_LIST=$(kubectlWrapperSilent --kubeconfig=$HOME/K8S/kube.config --context $K8S_CONTEXT get pods | grep -e "^ims-r7" -e "^ims-r10" -e "^mu-ims-" | awk '{ print $1 }' | tr '\n' ',' | sed 's/,$//')
                STATEFUL_SET_LIST="ims-r7,ims-r10,mu-ims-"
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
        logError "Unsupported project specified: $PROJECT"
        showUsage
        exit 1
esac

POD_LIST=$(printf "%s" "$POD_LIST" | sed 's/^,*//; s/,*$//; s/,,*/,/g')

case "$OPERATION" in
    "helmDelete")
        OPERATION_SCOPE="charts: $CHARTS"
        ;;
    *)
        OPERATION_SCOPE="pods: $POD_LIST"
        ;;
esac

logWarning "OAM operation $OPERATION_LABEL is going to be executed for $OPERATION_SCOPE"

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

case "$OPERATION" in
    "cleanup")
        operationCleanup
        ;;
    "helmDelete")
        operationHelmDelete
        ;;
    "refreshCache")
        operationRefreshCache
        ;;
    "softStop")
        operationSoftStop
        ;;
    *)
        logError "Invalid OPERATION specified: $OPERATION"
        showUsage
        exit 1
        ;;
esac

logInfo "OAM operation $OPERATION_LABEL for $OPERATION_SCOPE completed successfully."
