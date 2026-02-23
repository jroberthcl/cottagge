#!/usr/bin/python3
# -------------------------------------------------------------------------------
# dispacher
#
# HCL Tech / CTG - 2025-2026
# -------------------------------------------------------------------------------

#
# Imports
#

from abc import abstractmethod
from datetime import datetime
from dispatcher.lib.AuditHandler import AuditHandler
from dispatcher.lib.KafkaHandler import KafkaHandler
from dispatcher.lib.Logger import Logger, LogLevels, LogModes
from dispatcher.lib.S3Handler import S3Handler
from zoneinfo import ZoneInfo

import json
import os
import re
import sys
import traceback

#
# Classes
#

class Action:

    def __init__(self, app):
        self.app = app

    def run(self):
        self.app.logger.logDebug("Action.run()")

        if not self.checkMissingArguments():
            self.app.logger.logError("Action.run(): Missing required arguments")
            return False

        return True

    @abstractmethod
    def checkMissingArguments(self):
        self.app.logger.logDebug("Action.checkMissingArguments()")
        return True


class ActionKafkaUpload(Action):

    def __init__(self, app):
        super().__init__(app)

        if self.app.auditEnabled:
            self.auditHandler = AuditHandler(
                auditScope = self.app.auditScope,
                auditLabel = self.app.auditLabel,
                logger = self.app.logger
            )

        self.kafkaHandler = KafkaHandler(
            bootstrapServers = self.app.kafkaBootstrapServers,
            username = self.app.kafkaUsername,
            password = self.app.kafkaPassword,
            clientId = self.app.kafkaClientId,
            numPartitions = self.app.kafkaNumPartitions,
            topic = self.app.kafkaTopic,
            consumerGroupId = None,
            logger = self.app.logger
        )


    def checkMissingArguments(self):
        self.app.logger.logDebug("ActionKafkaUpload.checkMissingArguments()")

        result = True

        for arg in [ "kafkaBootstrapServers", "kafkaClientId", "kafkaPassword", "kafkaTopic", "kafkaUsername", "outputLabel", "outputSlot", "podLevel" ]:
            if getattr(self.app, arg) is None:
                self.app.logger.logError(f"ActionKafkaUpload.checkMissingArguments(): Missing argument '{arg}'")
                result = False

        if self.app.auditEnabled:
            for arg in [ "auditLabel", "auditScope" ]:
                if getattr(self.app, arg) is None:
                    self.app.logger.logError(f"ActionKafkaUpload.checkMissingArguments(): Missing argument '{arg}'")
                    result = False

        return result


    def run(self):
        self.app.logger.logDebug("ActionKafkaUpload.run()")

        if not super().run():
            self.app.logger.logError("ActionKafkaUpload.run(): Missing required arguments")
            return False

        try:
            filePaths = []

            dir = os.path.dirname(self.app.filePath)
            fileNames = sorted(
                (f for f in os.listdir(dir) if (os.path.isfile(os.path.join(dir, f)) and ".ctrl" not in f)),
                key=lambda f: os.path.getctime(os.path.join(dir, f))
            )
            filePaths = [os.path.join(dir, f) for f in fileNames]

            for filePath in filePaths:
                filePath = filePath.strip()
                if filePath.strip() == "":
                    continue

                if not self.kafkaHandler.sendMessagesFromFile(filePath = filePath, partition = self.app.kafkaPartition, archiveDir = self.app.archiveDir, auditHandler = self.auditHandler):
                    self.app.logger.logWarning(f"Error sending messages from file '{filePath}' to Kafka topic '{self.app.kafkaTopic}'")
                    continue

                if self.auditHandler is not None:
                    auditFileName = os.path.basename(filePath)

                    if self.app.auditFileNameSubstitutions is not None:
                        for key in self.app.auditFileNameSubstitutions.keys():
                            auditFileName = re.sub(key, self.app.auditFileNameSubstitutions[key], auditFileName)

                    if not self.auditHandler.storeAuditStatement(fileName = auditFileName, setDateToNow = True, numTickets = self.kafkaHandler.getAuditInfo()["numTickets"], outputSlot = self.app.outputSlot, kafkaTopic = self.app.kafkaTopic, kafkaPartition =  self.kafkaHandler.getAuditInfo()["partition"]):
                        self.app.logger.logWarning(f"Error storing audit statement for file '{auditFileName}' after Kafka signaling")
                        continue
        except Exception as e:
            self.app.logger.logError(f"ActionKafkaUpload.run(): Exception caught: {str(e)}\n{traceback.format_exc()}")
            return False

        return True


