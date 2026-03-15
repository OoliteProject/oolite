#!/bin/bash

run_script() {
    # First parameter is a suffix for the build type eg. test, dev
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    mkdir -p ../../build
    cd ../../build
    source ../ShellScripts/Linux/os_detection.sh
    source ../ShellScripts/common/get_version.sh
    source ../ShellScripts/Linux/install_freedesktop_fn.sh
    source ../ShellScripts/common/check_rename_fn.sh

    APPDIR="./oolite.AppDir"
    APPBIN="$APPDIR/usr/bin"
    APPSHR="$APPDIR/usr/share"
    rm -rf "$APPDIR"

    ABS_APPDIR_USR=$(realpath -m "$APPDIR/usr")
    if ! install_freedesktop "$ABS_APPDIR_USR"; then
        return 1
    fi

   	if (( $# == 1 )); then
        echo "Including Basic-debug.oxp"
        cp -rf AddOns "$APPBIN"
    fi

    LINUXDEPLOY_BIN="./linuxdeploy"
    if [ ! -x "$LINUXDEPLOY_BIN" ]; then
        echo "📥 linuxdeploy not found or not executable. Downloading..."
        curl -o "$LINUXDEPLOY_BIN" -L https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage || { echo "❌ Download failed" >&2; exit 1; }
        chmod +x "$LINUXDEPLOY_BIN"
    fi

    case "$CURRENT_DISTRO" in
        debian) SDL2="--library=/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0" ;;
        redhat) SDL2="--library=/usr/lib64/libSDL2-2.0.so.0 --library=/usr/lib64/libSDL3.so.0" ;;
        arch) SDL2="--library=/usr/lib/libSDL2-2.0.so.0 --library=/usr/lib/libSDL3.so.0" ;;
    esac

    echo "Building AppDir for AppImage..."
    # install_metadatainfo_fn already put the files in the parameters below in the right place,
    # but no harm putting again here
    if ! NO_STRIP=1 ./linuxdeploy \
    --appdir "$APPDIR" \
    --executable "$APPBIN/oolite" \
    --custom-apprun "$APPBIN/run_oolite.sh" \
    --desktop-file "$APPSHR/applications/space.oolite.Oolite.desktop" \
    --icon-file "$APPSHR/icons/hicolor/256x256/apps/space.oolite.Oolite.png" \
    $SDL2; then
        echo "❌ AppDir generation failed!" >&2
        return 1
    fi

   	if [[ $1 == "dev" ]]; then
        echo "Not stripping libs for snapshot AppImage"
   	else
        echo "Stripping libs in AppDir..."
        find "$APPDIR/usr" -type f \
        \( -name '*.so' -o -name '*.so.*' \) \
        -exec strip --strip-unneeded '{}' +   # keeps symbols needed for runtime linking
    fi

    APPIMAGETOOL_BIN="./appimagetool"
    if [ ! -x "$APPIMAGETOOL_BIN" ]; then
        echo "📥 appimagetool not found. Downloading..."
        curl -o "$APPIMAGETOOL_BIN" -L https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage || { echo "❌ appimagetool download failed" >&2; exit 1; }
        chmod +x "$APPIMAGETOOL_BIN"
    fi

    echo "Creating AppImage..."
    if ! ./appimagetool $APPDIR; then
        echo "❌ AppImage creation failed!" >&2
        return 1
    fi

   	if (( $# == 1 )); then
        SUFFIX="_${1}-${VER_FULL}"
    else
        SUFFIX="-$VER_FULL"
    fi

    if ! check_rename "oolite" "oolite*.AppImage" $SUFFIX; then
        return 1
    fi

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

