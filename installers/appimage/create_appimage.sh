#!/bin/bash

run_script() {
    # First parameter which is a version with format maj.min.rev.githash (e.g. 1.91.0.7549-231111-cf99a82)
    # Second parameter is a suffix for the build type eg. test, dev
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ../../DevEnvironments/common/check_rename_fn.sh
    APPDIR="Oolite.AppDir"
    rm -rf $APPDIR
    mkdir -p $APPDIR/usr/bin

    PROGDIR="../../oolite.app"
    cp -rf $PROGDIR/Resources $APPDIR/usr/bin

    rm -f linuxdeploy-x86_64.AppImage
    wget https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
    chmod +x linuxdeploy-x86_64.AppImage
    if ! ./linuxdeploy-x86_64.AppImage \
    --appdir $APPDIR \
    --executable $PROGDIR/oolite \
    --desktop-file ../FreeDesktop/oolite.desktop \
    --icon-file ../FreeDesktop/oolite-icon.png \
    --output appimage; then
        echo "❌ AppImage creation failed!" >&2
        return 1
    fi

   	if (( $# == 2 )); then
        SUFFIX="${2}_${1}"
    else
        SUFFIX="$1"
    fi

    if ! check_rename "Oolite" "Oolite-*" $SUFFIX; then
        return 1
    fi
    popd
}

run_script $1 $2
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

