#!/bin/bash

run_script() {
    # First parameter is a suffix for the build type eg. test, dev
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    mkdir -p ../../build
    cd ../../build
    source ../ShellScripts/Linux/os_detection.sh
    source ../ShellScripts/common/get_version.sh
    source ../ShellScripts/Linux/install_freedesktop_fn.sh

    local ARCH=$(uname -m)
    local APPDIR="./oolite.AppDir"
    local APPBIN="$APPDIR/usr/bin"
    local APPSHR="$APPDIR/usr/share"
    rm -rf "$APPDIR"

    local ABS_APPDIR_USR=$(realpath -m "$APPDIR/usr")
    if ! install_freedesktop "$ABS_APPDIR_USR" bin appdata; then
        return 1
    fi

    local LINUXDEPLOY_BIN="./linuxdeploy"
    if [ ! -x "$LINUXDEPLOY_BIN" ]; then
        echo "📥 linuxdeploy not found or not executable. Downloading..."
        curl -o "$LINUXDEPLOY_BIN" -L https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage || { echo "❌ Download failed" >&2; exit 1; }
        chmod +x "$LINUXDEPLOY_BIN"
    fi

    case "$CURRENT_DISTRO" in
        debian) SDL2="--library=/usr/lib/$ARCH-linux-gnu/libSDL2-2.0.so.0" ;;
        redhat) SDL2="--library=/usr/lib64/libSDL2-2.0.so.0 --library=/usr/lib64/libSDL3.so.0" ;;
        arch) SDL2="--library=/usr/lib/libSDL2-2.0.so.0 --library=/usr/lib/libSDL3.so.0" ;;
    esac

    local ICON_SUBPATH="icons/hicolor/256x256/apps/space.oolite.Oolite.png"
    local ICON_PATH="$APPSHR/$ICON_SUBPATH"
    echo "Building AppDir for AppImage..."
    # install_metadatainfo_fn already put the files in the parameters below in the right place,
    # but no harm putting again here
    if ! NO_STRIP=1 ./linuxdeploy \
    --appdir "$APPDIR" \
    --executable "$APPBIN/oolite" \
    --custom-apprun "$APPBIN/run_oolite.sh" \
    --desktop-file "$APPSHR/applications/space.oolite.Oolite.desktop" \
    --icon-file "$ICON_PATH" \
    $SDL2; then
        echo "❌ AppDir generation failed!" >&2
        return 1
    fi
    ln -sf "usr/share/$ICON_SUBPATH" "$APPDIR/.DirIcon"

   	if [[ $1 == "dev" ]]; then
        echo "Not stripping libs for snapshot AppImage"
   	else
        echo "Stripping libs in AppDir..."
        find "$APPDIR/usr" -type f \
        \( -name '*.so' -o -name '*.so.*' \) \
        -exec strip --strip-unneeded '{}' +   # keeps symbols needed for runtime linking
    fi

    local LINTER_BIN="./appdir-lint.sh"
    local EXCLUDE_LIST="./excludelist"

    if [ ! -x "$LINTER_BIN" ] || [ ! -f "$EXCLUDE_LIST" ]; then
        echo "📥 Downloading AppDir linter and excludelist..."
        curl -o "$LINTER_BIN" -L https://raw.githubusercontent.com/AppImage/AppImages/master/appdir-lint.sh || { echo "❌ Linter download failed" >&2; exit 1; }
        curl -o "$EXCLUDE_LIST" -L https://raw.githubusercontent.com/AppImage/AppImages/master/excludelist || { echo "❌ Excludelist download failed" >&2; exit 1; }
        chmod +x "$LINTER_BIN"
    fi

    echo "🔍 Running AppDir linter..."
    if ! "$LINTER_BIN" "$APPDIR"; then
        echo "❌ AppDir linting failed!" >&2
        return 1
    fi

    local APPIMAGETOOL_BIN="./appimagetool"
    if [ ! -x "$APPIMAGETOOL_BIN" ]; then
        echo "📥 appimagetool not found. Downloading..."
        curl -o "$APPIMAGETOOL_BIN" -L https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage || { echo "❌ appimagetool download failed" >&2; exit 1; }
        chmod +x "$APPIMAGETOOL_BIN"
    fi

    local SUFFIX
   	if (( $# == 1 )); then
        SUFFIX="_${1}-${VER_FULL}"
    else
        SUFFIX="-$VER_FULL"
    fi
    local FILENAME="oolite${SUFFIX}-${ARCH}.AppImage"
    echo "Creating AppImage $FILENAME..."
    if ! ./appimagetool "$APPDIR" "$FILENAME"; then
        echo "❌ AppImage creation failed!" >&2
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

