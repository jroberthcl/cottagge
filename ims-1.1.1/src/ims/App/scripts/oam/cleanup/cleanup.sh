#!/bin/bash
# -------------------------------------------------------------------------------
# cleanup.sh - Cleanup script for pods
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

#
# Variables
#

LOG_FILEPATH=/var/opt/SIU/log/cleanup-$(date +"%Y%m%d").log
export LOG_FILEPATH

export TZ="Europe/Paris"


#
# Functions
#

function getConfigParam() {
    local section="$1"
    local param="$2"

    awk -v section="[$section]" '
    {
        if ($0 == section) {
            found = 1;
            next;
        }

        if ($0 ~ /^\[.*\]/) {
            found = 0;
        }

        if (found && $0 ~ /^'"$param"'\s*=/ && $0 !~ /^\s*#/) {
            split($0, arr, "=");
            gsub(/^[ \t]+|[ \t]+$/, "", arr[2]);
            print arr[2];
            exit;
        }
    }' /var/opt/SIU/oam/cleanup/cfg/cleanup.config
}

function getConfigSection() {
    local section="$1"

    awk -v section="[$section]" '
    {
        if ($0 == section) {
            found = 1;
            next;
        }

        if ($0 ~ /^\[.*\]/) {
            found = 0;
        }

        if (found && NF && $0 !~ /^\s*#/) {
            print $0;
        }
    }' /var/opt/SIU/oam/cleanup/cfg/cleanup.config
}

function init() {
    if [ ! -d /var/opt/SIU/log ]; then
        mkdir -p /var/opt/SIU/log
    fi

    2>/dev/null rm -f /tmp/cleanup.*

    if [ ! -f /var/opt/SIU/oam/cleanup/cfg/cleanup.config ]; then
        mkdir -p /var/opt/SIU/oam/cleanup/cfg

        cp /var/opt/bits/App/scripts/oam/cleanup/cfg/cleanup.config.template /var/opt/SIU/oam/cleanup/cfg/cleanup.config
    fi
}

function log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S %Z") - cleanup.sh $1" | tee -a $LOG_FILEPATH
}

function logInfo() {
    log "[INF] $1"
}

function logError() {
    log "[ERR] $1"
}

function logWarning() {
    log "[WRN] $1"
}

function logDebug() {
    if [ $LOG_LEVEL -ge 5 ]; then
        log "[DBG] $1"
    fi
}

function showUsage() {
    echo "Usage: $0 --mode resetEIUM|resetFull|maintenance"
    echo ""
    echo "  --mode  Specifies the cleanup mode:"
    echo "            resetEIUM   - Resets eIUM data only."
    echo "            resetFull   - Resets eIUM data and cleans all specified directories."
    echo "            maintenance - Cleans files in specified directories based on retention policies."
    echo ""
}


#
# Main
#

init

MODE="none"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            if [[ -n "$2" && ( "$2" == "resetEIUM" || "$2" == "resetFull" || "$2" == "maintenance" ) ]]; then
                MODE=$2
                shift 2
            else
                logError "Invalid value for --mode. It must be either 'resetEIUM', 'resetFull' or 'maintenance'."
                showUsage
                exit 1
            fi
            ;;
        *)
            logError "Unknown argument: $1"
            showUsage
            exit 1
            ;;
    esac
done

if [ "$MODE" = "none" ]; then
    logError "Mode not specified"
    showUsage
    exit 1
fi

getConfigSection "GENERAL" > /tmp/cleanup.config.GENERAL
source /tmp/cleanup.config.GENERAL

getConfigSection "DIRECTORIES" > /tmp/cleanup.config.DIRECTORIES

case "$MODE" in
    resetEIUM | resetFull)
        logInfo "Starting cleanup in mode: $MODE"

        if [ $(ps -edaf | grep "/opt/SIU/bin/collector -JVMargs" | grep -v grep | wc -l) -gt 0 ]; then
            logInfo "Stopping eIUM collector process"
            kill -9 $(ps -edaf | grep "/opt/SIU/bin/collector -JVMargs" | grep -v grep | awk '{ print $2 }')
        else
            logWarning "eIUM collector process is NOT running"
        fi

        POD_NAME=$(hostname)
        cp /var/opt/bits/App/properties/*.jvm.out /etc/opt/SIU/SIUJava.ini && /opt/SIU/bin/siucleanup -all -n $POD_NAME

        if [ "$MODE" = "resetFull" ]; then
            cat /tmp/cleanup.config.DIRECTORIES | while read -r LINE; do
                DIR_PATH=$(echo "$LINE" | cut -d ':' -f1)

                logDebug "Deleting all files in directory: $DIR_PATH"
                if [ -d "$DIR_PATH" ]; then
                    rm -fr "${DIR_PATH:?}/"* 2>/dev/null
                    logInfo "Deleted all files in directory: $DIR_PATH"
                else
                    logWarning "Directory does not exist: $DIR_PATH"
                fi
            done
        fi
        ;;
    maintenance)
        cat /tmp/cleanup.config.DIRECTORIES | while read -r LINE; do
            DIR_PATH=$(echo "$LINE" | cut -d ':' -f 1)
            FILE_PATTERN=$(echo "$LINE" | cut -d ':' -f 2)
            RETENTION_MINUTES=$(echo "$LINE" | cut -d ':' -f 3)

            if [ "$RETENTION_MINUTES" = "FOREVER" ]; then
                logInfo "Skipping cleanup for directory: $DIR_PATH (RETENTION_MINUTES=FOREVER)"
                continue
            fi

            logDebug "Deleting files older than $RETENTION_MINUTES minutes in directory: $DIR_PATH, with pattern: $FILE_PATTERN"
            if [ -d "$DIR_PATH" ]; then
                find "$DIR_PATH" -type f -mmin +$RETENTION_MINUTES | grep -P "$FILE_PATTERN" | while read -r FILE; do
                    rm -f "$FILE" 2>/dev/null
                done
                logInfo "Cleaned files older than $RETENTION_MINUTES minutes in directory: $DIR_PATH, with pattern: $FILE_PATTERN"
            else
                logWarning "Directory does not exist: $DIR_PATH"
            fi
        done
        ;;
    *)
        logError "Invalid mode: $MODE"
        showUsage
        exit 1
        ;;
esac