class ActionS3RenameObject(Action):

    def __init__(self, app):
        super().__init__(app)

        self.s3Handler = S3Handler(
            endPointURL = self.app.s3EndPointURL,
            accessKey = self.app.s3AccessKey,
            secretKey = self.app.s3SecretKey,
            bucket = self.app.s3Bucket,
            logger = self.app.logger
        )


    def checkMissingArguments(self):
        self.app.logger.logDebug("ActionS3RenameObject.checkMissingArguments()")

        result = True

        for arg in [ "s3AccessKey", "s3Bucket", "s3EndPointURL", "s3ObjectName", "s3ObjectNameNew", "s3SecretKey" ]:
            if getattr(self.app, arg) is None:
                self.app.logger.logError(f"ActionS3RenameObject.checkMissingArguments(): Missing argument '{arg}'")
                result = False

        return result


    def run(self):
        self.app.logger.logDebug("ActionS3RenameObject.run()")

        if not super().run():
            self.app.logger.logError("ActionS3RenameObject.run(): Missing required arguments")
            return False

        try:
            if not self.s3Handler.renameObject(self.app.s3ObjectName, self.app.s3ObjectNameNew):
                self.app.logger.logError(f"ActionS3RenameObject.run(): Error renaming object '{self.app.s3ObjectName}' to '{self.app.s3ObjectNameNew}' in bucket '{self.app.s3Bucket}'")
                return False
        except Exception as e:
            self.app.logger.logError(f"ActionS3RenameObject.run(): Exception caught: {str(e)}\n{traceback.format_exc()}")
            return False

        return True


