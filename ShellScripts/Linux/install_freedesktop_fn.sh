#!/bin/bash -x
#
# Installs the manifest and injects version number
#
# Requires environment variables:
#   VERSION
#   APP_DATE
#

echo "I am install_freedesktop_fn.sh $@"
printenv | sort

install_freedesktop() {
    # Install metainfo (eg. for FlatHub and AppImageHub)
    # $1: oolite.app directory path (source)
    # $2: app folder (destination)
    # $3: debug symbol folder
    # $4: appdata or metainfo

    local err_msg="❌ Error: Failed to"

    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ../common/get_version.sh

    echo "Installing metainfo to to $2"

    local APPBIN="$2/bin"
    local APPSHR="$2/share"

    # Install binaries and scripts
    install -D "$1/oolite" "$APPBIN/oolite" || { echo "$err_msg install oolite binary" >&2; return 1; }
    if [[ -f "$1/oolite.debug" ]]; then
        install -D "$1/oolite.debug" "$2/$3/oolite.debug" || { echo "$err_msg install oolite debug symbols" >&2; return 1; }
    fi
    install -D "$1/run_oolite.sh" "$APPBIN/run_oolite.sh" || { echo "$err_msg install run_oolite.sh" >&2; return 1; }

    # Resources copy
    mkdir -p "$APPBIN/Resources"
    cp -rf "$1/Resources/." "$APPBIN/Resources/" || { echo "$err_msg copy Resources folder" >&2; return 1; }

    # AddOns copy if folder exists in oolite.app
    if [ -d "$1/AddOns" ]; then
        mkdir -p "$APPBIN/AddOns"
        cp -rf "$1/AddOns/." "$APPBIN/AddOns/" || { echo "$err_msg copy AddOns folder" >&2; return 1; }
    fi

    rm -f "$APPBIN/Resources/GNUstep.conf.orig"
    install -D "GNUstep.conf.template" "$APPBIN/Resources/GNUstep.conf.template" || { echo "$err_msg GNUstep template" >&2; return 1; }

    APP_METAINFO="$APPSHR/metainfo/space.oolite.Oolite.$4.xml"
    install -D ../../installers/FreeDesktop/space.oolite.Oolite.metainfo.xml.template "$APP_METAINFO" || { echo "$err_msg metainfo template" >&2; return 1; }

    sed -i "s/@VER@/${VERSION}/g" "$APP_METAINFO"
    sed -i "s/@DATE@/${APP_DATE}/g" "$APP_METAINFO"

    echo ===========================================
    echo Our manifest looks like this:
    cat "$APP_METAINFO"
    echo ===========================================

    # Desktop and Icon
    install -D ../../installers/FreeDesktop/space.oolite.Oolite.desktop "$APPSHR/applications/space.oolite.Oolite.desktop" || { echo "$err_msg desktop file" >&2; return 1; }

    install -D "$1/Resources/Textures/oolite-logo1.png" "$APPSHR/icons/hicolor/256x256/apps/space.oolite.Oolite.png" || { echo "$err_msg icon file" >&2; return 1; }

    popd
}