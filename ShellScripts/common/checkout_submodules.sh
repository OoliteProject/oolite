#!/bin/bash

run_script() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ./checkout_submodules_fn.sh
    cd ../..
    if ! checkout_submodules; then
        return 1
    fi
    popd
}

run_script
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

