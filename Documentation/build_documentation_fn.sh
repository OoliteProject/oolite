#!/bin/bash

build_documentation() {
    local deactivate_venv="${1:-YES}"
    local include_doxygen="${2:-YES}"

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

    source ./build_mds_fn.sh
    source ./build_referencesheet_fn.sh
    source ./build_doxygen_fn.sh

    cd ..
    if [[ "$(uname -s)" != "Darwin" || -n "$FLATPAK_DEST" ]]; then
        if [[ ! -d ".venv" ]]; then
            echo "❌ Virtual environment folder (.venv) not found!" >&2
            return 1
        else
            # Try to activate based on OS structure
            if [[ -f ".venv/Scripts/activate" ]]; then
                source ".venv/Scripts/activate"
            elif [[ -f ".venv/bin/activate" ]]; then
                source ".venv/bin/activate"
            else
                echo "❌ Activation script not found in .venv!" >&2
                return 1
            fi
        fi
    fi
    rm -rf build/documentation
    mkdir -p build/documentation/docs/assets/pdfs
    cd build/documentation
    cp -rf ../../Documentation/* ./
    rm -f *.sh

    # Flatten docs/md/ up to docs/ so Page URLs stay top-level (/advice/, /privacy/, ...)
    mv docs/md/*.md docs/
    mv docs/md/assets/* docs/assets/
    rm -rf docs/md

    if ! build_mds "$python_cmd"; then
        popd
        return 1
    fi

    if ! build_referencesheet; then
        popd
        return 1
    fi

    if [[ "$include_doxygen" == "YES" ]]; then
        if ! build_doxygen; then
            popd
            return 1
        fi
    fi

    if [[ "$deactivate_venv" == "YES" ]]; then
        if command -v deactivate >/dev/null 2>&1; then
            deactivate
        fi
    fi
    popd
}
