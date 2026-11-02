#!/bin/bash -e

run_script() {
    local python_cmd
    if python3 --version >/dev/null 2>&1; then
        python_cmd="python3"
    elif python --version >/dev/null 2>&1; then
        python_cmd="python"
    else
        echo "❌ Python not found!" >&2
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ./build_documentation_fn.sh
    source ../ShellScripts/Linux/install_pandoc_fn.sh
    source ../ShellScripts/Linux/install_weasyprint_fn.sh
    source ../ShellScripts/Linux/install_typst_fn.sh

    mkdir -p ~/.local/bin && export PATH="$HOME/.local/bin:$PATH"
    install_pandoc ~/.local/bin
    install_typst ~/.local/bin
    install_weasyprint
    build_documentation "$python_cmd"

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
