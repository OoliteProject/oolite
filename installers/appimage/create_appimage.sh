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
    export APPDIR
    local APPBIN="$APPDIR/bin"
    local APPSHR="$APPDIR/share"
    rm -rf "$APPDIR"

    local ABS_APPDIR=$(realpath -m "$APPDIR")
    if ! install_freedesktop "$ABS_APPDIR" bin appdata; then
        return 1
    fi

    local SHARUN_BIN="./quick-sharun"
    if [[ ! -x "$SHARUN_BIN" ]]; then
        echo "📥 quick-sharun not found or not executable. Downloading..."
        curl -o "$SHARUN_BIN" -L https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh || { echo "❌ Download failed" >&2; exit 1; }
        chmod +x "$SHARUN_BIN"
    fi

    local ICON_FILENAME="space.oolite.Oolite.png"
    local ICON_SUBPATH="icons/hicolor/256x256/apps/$ICON_FILENAME"
    local ICON="$APPSHR/$ICON_SUBPATH"
    export ICON
    local DESKTOP="$APPSHR/applications/space.oolite.Oolite.desktop"
    export DESKTOP
    local SUFFIX
   	if (( $# == 1 )); then
        SUFFIX="_${1}-${VER_FULL}"
    else
        SUFFIX="-$VER_FULL"
    fi
    local OUTNAME="oolite${SUFFIX}-${ARCH}.AppImage"
    export OUTNAME

    echo "Building AppDir for AppImage..."

    local DEPLOY_OPENGL=0
    export DEPLOY_OPENGL
    local DEPLOY_VULKAN=0
    export DEPLOY_VULKAN
    local DEPLOY_LOCALE=0
    export DEPLOY_LOCALE
    # install_metadatainfo_fn already put the files in the parameters below in the right place,
    # but no harm putting again here
    if ! $SHARUN_BIN "$APPBIN/run_oolite.sh"; then
        echo "❌ AppDir generation failed!" >&2
        return 1
    fi

    local LINTER_BIN="./appdir-lint.sh"
    local EXCLUDE_LIST="./excludelist"

    if [[ ! -x "$LINTER_BIN" ]] || [[ ! -f "$EXCLUDE_LIST" ]]; then
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

    echo "Creating AppImage $OUTNAME..."
    if ! $SHARUN_BIN --make-appimage; then
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

