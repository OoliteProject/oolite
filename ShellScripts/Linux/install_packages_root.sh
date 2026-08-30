#!/bin/bash -e

# This script must be run as root (for example with sudo).

run_script() {
    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    # Initialize local flags with defaults
    local INSTALL_CORE=true
    local INSTALL_APPIMAGE=false
    local INSTALL_FLATPAK=false
    local SCRIPT_DIR
    local pkgs
    local pkg
    local LIB_PARAM
    local BIN
    local LINTER_BIN
    local EXCLUDE_LIST

    # Parse Command Line Arguments
    if [[ "$#" -gt 0 ]]; then
        INSTALL_CORE=false
    fi

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --appimage)        INSTALL_APPIMAGE=true ;;
            --flatpak)         INSTALL_FLATPAK=true ;;
            --core)            INSTALL_CORE=true ;;
            --core+appimage|--core-appimage)
                INSTALL_CORE=true
                INSTALL_APPIMAGE=true
                ;;
            --core+flatpak|--core-flatpak)
                INSTALL_CORE=true
                INSTALL_FLATPAK=true
                ;;
            --all)
                INSTALL_CORE=true
                INSTALL_APPIMAGE=true
                INSTALL_FLATPAK=true
                ;;
            -h|--help)
                echo "Usage: ./install_deps_root.sh [options]"
                echo "Options:"
                echo "  --core           Install only base build dependencies (default if no args)"
                echo "  --appimage       Install only AppImage tools"
                echo "  --flatpak        Install only Flatpak tools"
                echo "  --core+appimage  Install base build dependencies + AppImage tools"
                echo "  --core+flatpak   Install base build dependencies + Flatpak tools"
                echo "  --all            Install everything"
                exit 0
                ;;
            *) echo "Unknown parameter: $1"; exit 1 ;;
        esac
        shift
    done

    if [[ "$INSTALL_CORE" == false && "$INSTALL_APPIMAGE" == false && "$INSTALL_FLATPAK" == false ]]; then
        INSTALL_CORE=true
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    source ./install_package_fn.sh
    source ../common/download_fn.sh
    source ./install_gitversion_fn.sh

    local outputdir="../../build"
    mkdir -p "$outputdir"

    if [[ "$INSTALL_CORE" == true ]]; then  # Core dependencies
        echo "📦 Installing Core Build Dependencies..."
        pkgs=(
            procps base-devel clang cmake jq meson gnutls-dev icu-dev ffi-dev xslt-dev png-dev zlib-dev nspr-dev
            espeak-ng-dev vorbis-dev openal-dev opengl-dev glu-dev sdl3 x11-dev
        )
        for pkg in "${pkgs[@]}"; do
            install_package "$pkg"
        done
        if ! python3 --version >/dev/null 2>&1; then  # Check Python
            install_package python
        fi
        install_gitversion "$outputdir"
        local espeak_folder="$(uname -m 2>/dev/null || echo x86_64)-linux-gnu"
        if [[ ! -d /usr/share/espeak-ng-data &&
              ! -d /usr/local/share/espeak-ng-data &&
              ! -d /usr/lib/$espeak_folder/espeak-ng-data ]]; then
            echo "❌ espeak-ng-data not in /usr/share, /usr/local/share or /usr/lib/$espeak_folder!"
            return 1
        fi
    fi

    if [[ "$INSTALL_APPIMAGE" == true ]]; then  # For building AppImage
        echo "📦 Installing AppImage Tools..."
        install_package appimage
        BIN="/usr/local/bin"
        download "https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh" "$BIN" "+x"
        download "https://raw.githubusercontent.com/AppImage/AppImages/master/appdir-lint.sh" "$BIN" "+x"
        download "https://raw.githubusercontent.com/AppImage/AppImages/master/excludelist" "$BIN"
        download "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage" "$BIN" "+x"
    fi

    if [[ "$INSTALL_FLATPAK" == true ]]; then  # For building Flatpak
        install_package flatpak
    fi

	popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

