#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
pushd "$SCRIPT_DIR" > /dev/null

set -u -o pipefail  # Strict expansions

# --- Error Handling Trap ---
cleanup_and_exit() {
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        exit_code=1  # force 0 exit code to 1 to indicate an error
    fi
    echo "❌ Oolite build failed on line $1 with exit code $exit_code!" >&2
    popd > /dev/null 2>&1 || true  # Always pop the directory stack before exiting
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then  # Exit only if not sourced
        exit "$exit_code"
    fi
}
trap 'cleanup_and_exit ${LINENO}' ERR  # Trap any command errors (ERR) passing ${LINENO} to know where it failed

# --- Feature Flags & Options ---
NATIVE_FILE=""
VER_FULL=""
GITHUB_REPOSITORY=""
CLEAN_BUILD=false
SETUP_FLAGS=() # Array to cleanly store additional meson setup arguments
COMPILE_FLAGS=() # Array to cleanly store additional meson compile arguments
INSTALL_FLAGS=() # Array to cleanly store additional meson install arguments
if [[ -v MINGW_PREFIX ]]; then
    meson() {  # Windows path override
        PATH="$MINGW_PREFIX/bin:/usr/bin:$PATH" command meson "$@"
    }
fi

meson_setup() {
    local build_dir="build/meson_$2"
    if [[ "$CLEAN_BUILD" == true ]]; then
        echo "--> Cleaning target build directory: ${build_dir}"
        rm -rf "$build_dir"  # If --clean was specified, delete the specific build directory first
    fi
    echo "--> Running Meson setup for: $2"
    type meson  # for debugging
    # Setup with --reconfigure, fallback to fresh setup. SETUP_FLAGS safely expands the array only if it's not empty
    meson setup "$build_dir" $1 ${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"} -Dver_full="$VER_FULL" -Dver_githash="$VER_GITHASH" -Dbuild_date="${CPP_DATE}" -Dbuilder="${BUILDER}" --native-file "${NATIVE_FILE}" --reconfigure 2>/dev/null || \
    meson setup "$build_dir" $1 ${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"} -Dver_full="$VER_FULL" -Dver_githash="$VER_GITHASH" -Dbuild_date="${CPP_DATE}" -Dbuilder="${BUILDER}" --native-file "${NATIVE_FILE}"
}

meson_build() {
    echo "--> Running Meson build for: $1"
    meson compile -C "build/meson_$1" ${COMPILE_FLAGS[@]+"${COMPILE_FLAGS[@]}"}
}

meson_install() {
    echo "--> Running Meson install for: $1"
    meson install -C "build/meson_$1" ${INSTALL_FLAGS[@]+"${INSTALL_FLAGS[@]}"}
}

