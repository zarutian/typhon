#!/bin/sh
TYPHON_LOCATION=$1
MT_TYPHON=$TYPHON_LOCATION/mt-typhon
TYPHON_LIBS="-l $TYPHON_LOCATION -l $TYPHON_LOCATION/mast"
TYPHON_RUNNER="$TYPHON_LOCATION/loader run"
MODULE=$2

$MT_TYPHON $TYPHON_LIBS $TYPHON_RUNNER "$MODULE"
