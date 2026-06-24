#!/bin/bash
# Processes Oolite data files after compilation

output_log() {
    if [[ -f "$1" ]]; then
        echo "--- Latest.log ---"
        cat "$1"
        echo "------------------------------"
    fi
}

run_test() {
    if python3 --version >/dev/null 2>&1; then
        local PYTHON_CMD="python3"
    elif python --version >/dev/null 2>&1; then
        local PYTHON_CMD="python"
    else
      echo "❌ Python executable not found!" >&2
      return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    local BUILD_TYPE="${1:-snapshot}"
    local TARGET_DIR=$(readlink -f "../build/meson_${BUILD_TYPE}/oolite.app")
    if [[ -n "$MSYSTEM" ]]; then
        local MESA_DLL="${MSYSTEM_PREFIX}/bin/opengl32.dll"
        if [[ -f "$MESA_DLL" ]]; then
            echo "📦 Copying $MSYSTEM Mesa driver at $MESA_DLL"
            cp "$MESA_DLL" "$TARGET_DIR/"
        fi
    fi

    local TEST_OUTPUT="$TARGET_DIR/../test_output"
    rm -rf "$TEST_OUTPUT"
    mkdir -p "$TEST_OUTPUT"
    local OOLITE_LOG="$TEST_OUTPUT/Latest.log"

    if ! $PYTHON_CMD launch_snapshot.py --path="$TARGET_DIR" --test_output="$TEST_OUTPUT"; then
        output_log "$OOLITE_LOG"
        echo "❌ Oolite test failed!" >&2
        echo "   If this is a windows build try creating a new release of the Windows dependencies in the GitHub UI here:" >&2
        echo "   https://github.com/OoliteProject/oolite_windeps_build/releases" >&2
        echo "   Then rerun this build." >&2
        return 1
    fi
    output_log "$OOLITE_LOG"

    echo "✅ Oolite test completed successfully"
    popd
}
