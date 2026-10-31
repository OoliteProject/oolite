#!/bin/bash

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ./build_doxygen_fn.sh
    source ./build_mds_fn.sh
    source ./build_referencesheet_fn.sh
    source ../ShellScripts/Linux/install_doc_packages_fn.sh

    mkdir -p ~/.local/bin && export PATH="$HOME/.local/bin:$PATH"
    if ! install_doc_packages ~/.local/bin; then
        return 1
    fi
    if ! build_doxygen; then
        return 1
    fi
    if ! build_mds; then
        return 1
    fi
    if ! build_referencesheet; then
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
