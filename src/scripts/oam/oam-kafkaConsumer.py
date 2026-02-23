# -------------------------------------------------------------------------------
# oam-kafkaConsumer.py - Tool for consuming messages to Kafka
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

#
# Imports
#

from asyncio import timeout
from importlib.metadata import files
import datetime
import os
import sys
import time
import traceback

from confluent_kafka import Consumer, KafkaError, TopicPartition
from uuid import uuid4


#
# Classes
#

class KafkaConsumer:

    def __init__ (self, bootstrapServers, username, password, groupId):

        if username is None or password is None:

            self.consumer = Consumer({ 'bootstrap.servers': bootstrapServers,
                                       'group.id': groupId,
                                       'auto.offset.reset': 'earliest',
                                       'enable.partition.eof': True,
                                       'partition.assignment.strategy': 'cooperative-sticky' })
        else:
            logInfo("groupeId: " + groupId)
            self.consumer = Consumer({ 'bootstrap.servers': bootstrapServers,
                                       'group.id': groupId,
                                       'auto.offset.reset': 'earliest',
                                       'enable.partition.eof': True,
                                       'ssl.ca.location' : '/etc/ssl/certs/ca-certificates.crt',
                                       'security.protocol': 'SASL_PLAINTEXT',
                                       'sasl.mechanism': 'SCRAM-SHA-256',
                                       'sasl.username': username,
                                       'sasl.password': password,
                                       'ssl.ca.location' : '/etc/ssl/certs/ca-bundle.crt',
                                       'partition.assignment.strategy': 'cooperative-sticky' })

    def print_assignment(self, consumer, partitions):
        logInfo(f"Assignment: {partitions}")


    def readMessagesFromOffset(self, topic, partition, offset, numMessages, timeout=30):

        logInfo(f"Subscribing to topic '{topic}'")
        self.consumer.unsubscribe()
        self.consumer.subscribe([ topic ], on_assign=self.print_assignment)

        try:
            tp = TopicPartition(topic, int(partition), int(offset))
            self.consumer.assign([tp])
            logInfo(f"Assigned to topic '{topic}' partition {partition} starting at offset {offset}'")

            msgs = self.consumer.consume(num_messages=numMessages, timeout=timeout)
            if not msgs:
                logInfo("No messages returned by consume()")
            else:
                for msg in msgs:
                    if msg is None:
                        continue
                    if msg.error():
                        logError(f"Consumer error: {msg.error()}")
                        continue
                    try:
                        logInfo(f"Received message: {msg.value().decode('utf-8')}")
                        self.consumer.commit(msg)
                    except Exception:
                        logInfo(f"Received non-decodable message: {msg.value()}")
        except Exception as e:
            logError(f"Failed to consume from specific offset: {e}")
            return False
        finally:
            # Close the consumer and exit the method to avoid running the default poll loop below
            try:
                self.consumer.close()
            except Exception:
                pass

        return True


#
# Functions
#


def log(message):
    print(f"{datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")} - oam-kafkaConsumer.py {message}")

def logInfo(message):
    log(f"[INF] {message}")

def logWarning(message):
    log(f"[WRN] {message}")

def logError(message):
    log(f"[ERR] {message}")

def logDebug(message):
    if logLevel >= 5:
        log(f"[DBG] {message}")

def showUsage():
    print("Usage:")
    print("")
    print("    oam-kafkaConsumer.py --action readMessagesFromOffset")
    print("                         --groupId <groupId>")
    print("                         --bootstrapServers <bootstrapServers>")
    print("                         --username <username>")
    print("                         --password <password>")
    print("                         --topic <topic>")
    print("                       [ --partition <partition>")
    print("                         --offset <offset>")
    print("                         --numMessages <numMessages> ]")
    print("                       [ --timeout <timeout> ]")
    print("                       [ --logLevel <logLevel> ]")
    print("")


#
# Main
#

action = None
groupId = None
topic = None
partition = None
offset = None
logLevel = 4
numMessages = 1
timeout = 30

i = 1
argc = len(sys.argv) - 1

