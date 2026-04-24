#!/bin/bash

install_freedesktop() {
    # Install metainfo (eg. for FlatHub and AppImageHub)
    # $1: app folder (destination)
    # $2: debug symbol folder
    # $3: appdata or metainfo

    local err_msg="❌ Error: Failed to"

    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ../common/get_version.sh

    echo "Installing metainfo to to $1"

    local PROGDIR="../../oolite.app"
    local APPBIN="$1/bin"
    local APPSHR="$1/share"

    # Install binaries and scripts
    install -D "$PROGDIR/oolite" "$APPBIN/oolite" || { echo "$err_msg install oolite binary" >&2; return 1; }
    if [[ -f "$PROGDIR/oolite.debug" ]]; then
        install -D "$PROGDIR/oolite.debug" "$1/$2/oolite.debug" || { echo "$err_msg install oolite debug symbols" >&2; return 1; }
    fi
    install -D "$PROGDIR/run_oolite.sh" "$APPBIN/run_oolite.sh" || { echo "$err_msg install run_oolite.sh" >&2; return 1; }
    install -D "$PROGDIR/splash-launcher" "$APPBIN/splash-launcher" || { echo "$err_msg install splash-launcher" >&2; return 1; }

    # Resources copy
    mkdir -p "$APPBIN/Resources"
    cp -rf "$PROGDIR/Resources/." "$APPBIN/Resources/" || { echo "$err_msg copy Resources folder" >&2; return 1; }

    # AddOns copy if folder exists in oolite.app
    if [ -d "$PROGDIR/AddOns" ]; then
        mkdir -p "$APPBIN/AddOns"
        cp -rf "$PROGDIR/AddOns/." "$APPBIN/AddOns/" || { echo "$err_msg copy AddOns folder" >&2; return 1; }
    fi

    install -D "GNUstep.conf.template" "$APPBIN/Resources/GNUstep.conf.template" || { echo "$err_msg GNUstep template" >&2; return 1; }

    APP_METAINFO="$APPSHR/metainfo/space.oolite.Oolite.$3.xml"
    install -D ../../installers/FreeDesktop/space.oolite.Oolite.metainfo.xml.template "$APP_METAINFO" || { echo "$err_msg metainfo template" >&2; return 1; }

    sed -i "s/@VER@/${VERSION}/g" "$APP_METAINFO"
    sed -i "s/@DATE@/${APP_DATE}/g" "$APP_METAINFO"

    # Desktop and Icon
    install -D ../../installers/FreeDesktop/space.oolite.Oolite.desktop "$APPSHR/applications/space.oolite.Oolite.desktop" || { echo "$err_msg desktop file" >&2; return 1; }

    install -D "$PROGDIR/Resources/Textures/oolite-logo1.png" "$APPSHR/icons/hicolor/256x256/apps/space.oolite.Oolite.png" || { echo "$err_msg icon file" >&2; return 1; }

    popd
}