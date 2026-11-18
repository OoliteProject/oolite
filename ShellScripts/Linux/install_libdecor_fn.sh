#!/bin/bash

# Installs the libdecor that the AppImage will bundle. This is the one place that decides which libdecor that is.
# Called via install_packages_root.sh, after it has put get-debloated-pkgs.sh in /usr/local/bin.
#
# SDL3 needs libdecor to draw the game window's title bar on GNOME Wayland (#793). quick-sharun bundles libdecor
# from the system library folder, so the build machine must have the libdecor we want to ship.
#
# - OOLITE_DISPOSABLE_BUILD_MACHINE=true: libdecor-mini (libdecor-rs), which REPLACES the system libdecor. It draws
#   its own title bar and needs only glibc, so the AppImage works without the player's libdecor plugins and never
#   loads GTK. get-debloated-pkgs.sh installs it with pacman, so this needs Arch Linux. The CI workflow sets this
#   flag only in the archlinux container job that builds the AppImage; the container is deleted after the job.
#   On a developer's machine, use ShellScripts/Linux/build_appimage_container.sh, which sets the flag inside a
#   container. Never set it on a machine you keep.
# - Otherwise: the distribution's libdecor, so no system library is replaced. AppImages built this way show a
#   title bar on GNOME Wayland only if the player has libdecor's plugins installed.
#
# Why a flag of our own rather than CI=true: CI=true says "running under a CI system", not "this machine is thrown
# away afterwards". Every CI system sets it, including self-hosted runners, which are real machines, and some
# developers export CI=true in their shells to make tools non-interactive. Replacing a system library has to be
# asked for explicitly, by the one workflow step that knows its machine is disposable.
#
# The libdecor-mini package is not pinned: each build takes the current one (#793). The log shows its version.
install_libdecor() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/os_detection.sh"
    source "$script_dir/install_package_fn.sh"

    if [[ "${OOLITE_DISPOSABLE_BUILD_MACHINE:-}" != "true" ]]; then
        echo "ℹ️ OOLITE_DISPOSABLE_BUILD_MACHINE is not 'true': installing the distribution's libdecor; no system library"
        echo "   is replaced. AppImages built here show a title bar on GNOME Wayland only if the player has libdecor's"
        echo "   plugins. To build an AppImage like the published ones (with libdecor-mini) without changing this"
        echo "   machine, run ShellScripts/Linux/build_appimage_container.sh."
        install_package libdecor
        return
    fi

    if [[ "$CURRENT_DISTRO" != "arch" ]]; then
        echo "❌ OOLITE_DISPOSABLE_BUILD_MACHINE=true, but libdecor-mini can only be installed on Arch Linux (found" >&2
        echo "   '$CURRENT_DISTRO'). Use ShellScripts/Linux/build_appimage_container.sh, or unset the flag." >&2
        return 1
    fi

    echo "⚠️ OOLITE_DISPOSABLE_BUILD_MACHINE=true: REPLACING this machine's libdecor with libdecor-mini, so AppImages"
    echo "   built here draw their own title bar on GNOME Wayland (#793). Other programs on this machine will use"
    echo "   libdecor-mini too. Only set this flag on a throwaway build machine, such as a CI container."
    # libdecor-mini declares that it provides and conflicts with libdecor; get-debloated-pkgs.sh runs
    # pacman -U --ask 4, which removes libdecor
    if ! get-debloated-pkgs.sh libdecor-mini; then
        echo "❌ get-debloated-pkgs.sh could not install libdecor-mini!" >&2
        return 1
    fi
    # the libdecor-mini download installs as the package libdecor-rs
    echo "✅ Installed libdecor-mini: $(pacman -Qoq /usr/lib/libdecor-0.so.0) $(pacman -Q "$(pacman -Qoq /usr/lib/libdecor-0.so.0)" | cut -d' ' -f2)"
}
