#!/bin/sh
TYPHON_LOCATION=$1
MT_TYPHON=./$TYPHON_LOCATION/mt-typhon
TYPHON_LIBS="-l $TYPHON_LOCATION/boot -l $TYPHON_LOCATION"
TYPHON_BAKER="$TYPHON_LOCATION/loader run montec -mix"
SOURCE=$2

$MT_TYPHON $TYPHON_LIBS $TYPHON_BAKER "$SOURCE" "${SOURCE%.mt}.mast"
