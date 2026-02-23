# -------------------------------------------------------------------------------
# s3Handler.py - Library for S3 buckets handling
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

#
# Imports
#

from dispatcher.lib.Logger import LogLevels, LogModes, Logger

from botocore.client import Config
import boto3
import hashlib
import os
import tempfile
import traceback


#
# Classes
#

class S3Handler:

    def __init__(self, endPointURL, accessKey, secretKey, bucket, logger = None):
        if logger is None:
            logger = Logger("S3Handler", filePath = "/var/opt/SIU/log/S3Handler", logLevel = LogLevels.INFO, logMode = LogModes.FILE_ONLY)
        else:
            self.logger = logger

        self.bucket = bucket
        self.session = boto3.session.Session()

        self.s3Client = self.session.client(
            's3',
            endpoint_url = endPointURL,
            aws_access_key_id = accessKey,
            aws_secret_access_key = secretKey,
            config = Config(signature_version = 's3v4'))


    def checkObjectExists(self, s3ObjectName):
        try:
            self.s3Client.head_object(Bucket = self.bucket, Key = s3ObjectName)
            self.logger.logInfo(f"checkObjectExists(): Object: {s3ObjectName} exists in self.bucket: {self.bucket}")
            return True
        except Exception as e:
            self.logger.logWarning(f"checkObjectExists(): Object: {s3ObjectName} does not exist in self.bucket: {self.bucket}")
            return False


    def close(self):
        try:
            if self.s3Client is not None:
                self.s3Client.close()
            if self.logger is not None:
                self.logger.close()
        except Exception as e:
            self.logger.logWarning(f"S3Handler: Error closing S3 client connection: {e}\n{traceback.format_exc()}")


    def deleteObject(self, s3ObjectName):
        try:
            self.s3Client.delete_object(Bucket = self.bucket, Key = s3ObjectName)
            self.logger.logInfo(f"deleteObject(): Object: {s3ObjectName} deleted from self.bucket: {self.bucket}")
        except Exception as e:
            self.logger.logError(f"deleteObject(): Error deleting object: {s3ObjectName} from self.bucket: {self.bucket}: {e}\n{traceback.format_exc()}")
            return False

        return True


    def downloadFile(self, filePath, s3ObjectName):
        try:
            self.s3Client.download_file(self.bucket, s3ObjectName, filePath)
            self.logger.logInfo(f"downloadFile(): Object: {s3ObjectName} downloaded from self.bucket: {self.bucket} to file: {filePath}")
        except Exception as e:
            self.logger.logError(f"downloadFile(): Error downloading object: {s3ObjectName} from self.bucket: {self.bucket} to file: {filePath} : {e}\n{traceback.format_exc()}")
            return False

        return True


    def listObjects(self, s3DestinationDir):
        try:
            self.logger.logInfo(f"listObjects(): Object in bucket: {self.bucket} / directory: {s3DestinationDir}")

            paginator = self.s3Client.get_paginator('list_objects_v2')
            for page in paginator.paginate(Bucket = self.bucket, Prefix = s3DestinationDir):
                for obj in page.get('Contents', []):
                    print(f"{obj['Key']}")
        except Exception as e:
            self.logger.logError(f"listObjects(): Error listing object in self.bucket: {self.bucket} / directory: {s3DestinationDir}: {e}\n{traceback.format_exc()}")
            return False

        return True


    def renameObject(self, s3ObjectName, s3ObjectNameNew):
        try:
            self.logger.logInfo(f"renameObject(): Renaming object '{s3ObjectName}' to '{s3ObjectNameNew}' in bucket '{self.bucket}'")

            try:
                self.s3Client.head_object(Bucket=self.bucket, Key=s3ObjectName)
            except Exception as e:
                self.logger.logWarning(f"renameObject(): Source object '{s3ObjectName}' not found in bucket '{self.bucket}': {e}")
                return False

            copy_source = {'Bucket': self.bucket, 'Key': s3ObjectName}
            self.s3Client.copy(copy_source, self.bucket, s3ObjectNameNew)
            self.logger.logInfo(f"renameObject(): Copied '{s3ObjectName}' to '{s3ObjectNameNew}'")
            self.s3Client.delete_object(Bucket=self.bucket, Key=s3ObjectName)
            self.logger.logInfo(f"renameObject(): Deleted original object '{s3ObjectName}'")
        except Exception as e:
            self.logger.logError(f"renameObject(): Error renaming object '{s3ObjectName}' to '{s3ObjectNameNew}' in bucket '{self.bucket}': {e}\n{traceback.format_exc()}")
            return False

        return True


    def uploadFile(self, filePath, s3DestinationDir):
        self.logger.logDebug(f"S3Handler.uploadFile(): Uploading file {filePath} to bucket {self.bucket} / directory {s3DestinationDir}")

        try:
            s3ObjectName = s3DestinationDir + "/" + os.path.basename(filePath)

            sha256_hash = hashlib.sha256()
            with open(filePath, "rb") as f:
                for byte_block in iter(lambda: f.read(4096), b""):
                    sha256_hash.update(byte_block)
            local_checksum = sha256_hash.hexdigest()

            self.logger.logDebug(f"S3Handler.uploadFile(): Local SHA-256 checksum for {filePath}: {local_checksum}")
            self.s3Client.upload_file(filePath, self.bucket, s3ObjectName)
            self.logger.logInfo(f"S3Handler.uploadFile(): File: {filePath} uploaded to self.bucket: {self.bucket} / object: {s3ObjectName}")

            with tempfile.NamedTemporaryFile(delete=True) as tmp:
                self.s3Client.download_file(self.bucket, s3ObjectName, tmp.name)
                sha256_hash_s3 = hashlib.sha256()
                with open(tmp.name, "rb") as f:
                    for byte_block in iter(lambda: f.read(4096), b""):
                        sha256_hash_s3.update(byte_block)
                remote_checksum = sha256_hash_s3.hexdigest()
                self.logger.logDebug(f"S3Handler.uploadFile(): Remote SHA-256 checksum for {s3ObjectName} in bucket {self.bucket}: {remote_checksum}")

            if local_checksum != remote_checksum:
                self.logger.logError(f"S3Handler.uploadFile(): Checksum mismatch after upload! Local: {local_checksum}, S3: {remote_checksum}")
                return False
            else:
                self.logger.logDebug(f"S3Handler.uploadFile(): SHA-256 checksum validated: {local_checksum}")
        except Exception as e:
            self.logger.logError(f"S3Handler.uploadFile(): Error uploading file {filePath} to self.bucket: {self.bucket} / object: {s3ObjectName}: {e}\n{traceback.format_exc()}")
            return False

        return True