try:
    while i <= argc:
        opt = sys.argv[i]
        if opt in [ "-a", "--action"]:
            if i + 1 <= argc:
                action = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--action'")
                sys.exit(1)
            if action not in ["readMessagesFromOffset"]:
                logError(f"Invalid action '{action}'")
                sys.exit(1)
        elif opt in [ "--groupId" ]:
            if i + 1 <= argc:
                groupId = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--groupId'")
                sys.exit(1)
        elif opt in [ "--bootstrapServers" ]:
            if i + 1 <= argc:
                bootstrapServers = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--bootstrapServers'")
                sys.exit(1)
        elif opt in [ "--username" ]:
            if i + 1 <= argc:
                username = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--username'")
                sys.exit(1)
        elif opt in [ "--password" ]:
            if i + 1 <= argc:
                password = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--password'")
                sys.exit(1)
        elif opt in [ "--topic" ]:
            if i + 1 <= argc:
                topic = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--topic'")
                sys.exit(1)
        elif opt in [ "--partition" ]:
            if i + 1 <= argc:
                partition = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--partition'")
                sys.exit(1)
        elif opt in [ "--offset" ]:
            if i + 1 <= argc:
                offset = sys.argv[i + 1]
                i += 2
            else:
                logError(f"Missing argument for option '--offset'")
                sys.exit(1)
        elif opt in [ "--numMessages" ]:
            if i + 1 <= argc:
                numMessages = int(sys.argv[i + 1])
                i += 2
            else:
                logError(f"Missing argument for option '--numMessages'")
                sys.exit(1)
        elif opt in [ "--logLevel" ]:
            if i + 1 <= argc:
                logLevel = int(sys.argv[i + 1])
                i += 2
            else:
                logError("Missing argument for option '--logLevel'")
                sys.exit(1)
        elif opt in [ "--timeout" ]:
            if i + 1 <= argc:
                timeout = int(sys.argv[i + 1])
                i += 2
            else:
                logError("Missing argument for option '--timeout'")
                sys.exit(1)
        elif opt in [ "-h", "--help" ]:
            showUsage()
            sys.exit(0)
        elif opt in [ "-v", "--version" ]:
            print("oam-kafkaConsumer.py version 1.0.0")
            sys.exit(0)
        else:
            logError(f"Invalid option: {opt}")
            sys.exit(1)
except Exception as e:
    logError(f"Error processing arguments: {e}\n{traceback.format_exc()}")
    sys.exit(1)


if action is None:
    logError(f"Missing mandatory argument 'action'")
    sys.exit(1)

if bootstrapServers is None:
    logError(f"Missing mandatory argument 'bootstrapServers'")
    sys.exit(1)

if action == "readMessagesFromOffset" and topic is None:
    logError(f"Missing mandatory argument 'partition' or 'offset' for action 'readMessagesFromOffset'")
    sys.exit(1)

exitCode = 0

try:
    KafkaConsumer = KafkaConsumer(bootstrapServers = bootstrapServers, username = username, password = password, groupId = groupId)

    if action == "readMessagesFromOffset":
        if partition is None or offset is None:
            while True:
                while True:
                    print("Partition ? [0-4] (0 to exit program) > ", end='')
                    partition = input().strip()
                    if partition in ['0', '1', '2', '3', '4']:
                        break
                    else:
                        print("Invalid partition. Please enter a number between 1 and 4.")

                if partition == '0':
                    break

                while True:
                    print("Offset (numeric) ? > ", end='')
                    offset = input().strip()
                    if offset.isdigit():
                        break
                    else:
                        print("Invalid offset. Please enter a numeric value.")

                while True:
                    print("Number of messages to read (numeric) ?> ", end='')
                    numMessagesInput = input().strip()
                    if numMessagesInput.isdigit():
                        numMessages = int(numMessagesInput)
                        break
                    else:
                        print("Invalid number. Please enter a numeric value.")

                KafkaConsumer.readMessagesFromOffset(topic = topic, partition = partition, offset = offset, numMessages = numMessages, timeout = timeout)
        else:
            KafkaConsumer.readMessagesFromOffset(topic = topic, partition = partition, offset = offset, numMessages = numMessages, timeout = timeout)
except Exception as e:
    logError(f"Unexpected exception {e}\n{traceback.format_exc()}")
    exitCode = 1

sys.exit(exitCode)
