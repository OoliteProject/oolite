#!/bin/bash

run_script() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ./checkout_deps_fn.sh
    if ! checkout_deps; then
    return 1
    fi

    source ../common/checkout_submodules_fn.sh
    checkout_submodules
    popd
}

run_script
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