class ActionS3Upload(Action):

    def __init__(self, app):
        super().__init__(app)

        if self.app.auditEnabled:
            self.auditHandler = AuditHandler(
                auditScope = self.app.auditScope,
                auditLabel = self.app.auditLabel,
                logger = self.app.logger
            )
        else:
            self.auditHandler = None

        if self.app.kafkaSignalingEnabled:
            self.kafkaHandler = KafkaHandler(
                bootstrapServers = self.app.kafkaBootstrapServers,
                username = self.app.kafkaUsername,
                password = self.app.kafkaPassword,
                clientId = self.app.kafkaClientId,
                numPartitions = self.app.kafkaNumPartitions,
                topic = self.app.kafkaTopic,
                consumerGroupId = self.app.consumerGroupId,
                logger = self.app.logger
            )
        else:
            self.kafkaHandler = None

        self.s3Handler = S3Handler(
            endPointURL = self.app.s3EndPointURL,
            accessKey = self.app.s3AccessKey,
            secretKey = self.app.s3SecretKey,
            bucket = self.app.s3Bucket,
            logger = self.app.logger
        )


    def checkMissingArguments(self):
        self.app.logger.logDebug("ActionS3Upload.checkMissingArguments()")

        result = True

        for arg in [ "outputLabel", "outputSlot", "podLevel", "filePath", "s3AccessKey", "s3Bucket", "s3DestinationDir", "s3EndPointURL", "s3SecretKey" ]:
            if getattr(self.app, arg) is None:
                self.app.logger.logError(f"ActionS3Upload.checkMissingArguments(): Missing argument '{arg}'")
                result = False

        if self.app.auditEnabled:
            for arg in [ "auditLabel", "auditScope" ]:
                if getattr(self.app, arg) is None:
                    self.app.logger.logError(f"ActionS3Upload.checkMissingArguments(): Missing argument '{arg}'")
                    result = False

        if self.app.kafkaSignalingEnabled:
            for arg in [ "kafkaBootstrapServers", "kafkaClientId", "kafkaPassword", "kafkaTopic", "kafkaUsername" ]:
                if getattr(self.app, arg) is None:
                    self.app.logger.logError(f"ActionS3Upload.checkMissingArguments(): Missing argument '{arg}'")
                    result = False

            if self.app.kafkaNumPartitions is None and self.app.kafkaPartition is None:
                self.app.logger.logError(f"ActionS3Upload.checkMissingArguments(): Missing argument 'kafkaNumPartitions' or 'kafkaPartition'")
                result = False

        return result


    def run(self):
        self.app.logger.logDebug("ActionS3Upload.run()")

        if not super().run():
            self.app.logger.logError("ActionS3Upload.run(): Missing required arguments")
            return False

        try:
            filePaths = []

            dir = os.path.dirname(self.app.filePath)
            fileNames = sorted(
                (f for f in os.listdir(dir) if (os.path.isfile(os.path.join(dir, f)) and ".ctrl" not in f)),
                key=lambda f: os.path.getctime(os.path.join(dir, f))
            )
            filePaths = [os.path.join(dir, f) for f in fileNames]

            for filePath in filePaths:
                auditFileName = os.path.basename(filePath)

                filePath = filePath.strip()
                if filePath.strip() == "":
                    continue

                ctrlDoneS3FilePath = filePath + ".ctrl.doneS3"
                ctrlDoneKafkaFilePath = filePath + ".ctrl.doneKafka"

                if os.path.exists(ctrlDoneS3FilePath):
                    self.app.logger.logWarning(f"Control file '{ctrlDoneS3FilePath}' found. File upload skipped.")
                    continue

                if not os.path.exists(filePath):
                    self.app.logger.logWarning(f"File '{filePath}' does not exist")
                    continue

                numTickets = -1
                try:
                    with open(filePath, "r") as fIn:
                        numTickets = sum(1 for line in fIn if line.strip() != "")
                        self.app.logger.logDebug(f"File: {filePath} contains {numTickets} tickets")
                    fIn.close()
                except Exception as e:
                    self.app.logger.logDebug(f"Error reading file '{filePath}': {e}\n{traceback.format_exc()}. Unable to count tickets.")

                if not self.s3Handler.uploadFile(filePath = filePath, s3DestinationDir = self.app.s3DestinationDir):
                    self.app.logger.logWarning(f"Error uploading file '{filePath}' to s3Bucket '{self.app.s3Bucket}'")
                    continue

                try:
                    with open(ctrlDoneS3FilePath, "w"):
                        pass

                    self.app.logger.logDebug(f"Created control file: {ctrlDoneS3FilePath}")

                    if self.auditHandler is not None:
                        if self.app.auditFileNameSubstitutions is not None:
                            if self.app.auditFileNameSubstitutions is not None:
                                for key in self.app.auditFileNameSubstitutions.keys():
                                    auditFileName = re.sub(key, self.app.auditFileNameSubstitutions[key], auditFileName)

                        self.app.logger.logDebug(f"Storing audit statement for file self.app.outputSlot={self.app.outputSlot} after S3 upload")
                        self.auditHandler.storeAuditStatement(fileName = auditFileName, setDateToNow = True, numTickets = numTickets, outputSlot = self.app.outputSlot)

                except Exception as e:
                    self.app.logger.logError(f"Error creating control file '{ctrlDoneS3FilePath}': {e}\n{traceback.format_exc()}")
                    continue

                if self.app.kafkaSignalingEnabled:
                    if os.path.exists(ctrlDoneKafkaFilePath):
                        self.app.logger.logWarning(f"Control file '{ctrlDoneKafkaFilePath}' found. Kafka signaling skipped.")
                    else:
                        message = '{"FilePath":"' + os.path.basename(filePath) + '"}'

                        if not self.kafkaHandler.sendSingleMessage(message = message, partition = self.app.kafkaPartition):
                            continue

                        if self.auditHandler is not None:
                            if not self.auditHandler.storeAuditStatement(fileName = auditFileName, kafkaTopic = self.app.kafkaTopic, kafkaPartition = self.kafkaHandler.getAuditInfo()["partition"]):
                                self.app.logger.logWarning(f"Error storing audit statement for file '{auditFileName}' after Kafka signaling")
                                continue

                        try:
                            with open(ctrlDoneKafkaFilePath, "w"):
                                pass
                            self.app.logger.logDebug(f"Created control file: {ctrlDoneKafkaFilePath}")
                        except Exception as e:
                            self.app.logger.logError(f"Error creating control file '{ctrlDoneKafkaFilePath}': {e}\n{traceback.format_exc()}")
                            continue

                if os.path.exists(ctrlDoneS3FilePath) and (not self.app.kafkaSignalingEnabled or os.path.exists(ctrlDoneKafkaFilePath)):
                    if self.app.archiveDir is not None:
                        if not os.path.exists(self.app.archiveDir):
                            try:
                                os.makedirs(self.app.archiveDir, exist_ok = True)
                            except Exception as e:
                                self.app.logger.logError(f"Error creating archive directory '{self.app.archiveDir}': {e}\n{traceback.format_exc()}")
                                continue

                        archiveFilePath = os.path.join(self.app.archiveDir, os.path.basename(filePath))
                        try:
                            os.rename(filePath, archiveFilePath)
                            self.app.logger.logDebug(f"File: {filePath} moved to archive directory: {self.app.archiveDir}")
                        except Exception as e:
                            self.app.logger.logError(f"Error moving file to archive directory: {e}\n{traceback.format_exc()}")
                            continue
                    else:
                        try:
                            os.remove(filePath)
                            self.app.logger.logDebug(f"File: {filePath} deleted after upload")
                        except Exception as e:
                            self.app.logger.logError(f"Error deleting file after upload: {e}\n{traceback.format_exc()}")
                            continue

                    try:
                        os.remove(ctrlDoneS3FilePath)
                        self.app.logger.logInfo(f"Control file: {ctrlDoneS3FilePath} deleted after upload")
                        if self.app.kafkaSignalingEnabled:
                            os.remove(ctrlDoneKafkaFilePath)
                            self.app.logger.logDebug(f"Control file: {ctrlDoneKafkaFilePath} deleted after upload")
                    except Exception as e:
                        self.app.logger.logError(f"Error deleting control file(s) after upload: {e}\n{traceback.format_exc()}")
                        continue

        except Exception as e:
            self.app.logger.logError(f"ActionS3Upload.run(): Exception caught: {str(e)}\n{traceback.format_exc()}")
            return False

        return True


