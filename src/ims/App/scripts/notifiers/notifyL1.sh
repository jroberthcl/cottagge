#!/bin/bash
# -------------------------------------------------------------------------------
# notifyL1.sh
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

#
# Globals
#

LOG_FILEPATH=none
export LOG_FILEPATH


#
# Functions
#

function log() {
    local MESSAGE=$1
    local OUTPUT_MODE=${2:-"CONSOLE_AND_FILE"}
    local AUX=$(printf "%-32.32s" "$LOG_LABEL")
    local TXT="$(date +'%Y-%m-%d %H:%M:%S %Z') $AUX $MESSAGE [pid:$$ ppid:${PPID}]"

    case "$OUTPUT_MODE" in
        "CONSOLE_ONLY")
            echo "$TXT"
            ;;
        "CONSOLE_AND_FILE")
            echo "$TXT"
            if  [ "$LOG_FILEPATH" != "none" ]; then
                echo "$TXT" >> $LOG_FILEPATH
            fi
            ;;
        "FILE_ONLY")
            if  [ "$LOG_FILEPATH" != "none" ]; then
                echo "$TXT" >> $LOG_FILEPATH
            fi
            ;;
    esac
}

function logInfo() {
    log "[INF] $1" "CONSOLE_AND_FILE"
}

function logError() {
    log "[ERR] $1" "CONSOLE_AND_FILE"
}

function logWarning() {
    log "[WRN] $1" "CONSOLE_AND_FILE"
}

function logDebug() {
    if [ $LOG_LEVEL -ge 5 ]; then
        log "[DBG] $1" "CONSOLE_AND_FILE"
    else
        log "[DBG] $1" "FILE_ONLY"
    fi
}

function showUsage() {
    echo "Usage:"
    echo "    notifyL1.sh --label <label>        --dispatchMode DELETE"
    echo "    notifyL1.sh --label <label>        --dispatchMode POST_PROCESSING --sourceLabel <source_label>"
    echo "    notifyL1.sh --label <label>        --dispatchMode LOCAL"
    echo "    notifyL1.sh --label <label>        --dispatchMode S3"
    echo ""
    echo "Usage: (for IMS)"
    echo "    notifyL1.sh --label Default        --dispatchMode DELETE"
    echo "    notifyL1.sh --label PostProcessing --dispatchMode POST_PROCESSING --sourceLabel R7|R10"
    echo "   notifyL1.sh --label <label>         --dispatchMode LOCAL"
    echo "    notifyL1.sh --label Main           --dispatchMode S3"
    echo "                      | Rejected"
    echo ""
    echo "Usage: (for VTC)"
    echo "    notifyL1.sh --label Default        --dispatchMode DELETE"
    echo "    notifyL1.sh --label PostProcessing --dispatchMode POST_PROCESSING --sourceLabel PFVN"
    echo "    notifyL1.sh --label <label>        --dispatchMode LOCAL"
    echo "    notifyL1.sh --label Main           --dispatchMode S3"
    echo "                      | Rejected"
    echo ""
}


#
# Main
#

AUDIT_LABEL=none
DISPATCH_MODE=none
LOG_LABEL="NotifyL1.sh"
OUTPUT_LABEL=none
POD_LEVEL=l1
SOURCE_LABEL=none

export TZ="Europe/Paris"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dispatchMode)
            DISPATCH_MODE="$2"
            shift
            ;;
        --label)
            AUDIT_LABEL="INTER_"$(echo "$2" | tr '[:lower:]' '[:upper:]')
            LOG_LABEL="notifyL1.sh ($2)"
            OUTPUT_LABEL="$2"
            shift
            ;;
        --sourceLabel)
            SOURCE_LABEL="$2"
            shift
            ;;
        *)
            echo "Unknown parameter passed: $1";
            #showUsage
            exit 1
            ;;
    esac
    shift
done

LOG_FILEPATH="/var/opt/SIU/log/notifyL1_$OUTPUT_LABEL-$(date +%Y%m%d).log"
export LOG_FILEPATH

LOG_LEVEL=${LOG_LEVEL:-4}
export LOG_LEVEL


