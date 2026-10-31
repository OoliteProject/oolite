#!/bin/bash

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    source ./install_package_fn.sh
    install_package doxygen jq weasyprint-deps
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
