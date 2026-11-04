#!/bin/bash

create_venv() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "❌ Python not installed!" >&2
        return 1
    fi

    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    local VENV_DIR="${1:-$SCRIPT_DIR/../../.venv}"

    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
    fi
    source "$VENV_DIR/bin/activate"
}