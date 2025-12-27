#!/bin/bash

run_script() {
    # First parameter which is a version with format maj.min.rev.githash (e.g. 1.91.0.7549-231111-cf99a82)
    # Second parameter is a suffix for the build type eg. test, dev
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    mkdir -p ../../build
    cd ../../build
    source ../ShellScripts/Linux/os_detection.sh
    source ../ShellScripts/common/check_rename_fn.sh

    APPDIR="./Oolite.AppDir"
    rm -rf $APPDIR
    mkdir -p $APPDIR/usr/bin

    PROGDIR="../oolite.app"
    cp -rf $PROGDIR/Resources $APPDIR/usr/bin

    curl -o linuxdeploy -L https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
    chmod +x linuxdeploy

    case "$CURRENT_DISTRO" in
        debian) SDL2="--library=/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0" ;;
        redhat) SDL2="--library=/usr/lib64/libSDL2-2.0.so.0 --library=/usr/lib64/libSDL3.so.0" ;;
        arch) SDL2="--library=/usr/lib/libSDL2-2.0.so.0 --library=/usr/lib/libSDL3.so.0" ;;
    esac

    echo "Building AppDir for AppImage..."
    if ! NO_STRIP=1 ./linuxdeploy \
    --appdir $APPDIR \
    --executable $PROGDIR/oolite \
    --desktop-file ../installers/FreeDesktop/oolite.desktop \
    --icon-file ../installers/FreeDesktop/oolite-icon.png \
    $SDL2; then
        echo "❌ AppDir generation failed!" >&2
        return 1
    fi

   	if (( $# == 2 )) && [[ $2 == "dev" ]]; then
        echo "Not stripping libs for snapshot AppImage"
   	else
        echo "Stripping libs in AppDir..."
        find "$APPDIR/usr" -type f \
        \( -name '*.so' -o -name '*.so.*' \) \
        -exec strip --strip-unneeded '{}' +   # keeps symbols needed for runtime linking
    fi

    curl -o appimagetool -L https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool

    echo "Creating AppImage..."
    if ! ./appimagetool $APPDIR; then
        echo "❌ AppImage creation failed!" >&2
        return 1
    fi

   	if (( $# == 2 )); then
        SUFFIX="${2}_${1}"
    else
        SUFFIX="$1"
    fi

    if ! check_rename "Oolite" "Oolite-*" $SUFFIX; then
        return 1
    fi
    # shellcheck disable=SC2164
    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

