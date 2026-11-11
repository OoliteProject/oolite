#!/bin/bash

build_zensical() {
    # Builds documentation site eg. on GitHub Pages
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

    if ! build_documentation; then
        popd
        return 1
    fi

    if [[ -f "../.venv/Scripts/activate" ]]; then
        source "../.venv/Scripts/activate"
    elif [[ -f "../.venv/bin/activate" ]]; then
        source "../.venv/bin/activate"
    fi

    cd ../build/documentation

    if ! zensical build --clean; then
        echo "❌ Zensical build failed!" >&2
        return 1
    fi
    echo "✅ Zensical build completed successfully"

    if command -v deactivate >/dev/null 2>&1; then
        deactivate
    fi
    popd
}
