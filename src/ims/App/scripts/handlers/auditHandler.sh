#!/bin/bash
# -------------------------------------------------------------------------------
# auditHandler.sh
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

#
# Globals
#

LOG_FILEPATH=/var/opt/SIU/log/auditHandler-$(date +%Y%m%d).log
export LOG_FILEPATH

LOG_LEVEL=5
export LOG_LEVEL


#
# Functions
#

function log() {
    local MESSAGE=$1
    local TXT="$(date +'%Y-%m-%d %H:%M:%S %Z') auditHandler $MESSAGE [pid:$$ ppid:${PPID}]"

    echo "$TXT" >> $LOG_FILEPATH
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


#
# Main
#

export TZ="Europe/Paris"

if [ ! -f /var/opt/SIU/env/auditHandler.env ]; then
    logError "Environment file '/var/opt/SIU/env/auditHandler.env' not found"
    exit 1
fi

logInfo "Initiating auditHandler.sh"

source /var/opt/SIU/env/auditHandler.env

if [ ! -d /var/opt/SIU/audit ]; then
    logError "Directory '/var/opt/SIU/audit' does not exist"
    exit 0
fi

let i=0
while true; do
    if [ -f /var/opt/SIU/ctrl/flag.softstop.dispatchers_terminated ]; then
        logWarning "Soft stop process detected. Terminating audit handler after processing pending files."

        rm -f /var/opt/SIU/ctrl/flag.softstop.dispatchers_terminated
        touch /var/opt/SIU/ctrl/flag.softstop.audit_terminating
    fi

    for AUDIT_FILEPATH in $(ls -rt /var/opt/SIU/audit/*.audit 2>/dev/null | head -n 100); do
        cat $AUDIT_FILEPATH >> /var/opt/SIU/audit/auditHandler.sql
        rm -f $AUDIT_FILEPATH ${AUDIT_FILEPATH}
    done

    if [ -s /var/opt/SIU/audit/auditHandler.sql ]; then
        logDebug "Processing audit statements in file '/var/opt/SIU/audit/auditHandler.sql'"

        let NUM_STATEMENTS=$(wc -l < /var/opt/SIU/audit/auditHandler.sql)

        2>&1 >> $LOG_FILEPATH /usr/bin/psql -h $DBSIU_SERVER -p $DBSIU_PORT -U $DBSIU_USER -d $DBSIU_NAME -f /var/opt/SIU/audit/auditHandler.sql

        if [ $? -ne 0 ]; then
            logError "Failed to execute audit statements in file /var/opt/SIU/audit/auditHandler.sql"
            mv /var/opt/SIU/audit/auditHandler.sql /var/opt/SIU/audit/auditHandler.sql.$(date +%Y%m%d%H%M%S).error
        else
            logInfo "Successfully executed audit statements in file /var/opt/SIU/audit/auditHandler.sql with $NUM_STATEMENTS statements"
            mv /var/opt/SIU/audit/auditHandler.sql /var/opt/SIU/audit/auditHandler.sql.$(date +%Y%m%d%H%M%S).done
        fi
    else
        logDebug "No pending audit statements to process"
    fi

    if [ -f /var/opt/SIU/ctrl/flag.softstop.audit_terminating ]; then
        rm -f /var/opt/SIU/ctrl/flag.softstop.audit_terminating
        break
    fi

    let i=$i+1
    if [ $i -ge 600 ]; then
        let i=0
    fi

    sleep 20
done

logInfo "Audit handler terminated."

