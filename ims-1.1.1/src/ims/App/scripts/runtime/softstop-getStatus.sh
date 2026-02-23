#!/bin/bash
# -------------------------------------------------------------------------------
# softstop-getStatus.sh
#
# HCL Tech / CTG - 2025
# -------------------------------------------------------------------------------

if [ -f /var/opt/SIU/ctrl/flag.softstop.completed ]; then
    echo SOFTSTOP_COMPLETED
    exit 0
fi

if [ -f /var/opt/SIU/ctrl/flag.softstop.acknowledged ]; then
    echo SOFTSTOP_ACKNOWLEDGED
    exit 0
fi

if [ ! -f /var/opt/SIU/ctrl/flag.softstop ]; then
    echo SOFTSTOP_NOT_REQUESTED
    exit 0
fi

if [ -f /var/opt/SIU/ctrl/currentInputFileName ]; then
    echo SOFTSTOP_NOT_ACKNOWLEDGED
    exit 0
fi

echo SOFTSTOP_COMPLETED

exit 0