show_help() {  # Script Help Menu
    echo "Usage: $0 [options] <target>"
    echo ""
    echo "Options:"
    echo -e "  \033[36m--clean\033[0m                        Delete target build directory before compiling"
    echo -e "  \033[36m--setup-flags=\"...\"\033[0m          Pass additional arguments directly to 'meson setup'"
    echo -e "  \033[36m--native-file=\"...\"\033[0m          Specify native file (defaults to clang.ini)"
    echo -e "  \033[36m--ver-full=\"...\"\033[0m             Specify full version string"
    echo -e "  \033[36m--github-repository=\"...\"\033[0m    Specify target GitHub repository"
    echo ""
    echo "Targets:"
    echo -e "  \033[36msetup-deployment\033[0m         Setup a deployment release executable"
    echo -e "  \033[36msetup-test\033[0m               Setup a test release executable"
    echo -e "  \033[36msetup-dev\033[0m                Setup a dev release executable"
    echo -e "  \033[36msetup-debug\033[0m              Setup a debug executable"
    echo -e "  \033[36mcompile-deployment\033[0m       Compile a deployment release executable"
    echo -e "  \033[36mcompile-test\033[0m             Compile a test release executable"
    echo -e "  \033[36mcompile-dev\033[0m              Compile a dev release executable"
    echo -e "  \033[36mcompile-debug\033[0m            Compile a debug executable"
    echo -e "  \033[36mbuild-deployment\033[0m         Setup and compile a deployment release executable"
    echo -e "  \033[36mbuild-test\033[0m               Setup and compile a test release executable"
    echo -e "  \033[36mbuild-dev\033[0m                Setup and compile a dev release executable"
    echo -e "  \033[36mbuild-debug\033[0m              Setup and compile a debug executable"
    echo -e "  \033[36minstall-deployment\033[0m       Install the deployment release installation"
    echo -e "  \033[36minstall-test\033[0m             Install the test release installation"
    echo -e "  \033[36minstall-dev\033[0m              Install the dev release installation"
    echo -e "  \033[36minstall-debug\033[0m            Install the debug installation"
    echo -e "  \033[36mtest\033[0m                     Run test suite (depends on build-dev)"
    echo -e "  \033[36mclean\033[0m                    Remove all generated build artifacts"
    echo -e "  \033[36mpkg-flatpak\033[0m              Package a Flatpak application"
    echo -e "  \033[36mpkg-appimage-deployment\033[0m  Package a Linux deployment release AppImage"
    echo -e "  \033[36mpkg-appimage-test\033[0m        Package a Linux test release AppImage"
    echo -e "  \033[36mpkg-appimage-dev\033[0m         Package a Linux dev release AppImage"
    echo -e "  \033[36mpkg-win-deployment\033[0m       Package a Windows NSIS deployment release installer"
    echo -e "  \033[36mpkg-win-test\033[0m             Package a Windows NSIS test release installer"
    echo -e "  \033[36mpkg-win-dev\033[0m              Package a Windows NSIS dev release installer"
}

execute_target() {  # Target Execution Logic
    case "$1" in
        setup-deployment)
            meson_setup "-Ddeployment_release=true -Ddebug=false -Dstrip_bin=true -Db_lto=true" "deployment"
            ;;
        setup-test)
            meson_setup "-Ddebug=false -Dstrip_bin=true -Db_lto=true" "test"
            ;;
        setup-dev)
            meson_setup "-Ddev_release=true -Ddebug=false -Dstrip_bin=false" "dev"
            ;;
        setup-debug)
            meson_setup "-Ddebug=true -Dstrip_bin=false" "debug"
            ;;
        compile-deployment)
            meson_build "deployment"
            ;;
        compile-test)
            meson_build "test"
            ;;
        compile-dev)
            meson_build "dev"
            ;;
        compile-debug)
            meson_build "debug"
            ;;
        build-deployment)
            execute_target "setup-deployment"
            execute_target "compile-deployment"
            ;;
        build-test)
            execute_target "setup-test"
            execute_target "compile-test"
            ;;
        build-dev)
            execute_target "setup-dev"
            execute_target "compile-dev"
            ;;
        build-debug)
            execute_target "setup-debug"
            execute_target "compile-debug"
            ;;
        install-deployment)
            meson_install "deployment"
            ;;
        install-test)
            meson_install "test"
            ;;
        install-dev)
            meson_install "dev"
            ;;
        install-debug)
            meson_install "debug"
            ;;
        test-deployment)
            echo "❌ Cannot test deployment as not set up for debug console!" >&2
            exit 1
            ;;
        test-test)
            execute_target "build-test"
            source tests/run_test_fn.sh && run_test "test"
            ;;
        test-dev)
            execute_target "build-dev"
            source tests/run_test_fn.sh && run_test "dev"
            ;;
        test-debug)
            execute_target "build-debug"
            source tests/run_test_fn.sh && run_test "debug"
            ;;
        clean)
            echo "--> Cleaning all build artifacts..."
            rm -rf build/meson_*
            ;;
        flatpak-deployment)  # This is used internally by the flatpak YAML
            execute_target "build-deployment"
            source installers/flatpak/flatpak_postbuild_fn.sh && flatpak_postbuild meson_deployment/oolite.app "$VER_FULL" "$APP_DATE"
            ;;
        pkg-flatpak)
            source installers/flatpak/create_flatpak_fn.sh && create_flatpak "$VER_FULL" "$GITHUB_REPOSITORY"
            ;;
        pkg-appimage-deployment)
            execute_target "build-deployment"
            source installers/appimage/create_appimage_fn.sh && create_appimage meson_deployment/oolite.app "$VER_FULL" "$APP_DATE" ""
            ;;
        pkg-appimage-test)
            execute_target "build-test"
            source installers/appimage/create_appimage_fn.sh && create_appimage meson_test/oolite.app "$VER_FULL" "$APP_DATE" "test"
            ;;
        pkg-appimage-dev)
            execute_target "build-dev"
            source installers/appimage/create_appimage_fn.sh && create_appimage meson_dev/oolite.app "$VER_FULL" "$APP_DATE" "dev"
            ;;
        pkg-win-deployment)
            execute_target "build-deployment"
            source installers/win32/create_nsis_fn.sh && create_nsis meson_deployment/oolite.app "$VER_FULL" "$VER_GITREV" "$VER_GITHASH" "$BUILDTIME" ""
            ;;
        pkg-win-test)
            execute_target "build-test"
            source installers/win32/create_nsis_fn.sh && create_nsis meson_test/oolite.app "$VER_FULL" "$VER_GITREV" "$VER_GITHASH" "$BUILDTIME" "test"
            ;;
        pkg-win-dev)
            execute_target "build-dev"
            source installers/win32/create_nsis_fn.sh && create_nsis meson_dev/oolite.app "$VER_FULL" "$VER_GITREV" "$VER_GITHASH" "$BUILDTIME" "dev"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "❌ Unknown target '$1'" >&2
            show_help
            exit 1
            ;;
    esac
}

