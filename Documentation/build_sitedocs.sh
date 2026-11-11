#!/bin/bash -e

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ../ShellScripts/Linux/install_zensical_fn.sh
    source ../ShellScripts/Linux/install_typst_fn.sh
    source ./build_zensical_fn.sh

    mkdir -p ~/.local/bin && export PATH="$HOME/.local/bin:$PATH"
    install_typst ~/.local/bin
    install_zensical
    build_zensical
    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
