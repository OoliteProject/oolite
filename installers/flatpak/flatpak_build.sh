#!/bin/bash -x
#
# Prepares the app directory for the flatpak builder
#

echo "I am flatpak_build.sh $@"
printenv | sort

source /app/share/GNUstep/Makefiles/GNUstep.sh
source ShellScripts/common/get_version.sh
source ShellScripts/Linux/install_freedesktop_fn.sh

export ADDITIONAL_CFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
export ADDITIONAL_OBJCFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
make -f Makefile release-deployment -j$FLATPAK_BUILDER_N_JOBS

ABS_OOLITEDIR=$(realpath -m "build/meson_deployment/oolite.app")
install_freedesktop $ABS_OOLITEDIR /app lib/debug/bin metainfo
# Ensure the destination directory exists
mkdir -p /app/lib/debug/source/oolite
# Copy the src directory recursively
cp -r src /app/lib/debug/source/oolite/ || {
    echo "❌ $err_msg install oolite source code" >&2
    return 1
}
