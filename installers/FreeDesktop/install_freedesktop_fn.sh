#!/bin/bash -x

install_freedesktop() {
    # Installs the metadata and manifest and injects version number
    # Called via create_flatpak_fn and flatpak_postbuild_fn
    local -n output_ver_full="$1"  # Oolite version
    local build_folder="$2"  # oolite.app directory path (source)
    local app_folder="$3"  # app folder (destination)
    local symbol_folder="$4"  # debug symbol folder
    local metainfo_suffix="$5"  # can be appdata or metainfo

    local err_msg="❌ Error: Failed to install"

    source ../../ShellScripts/common/parse_manifest_fn.sh

    echo "Installing metainfo to $app_folder"

    local ver_quad githash buildtime app_date
    parse_manifest output_ver_full ver_quad githash buildtime app_date "$build_folder/Resources/manifest.plist"

    local freedesktopdir="../../installers/FreeDesktop"
    local appshr="$app_folder/share"
    local resourcesdir="$appshr/oolite/Resources"

    local app_metainfo="$appshr/metainfo/space.oolite.Oolite.$metainfo_suffix.xml"
    install -D "$freedesktopdir/space.oolite.Oolite.metainfo.xml.template" "$app_metainfo" || { echo "$err_msg metainfo template" >&2; return 1; }

    sed -i "s/@VER@/${output_ver_full}/g" "$app_metainfo"
    sed -i "s/@DATE@/${app_date}/g" "$app_metainfo"

    echo ===========================================
    echo Our manifest looks like this:
    cat "$app_metainfo"
    echo ===========================================

    # Desktop and Icon
    install -D "$freedesktopdir/space.oolite.Oolite.desktop" "$appshr/applications/space.oolite.Oolite.desktop" || { echo "$err_msg desktop file" >&2; return 1; }
    install -D "$build_folder/Resources/Textures/oolite-logo1.png" "$appshr/icons/hicolor/256x256/apps/space.oolite.Oolite.png" || { echo "$err_msg icon file" >&2; return 1; }
}