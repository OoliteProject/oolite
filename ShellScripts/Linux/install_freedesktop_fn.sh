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

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ../common/get_version.sh

    echo "Installing metainfo to to $2"

    local appbin="$2/bin"
    local appshr="$2/share"

    # Install binaries and scripts
    install -D "$1/oolite" "$appbin/oolite" || { echo "$err_msg install oolite binary" >&2; return 1; }
    if [[ -f "$1/oolite.debug" ]]; then
        install -D "$1/oolite.debug" "$2/$3/oolite.debug" || { echo "$err_msg install oolite debug symbols" >&2; return 1; }
    fi
    install -D "$1/run_oolite.sh" "$appbin/run_oolite.sh" || { echo "$err_msg install run_oolite.sh" >&2; return 1; }

    # Resources copy
    local resourcesdir="$appshr/oolite/Resources"
    mkdir -p "$resourcesdir"
    cp -rf "$1/Resources/." "$resourcesdir/" || { echo "$err_msg copy Resources folder" >&2; return 1; }

    # AddOns copy if folder exists in oolite.app
    if [ -d "$1/AddOns" ]; then
        local addonsdir="$appshr/oolite/AddOns"
        mkdir -p "$addonsdir"
        cp -rf "$1/AddOns/." "$addonsdir/" || { echo "$err_msg copy AddOns folder" >&2; return 1; }
    fi

    rm -f "$resourcesdir/GNUstep.conf.orig"
    install -D "GNUstep.conf.template" "$resourcesdir/GNUstep.conf.template" || { echo "$err_msg GNUstep template" >&2; return 1; }

    local app_metainfo="$appshr/metainfo/space.oolite.Oolite.$4.xml"
    install -D ../../installers/FreeDesktop/space.oolite.Oolite.metainfo.xml.template "$app_metainfo" || { echo "$err_msg metainfo template" >&2; return 1; }

    sed -i "s/@VER@/${VERSION}/g" "$app_metainfo"
    sed -i "s/@DATE@/${APP_DATE}/g" "$app_metainfo"

    echo ===========================================
    echo Our manifest looks like this:
    cat "$app_metainfo"
    echo ===========================================

    # Desktop and Icon
    install -D ../../installers/FreeDesktop/space.oolite.Oolite.desktop "$appshr/applications/space.oolite.Oolite.desktop" || { echo "$err_msg desktop file" >&2; return 1; }

    install -D "$1/Resources/Textures/oolite-logo1.png" "$appshr/icons/hicolor/256x256/apps/space.oolite.Oolite.png" || { echo "$err_msg icon file" >&2; return 1; }

    popd
}