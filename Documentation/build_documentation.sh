#!/bin/bash

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    rm -rf ../build/documentation
    source ./build_doxygen_fn.sh
    source ./build_referencesheet_fn.sh
    source ./build_mds_fn.sh

    if ! build_doxygen; then
        return 1
    fi

    if ! build_referencesheet; then
        return 1
    fi

    if ! build_mds; then
        return 1
    fi

    # build_mds() outputs into Documentation/docs/; stage the PDFs into the
    # build tree where mkdocs expects them (mirrors the ReadTheDocs pre_build)
    mkdir -p ../build/documentation/docs/assets/pdfs
    if ! cp docs/assets/pdfs/*.pdf ../build/documentation/docs/assets/pdfs/; then
        echo "❌ Could not stage PDFs into build tree!" >&2
        return 1
    fi

    if python3 --version >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif python --version >/dev/null 2>&1; then
        PYTHON_CMD="python"
    else
      echo "❌ Python executable not found" >&2
      return 1
    fi

    cd ../build/documentation/
    cp ../../LICENSE.md ./docs/license.md
    VENV_DIR=".venv"
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating virtual environment..."
        "$PYTHON_CMD" -m venv "$VENV_DIR"
    fi
    if [ -d "$VENV_DIR/Scripts" ]; then
        source "$VENV_DIR/Scripts/activate"
    else
        source "$VENV_DIR/bin/activate"
    fi

    # Install the docs requirements, as ReadTheDocs does
    if ! "$PYTHON_CMD" -m pip install -r ../../Documentation/requirements.txt; then
        echo "❌ Could not install documentation requirements!" >&2
        return 1
    fi

    if ! mkdocs build --clean; then
        echo "❌ MKDocs build failed!" >&2
        return 1
    fi
    echo "✅ MKDocs build completed successfully"

    deactivate
    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
