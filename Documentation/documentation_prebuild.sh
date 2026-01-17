#!/bin/bash

run_script() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    set -x
    echo "Running pre-build steps..."

    source ./build_doxygen_fn.sh

    if ! build_doxygen; then
        return 1
    fi

    cp -r ./* ../build/documentation/
    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
