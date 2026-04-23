#!/bin/bash

source /app/share/GNUstep/Makefiles/GNUstep.sh
source ShellScripts/common/get_version.sh
source ShellScripts/Linux/install_freedesktop_fn.sh

export ADDITIONAL_CFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
export ADDITIONAL_OBJCFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
make -f Makefile release-deployment -j$FLATPAK_BUILDER_N_JOBS

install_freedesktop /app lib/debug/bin metainfo
# Ensure the destination directory exists
mkdir -p /app/lib/debug/source/oolite
# Copy the src directory recursively
cp -r src /app/lib/debug/source/oolite/ || {
    echo "❌ $err_msg install oolite source code" >&2
    return 1
}
