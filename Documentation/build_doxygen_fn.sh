#!/bin/bash

build_doxygen() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ..
    rm -rf build/documentation
    mkdir -p build/documentation/docs/api
    cd build/documentation/
    curl -L https://raw.githubusercontent.com/jothepro/doxygen-awesome-css/main/doxygen-awesome.css -o ./doxygen-awesome.css
    cd ../..
    if ! doxygen; then
        echo "❌ Doxygen build failed" >&2
        return 1
    fi
    echo "✅ Doxygen build completed successfully"
    popd
}
