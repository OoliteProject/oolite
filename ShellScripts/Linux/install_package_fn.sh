#!/bin/bash

install_package() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source $script_dir/os_detection.sh

    local generic_name=$1
    local pkg_name=""

    # This CASE statement is the dictionary.
    # Add your packages here.
    case "$generic_name" in
        "git") pkg_name="git" ;;

        "base-devel")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="build-essential" ;;
                redhat) pkg_name="gcc gcc-c++ make" ;;
                arch) pkg_name="base-devel" ;;
            esac ;;

        "clang") pkg_name="clang lld lldb" ;;

        "cmake") pkg_name="cmake" ;;

        "meson")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="meson ninja-build" ;;
                redhat) pkg_name="meson ninja-build" ;;
                arch) pkg_name="meson ninja" ;;
            esac ;;

        "gnutls-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libgnutls28-dev" ;;
                redhat) pkg_name="gnutls-devel" ;;
                arch) pkg_name="gnutls" ;;
            esac ;;

        "python")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="python3-pip" ;;
                redhat) pkg_name="python3-pip" ;;
                arch) pkg_name="python-pip" ;;
            esac ;;

        "icu-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libicu-dev" ;;
                redhat) pkg_name="libicu-devel" ;;
                arch) pkg_name="icu" ;;
            esac ;;

        "ffi-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libffi-dev" ;;
                redhat) pkg_name="libffi-devel" ;;
                arch) pkg_name="libffi" ;;
            esac ;;

        "xslt-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libxml2-dev libxslt1-dev" ;;
                redhat) pkg_name="libxml2-devel libxslt-devel" ;;
                arch) pkg_name="libxml2 libxslt" ;;
            esac ;;

        "png-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libpng-dev" ;;
                redhat) pkg_name="libpng-devel" ;;
                arch)   pkg_name="libpng" ;;
            esac ;;

        "zlib-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="zlib1g-dev" ;;
                redhat) pkg_name="zlib-devel" ;;
                arch) pkg_name="zlib" ;;
            esac ;;

        "nspr-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libnspr4-dev" ;;
                redhat) pkg_name="nspr-devel" ;;
                arch) pkg_name="nspr" ;;
            esac ;;

        "espeak-ng-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libespeak-ng-dev" ;;
                redhat) pkg_name="espeak-ng-devel" ;;
                arch) pkg_name="espeak-ng" ;;
            esac ;;

        "vorbis-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libvorbis-dev" ;;
                redhat) pkg_name="libvorbis-devel" ;;
                arch) pkg_name="libvorbis" ;;
            esac ;;

        "openal-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libopenal-dev" ;;
                redhat) pkg_name="openal-soft-devel" ;;
                arch) pkg_name="openal" ;;
            esac ;;

        "opengl-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libgl-dev" ;;
                redhat) pkg_name="mesa-libGL-devel" ;;
                arch) pkg_name="libglvnd" ;;
            esac ;;

        "glu-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libglu1-mesa-dev" ;;
                redhat) pkg_name="mesa-libGLU-devel" ;;
                arch) pkg_name="glu" ;;
            esac ;;

	"sdl3")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libsdl3-dev" ;;
                redhat) pkg_name="SDL3-devel" ;;
		arch) pkg_name="sdl3";
            esac ;;

        "x11-dev")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="libx11-dev" ;;
                redhat) pkg_name="libX11-devel" ;;
                arch) pkg_name="libx11" ;;
            esac ;;

        "appimage")
            case "$CURRENT_DISTRO" in
                debian) pkg_name="file fuse3" ;;
                redhat) pkg_name="file fuse3 desktop-file-utils which zsync" ;;
                arch) pkg_name="file fuse3 desktop-file-utils zsync" ;;
            esac ;;

        "flatpak") pkg_name="flatpak flatpak-builder" ;;

        *)
            echo "❌ Could not translate '$generic_name' for $CURRENT_DISTRO!" >&2
            return 1
            ;;
    esac

    # Perform the Installation
    if [[ -z "$pkg_name" ]]; then
        echo "❌ Could not determine package name for $generic_name!" >&2
        return 1
    elif [[ "$pkg_name" == "NONE" ]]; then
        echo "⏭️ PKGNAME is set to NONE. Skipping install."
        return 0
    else
        echo "--> Installing $generic_name ($pkg_name)..."
        if ! "${INSTALL_CMD[@]}" $pkg_name; then
            echo "❌ Could not install $generic_name ($pkg_name)!" >&2
            return 1
        fi
    fi
}
