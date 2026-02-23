import com.hp.siu.logging.*;
import com.hp.siu.utils.*;

class inputFileHandler {
    static fileName = "NONE"
    static numTickets = 0
}

inputFileHandler.numTickets = inputFileHandler.numTickets + 1

if (inputFileHandler.fileName.equals("NONE") || !inputFileHandler.fileName.equals(nme.inputFileName)) {
    logger.logDebug(">>>> handleNewInputFile.groovy: new input file detected: " + nme.inputFileName)
    nme.flagNewInputFile = 1
    nme.auditNumTickets = inputFileHandler.numTickets
    nme.auditFileName = inputFileHandler.fileName
    inputFileHandler.numTickets = 0
    inputFileHandler.fileName = nme.inputFileName

    try {
        def flagFile = new File("/var/opt/SIU/ctrl/currentInputFileName")
        flagFile.parentFile?.mkdirs()
        flagFile.withWriter('UTF-8') { it.write(nme.inputFileName) }
        logger.logDebug(">>>> handleNewInputFile.groovy: wrote flag file ${flagFile.absolutePath}")
    } catch (Exception e) {
        logger.logError(">>>> handleNewInputFile.groovy: failed to write flag file > " + e.message)
    }
}
