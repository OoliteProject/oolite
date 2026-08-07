#!/bin/bash -ex
#
# Creates the appimage.

create_appimage() {
    local build_type="$1"  # Typically one of "deployment", "test", "dev"
    local build_folder="$2"  # Build folder

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"
    source ../FreeDesktop/install_freedesktop_fn.sh

    cd ../../build/appimage
    local arch=$(uname -m)
    local APPDIR="./oolite.AppDir"
    export APPDIR
    local appbin="$APPDIR/bin"
    local appshr="$APPDIR/share"

    if ! install_freedesktop ver_full "../$build_folder" "$APPDIR" "bin" "appdata"; then
        return 1
    fi

    local icon_filename="space.oolite.Oolite.png"
    local icon_subpath="icons/hicolor/256x256/apps/$icon_filename"
    local ICON="$appshr/$icon_subpath"
    export ICON
    local DESKTOP="$appshr/applications/space.oolite.Oolite.desktop"
    export DESKTOP
    local OUTNAME="Oolite-$ver_full-$build_type-$arch.AppImage"
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
    if ! quick-sharun.sh "$appbin/oolite"; then
        echo "❌ AppDir generation failed!" >&2
        return 1
    fi

    echo "🔍 Running AppDir linter..."
    if ! appdir-lint.sh "$APPDIR"; then
        echo "❌ AppDir linting failed!" >&2
        return 1
    fi

    appimagetool_bin="appimagetool-$arch.AppImage"
    echo "Creating AppImage $OUTNAME..."
    if ! $appimagetool_bin "$APPDIR" "../$OUTNAME"; then
        echo "❌ AppImage creation failed!" >&2
        return 1
    fi

    popd
}
