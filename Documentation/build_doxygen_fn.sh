#!/bin/bash

build_doxygen() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ..
    rm -rf build/documentation
    mkdir -p build/documentation/docs/api
    cd build/documentation/
    curl -L https://github.com/jothepro/doxygen-awesome-css/archive/refs/tags/v2.4.1.tar.gz -o doxygen-awesome-css.tar.gz
    tar -xvzf doxygen-awesome-css.tar.gz --strip-components=1
    cp -r ../../Documentation/* ./
    if ! doxygen; then
        echo "❌ Doxygen build failed" >&2
        return 1
    fi
    echo "✅ Doxygen build completed successfully"
    popd
}
