#!/bin/bash
# -------------------------------------------------------------------------------
# oam-pod_cleanup.sh
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

function showUsage() {
    echo "Usage for IMS  : oam-helmDelete.sh --chart isml1|isml2|all"
    echo "Usage for DMOB : oam-helmDelete.sh --chart dmobl1|dmobl2|all"
    echo ""
    echo "Arguments:"
    echo "  --chart Specifies the pod group to be cleaned up:"
    echo "            For IMS:  isml1, isml2, all"
    echo ""
    echo "Expected environment variable:"
    echo "  K8S_CONTEXT : Specifies the Kubernetes context in the format <project>-<env>"
    echo "                 where <project> is 'ims' or 'dmob' and <env> is 'dev', 'int', or 'prod'."
    echo ""

}


#
# Variables
#

MODE=none
CHARTS=none


#
# Main
#

if [[ -z "$K8S_CONTEXT" ]]; then
    echo "K8S_CONTEXT environment variable is not set. Please set it before running the script."
    exit 1
fi

PROJECT=$(echo "$K8S_CONTEXT" | cut -d'-' -f1)
ENV=$(echo "$K8S_CONTEXT" | cut -d'-' -f2)

case "$PROJECT" in
    "ims")
        case "$ENV" in
            "dev" | "int" | "prod")
                ;;
            *)
                echo "Invalid environment specified: $K8S_CONTEXT"
                showUsage
                exit 1
                ;;
        esac

        while [[ $# -gt 0 ]]
        do
            case "$1" in
                "--chart")
                    case "$2" in
                        "imsl1" | "imsl2")
                            CHARTS="$2"
                            ;;
                        "all" )
                            CHARTS="imsl1,imsl2"
                            ;;
                        *)
                            echo "Error: Invalid chart specified: $2"
                            showUsage
                            exit 1
                            ;;
                    esac
                    shift
                    ;;
                *)
                    echo "Error: Invalid argument: $1"
                    showUsage
                    exit 1
                    ;;
            esac
            shift
        done
        ;;
    "dmob" )
        case "$ENV" in
            "dev" | "int" | "prod")
                ;;
            *)
                echo "Invalid environment specified: $K8S_CONTEXT"
                showUsage
                exit 1
                ;;
        esac

        while [[ $# -gt 0 ]]
        do
            case "$1" in
                "--chart")
                    case "$2" in
                        "dmobl1" | "dmobl2")
                            CHARTS="$2"
                            ;;
                        "all" )
                            CHARTS="dmobl1,dmobl2"
                            ;;
                        *)
                            echo "Error: Invalid chart specified: $2"
                            showUsage
                            exit 1
                            ;;
                    esac
                    shift
                    ;;
                *)
                    echo "Error: Invalid argument: $1"
                    showUsage
                    exit 1
                    ;;
            esac
            shift
        done
        ;;
    * )
        DEFAULT_ENV="none"
        ;;
esac

if [ "$CHARTS" = "none" ]; then
    echo "Error: Chart not specified"
    showUsage
    exit 1
fi

if [ "$ENV" = "prod" ]; then
    echo "Warning: You are about to perform helm delete operations in the PROD environment!!!!"
    echo ""
    while true; do
        read -p "Are you sure you want to proceed? (y/n): " RESPONSE
        case $RESPONSE in
            y) break;;
            n) echo "Helm deletion cancelled."; exit;;
            * ) echo "Please answer 'y' or 'n'";;
        esac
    done
    echo ""
fi

echo "List of charts to be deleted in context '$K8S_CONTEXT': $(echo $CHARTS | tr ',' ' ')"

while true; do
    read -p "Are you sure you want to proceed with deletion of these charts? (y/n): " RESPONSE
    case $RESPONSE in
        y) break;;
        n) echo "Helm deletion cancelled."; exit;;
        * ) echo "Please answer 'y' or 'n'";;
    esac
done

for CHART in $(echo $CHARTS | tr ',' ' '); do
    echo "Deleting chart: $CHART in context: $K8S_CONTEXT"
    helm --kube-context $K8S_CONTEXT delete $CHART
done

echo "Helm deletion completed."
