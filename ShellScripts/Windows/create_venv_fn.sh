#!/bin/bash

create_venv() {
    if ! command -v python >/dev/null 2>&1; then
        echo "❌ Python not installed!" >&2
        return 1
    fi

    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    local VENV_DIR="${1:-$SCRIPT_DIR/../../.venv}"

    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating virtual environment..."
        python -m venv --system-site-packages "$VENV_DIR"
    fi

    # Windows/MSYS2 uses 'Scripts' directory for the activation script
    if [ -f "$VENV_DIR/Scripts/activate" ]; then
        source "$VENV_DIR/Scripts/activate"
    else
        # Fallback for standard POSIX structure just in case
        source "$VENV_DIR/bin/activate"
    fi
}