#
# Main
#

class App():

    def __init__(self):
        now = datetime.now(ZoneInfo("Europe/Paris"))
        self.logger = Logger(filePath = f"/var/opt/SIU/log/dispatcher-{now.strftime('%Y-%m-%d')}.log", label = "dispatcher.py", logLevel = LogLevels.DEBUG, logMode = LogModes.FILE_ONLY)

        self.action = None
        self.archiveDir = None
        self.auditEnabled = False
        self.auditLabel = None
        self.auditScope = None
        self.auditFileNameSubstitutions = None
        self.filePath = None
        self.kafkaBootstrapServers = None
        self.kafkaClientId = None
        self.consumerGroupId = None
        self.kafkaNumPartitions = None
        self.kafkaPartition = None
        self.kafkaPassword = None
        self.kafkaSignalingEnabled = False
        self.kafkaTopic = None
        self.kafkaUsername = None
        self.logFilePath = None
        self.logLabel = ""
        self.logLevel = 4
        self.outputLabel = None
        self.outputSlot = None
        self.podLevel = None
        self.s3AccessKey = None
        self.s3Bucket = None
        self.s3DestinationDir = None
        self.s3EndPointURL = None
        self.s3ObjectName = None
        self.s3ObjectNameNew = None
        self.s3SecretKey = None
        self.version = "1.1 [Nov 2025]"


    def run(self):
        self.logger.logDebug("App.run()")

        i = 1
        argc = len(sys.argv) - 1

        try:
            while i <= argc:
                opt = sys.argv[i]
                if opt in [ "--action"]:
                    if i + 1 <= argc:
                        self.action = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--action'")
                        sys.exit(1)
                    if self.action not in ["help", "kafkaUpload", "s3RenameObject", "s3Upload", "version" ]:
                        self.logger.logError(f"Invalid action '{self.action}'")
                        sys.exit(1)
                elif opt in [ "--archiveDir" ]:
                    if i + 1 <= argc:
                        self.archiveDir = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--archiveDir'")
                        sys.exit(1)
                elif opt in [ "--auditEnabled" ]:
                    self.auditEnabled = True
                    i += 1
                elif opt in [ "--auditFileNameSubstitutions" ]:
                    if i + 1 <= argc:
                        self.auditFileNameSubstitutions = json.loads(sys.argv[i + 1].replace("'", "\""))
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--auditFileNameSubstitutions'")
                        sys.exit(1)
                elif opt in [ "--auditLabel" ]:
                    if i + 1 <= argc:
                        self.auditLabel = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--auditLabel'")
                        sys.exit(1)
                elif opt in [ "--auditScope" ]:
                    if i + 1 <= argc:
                        self.auditScope = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--auditScope'")
                        sys.exit(1)
                elif opt in [ "--filePath" ]:
                    if i + 1 <= argc:
                        self.filePath = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--filePath'")
                        sys.exit(1)
                elif opt in [ "--kafkaBootstrapServers" ]:
                    if i + 1 <= argc:
                        self.kafkaBootstrapServers = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaBootstrapServers'")
                        sys.exit(1)
                elif opt in [ "--kafkaClientId" ]:
                    if i + 1 <= argc:
                        self.kafkaClientId = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaClientId'")
                        sys.exit(1)
                elif opt in [ "--kafkaConsumerGroupId" ]:
                    if i + 1 <= argc:
                        self.consumerGroupId = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaConsumerGroupId'")
                        sys.exit(1)
                elif opt in [ "--kafkaPartition" ]:
                    if i + 1 <= argc:
                        self.kafkaPartition = int(sys.argv[i + 1])
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaPartition'")
                        sys.exit(1)
                elif opt in [ "--kafkaNumPartitions" ]:
                    if i + 1 <= argc:
                        self.kafkaNumPartitions = int(sys.argv[i + 1])
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaNumPartitions'")
                        sys.exit(1)
                elif opt in [ "--kafkaPassword" ]:
                    if i + 1 <= argc:
                        self.kafkaPassword = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaPassword'")
                        sys.exit(1)
                elif opt in [ "--kafkaSignalingEnabled" ]:
                    self.kafkaSignalingEnabled = True
                    i += 1
                elif opt in [ "--kafkaTopic" ]:
                    if i + 1 <= argc:
                        self.kafkaTopic = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaTopic'")
                        sys.exit(1)
                elif opt in [ "--kafkaUsername" ]:
                    if i + 1 <= argc:
                        self.kafkaUsername = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--kafkaUsername'")
                        sys.exit(1)
                elif opt in [ "--logLevel" ]:
                    if i + 1 <= argc:
                        self.logLevel = int(sys.argv[i + 1])
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--logLevel'")
                        sys.exit(1)
                elif opt in [ "--logLabel" ]:
                    if i + 1 <= argc:
                        self.logLabel = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--logLabel'")
                        sys.exit(1)
                elif opt in [ "--logFilePath" ]:
                    if i + 1 <= argc:
                        self.logFilePath = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--logFilePath'")
                        sys.exit(1)
                elif opt in [ "--outputLabel" ]:
                    if i + 1 <= argc:
                        self.outputLabel = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--outputLabel'")
                        sys.exit(1)
                elif opt in [ "--outputSlot" ]:
                    if i + 1 <= argc:
                        self.outputSlot = int(sys.argv[i + 1])
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--outputSlot'")
                        sys.exit(1)
                elif opt in [ "--podLevel" ]:
                    if i + 1 <= argc:
                        self.podLevel = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--podLevel'")
                        sys.exit(1)
                elif opt in [ "--s3AccessKey" ]:
                    if i + 1 <= argc:
                        self.s3AccessKey = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--s3AccessKey'")
                        sys.exit(1)
                elif opt in [ "--s3Bucket" ]:
                    if i + 1 <= argc:
                        self.s3Bucket = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--s3Bucket'")
                        sys.exit(1)
                elif opt in [ "--s3DestinationDir" ]:
                    if i + 1 <= argc:
                        self.s3DestinationDir = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--s3DestinationDir'")
                        sys.exit(1)
                elif opt in [ "--s3EndPointURL" ]:
                    if i + 1 <= argc:
                        self.s3EndPointURL = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--s3EndPointURL'")
                        sys.exit(1)
                elif opt in [ "--s3ObjectName" ]:
                    if i + 1 <= argc:
                        self.s3ObjectName = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--s3ObjectName'")
                        sys.exit(1)
                elif opt in [ "--s3ObjectNameNew" ]:
                    if i + 1 <= argc:
                        self.s3ObjectNameNew = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--s3ObjectNameNew'")
                        sys.exit(1)
                elif opt in [ "--s3SecretKey" ]:
                    if i + 1 <= argc:
                        self.s3SecretKey = sys.argv[i + 1]
                        i += 2
                    else:
                        self.logger.logError("Missing argument for option '--s3SecretKey'")
                        sys.exit(1)
                elif opt in [ "--help" ]:
                    self.showUsage()
                    sys.exit(0)
                elif opt in [ "--version" ]:
                    print(f"dispatcher version {self.version} (support: christophe.cremy@hcltech.com)")
                    sys.exit(0)
                else:
                    self.logger.logError(f"Invalid option: {opt}")
                    sys.exit(1)

            if self.logFilePath is not None:
                self.logger.logWarning(f"Setting log file path to '{self.logFilePath}'")

                self.logger = Logger(filePath = self.logFilePath, label = self.logLabel, logLevel = self.logLevel, logMode = LogModes.FILE_ONLY)

            if self.action is None:
                self.logger.logError("No action specified")
                self.showUsage()
                sys.exit(1)

            actionClass = globals().get(f"Action{self.action[0].upper()}{self.action[1:]}")
            if actionClass is None:
                self.logger.logError(f"Action class for action '{self.action}' not found")
                sys.exit(1)

            actionInstance = actionClass(app = self)
            if actionInstance is None:
                self.logger.logError(f"Error creating action instance for action '{self.action}'")
                sys.exit(1)

            self.logger.logInfo(f"Executing action '{self.action}'")

            if not actionInstance.run():
                self.logger.logError(f"Error executing action '{self.action}'")
                sys.exit(1)
        except Exception as e:
            self.logger.logError(f"App.run(): Exception caught: {str(e)}")
            sys.exit(1)


    def showUsage(self):
        print("Usages:")
        print("")
        print("  dispatcher.py --help")
        print("")
        print("  dispatcher.py --action s3RenameObject")
        print("                --s3AccessKey <s3AccessKey>")
        print("                --s3Bucket <s3Bucket>")
        print("                --s3EndPointURL <s3EndPointURL>")
        print("                --s3SecretKey <s3SecretKey>")
        print("                --s3ObjectName <s3ObjectName>")
        print("                --s3ObjectNameNew <s3ObjectNameNew>")
        print("")
        print("  dispatcher.py --action s3Upload")
        print("              [ --archiveDir <archiveDir> ]")
        print("              [")
        print("                  --auditEnabled")
        print("                  --auditFileNameSubstitutions <auditFileNameSubstitutions>")
        print("                  --auditLabel <auditLabel>")
        print("                  --auditScope <auditScope>")
        print("              ]")
        print("                --filePath <filePath>")
        print("              [")
        print("                  --kafkaSignalingEnabled")
        print("                  --kafkaBootstrapServers <kafkaBootstrapServers>")
        print("                  --kafkaClientId <kafkaClientId>")
        print("                [ --kafkaConsumerGroupId <kafkaConsumerGroupId> ]")
        print("                [ --kafkaPartition <kafkaPartition> ]")
        print("                  --kafkaPassword <kafkaPassword>")
        print("                [ --kafkaNumPartitions <kafkaNumPartitions> ]")
        print("                  --kafkaTopic <kafkaTopic>")
        print("                  --kafkaUsername <kafkaUsername>")
        print("              ]")
        print("              [ --logLabel <logLabel> ]")
        print("              [ --logLevel <logLevel> ]")
        print("              [ --logFilePath <logFilePath> ]")
        print("                --outputLabel <outputLabel>")
        print("                --outputSlot <outputSlot>")
        print("                --podLevel <podLevel>")
        print("                --s3AccessKey <s3AccessKey>")
        print("                --s3Bucket <s3Bucket>")
        print("                --s3DestinationDir <s3DestinationDir>")
        print("                --s3EndPointURL <s3EndPointURL>")
        print("                --s3SecretKey <s3SecretKey>")
        print("")
        print("  dispatcher.py --action kafkaUpload")
        print("              [ --archiveDir <archiveDir> ]")
        print("              [")
        print("                  --auditEnabled")
        print("                  --auditFileNameSubstitutions <auditFileNameSubstitutions>")
        print("                  --auditLabel <auditLabel>")
        print("                  --auditScope <auditScope>")
        print("              ]")
        print("                --filePath <filePath>")
        print("              [")
        print("                --kafkaBootstrapServers <kafkaBootstrapServers>")
        print("                --kafkaClientId <kafkaClientId>")
        print("              [ --kafkaPartition <kafkaPartition> ]")
        print("                --kafkaPassword <kafkaPassword>")
        print("              [ --kafkaNumPartitions <kafkaNumPartitions> ]")
        print("                --kafkaTopic <kafkaTopic>")
        print("                --kafkaUsername <kafkaUsername>")
        print("              [ --logLabel <logLabel> ]")
        print("              [ --logLevel <logLevel> ]")
        print("              [ --logFilePath <logFilePath> ]")
        print("                --outputLabel <outputLabel>")
        print("                --outputSlot <outputSlot>")
        print("                --podLevel <podLevel>")
        print("")
        print("  dispatcher.py --version")
        print("")
