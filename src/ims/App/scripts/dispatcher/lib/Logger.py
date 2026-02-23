# -------------------------------------------------------------------------------
# Logger - Library for logging messages handling
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

#
# Imports
#

from datetime import datetime
from zoneinfo import ZoneInfo

import os
import sys


#
# Classes
#

class LogLevels:
  INFO = 4
  DEBUG = 5
  DEBUG2 = 6
  DEBUG3 = 7
  DEBUG4 = 8


class LogModes:
  CONSOLE_AND_FILE = 0
  CONSOLE_ONLY = 1
  FILE_ONLY = 2


class Logger:
    LOG_LEVELS = { LogLevels.INFO, LogLevels.DEBUG, LogLevels.DEBUG2, LogLevels.DEBUG3, LogLevels.DEBUG4 }
    LOG_MODES = { LogModes.CONSOLE_ONLY, LogModes.FILE_ONLY, LogModes.CONSOLE_AND_FILE }

    def __init__(self, filePath = None, label = "", logMode = LogModes.CONSOLE_ONLY, logLevel = LogLevels.INFO):
        self.label = label
        self.logLevel = logLevel
        self.logMode = logMode
        self.filePath = filePath
        if filePath is None:
            self.logMode = LogModes.CONSOLE_ONLY
            self.fOut = None
        else:
            try:
                self.fOut = open(self.filePath, "a")
            except Exception as e:
                print(f"Logger.__init__(): Error opening log file: {self.filePath}: {e}. Setting logMode to CONSOLE only.")
                self.fOut = None
                self.logMode = LogModes.CONSOLE_ONLY


    def close(self):
        try:
            if self.fOut is not None:
                self.fOut.close()
        except Exception as e:
            print(f"Logger.close(): Error closing log file: {self.filePath}: {e}")


    def log(self, message, labelSize = 32):
        pid = os.getpid()
        ppid = os.getppid()
        auxLabel = f"{self.label}".ljust(labelSize)
        now = datetime.now(ZoneInfo("Europe/Paris"))
        txt = f"{now.strftime('%Y-%m-%d %H:%M:%S %Z')} {auxLabel} {message} [pid:{pid} ppid:{ppid}]"

        if self.logMode in [LogModes.CONSOLE_ONLY, LogModes.CONSOLE_AND_FILE]:
            print(txt)
            sys.stdout.flush()

        if self.logMode in [LogModes.CONSOLE_AND_FILE, LogModes.FILE_ONLY]:
            self.fOut.write(f"{txt}\n")
            self.fOut.flush()


    def logDebug(self, message):
        if self.logLevel >= LogLevels.DEBUG:
            self.log(f"[DBG] {message}")
        else:
            self.log(f"[DBG] {message}")


    def logDebug2(self, message):
        if self.logLevel >= LogLevels.DEBUG2:
            self.log(f"[DG2] {message}")


    def logDebug3(self, message):
        if self.logLevel >= LogLevels.DEBUG3:
            self.log(f"[DG3] {message}")


    def logDebug4(self, message):
        if self.logLevel >= LogLevels.DEBUG4:
            self.log(f"[DG4] {message}")


    def logError(self, message):
        self.log(f"[ERR] {message}")


    def logInfo(self, message):
        self.log(f"[INF] {message}")


    def logWarning(self, message):
        self.log(f"[WRN] {message}")