TARGET=""
while [[ $# -gt 0 ]]; do  # Flexible Argument Parser
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --setup-flags=*)
            read -r -a flags_array <<< "${1#*=}"
            SETUP_FLAGS+=("${flags_array[@]}")
            shift
            ;;
        --compile-flags=*)
            read -r -a flags_array <<< "${1#*=}"
            COMPILE_FLAGS+=("${flags_array[@]}")
            shift
            ;;
        --install-flags=*)
            read -r -a flags_array <<< "${1#*=}"
            INSTALL_FLAGS+=("${flags_array[@]}")
            shift
            ;;
        --native-file=*)
            NATIVE_FILE="${1#*=}"
            shift
            ;;
        --ver-full=*)
            VER_FULL="${1#*=}"
            shift
            ;;
        --github-repository=*)
            GITHUB_REPOSITORY="${1#*=}"
            shift
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "❌ Unknown option '$1'" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -n "$TARGET" ]]; then
                echo "❌ Multiple targets specified ('$TARGET' and '$1'). Only one target allowed." >&2
                exit 1
            fi
            TARGET="$1"
            shift
            ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    show_help  # Fallback to help menu if no target was provided
    exit 1
fi
if [[ -z "$NATIVE_FILE" ]]; then
    NATIVE_FILE="clang.ini"  # Apply default for NATIVE_FILE if it wasn't passed as a parameter
fi

source ShellScripts/common/get_build_date_fn.sh && get_build_date CPP_DATE APP_DATE BUILDTIME BUILDER "$GITHUB_REPOSITORY"
source ShellScripts/common/get_version_fn.sh && get_version VER_FULL VER_NSIS VER_GITREV VER_GITHASH "$VER_FULL"

execute_target "$TARGET"

trap - ERR  # Successful Exit - remove the ERR trap so it doesn't accidentally fire during normal bailing
popd > /dev/null

if [[ "$TARGET" != "help" && "$TARGET" != "--help" && "$TARGET" != "-h" && "$TARGET" != "clean" ]]; then
    echo "✅ Oolite target '$TARGET' completed successfully"  # Print success if not a help menu or a cleanup action
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit 0
fi