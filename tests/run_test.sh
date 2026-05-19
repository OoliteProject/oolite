#!/bin/bash
# Processes Oolite data files after compilation

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

    if [[ -n "$MSYSTEM" ]]; then
        MESA_DLL="${MSYSTEM_PREFIX}/bin/opengl32.dll"
        TARGET_DIR="../oolite.app"

        if [[ -f "$MESA_DLL" ]]; then
            echo "📦 Found $MSYSTEM Mesa driver at $MESA_DLL"
            cp "$MESA_DLL" "$TARGET_DIR/"
        fi
    fi

    if ! $PYTHON_CMD launch_snapshot.py --path=../oolite.app; then
        ERROR_LOG="../oolite.app/xwfb_errors.log"
        if [[ -f "$ERROR_LOG" ]]; then
            echo "--- Found xwfb_errors.log ---"
            cat "$ERROR_LOG"
            echo "------------------------------"
        fi >&2
        WESTON_LOG="../oolite.app/weston_debug.log"
        if [[ -f "$WESTON_LOG" ]]; then
            echo "--- Found weston_debug.log ---"
            cat "$WESTON_LOG"
            echo "------------------------------"
        fi >&2
        echo "❌ Oolite test failed!" >&2
        echo "   If this is a windows build try creating a new release of the Windows dependencies in the GitHub UI here:" >&2
        echo "   https://github.com/OoliteProject/oolite_windeps_build/releases" >&2
        echo "   Then rerun this build." >&2
        return 1
    fi

    echo "✅ Oolite test completed successfully"
    popd
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

