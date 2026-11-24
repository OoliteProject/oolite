#!/bin/bash -e

# Installs all required packages and dependencies. This script must be run as root (for example with sudo).

run_script() {
    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    # Initialize local flags with defaults
    local INSTALL_CORE=true
    local INSTALL_DOCKER=false
    local INSTALL_APPIMAGE_ARCH=false
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
            --appimage)        INSTALL_DOCKER=true ;;  # mk.sh pkg-appimage builds in a container
            --appimage-arch)   INSTALL_APPIMAGE_ARCH=true ;;
            --flatpak)         INSTALL_FLATPAK=true ;;
            --core)            INSTALL_CORE=true ;;
            --core+appimage|--core-appimage)
                INSTALL_CORE=true
                INSTALL_DOCKER=true
                ;;
            --core+appimage-arch|--core-appimage-arch)
                INSTALL_CORE=true
                INSTALL_APPIMAGE_ARCH=true
                ;;
            --core+flatpak|--core-flatpak)
                INSTALL_CORE=true
                INSTALL_FLATPAK=true
                ;;
            --all)
                INSTALL_CORE=true
                INSTALL_DOCKER=true
                INSTALL_FLATPAK=true
                ;;
            -h|--help)
                echo "Usage: ./install_deps_root.sh [options]"
                echo "Options:"
                echo "  --core                Install only base build dependencies (default if no args)"
                echo "  --appimage            Install only Docker, which ./mk.sh pkg-appimage needs"
                echo "  --appimage-arch       Install only the AppImage tools (see below)"
                echo "  --flatpak             Install only Flatpak tools"
                echo "  --core+appimage       Install base build dependencies + Docker"
                echo "  --core+appimage-arch  Install base build dependencies + the AppImage tools (see below)"
                echo "  --core+flatpak        Install base build dependencies + Flatpak tools"
                echo "  --all                 Install base build dependencies + Docker + Flatpak tools"
                echo "The AppImage tools are only installed in a throwaway Arch container (INSTALL_LIBDECOR_MINI=true),"
                echo "because they replace the system libdecor. To build an AppImage, use ./mk.sh pkg-appimage."
                exit 0
                ;;
            *) echo "Unknown parameter: $1"; exit 1 ;;
        esac
        shift
    done

    if [[ "$INSTALL_CORE" == false && "$INSTALL_DOCKER" == false && "$INSTALL_APPIMAGE_ARCH" == false && "$INSTALL_FLATPAK" == false ]]; then
        INSTALL_CORE=true
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    source ./install_package_fn.sh
    source ../common/download_fn.sh
    source ./install_libdecor_fn.sh

    if [[ "$INSTALL_APPIMAGE_ARCH" == true ]]; then  # check before installing anything
        require_install_libdecor_mini || { popd > /dev/null; return 1; }
    fi

    local outputdir="../../build"
    mkdir -p "$outputdir"

    if [[ "$INSTALL_CORE" == true ]]; then  # Core dependencies
        echo "📦 Installing Core Build Dependencies..."
        if ! python3 --version >/dev/null 2>&1; then  # Check Python
            install_package python
        fi
        pkgs=(
            procps base-devel clang cmake jq meson gnutls-dev icu-dev ffi-dev xslt-dev png-dev zlib-dev nspr-dev
            espeak-ng-dev vorbis-dev openal-dev opengl-dev glu-dev sdl3 x11-dev
            doxygen
        )
        for pkg in "${pkgs[@]}"; do
            install_package "$pkg"
        done
        source ./install_gitversion_fn.sh && install_gitversion /usr/local/bin "$outputdir"
        local espeak_folder="$(uname -m 2>/dev/null || echo x86_64)-linux-gnu"
        if [[ ! -d "/usr/share/espeak-ng-data" &&
              ! -d "/usr/local/share/espeak-ng-data" &&
              ! -d "/usr/lib/$espeak_folder/espeak-ng-data" ]]; then
            echo "❌ espeak-ng-data not in /usr/share, /usr/local/share or /usr/lib/$espeak_folder!"
            return 1
        fi
        source ./install_typst_fn.sh && install_typst /usr/local/bin "$outputdir"
    fi

    if [[ "$INSTALL_DOCKER" == true ]]; then  # For building AppImage in a container
        source ./install_docker_fn.sh
        install_docker || return 1
    fi

    if [[ "$INSTALL_APPIMAGE_ARCH" == true ]]; then  # For building AppImage inside that container
        echo "📦 Installing AppImage Tools..."
        install_package appimage-arch
        BIN="/usr/local/bin"
        # quick-sharun.sh and get-debloated-pkgs.sh are pinned to one Anylinux-AppImages commit, because a change
        # to quick-sharun can break the AppImage without any change here (#793). To update: try the latest commit
        # from https://github.com/pkgforge-dev/Anylinux-AppImages/commits/main, build the AppImage with
        # build_appimage_container.sh, check that the game starts with a title bar on GNOME Wayland and X11,
        # then change the hash below. The libdecor-mini package itself is not pinned (install_libdecor_fn.sh).
        local anylinux="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/7cb538a024588e29de89c2cea19cee8c9eca31c7/useful-tools"
        download "$anylinux/quick-sharun.sh" "$BIN/quick-sharun.sh" "+x"
        download "$anylinux/get-debloated-pkgs.sh" "$BIN/get-debloated-pkgs.sh" "+x"
        download "https://raw.githubusercontent.com/AppImage/AppImages/master/appdir-lint.sh" "$BIN/appdir-lint.sh" "+x"
        download "https://raw.githubusercontent.com/AppImage/AppImages/master/excludelist" "$BIN/excludelist"
        local appimage_filename="appimagetool-$(uname -m).AppImage"
        download "https://github.com/AppImage/appimagetool/releases/download/continuous/$appimage_filename" "$BIN/$appimage_filename" "+x"
        install_libdecor || return 1
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

