#!/bin/bash
# No parameters: build target = release
# One parameter: build target

run_script() {
    # First optional parameter is build target. Default target is release.
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    export CC=clang
    export CXX=clang++

    cd ../..

    if [[ -z "$1" ]]; then
        TARGET=release
    else
        TARGET=$1
    fi

    local SHARE
    if [[ -z "$MINGW_PREFIX" ]]; then
        SHARE="build/gnustep/share"
        if [[ ! -d "$SHARE" ]]; then
            SHARE="$HOME/.local/share"
            if [[ ! -d "$SHARE" ]]; then
                SHARE="/usr/local/share"
            fi
        fi
    else
        SHARE="${MINGW_PREFIX}/share"
    fi

    local GNUSTEP_SH="$SHARE/GNUstep/Makefiles/GNUstep.sh"

    if [[ -f "$GNUSTEP_SH" ]]; then
        source "$GNUSTEP_SH"
    else
        echo "❌ Could not find GNUstep.sh in $SHARE!"
        return 1
    fi

    make -f Makefile clean
    if ! make -f Makefile $TARGET -j$(nproc); then
        echo "❌ Oolite build failed!" >&2
        return 1
    fi
    echo "✅ Oolite build completed successfully"

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

