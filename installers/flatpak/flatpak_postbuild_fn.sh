#!/bin/bash -x

flatpak_postbuild() {
    # Prepares the app directory for the flatpak builder
    # Parameter one: build folder
    local build_folder="$1"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"
    source ../FreeDesktop/install_freedesktop_fn.sh

    cd ../../build/flatpak
    install_freedesktop ver_full "../$build_folder" "/app" "lib/debug/bin" "metainfo"
    mkdir -p /app/lib/debug/source/oolite  # Ensure the destination directory exists
    cp -r ../../src /app/lib/debug/source/oolite/ || {  # Copy the src directory recursively
        echo "❌ $err_msg install oolite source code" >&2
        return 1
    }
    popd
}