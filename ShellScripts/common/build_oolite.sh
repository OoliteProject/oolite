#!/bin/bash
# No parameters: build target = release
# One parameter: build target

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    cd ../..

    local target
    if [[ -z "$1" ]]; then
        target=release
    else
        target=$1
    fi

    make clean
    if ! make $target; then
        echo "❌ Oolite build failed!" >&2
        return 1
    fi
    echo "✅ Oolite build completed successfully"

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi