# -------------------------------------------------------------------------------
# kafkaHandler.py - Library for Kafka handling
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

#
# Imports
#

from confluent_kafka import Consumer, Producer, TopicPartition
from confluent_kafka.admin import AdminClient

from dispatcher.lib.Logger import LogLevels, LogModes, Logger
from time import time

import os
import random
import re
import traceback


#
# Classes
#

class KafkaHandler:

    def __init__ (self, bootstrapServers, username, password, clientId, numPartitions, topic, consumerGroupId = None, logger = None):
        if logger is None:
            logger = Logger(filePath = "/var/opt/SIU/log/KafkaHandler", logLevel = LogLevels.INFO, logMode = LogModes.FILE_ONLY)
        else:
            self.logger = logger

        self.numPartitions = numPartitions
        self.topic = topic
        self.auditInfo  = {
            "partition": None,
            "numTickets": 0
        }

        if username is None or password is None:
            self.producer = Producer({
                "bootstrap.servers": bootstrapServers,
                "acks": "all",
                "client.id": clientId,
                "transaction.timeout.ms": 60000})
        else:
            self.producer = Producer({
                "bootstrap.servers": bootstrapServers,
                "acks": "all",
                "linger.ms" : 1,
                "retries": 3,
                "ssl.ca.location" : "/etc/ssl/certs/ca-certificates.crt",
                "security.protocol": "SASL_PLAINTEXT",
                "sasl.mechanism": "SCRAM-SHA-256",
                "sasl.username": username,
                "sasl.password": password,
                "client.id": clientId,
                "transaction.timeout.ms": 60000 })

        self.consumerGroupId = consumerGroupId
        self.tps = None

        if self.consumerGroupId is not None:
            if username is None or password is None:
                self.adminClient = AdminClient({
                    "bootstrap.servers": bootstrapServers,
                    "client.id": clientId })

                self.consumer = Consumer({
                    "bootstrap.servers": bootstrapServers,
                    "group.id": consumerGroupId,
                    "enable.auto.commit": False,
                    "enable.auto.offset.store": False,
                    "enable.partition.eof": False })
            else:
                self.adminClient = AdminClient({
                    "bootstrap.servers": bootstrapServers,
                    "ssl.ca.location" : "/etc/ssl/certs/ca-certificates.crt",
                    "security.protocol": "SASL_PLAINTEXT",
                    "sasl.mechanism": "SCRAM-SHA-256",
                    "sasl.username": username,
                    "sasl.password": password,
                    "client.id": clientId })

                self.consumer = Consumer({
                    "bootstrap.servers": bootstrapServers,
                    "ssl.ca.location" : "/etc/ssl/certs/ca-certificates.crt",
                    "security.protocol": "SASL_PLAINTEXT",
                    "sasl.mechanism": "SCRAM-SHA-256",
                    "sasl.username": username,
                    "sasl.password": password,
                    "group.id": consumerGroupId,
                    "enable.auto.commit": False,
                    "enable.auto.offset.store": False,
                    "enable.partition.eof": False })
        else:
            self.adminClient = None
            self.consumer = None


    def computeLags(self):
        if self.consumerGroupId is None:
            return None

        if self.tps is None:
            metadata = self.consumer.list_topics(self.topic, timeout=10)
            toppicMetadata = metadata.topics.get(self.topic)

            if toppicMetadata is None:
                self.logger.logError(f"KafkaHandler.computeLags(): Topic '{self.topic}' not found in cluster")
                return None

            partitions = sorted([p.id for p in toppicMetadata.partitions.values()])
            self.tps = [TopicPartition(self.topic, p) for p in partitions]

        lags = {}
        for tp in self.tps:
            committed_tp = self.consumer.committed([tp], timeout=10)[0]
            committed_offset = committed_tp.offset if committed_tp.offset != -1001 else None
            low, high = self.consumer.get_watermark_offsets(tp, timeout=10)
            lag = (high - committed_offset) if committed_offset is not None else None

            self.logger.logDebug(f"KafkaHandler.computeLags(): Topic '{self.topic}' Partition {tp.partition} - Committed Offset: {committed_offset}, Low Watermark: {low}, High Watermark: {high}, Lag: {lag}")
            lags[tp.partition] = lag

        if len(lags) == 0:
            self.logger.logWarning(f"KafkaHandler.computeLags(): No offsets found for consumer group '{self.consumerGroupId}' on topic '{self.topic}'")
            return None

        return lags


    def deliverReport(self, err, msg):
        if err is not None:
            self.logger.logError(f"deliverReport(): Message delivery failed: {err}")
            result = False
        else:
            self.logger.logDebug2(f"deliverReport(): Message delivered to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}")
            self.auditInfo["numTickets"] += 1


    def getAuditInfo(self):
        return self.auditInfo


    def getGroupsOffsetsAndLags(self):
        try:
            if self.consumerGroupId is not None:
                if self.tps is None:
                    md = self.adminClient.list_topics(timeout = 10)
                    if self.topic not in md.topics:
                        self.logger.logError(f"Topic '{self.topic}' not found in cluster")
                        return None

                    self.tps = [TopicPartition(self.topic, p) for p in list(md.topics[self.topic].partitions.keys())]

                if self.tps is not None:
                    groupOffsets = self.adminClient.list_consumer_group_offsets(self.consumerGroupId, partitions = self.tps, timeout = 10)
                    offsetsInfo = {}
                    for tp, offset in groupOffsets.items():
                        self.logger.logDebug(f"getGroupsOffsetsAndLags(): Consumer group '{self.consumerGroupId}' on topic '{self.topic}' partition '{tp.partition}' has offset: {offset.offset}")
                        offsetsInfo[tp.partition] = offset.offset

                    if len(offsetsInfo) == 0:
                        self.logger.logWarning(f"getGroupsOffsetsAndLags(): No offsets found for consumer group '{self.consumerGroupId}' on topic '{self.topic}'")
                        return None

                    return offsetsInfo
            else:
                self.logger.logDebug("getGroupsOffsetsAndLags(): consumerGroupId is not set")
                return None
        except Exception as e:
            self.logger.logError(f"getGroupsOffsetsAndLags(): Error getting topic partitions for topic '{self.topic}': {e}\n{traceback.format_exc()}")
            return None


    def getNextPartition(self):
        self.logger.logDebug(f"KafkaHandler.getNextPartition(): Getting next partition for topic: {self.topic}")

        selectedPartition = None

        lags = self.computeLags()
        if lags is not None:
            partitionsWithMinLag = []
            minLag = None

            for partition in lags.keys():
                lag = lags[partition]
                if minLag is None or lag < minLag:
                    minLag = lag

            self.logger.logDebug(f"KafkaHandler.getNextPartition(): Minimum lag for topic '{self.topic}' is {minLag}")

            for partition in lags.keys():
                lag = lags[partition]
                if lag == minLag:
                    partitionsWithMinLag.append(partition)

            self.logger.logDebug(f"KafkaHandler.getNextPartition(): Partitions with minimum lag: {partitionsWithMinLag}")

            selectedPartition = random.choice(partitionsWithMinLag)
            self.logger.logDebug(f"KafkaHandler.getNextPartition(): Selected partition {selectedPartition}")

        if selectedPartition is None:
            if self.numPartitions is not None and self.numPartitions > 0:
                return random.randint(0, self.numPartitions - 1)
        else:
            return selectedPartition


    def sendSingleMessage(self, message, partition = None):
        self.logger.logDebug(f"KafkaHandler.sendSingleMessage(): Sending single message to topic: {self.topic}")

        result = True

        if partition is None:
            partition = self.getNextPartition()

        self.logger.logDebug(f"KafkaHandler.sendSingleMessage(): Sending message to topic: {self.topic} on partition: {partition}")

        try:
            self.producer.produce(self.topic, partition = partition, value = message , headers = [('isBulkMode', '00')], callback = self.deliverReport, on_delivery = lambda err, msg: self.logger.logDebug(f"KafkaHandler.sendSingleMessage(): Latency: { msg.latency() } ms"))
            self.producer.flush()
            self.logger.logInfo(f"KafkaHandler.sendSingleMessage(): Message sent to topic: {self.topic} on partition: {partition}")

            self.auditInfo["numTickets"] = 1
            self.auditInfo["partition"] = partition
        except Exception as e:
            self.logger.logError(f"KafkaHandler.sendSingleMessage(): Error sending message to topic: {self.topic}: {e}\n{traceback.format_exc()}")
            result = False

        return result


    def sendMessagesFromFile(self, filePath, partition = None, archiveDir = None, auditHandler = None):
        result = True

        if partition is None:
            partition = self.getNextPartition()

        self.auditInfo["numTickets"] = 0
        self.logger.logDebug(f"KafkaHandler.sendMessagesFromFile(): Sending messages from file '{filePath}' to topic: {self.topic} on partition: {partition}")

        try:
            lastLine = 0
            ctrlFile = None
            outputFile = None

            if not os.path.exists(filePath):
                self.logger.logError(f"KafkaHandler.sendMessagesFromFile(): Input file '{filePath}' does not exist")
                return False

            if os.path.exists(filePath + ".ctrl.kafka"):
                ctrlFile = open(filePath + ".ctrl.kafka", 'r+')
                lastLine = int(ctrlFile.readline().strip())
            else:
                ctrlFile = open(filePath + ".ctrl.kafka", 'w+')
                ctrlFile.seek(0)
                ctrlFile.write("0\n")
                ctrlFile.flush()

            outputFile = open(filePath, 'r')
            currentLine = 1
            lineNumbers = 0
            while True:
                line = outputFile.readline().rstrip("\n")
                if not line:
                    break

                lineNumbers += 1

                if currentLine > lastLine:
                    self.producer.produce(self.topic, partition = partition, value = line , headers = [('isBulkMode', '00')], callback = self.deliverReport)
                    self.producer.flush()
                    ctrlFile.seek(0)
                    ctrlFile.write(f"{currentLine}\n")
                    ctrlFile.flush()

                currentLine += 1

            if currentLine >= lineNumbers:
                if archiveDir is not None and os.path.exists(archiveDir):
                    baseName = os.path.basename(filePath)
                    archiveFilePath = os.path.join(archiveDir, f"{baseName}.{int(time.time())}")
                    os.rename(filePath, archiveFilePath)
                    self.logger.logDebug(f"KafkaHandler.sendMessagesFromFile(): Input file '{filePath}' archived to '{archiveFilePath}'")
                else:
                    os.remove(filePath)
                    self.logger.logDebug(f"KafkaHandler.sendMessagesFromFile(): Input file '{filePath}' deleted")

                os.remove(filePath + ".ctrl.kafka")

                self.auditInfo["numTickets"] = (currentLine - 1)
                self.auditInfo["partition"] = partition

            self.logger.logInfo(f"KafkaHandler.sendMessagesFromFile(): {self.auditInfo['numTickets']} messages sent from file '{filePath}' to topic: {self.topic} on partition: {partition}")
        except Exception as e:
            self.logger.logError(f"KafkaHandler.sendMessagesFromFile(): Error sending messages from file '{filePath}' to topic: {self.topic}: {e}\n{traceback.format_exc()}")
            result["successful"] = False
        finally:
            if ctrlFile is not None:
                ctrlFile.close()

            if outputFile is not None:
                outputFile.close()

        return result

