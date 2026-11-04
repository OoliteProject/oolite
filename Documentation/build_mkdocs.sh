#!/bin/bash

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

    if ! build_documentation "NO"; then
        popd
        return 1
    fi

    cd ../build/documentation
    # Install the docs requirements, as ReadTheDocs does
    if ! "$python_cmd" -m pip install -r ../../Documentation/requirements.txt; then
        echo "❌ Could not install documentation requirements!" >&2
        return 1
    fi

    if ! mkdocs build --clean; then
        echo "❌ MKDocs build failed!" >&2
        return 1
    fi
    echo "✅ MKDocs build completed successfully"

    if command -v deactivate >/dev/null 2>&1; then
        deactivate
    fi
    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
