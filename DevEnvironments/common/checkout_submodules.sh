#!/bin/bash

run_script() {
    pushd "$(dirname "$0")"
    source ./checkout_submodules_fn.sh
    cd ../..
    checkout_submodules
    popd
}

run_script
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

