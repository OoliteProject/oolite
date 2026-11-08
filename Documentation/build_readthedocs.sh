#!/bin/bash -e

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ./build_documentation_fn.sh
    source ../ShellScripts/Linux/install_typst_fn.sh

    mkdir -p ~/.local/bin && export PATH="$HOME/.local/bin:$PATH"
    install_typst ~/.local/bin
    build_documentation

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
