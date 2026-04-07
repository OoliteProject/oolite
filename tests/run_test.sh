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

    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
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
        echo "❌ Oolite test failed!" >&2
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

