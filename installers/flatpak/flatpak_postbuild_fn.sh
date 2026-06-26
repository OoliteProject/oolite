#!/bin/bash -x
#
# Prepares the app directory for the flatpak builder
#

flatpak_postbuild() {
    local build_folder="$1"  # Build folder
    local ver_full="$2"  # Oolite version
    local app_date="$3"  # Oolite build date

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"
    cd ../../build
    source ../ShellScripts/Linux/install_freedesktop_fn.sh

    local abs_oolitedir=$(realpath -m "$build_folder")
    install_freedesktop "$abs_oolitedir" "$ver_full" "$app_date" "/app" "lib/debug/bin" "metainfo"
    mkdir -p /app/lib/debug/source/oolite  # Ensure the destination directory exists
    # Copy the src directory recursively
    cp -r ../src /app/lib/debug/source/oolite/ || {
        echo "❌ $err_msg install oolite source code" >&2
        return 1
    }
}