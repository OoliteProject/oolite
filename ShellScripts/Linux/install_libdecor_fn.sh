#!/bin/bash

# Installs libdecor-mini, the libdecor that the AppImage bundles. Called via install_packages_root.sh.
#
# SDL3 needs libdecor to draw the game window's title bar on GNOME Wayland (#793). quick-sharun bundles libdecor
# from the system library folder, so the build machine must have the libdecor we want to ship: libdecor-mini
# (libdecor-rs). It draws its own title bar and needs only glibc, so the AppImage works without the player's
# libdecor plugins and never loads GTK.
#
# get-debloated-pkgs.sh installs it with pacman --ask 4, which REPLACES the system libdecor, so every other program
# on the machine uses libdecor-mini too. That is only done where INSTALL_LIBDECOR_MINI=true: in the
# archlinux container of the build-appimage CI job, and in the container of build_appimage_container.sh, which is
# how developers build the AppImage (mk.sh pkg-appimage). Both containers are deleted afterwards, and both build the AppImage the same
# way. Never set the flag on a machine you keep.
#
# Why a flag of our own rather than CI=true: CI=true says "running under a CI system", not "this machine is thrown
# away afterwards". Every CI system sets it, including self-hosted runners, which are real machines, and some
# developers export CI=true in their shells to make tools non-interactive. Replacing a system library has to be
# asked for explicitly, by whatever knows its machine is disposable.
#
# The libdecor-mini package is not pinned: each build takes the current one (#793). The log shows its version.

require_install_libdecor_mini() {
    # Stops before anything is installed if this machine may not get libdecor-mini.
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/os_detection.sh"

    if [[ "${INSTALL_LIBDECOR_MINI:-}" != "true" ]]; then
        echo "❌ The AppImage tools are only installed in a throwaway container, because they replace the system" >&2
        echo "   libdecor with libdecor-mini. To build the AppImage, run:" >&2
        echo "     ./mk.sh pkg-appimage dev" >&2
        echo "   (CI and that script set INSTALL_LIBDECOR_MINI=true inside their containers.)" >&2
        return 1
    fi
    if [[ "$CURRENT_DISTRO" != "arch" ]]; then
        echo "❌ The AppImage is built on Arch Linux (found '$CURRENT_DISTRO'): libdecor-mini is installed with" >&2
        echo "   pacman. Use ./mk.sh pkg-appimage." >&2
        return 1
    fi
}

install_libdecor() {
    require_install_libdecor_mini || return 1

    echo "⚠️ INSTALL_LIBDECOR_MINI=true: REPLACING this container's libdecor with libdecor-mini, so AppImages"
    echo "   built here draw their own title bar on GNOME Wayland (#793). Other programs in this container will"
    echo "   use libdecor-mini too. Only set this flag in a throwaway build container."
    # libdecor-mini declares that it provides and conflicts with libdecor; get-debloated-pkgs.sh runs
    # pacman -U --ask 4, which removes libdecor
    if ! get-debloated-pkgs.sh libdecor-mini; then
        echo "❌ get-debloated-pkgs.sh could not install libdecor-mini!" >&2
        return 1
    fi
    # the libdecor-mini download installs as the package libdecor-rs
    local pkg=$(pacman -Qoq /usr/lib/libdecor-0.so.0)
    echo "✅ Installed libdecor-mini: $(pacman -Q "$pkg")"
}
