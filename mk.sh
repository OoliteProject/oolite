#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
pushd "$SCRIPT_DIR" > /dev/null

set -u -o pipefail  # Strict expansions

cleanup_and_exit() {  # Error handling trap
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

output_meson_log() {
    meson_log="$1/meson-logs/meson-log.txt"
    if [[ -f "$meson_log" ]]; then
        echo -e "\n=== MESON LOG START ===" >&2
        cat "$meson_log" >&2
        echo -e "=== MESON LOG END ===\n" >&2
    fi
}

# --- Feature Flags & Options ---
NATIVE_FILE=""
VER_FULL=""
BUILDTIME=""
GITHUB_REPOSITORY=""
CLEAN_BUILD=false
SETUP_FLAGS=() # Array to cleanly store additional meson setup arguments
COMPILE_FLAGS=() # Array to cleanly store additional meson compile arguments
CONFIGURE_FLAGS=() # Array to cleanly store additional meson configure arguments
INSTALL_FLAGS=() # Array to cleanly store additional meson install arguments

clean() {
    echo "--> Cleaning target build directory: $1"
    rm -rf "$1"
}

meson_setup() {
    local build_dir="build/meson_$1"
    echo "--> Running Meson setup for: $1"
    local meson_opts=("${@:2}")
    if [[ -n "${VER_FULL:-}" ]]; then
        export VER_FULL
    fi
    if [[ -n "${BUILDTIME:-}" ]]; then
        export BUILDTIME
    fi
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
        export GITHUB_REPOSITORY
    fi
    if [[ -d "$build_dir" ]] && [[ -f "$build_dir/build.ninja" ]]; then
        echo "🔄 Directory exists, attempting to reconfigure..."
        if ! meson setup "$build_dir" "${meson_opts[@]}" ${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"} --native-file "${NATIVE_FILE}" --reconfigure; then
            echo "❌ Meson reconfiguration failed!" >&2
            output_meson_log "$build_dir"
            exit 1
        fi
    else
        echo "🏗️ Creating new build configuration..."
        if ! meson setup "$build_dir" "${meson_opts[@]}" ${SETUP_FLAGS[@]+"${SETUP_FLAGS[@]}"} --native-file "${NATIVE_FILE}"; then
            echo "❌ Meson initial setup failed!" >&2
            output_meson_log "$build_dir"
            exit 1
        fi
    fi
}

meson_compile() {
    local build_dir="build/meson_$1"
    echo "--> Running Meson build for: $1"
    if ! meson compile -C "$build_dir" ${COMPILE_FLAGS[@]+"${COMPILE_FLAGS[@]}"}; then
        echo "❌ Meson compile failed!" >&2
        output_meson_log "$build_dir"
        exit 1
    fi
}

meson_configure() {
    local build_dir="build/meson_$1"
    echo "--> Running Meson configure for: $1"
    local meson_opts=("${@:2}")
    if ! meson configure "$build_dir" "${meson_opts[@]}" ${CONFIGURE_FLAGS[@]+"${CONFIGURE_FLAGS[@]}"}; then
        echo "❌ Meson configure failed!" >&2
        output_meson_log "$build_dir"
        exit 1
    fi
}

meson_install() {
    local build_dir="build/meson_$1"
    echo "--> Running Meson install for: $1"
    if ! meson install -C "$build_dir" ${INSTALL_FLAGS[@]+"${INSTALL_FLAGS[@]}"}; then
        echo "❌ Meson install failed!" >&2
        output_meson_log "$build_dir"
        exit 1
    fi
}

show_help() {  # Script Help Menu
    echo "Usage: $0 [options] <action> <build_type>"
    echo "       $0 [options] <global_action>"
    echo ""
    echo "Options:"
    echo -e "  \033[36m--setup-flags=\"...\"\033[0m          Pass additional arguments directly to 'meson setup'"
    echo -e "  \033[36m--compile-flags=\"...\"\033[0m        Pass additional arguments directly to 'meson compile'"
    echo -e "  \033[36m--configure-flags=\"...\"\033[0m      Pass additional arguments directly to 'meson configure'"
    echo -e "  \033[36m--install-flags=\"...\"\033[0m        Pass additional arguments directly to 'meson install'"
    echo -e "  \033[36m--native-file=\"...\"\033[0m          Specify native file (defaults to clang.ini)"
    echo -e "  \033[36m--ver-full=\"...\"\033[0m             Specify full version string"
    echo -e "  \033[36m--buildtime=\"...\"\033[0m            Specify build time"
    echo -e "  \033[36m--github-repository=\"...\"\033[0m    Specify target GitHub repository"
    echo ""
    echo "Build Type Actions (Requires build_type as second parameter):"
    echo -e "  \033[36msetup <build_type>\033[0m              Setup a release build directory"
    echo -e "  \033[36mcompile <build_type>\033[0m            Compile a build directory"
    echo -e "  \033[36mbuild <build_type>\033[0m              Setup and compile a build directory"
    echo -e "  \033[36mconfigure <build_type>\033[0m          Modify build options of an existing build directory"
    echo -e "  \033[36minstall <build_type>\033[0m            Install an existing build directory"
    echo -e "  \033[36mtest <build_type>\033[0m               Run test suites (deployment build_type excluded)"
    echo -e "  \033[36mclean <build_type>\033[0m              Clean a specific build_type's directory"
    echo -e "  \033[36mflatpak-internal <build_type>\033[0m   Build flatpak dependencies internally"
    echo -e "  \033[36mpkg-flatpak <build_type>\033[0m        Package a Flatpak application"
    echo -e "  \033[36mpkg-appimage <build_type>\033[0m       Package a Linux AppImage installer"
    echo -e "  \033[36mpkg-win <build_type>\033[0m            Package a Windows NSIS installer"
    echo ""
    echo "Global Actions:"
    echo -e "  \033[36mclean-all\033[0m                    Remove generated artifacts for all builds"
    echo -e "  \033[36mhelp\033[0m                         Show this breakdown menu"
    echo ""
    echo "Build Types:"
    echo -e "  \033[32mdeployment, test, dev, debug\033[0m"
}

validate_build_type() {
    local build_type="$1"
    if [[ "$build_type" != "deployment" && "$build_type" != "test" && "$build_type" != "dev" && "$build_type" != "debug" ]]; then
        echo "❌ Invalid build_type '$build_type'. Expected: deployment, test, dev, or debug." >&2
        exit 1
    fi
}

execute_target() {  # Target Execution Logic
    local action="$1"
    local build_type="${2:-}"

case "$action" in
        setup)
            validate_build_type "$build_type"
            if [[ "$build_type" == "deployment" ]]; then
                # Arguments passed individually (acts like an array)
                meson_setup "deployment" "-Ddeployment_release=true" "-Ddebug=false" "-Dstrip_bin=true" "-Db_lto=true"
            elif [[ "$build_type" == "test" ]]; then
                meson_setup "test" "-Ddebug=false" "-Dstrip_bin=true" "-Db_lto=true"
            elif [[ "$build_type" == "dev" ]]; then
                meson_setup "dev" "-Ddev_release=true" "-Ddebug=false" "-Dstrip_bin=false"
            elif [[ "$build_type" == "debug" ]]; then
                meson_setup "debug" "-Ddebug=true" "-Dstrip_bin=false"
            fi
            ;;
        compile)
            validate_build_type "$build_type"
            meson_compile "$build_type"
            ;;
        build)
            validate_build_type "$build_type"
            execute_target "setup" "$build_type"
            execute_target "compile" "$build_type"
            ;;
        configure)
            validate_build_type "$build_type"
            meson_configure "$build_type"
            ;;
        install)
            validate_build_type "$build_type"
            meson_install "$build_type"
            ;;
        test)
            validate_build_type "$build_type"
            if [[ "$build_type" == "deployment" ]]; then
                echo "❌ Cannot test deployment as not set up for debug console!" >&2
                exit 1
            fi
            source tests/run_test_fn.sh && run_test "$build_type"
            ;;
        clean)
            if [[ "$build_type" == "appimage" ]]; then
                clean "build/appimage"
            elif [[ "$build_type" == "flatpak" ]]; then
                clean "build/flatpak"
            else
                validate_build_type "$build_type"
                clean "build/meson_$build_type"
            fi
            ;;
        flatpak-internal)
            validate_build_type "$build_type"
            execute_target "build" "$build_type"
            if ! meson_configure "$build_type" "--prefix=/app"; then
                echo "❌ Flatpak meson configure with prefix /app failed!" >&2
                exit 1
            fi
            if ! meson_install "$build_type"; then
                echo "❌ Flatpak meson install failed!" >&2
                exit 1
            fi
            if ! source installers/flatpak/flatpak_postbuild_fn.sh; then
                echo "❌ Failed to source flatpak_postbuild_fn.sh!" >&2
                exit 1
            fi
            if ! flatpak_postbuild "meson_${build_type}/oolite.app"; then
                echo "❌ Flatpak post build failed!" >&2
                exit 1
            fi
            ;;
        pkg-flatpak)
            validate_build_type "$build_type"
            if ! source installers/flatpak/create_flatpak_fn.sh; then
                echo "❌ Failed to source create_flatpak_fn.sh!" >&2
                exit 1
            fi
            if ! create_flatpak "$build_type" "$GITHUB_REPOSITORY"; then
                echo "❌ Flatpak generation failed!" >&2
                exit 1
            fi
            ;;
        pkg-appimage)
            validate_build_type "$build_type"
            local appdir=$(realpath -m "build/appimage/oolite.AppDir")
            if ! meson_configure "$build_type" "--prefix=$appdir"; then
                echo "❌ AppImage meson configure with prefix /app failed!" >&2
                exit 1
            fi
            if ! meson_install "$build_type"; then
                echo "❌ AppImage meson install failed!" >&2
                exit 1
            fi
            if ! source installers/appimage/create_appimage_fn.sh; then
                echo "❌ Failed to source create_appimage_fn.sh!" >&2
                exit 1
            fi
            if ! create_appimage "$build_type" "meson_${build_type}/oolite.app"; then
                echo "❌ AppImage generation failed!" >&2
                exit 1
            fi
            ;;
        pkg-win)
            validate_build_type "$build_type"
            if ! source installers/win32/create_nsis_fn.sh; then
                echo "❌ Failed to source create_nsis_fn.sh!" >&2
                exit 1
            fi
            if ! create_nsis "$build_type" "meson_${build_type}/oolite.app"; then
                echo "❌ NSIS generation failed!" >&2
                exit 1
            fi
            ;;
        *)
            echo "❌ Fatal structural error handling action '$action'" >&2
            exit 1
            ;;
    esac
}

