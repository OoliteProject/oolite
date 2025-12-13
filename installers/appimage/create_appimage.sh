#!/bin/bash

run_script() {
#   Takes parameter which is a version with format maj.min.rev.githash (e.g. 1.91.0.7549-231111-cf99a82)
    pushd "$(dirname "$0")"
    source ../../DevEnvironments/common/check_rename_fn.sh

    APPDIR="Oolite.AppDir"
    rm -rf $APPDIR
    mkdir -p $APPDIR/usr/bin

    PROGDIR="../../oolite.app"
    cp -rf $PROGDIR/Resources $APPDIR/usr/bin

    if ! linuxdeploy \
    --appdir $APPDIR \
    --executable $PROGDIR/oolite \
    --desktop-file ../FreeDesktop/oolite.desktop \
    --icon-file ../FreeDesktop/oolite-icon.png \
    --output appimage; then
        echo "❌ AppImage creation failed!" >&2
        return 1
    fi

	read filename fullname <<< "$(check_rename "Oolite" "Oolite-*" $1)"
    popd
}

run_script $1
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

