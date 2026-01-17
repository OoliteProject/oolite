#!/bin/bash

run_script() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ./build_doxygen_fn.sh

    if ! build_doxygen; then
        return 1
    fi

    cd ../build/documentation/
    if ! virtualenv venv; then
        echo "❌ Virtualenv creation failed" >&2
        return 1
    fi
    source venv/bin/activate

    cp -r ../../Documentation/* ./
    pip install -r requirements.txt
    if ! mkdocs build --clean; then
        echo "❌ MKDocs build failed" >&2
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