ACTION=""
BUILD_TYPE=""

# --- Flexible Argument Parser (Allows flags and positionals anywhere) ---
while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --configure-flags=*)
            read -r -a flags_array <<< "${1#*=}"
            CONFIGURE_FLAGS+=("${flags_array[@]}")
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
        --buildtime=*)
            BUILDTIME="${1#*=}"
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
            # Process sequential text items dynamically
            if [[ -z "$ACTION" ]]; then
                ACTION="$1"
            elif [[ -z "$BUILD_TYPE" ]]; then
                BUILD_TYPE="$1"
            else
                echo "❌ Unexpected extra argument '$1'." >&2
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    show_help  # Fallback to help menu if no action was provided
    exit 1
fi

# Intercept global action 'clean-all' before validating build_type requirements
if [[ "$ACTION" == "clean-all" ]]; then
    echo "--> Cleaning all build artifacts..."
    rm -rf build/meson_*
    rm -rf build/flatpak
    rm -rf build/appimage
    trap - ERR
    popd > /dev/null
    echo "✅ Oolite task 'clean-all' completed successfully"
    exit 0
fi

# Everything past this point strictly requires a build_type parameter
if [[ -z "$BUILD_TYPE" ]]; then
    echo "❌ Error: Action '$ACTION' requires a target build_type parameter." >&2
    show_help
    exit 1
fi

if [[ -z "$NATIVE_FILE" ]]; then
    NATIVE_FILE="clang.ini"  # Apply default if it wasn't passed as an option
fi

execute_target "$ACTION" "$BUILD_TYPE"

trap - ERR  # Successful Exit
popd > /dev/null

echo "✅ Oolite task '$ACTION $BUILD_TYPE' completed successfully"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit 0
fi