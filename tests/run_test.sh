#!/bin/bash
# Processes Oolite data files after compilation

output_logs() {
    if [[ -f "$1" ]]; then
        echo "--- xwfb_output.log ---"
        cat "$1"
        echo "-----------------------"
    fi
    if [[ -f "$2" ]]; then
        echo "--- Latest.log ---"
        cat "$2"
        echo "------------------------------"
    fi
}

run_script() {
    if python3 --version >/dev/null 2>&1; then
        local PYTHON_CMD="python3"
    elif python --version >/dev/null 2>&1; then
        local PYTHON_CMD="python"
    else
      echo "❌ Python executable not found!" >&2
      return 1
    fi

    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    local TARGET_DIR="../oolite.app"
    if [[ -n "$MSYSTEM" ]]; then
        local MESA_DLL="${MSYSTEM_PREFIX}/bin/opengl32.dll"

        if [[ -f "$MESA_DLL" ]]; then
            echo "📦 Found $MSYSTEM Mesa driver at $MESA_DLL"
            cp "$MESA_DLL" "$TARGET_DIR/"
        fi
    fi

    local LOGS_DIR="$TARGET_DIR/logs"
    rm -rf "$LOGS_DIR"
    mkdir -p "$LOGS_DIR"
    local XWFB_LOG="$LOGS_DIR/xwfb_output.log"
    local OOLITE_LOG="$LOGS_DIR/Latest.log"

    if ! $PYTHON_CMD launch_snapshot.py --path="$TARGET_DIR"; then
        output_logs "$XWFB_LOG" "$OOLITE_LOG"
        echo "❌ Oolite test failed!" >&2
        echo "   If this is a windows build try creating a new release of the Windows dependencies in the GitHub UI here:" >&2
        echo "   https://github.com/OoliteProject/oolite_windeps_build/releases" >&2
        echo "   Then rerun this build." >&2
        return 1
    fi
    output_logs "$XWFB_LOG" "$OOLITE_LOG"

    echo "✅ Oolite test completed successfully"
    popd
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

