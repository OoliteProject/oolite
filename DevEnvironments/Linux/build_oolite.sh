#!/bin/bash
# No parameters: build target = release
# One parameter: build target

run_script() {
    # First optional parameter is build target. Default target is release.
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    export CC=clang
    export CXX=clang++

    cd ../..

    if [[ -z "$1" ]]; then
        TARGET=release
    else
        TARGET=$1
    fi

    source /usr/local/share/GNUstep/Makefiles/GNUstep.sh
    make -f Makefile clean
    if make -f Makefile $TARGET -j$(nproc); then
        echo "✅ Oolite build completed successfully"
    else
        echo "❌ Oolite build failed" >&2
		    return 1
    fi

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

