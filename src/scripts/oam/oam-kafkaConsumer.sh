#!/bin/bash
# -------------------------------------------------------------------------------
# oam-kafkaConsumer.sh - Tool for consuming messages to Kafka
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

#
# Variables
#


BOOTSTRAP_SERVERS="app04-kam-pp.phys.pack:9092,app05-kam-pp.phys.pack:9092,app06-kam-pp.phys.pack:9092,app07-kam-pp.phys.pack:9092"
USERNAME="u_app4450_collecte_voix_fixe"
PASSWORD="csyevo5iwfydsvnzw2qwr5rhz4ri9d3y"


#
# Functions
#

function showUsage() {
    echo "Usage:"
    echo "    oam-kafkaConsumer.sh --groupId <groupId>"
    echo "                         --topic <topic>"
    echo "                       [ --partition <partition>"
    echo "                         --offset <offset>"
    echo "                         --numMessages <numMessages> ]"
}


#
# Main
#

NUM_MESSAGES=none
OFFSET=none
PARTITION=none

while [[ $# -gt 0 ]]; do
    case $1 in
        --groupId)
            GROUP_ID="$2"
            shift
            ;;
        --topic)
            TOPIC="$2"
            shift
            ;;
        --partition)
            PARTITION="$2"
            shift
            ;;
        --offset)
            OFFSET="$2"
            shift
            ;;
        --numMessages)
            NUM_MESSAGES="$2"
            shift
            ;;
        *)
            echo "Unknown parameter passed: $1"
            showUsage;
            exit 1
            ;;
    esac
    shift
done

if [ -z "$GROUP_ID" ] || [ -z "$TOPIC" ]; then
    echo "ERROR: Missing required arguments"
    showUsage
    exit 1
fi

echo "BOOTSTRAP_SERVERS: $BOOTSTRAP_SERVERS"
echo "GROUP_ID: $GROUP_ID"
echo "TOPIC: $TOPIC"
echo "PARTITION: $PARTITION"
echo "OFFSET: $OFFSET"
echo "NUM_MESSAGES: $NUM_MESSAGES"


if [ -z "$NUM_MESSAGES" ]; then
    NUM_MESSAGES=1
fi

echo "Reading $NUM_MESSAGES message(s) from topic '$TOPIC', partition $PARTITION, starting at offset $OFFSET"
echo ""

ARGS=""

if [ "$PARTITION" != "none" ]; then
    ARGS="$ARGS --partition $PARTITION"
fi

if [ "$OFFSET" != "none" ]; then
    ARGS="$ARGS --offset $OFFSET"
fi

if [ "$NUM_MESSAGES" != "none" ]; then
    ARGS="$ARGS --numMessages $NUM_MESSAGES"
fi

/usr/bin/python3.12 /var/opt/bits/App/scripts/oam/oam-kafkaConsumer.py --action readMessagesFromOffset --bootstrapServers "$BOOTSTRAP_SERVERS" --username "$USERNAME" --password "$PASSWORD" --groupId "$GROUP_ID" --topic "$TOPIC" $ARGS
