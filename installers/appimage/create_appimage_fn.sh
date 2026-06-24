#!/bin/bash -x
#
# Creates the appimage.
# First parameter can be set to build type, typically one of "test", "dev" or omitted for release builds.
#

create_appimage() {
    # First parameter is a suffix for the build type eg. test, dev
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    mkdir -p ../../build
    cd ../../build
    source ../ShellScripts/Linux/os_detection.sh
    source ../ShellScripts/common/get_version.sh
    source ../ShellScripts/Linux/install_freedesktop_fn.sh

    local arch=$(uname -m)
    local APPDIR="./oolite.AppDir"
    export APPDIR
    local appbin="$APPDIR/bin"
    local appshr="$APPDIR/share"
    rm -rf "$APPDIR"

    local abs_oolitedir=$(realpath -m "$1")
    local abs_appdir=$(realpath -m "$APPDIR")
    if ! install_freedesktop "$abs_oolitedir" "$abs_appdir" bin appdata; then
        return 1
    fi

    local sharun_bin="./quick-sharun"
    if [[ ! -x "$sharun_bin" ]]; then
        echo "📥 quick-sharun not found or not executable. Downloading..."
        curl -o "$sharun_bin" -L https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh || { echo "❌ Download failed" >&2; exit 1; }
        chmod +x "$sharun_bin"
    fi

    local icon_filename="space.oolite.Oolite.png"
    local icon_subpath="icons/hicolor/256x256/apps/$icon_filename"
    local ICON="$appshr/$icon_subpath"
    export ICON
    local DESKTOP="$appshr/applications/space.oolite.Oolite.desktop"
    export DESKTOP
    local suffix
   	if (( $# == 2 )); then
        suffix="_${2}-${VER_FULL}"
    else
        suffix="-$VER_FULL"
    fi
    local OUTNAME="oolite${suffix}-${arch}.AppImage"
    export OUTNAME

    echo "Building AppDir for AppImage..."

    local DEPLOY_OPENGL=0
    export DEPLOY_OPENGL
    local DEPLOY_VULKAN=0
    export DEPLOY_VULKAN
    local DEPLOY_LOCALE=0
    export DEPLOY_LOCALE
    local STRACE_MODE=0
    export STRACE_MODE

    # install_metadatainfo_fn already put the files in the parameters below in the right place,
    # but no harm putting again here
    if ! $sharun_bin "$appbin/oolite"; then
        echo "❌ AppDir generation failed!" >&2
        return 1
    fi

    local linter_bin="./appdir-lint.sh"
    local exclude_list="./excludelist"

    if [[ ! -x "$linter_bin" ]] || [[ ! -f "$exclude_list" ]]; then
        echo "📥 Downloading AppDir linter and excludelist..."
        curl -o "$linter_bin" -L https://raw.githubusercontent.com/AppImage/AppImages/master/appdir-lint.sh || { echo "❌ Linter download failed" >&2; return 1; }
        curl -o "$exclude_list" -L https://raw.githubusercontent.com/AppImage/AppImages/master/excludelist || { echo "❌ Excludelist download failed" >&2; return 1; }
        chmod +x "$linter_bin"
    fi

    echo "🔍 Running AppDir linter..."
    if ! "$linter_bin" "$APPDIR"; then
        echo "❌ AppDir linting failed!" >&2
        return 1
    fi

    appimagetool_bin="./appimagetool"
    if [ ! -x "$appimagetool_bin" ]; then
        echo "📥 appimagetool not found. Downloading..."
        curl -o "$appimagetool_bin" -L https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$arch.AppImage || { echo "❌ appimagetool download failed" >&2; return 1; }
        chmod +x "$appimagetool_bin"
    fi

    echo "Creating AppImage $OUTNAME..."
    if ! $appimagetool_bin "$abs_appdir" "$OUTNAME"; then
        echo "❌ AppImage creation failed!" >&2
        return 1
    fi

    popd
}
