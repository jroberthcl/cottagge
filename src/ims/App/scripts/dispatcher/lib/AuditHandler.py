# -------------------------------------------------------------------------------
# kafkaHandler.py - Library for Kafka handling
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

#
# Imports
#

from dispatcher.lib.Logger import LogLevels, LogModes, Logger

import os
import re
import sys
import traceback
from datetime import datetime
from zoneinfo import ZoneInfo


#
# Classes
#

class AuditHandler:
    def __init__(self, auditLabel, auditScope, logger = None):
        if logger is None:
            self.logger = Logger(filePath = "/var/opt/SIU/log/AuditHandler", logLevel = LogLevels.INFO, logMode = LogModes.FILE_ONLY)
        else:
            self.logger = logger

        self.auditLabel = auditLabel
        self.auditScope = auditScope


    def storeAuditStatement(self, fileName = None, setDateToNow = False, numTickets = None, outputSlot = None, kafkaTopic = None, kafkaPartition = None):
        if fileName is None:
            self.logger.logError("AuditHandler().storeAuditStatement(): fileName is None")
            return False

        columnNameDate = f"{self.auditLabel}_DATE"
        columnNameKafkaPartition = f"{self.auditLabel}_KPART"
        columnNameKafkaTopicIndex = f"{self.auditLabel}_KIDX"
        columnNameNumTickets = f"{self.auditLabel}_NUM"
        columnNameOutputSlot = f"{self.auditLabel}_SLOT"

        try:
            setArgs = ""
            whereArgs = f"SCOPE='{self.auditScope}' and FILE_NAME='{fileName}'"

            if setDateToNow:
                setArgs += f", {columnNameDate}='{datetime.now(ZoneInfo("Europe/Paris")).strftime('%Y-%m-%dT%H:%M:%S.%f')}'"
                whereArgs += f" and {columnNameDate} is NULL"

            if numTickets is not None:
                setArgs += f", {columnNameNumTickets}={numTickets}"

            if outputSlot is not None:
                setArgs += f", {columnNameOutputSlot}={outputSlot}"

            if kafkaPartition is not None:
                setArgs += f", {columnNameKafkaPartition}={kafkaPartition}"

            if kafkaTopic is not None:
                kafkaTopicMatch = re.search(r'-(\d+)$', kafkaTopic)
                if kafkaTopicMatch:
                    kafkaTopicIndex = kafkaTopicMatch.group(1)
                    setArgs += f", {columnNameKafkaTopicIndex}={kafkaTopicIndex}"

            if setArgs.startswith(", "):
                setArgs = setArgs[2:]

            if setArgs == "":
                self.logger.logError(f"AuditHandler().storeAuditStatement(): No arguments to store for file '{fileName}'")
                return False

            record = f"update AUDIT_FILES set {setArgs} where {whereArgs};\n"

            auditFilePath = f"/var/opt/SIU/audit/{fileName}.{self.auditLabel}.audit"
            with open(auditFilePath, "a") as fOut:
                fOut.write(record)
                self.logger.logDebug(f"AuditHandler().storeAuditStatement(): Stored audit statement '{record.strip()}'")
            fOut.close()
            return True
        except Exception as e:
            self.logger.logError(f"AuditHandler().storeAuditStatement(): Error storing audit statement for file '{fileName}': {e}\n{traceback.format_exc()}")
            return False

