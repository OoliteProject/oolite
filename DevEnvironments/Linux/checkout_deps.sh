#!/bin/bash

run_script() {
    pushd "$(dirname "$0")"
    source ./checkout_deps_fn.sh
    checkout_deps
    popd
}

run_script
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

