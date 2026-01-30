#!/bin/bash

run_script() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    rm -rf ../build/documentation
    source ./build_doxygen_fn.sh
    source ./build_referencesheet_fn.sh

    if ! build_doxygen; then
        return 1
    fi

    if ! build_referencesheet; then
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
    cp -r ../../Documentation/* ./
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

    if ! pip install -r requirements.txt; then
        echo "❌ Could not install MKDocs requirements!" >&2
        return 1
    fi
    "$PYTHON_CMD" -m playwright install chromium
    # If PDF generation fails, run: "$PYTHON_CMD" -m playwright install-deps chromium

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

