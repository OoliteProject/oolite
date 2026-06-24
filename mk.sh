#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
pushd "$SCRIPT_DIR" > /dev/null

# Strict expansions, but NO 'set -e'
set -o pipefail

# --- Error Handling Trap ---
cleanup_and_exit() {
    local exit_code=$?

    # If the exit code is 0 (success) but this function was triggered,
    # force it to 1 to indicate an error.
    if [[ $exit_code -eq 0 ]]; then
        exit_code=1
    fi

    echo "❌ Oolite build failed on line $1 with exit code $exit_code!" >&2

    # Always pop the directory stack before exiting
    popd > /dev/null 2>&1 || true

    # Exit only if not sourced
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        exit "$exit_code"
    fi
}

# Trap any command errors (ERR) passing ${LINENO} to know exactly where it failed.
trap 'cleanup_and_exit ${LINENO}' ERR

# --- Environment Variables & Defaults ---
NATIVE_FILE="${NATIVE_FILE:-clang.ini}"
BUILDER="${BUILDER:-unknown}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"

# --- Feature Flags & Options ---
CLEAN_BUILD=false
SETUP_FLAGS=() # Array to cleanly store additional meson setup arguments

# --- Helper Functions ---
# Replicates $(call meson_build,flags,suffix)
meson_build() {
    local build_dir="build/meson_$2"
    # If --clean was specified, delete the specific build directory first
    if [[ "$CLEAN_BUILD" == true ]]; then
        echo "--> Cleaning target build directory: ${build_dir}"
        rm -rf "$build_dir"
    fi
    echo "--> Running Meson build for: $2"
    # Setup with --reconfigure, fallback to fresh setup. SETUP_FLAGS safely expands the array only if it's not empty
    meson setup "$build_dir" $1 ${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"} -Dgithub_repository="${GITHUB_REPOSITORY}" --native-file "${NATIVE_FILE}" --reconfigure 2>/dev/null || \
    meson setup "$build_dir" $1 ${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"} -Dgithub_repository="${GITHUB_REPOSITORY}" --native-file "${NATIVE_FILE}"
    meson compile -C "$build_dir"
}

meson_install() {
    echo "--> Running Meson install for: $1"
    meson install -C "build/meson_$1"
}

# --- Script Help Menu ---
show_help() {
    echo "Usage: $0 [options] <target>"
    echo ""
    echo "Options:"
    echo -e "  \033[36m--clean\033[0m                   Delete target build directory before compiling"
    echo -e "  \033[36m--setup-flags=\"...\"\033[0m     Pass additional arguments directly to 'meson setup'"
    echo ""
    echo "Targets:"
    echo -e "  \033[36mrelease\033[0m                 Build a test release executable"
    echo -e "  \033[36mrelease-deployment\033[0m      Build a release deployment executable"
    echo -e "  \033[36mrelease-snapshot\033[0m        Build a snapshot release executable"
    echo -e "  \033[36mdebug\033[0m                  Build a debug executable"
    echo -e "  \033[36minstall\033[0m                 Install the test release build"
    echo -e "  \033[36minstall-deployment\033[0m      Install the release deployment build"
    echo -e "  \033[36minstall-snapshot\033[0m        Install the snapshot release build"
    echo -e "  \033[36mtest\033[0m                   Run test suite (depends on release-snapshot)"
    echo -e "  \033[36mclean\033[0m                  Remove all generated build artifacts"
    echo -e "  \033[36mpkg-flatpak\033[0m            Package a Flatpak application"
    echo -e "  \033[36mpkg-appimage\033[0m           Package a test release AppImage"
    echo -e "  \033[36mpkg-appimage-deployment\033[0m Package a deployment AppImage"
    echo -e "  \033[36mpkg-appimage-snapshot\033[0m   Package a snapshot AppImage"
    echo -e "  \033[36mpkg-win\033[0m                Package a Windows NSIS test release installer"
    echo -e "  \033[36mpkg-win-deployment\033[0m     Package a Windows NSIS deployment installer"
    echo -e "  \033[36mpkg-win-snapshot\033[0m       Package a Windows NSIS snapshot installer"
}

# --- Target Execution Logic ---
execute_target() {
    case "$1" in
        release)
            meson_build "-Ddebug=false -Dstrip_bin=true -Db_lto=true" "release"
            ;;
        release-deployment)
            meson_build "-Ddeployment_release_configuration=true -Ddebug=false -Dstrip_bin=true -Db_lto=true" "deployment"
            ;;
        release-snapshot)
            meson_build "-Dsnapshot_build=true -Ddebug=false -Dstrip_bin=false" "snapshot"
            ;;
        debug)
            meson_build "-Ddebug=true -Dstrip_bin=false" "debug"
            ;;
        install)
            meson_install "release"
            ;;
        install-deployment)
            meson_install "deployment"
            ;;
        install-snapshot)
            meson_install "snapshot"
            ;;
        test)
            execute_target "release-snapshot"
            source tests/run_test_fn.sh && run_test
            ;;
        clean)
            echo "--> Cleaning all build artifacts..."
            rm -rf build/meson_*
            ;;
        pkg-flatpak)
            source installers/flatpak/create_flatpak_fn.sh && create_flatpak
            ;;
        pkg-appimage)
            execute_target "release"
            source installers/appimage/create_appimage_fn.sh && create_appimage meson_release/oolite.app "test"
            ;;
        pkg-appimage-deployment)
            execute_target "release-deployment"
            source installers/appimage/create_appimage_fn.sh && create_appimage meson_deployment/oolite.app
            ;;
        pkg-appimage-snapshot)
            execute_target "release-snapshot"
            source installers/appimage/create_appimage_fn.sh && create_appimage meson_snapshot/oolite.app "dev"
            ;;
        pkg-win)
            execute_target "release"
            source installers/win32/create_nsis_fn.sh && create_nsis meson_release/oolite.app "test"
            ;;
        pkg-win-deployment)
            execute_target "release-deployment"
            source installers/win32/create_nsis_fn.sh && create_nsis meson_deployment/oolite.app
            ;;
        pkg-win-snapshot)
            execute_target "release-snapshot"
            source installers/win32/create_nsis_fn.sh && create_nsis meson_snapshot/oolite.app "dev"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Error: Unknown target '$1'" >&2
            show_help
            exit 1
            ;;
    esac
}

# --- Flexible Argument Parser ---
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --setup-flags=*)
            # Handle inline assignment format (e.g., --setup-flags="-Dfoo=bar")
            read -r -a flags_array <<< "${1#*=}"
            SETUP_FLAGS+=("${flags_array[@]}")
            shift
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Error: Unknown option '$1'" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -n "$TARGET" ]]; then
                echo "Error: Multiple targets specified ('$TARGET' and '$1'). Only one target allowed." >&2
                exit 1
            fi
            TARGET="$1"
            shift
            ;;
    esac
done

# Fallback to help menu if no target was provided
if [[ -z "$TARGET" ]]; then
    show_help
    exit 1
fi

execute_target "$TARGET"
# Successful Exit - remove the ERR trap so it doesn't accidentally fire during normal bailing.
trap - ERR
popd > /dev/null

# Only print build success if it wasn't a help menu or a cleanup action
if [[ "$TARGET" != "help" && "$TARGET" != "--help" && "$TARGET" != "-h" && "$TARGET" != "clean" ]]; then
    echo "✅ Oolite target '$TARGET' completed successfully"
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit 0
fi