case "$DISPATCH_MODE" in
    "DELETE")
        logDebug "Executing DELETE transfer mode"

        echo $FILENAMES | tr ';' '\n' | while read -r FILEPATH; do
            if [ -f $FILEPATH ]; then
                rm -f $FILEPATH
                if [ $? -ne 0 ]; then
                    logError "Failed to delete file '$FILEPATH'"
                fi
            else
                logWarning "File '$FILEPATH' does not exist"
            fi
        done
        ;;
    "POST_PROCESSING")
        logDebug "Executing POST_PROCESSING transfer mode"

        if [ -f /var/opt/SIU/ctrl/currentInputFileName ]; then
            mv /var/opt/SIU/ctrl/currentInputFileName /var/opt/SIU/ctrl/currentInputFileName.done
        else
            logWarning "File '/var/opt/SIU/ctrl/currentInputFileName' not found"
        fi

        if [ ! -z "$FILENAMES" ]; then
            echo $FILENAMES | tr ';' '\n' | while read -r FILE; do
                if [ -f $FILE ]; then
                    rm -f $FILE $DEST_DIR
                    logDebug "File '$FILE' deleted"
                fi
            done
        fi

        if [ ! -f /var/opt/SIU/ctrl/flag.softstop ]; then
            logDebug "Soft stop flag file not found. Exiting..."
            exit 0
        fi

        touch /var/opt/SIU/ctrl/flag.softstop.acknowledged

        # Variables expected to be defined in environment
        #   S3_ENDPOINTURL
        #   S3_ACCESSKEY
        #   S3_SECRETKEY
        #   S3_BUCKET
        #   S3_DIR_INTERPOD

        varName="S3_DIR_"$SOURCE_LABEL
        if [ -z "$(eval echo "\$$varName")" ]; then
            logError "Source label '$SOURCE_LABEL' is not valid. Environment variable '$varName' is not defined"
            exit 1
        fi
        SOURCE_DIR=$(eval echo "\$$varName")

        S3_OBJECT_NAME=$(basename $(echo $FILENAMES | tr ';' '\n' | head -n 1))
        S3_OBJECT_NAME=$SOURCE_DIR/$S3_OBJECT_NAME

        logWarning "Soft stop requested. Waiting for the end of execution of transfer processes..."

        let i=0
        while true; do
            RUNNING_PROCESSES=$(ps -edaf | grep "dispatcher --action s3Upload" | grep -v grep | wc -l)
            if [ $RUNNING_PROCESSES -lt 1 ]; then
                break
            else
                let i=$i+1
                if [ $i -ge 10 ]; then
                    let i=0
                    logInfo "Soft stop in progress. Waiting for transfer processes to finish..."
                fi
                sleep 0.1
            fi
        done

        touch /var/opt/SIU/ctrl/flag.softstop.dispatchers_terminated

        let i=0
        while true; do
            RUNNING_PROCESSES=$(ps -edaf | grep "auditHandler.sh" | grep -v grep | wc -l)
            if [ $RUNNING_PROCESSES -lt 1 ]; then
                break
            else
                let i=$i+1
                if [ $i -ge 100 ]; then
                    let i=0
                    logInfo "Soft stop still in progress. Waiting for audit handler processe to terminiate..."
                fi
                sleep 0.1
            fi
        done

        logInfo "All dispatcher and audit handler processes finished. Renaming input file in S3 bucket with extension .done"

        logDebug "Executiong command: cd /var/opt/bits/App/scripts && /usr/bin/python3.12 -m dispatcher --action s3RenameObject --s3AccessKey $S3_ACCESSKEY --s3Bucket $S3_BUCKET --s3EndPointURL $S3_ENDPOINTURL --s3ObjectName $S3_OBJECT_NAME --s3ObjectNameNew ${S3_OBJECT_NAME}.done --s3SecretKey $S3_SECRETKEY --logFilePath $LOG_FILEPATH --logLevel $LOG_LEVEL"

        cd /var/opt/bits/App/scripts && /usr/bin/python3.12 -m dispatcher --action s3RenameObject --s3AccessKey $S3_ACCESSKEY --s3Bucket $S3_BUCKET --s3EndPointURL $S3_ENDPOINTURL --s3ObjectName $S3_OBJECT_NAME --s3ObjectNameNew ${S3_OBJECT_NAME}.done --s3SecretKey $S3_SECRETKEY --logFilePath $LOG_FILEPATH --logLevel $LOG_LEVEL

        if [ $? -ne 0 ]; then
            logError "Could not rename input file in S3 bucket"
        fi

        mv /var/opt/SIU/ctrl/flag.softstop /var/opt/SIU/ctrl/flag.softstop.completed
        rm -f /var/opt/SIU/ctrl/flag.softstop.acknowledged

        logInfo "Pod is ready to be stopped."

        while true; do
            logDebug "Waiting for pod to be stopped..."
            sleep 4
        done

        exit 0
        ;;
    "LOCAL" | "S3")
        if [ -z "$FILENAMES" ]; then
            logDebug "$DISPATCH_MODE transfer mode, no files to transfer"
            exit 0
        fi

        logDebug "$DISPATCH_MODE transfer mode, file: $FILENAMES"

        # Variables expected to be defined in environment for S3 transfer mode
        #   KAFKA_BROKERURL
        #   KAFKA_GROUPID_INTERPOD
        #   KAFKA_NUMPARTITIONS
        #   KAFKA_PASSWORD
        #   KAFKA_TOPIC_INTERPOD
        #   KAFKA_USERNAME
        #   S3_ENDPOINTURL
        #   S3_ACCESSKEY
        #   S3_SECRETKEY
        #   S3_BUCKET
        #   S3_DIR_INTERPOD

        OUTPUT_DIR="/var/opt/SIU/output/${OUTPUT_LABEL}"
        if [ ! -d $OUTPUT_DIR ]; then
            mkdir -p $OUTPUT_DIR
            if [ $? -ne 0 ]; then
                logError "Failed to create output directory '$OUTPUT_DIR'"
                exit 0
            fi
        fi

        FILEPATH=$(echo $FILENAMES | tr ';' '\n' | head -n 1)
        INPUT_FILENAME=$(basename $FILEPATH | sed 's/\.norm$//' | sed 's/\.rejected$//' | sed 's/\.internalFormat$//')

        if [ -s $FILEPATH ]; then
            FILENAME=$(basename $FILEPATH)
            OUTPUT_FILEPATH=$OUTPUT_DIR/$FILENAME

            NUM_RECORDS=$(wc -l < $FILEPATH | tr -d ' ')
            logDebug "File '$FILEPATH' contains $NUM_RECORDS records"

            awk -F '|' -v numRecords=$NUM_RECORDS '
                BEGIN {
                    currentRecords = 1;
                }
                {
                    if (currentRecords == numRecords) {
                        gsub(/^0\|/, "9|", $0);
                    }
                    print $0;
                    currentRecords++;
                }
            ' $FILEPATH > $OUTPUT_FILEPATH

            if [ $(wc -l < $OUTPUT_FILEPATH) -ne $NUM_RECORDS ]; then
                logError "Failed to set recordTag to 9 in the last record of file '$FILEPATH'"

                mv $FILEPATH $OUTPUT_DIR
                if [ $? -ne 0 ]; then
                    logError "Failed to move file '$FILEPATH' to directory '$OUTPUT_DIR'"
                    exit 0
                fi
            else
                rm -f $FILEPATH
            fi

            DATE_TIME=$(date +"%Y-%m-%dT%H:%M:%S.%6N")
            SQL_UPDATE="update AUDIT_FILES set PROC_DATEEND='$DATE_TIME' where SCOPE='$COLLECTION_CHAIN' and FILE_NAME='"$INPUT_FILENAME"' and PROC_DATEEND is NULL;"

            if [ ! -d /var/opt/SIU/audit ]; then
                mkdir -p /var/opt/SIU/audit
                if [ $? -ne 0 ]; then
                    logError "Failed to create audit directory '/var/opt/SIU/audit'"
                fi
            fi

            echo "$SQL_UPDATE" >> /var/opt/SIU/audit/$FILENAME.audit
            logDebug "Stored audit statement: $SQL_UPDATE"
        else
            logError "File '$FILEPATH' does not exist or is empty"
            exit 0
        fi

        case "$DISPATCH_MODE" in
            "LOCAL")
                logInfo "LOCAL transfer mode selected. File '$OUTPUT_FILEPATH' is ready for pickup."
                ;;
            "S3")
                if [[ "$KAFKA_TOPIC_INTERPOD" =~ -$ ]]; then
                    KAFKA_TOPIC=${KAFKA_TOPIC_INTERPOD}$((CONTAINER_INDEX / KAFKA_NUMPARTITIONS))
                else
                    KAFKA_TOPIC=${KAFKA_TOPIC_INTERPOD}
                fi
                logDebug "KAFKA_TOPIC: $KAFKA_TOPIC"

                AUDIT_FILENAME_SUBSTITUTIONS="{'[.]rejected.*' : '', '[.]norm' : ''}"

                logInfo "Launching dispatcher to upload output file to S3 bucket"

                logDebug "Executing command: cd /var/opt/bits/App/scripts && /usr/bin/python3.12 -m dispatcher --action s3Upload --auditEnabled --auditFileNameSubstitutions \"$AUDIT_FILENAME_SUBSTITUTIONS\" --auditLabel $AUDIT_LABEL --auditScope $COLLECTION_CHAIN --filePath $OUTPUT_FILEPATH --kafkaSignalingEnabled --kafkaBootstrapServers $KAFKA_BROKERURL --kafkaClientId $COLLECTOR_NAME --kafkaConsumerGroupId $KAFKA_GROUPID_INTERPOD --kafkaNumPartitions $KAFKA_NUMPARTITIONS --kafkaPassword $KAFKA_PASSWORD --kafkaTopic $KAFKA_TOPIC --kafkaUsername $KAFKA_USERNAME --s3AccessKey $S3_ACCESSKEY --s3Bucket $S3_BUCKET --s3DestinationDir $S3_DIR_INTERPOD --s3EndPointURL $S3_ENDPOINTURL --s3SecretKey $S3_SECRETKEY --podLevel $POD_LEVEL --logFilePath $LOG_FILEPATH --logLabel \"$LOG_LABEL\" --logLevel $LOG_LEVEL --outputLabel "$OUTPUT_LABEL" --outputSlot 0"

                cd /var/opt/bits/App/scripts && /usr/bin/python3.12 -m dispatcher --action s3Upload --auditEnabled --auditLabel $AUDIT_LABEL --auditFileNameSubstitutions "$AUDIT_FILENAME_SUBSTITUTIONS" --auditScope $COLLECTION_CHAIN --filePath $OUTPUT_FILEPATH --kafkaSignalingEnabled --kafkaBootstrapServers $KAFKA_BROKERURL --kafkaClientId $COLLECTOR_NAME --kafkaConsumerGroupId $KAFKA_GROUPID_INTERPOD --kafkaNumPartitions $KAFKA_NUMPARTITIONS --kafkaPassword $KAFKA_PASSWORD --kafkaTopic $KAFKA_TOPIC --kafkaUsername $KAFKA_USERNAME --s3AccessKey $S3_ACCESSKEY --s3Bucket $S3_BUCKET --s3DestinationDir $S3_DIR_INTERPOD --s3EndPointURL $S3_ENDPOINTURL --s3SecretKey $S3_SECRETKEY --podLevel $POD_LEVEL --logFilePath $LOG_FILEPATH --logLabel "$LOG_LABEL" --logLevel $LOG_LEVEL --outputLabel "$OUTPUT_LABEL" --outputSlot 0
                ;;
        esac

        case $? in
            0)
                logDebug "Dispatcher finished with exit value: 0"
                ;;
            *)
                logError "Dispatcher finished with exit value: $?"
                ;;
        esac

        if [ ! -d /var/opt/SIU/env ]; then
            mkdir -p /var/opt/SIU/env
        fi

        if [ ! -f /var/opt/SIU/env/auditHandler.env ]; then
            >  /var/opt/SIU/env/auditHandler.env echo "DBSIU_NAME=$DBSIU_NAME"
            >> /var/opt/SIU/env/auditHandler.env echo "DBSIU_PASSWORD=$DBSIU_PASSWORD"
            >> /var/opt/SIU/env/auditHandler.env echo "DBSIU_PORT=$DBSIU_PORT"
            >> /var/opt/SIU/env/auditHandler.env echo "DBSIU_SERVER=$DBSIU_SERVER"
            >> /var/opt/SIU/env/auditHandler.env echo "DBSIU_USER=$DBSIU_USER"
        fi

        if [ ! -f /home/eium/.pgpass ]; then
            echo "$DBSIU_SERVER:$DBSIU_PORT:$DBSIU_NAME:$DBSIU_USER:$DBSIU_PASSWORD" > /home/eium/.pgpass
            chmod 600 /home/eium/.pgpass
        fi

        logDebug "Launching Audit Handler"

        flock -n /var/opt/SIU/ctrl/auditHandler.lock -c "/var/opt/bits/App/scripts/handlers/auditHandler.sh &"

        exit 0
        ;;
    *)
        logError "Unsupported transfer mode '$DISPATCH_MODE'"
        exit 1
        ;;
esac

