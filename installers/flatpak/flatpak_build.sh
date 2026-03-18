#!/bin/bash

source /app/share/GNUstep/Makefiles/GNUstep.sh
source ShellScripts/Linux/install_freedesktop_fn.sh

export ADDITIONAL_CFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
export ADDITIONAL_OBJCFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
make -f Makefile release-deployment -j$FLATPAK_BUILDER_N_JOBS

install_freedesktop /app metainfo
