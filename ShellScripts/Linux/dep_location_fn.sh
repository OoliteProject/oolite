#!/bin/bash

dep_location() {
    # Parameter one: Name of variable to store LIB_SUBDIR
    # Parameter two: Name of variable to store TARGET
    # Parameter three: Name of variable to store ESCALATE
    # Parameter four: build folder
    # Parameter five: "system", "home", or "build" (defaults to home)
    # Parameter six: Escalate command (defaults to sudo)

    # Use underscore prefixes to prevent circular reference errors
    local -n _lib_ref=$1
    local -n _target_ref=$2
    local -n _esc_ref=$3

    local _build_folder=$4
    local _mode="${5:-home}"
    local _escalate_cmd="${6:-sudo}"

    # Get the directory where the script is located
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

    source "$SCRIPT_DIR/os_detection.sh"
    cd ../../

    # Logic for LIB_SUBDIR
    if [[ ${CURRENT_DISTRO,,} == "redhat" ]]; then
        _lib_ref="lib64"
    else
        _lib_ref="lib"
    fi

    # Set paths and elevation based on mode
    case "$_mode" in
        "system")
            _target_ref="/usr/local"
            _esc_ref="$_escalate_cmd"
            ;;
        "home")
            _target_ref="$HOME/.local"
            _esc_ref=""
            ;;
        "build")
            mkdir -p ./build
            _target_ref="$(pwd)/build/$_build_folder"
            _esc_ref=""
            ;;
        *)
            echo "Usage: $0 [lib_var] [target_var] [esc_var] {build_folder} {system|home|build}"
            popd > /dev/null
            return 1
            ;;
    esac

    # Ensure target subdirectories exist
    $_esc_ref mkdir -p "$_target_ref/$_lib_ref"
    $_esc_ref mkdir -p "$_target_ref/include"
}