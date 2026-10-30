#!/bin/bash

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ./install_doc_packages_fn.sh

    if ! install_doc_packages; then
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
