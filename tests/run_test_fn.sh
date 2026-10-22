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

    local BUILD_TYPE="${1:-dev}"
    # OOLITE_TEST_APP tests an oolite.app somewhere other than build/meson_<build type>.
    local TARGET_DIR=$(readlink -f "${OOLITE_TEST_APP:-../build/meson_${BUILD_TYPE}/oolite.app}")
    if [[ -v MINGW_PREFIX ]]; then
        local MESA_DLL="${MINGW_PREFIX}/bin/opengl32.dll"
        if [[ -f "$MESA_DLL" ]]; then
            echo "📦 Copying $MSYSTEM Mesa driver at $MESA_DLL"
            cp "$MESA_DLL" "$TARGET_DIR/"
        fi
    fi

    local TEST_OUTPUT="$TARGET_DIR/../test_output"
    rm -rf "$TEST_OUTPUT"
    mkdir -p "$TEST_OUTPUT"
    local OOLITE_LOG="$TEST_OUTPUT/Latest.log"

    local LAUNCH_PATH="$TARGET_DIR"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        LAUNCH_PATH="$TARGET_DIR/Contents/MacOS/oolite"  # app bundle
    fi

    # 1. Smoke test, with the OXPs in test-oxps.txt (cached between runs).
    local OXZ_CACHE="${OOLITE_TEST_OXZ_CACHE:-$script_dir/../build/test-oxz-cache}"
    if ! $PYTHON_CMD -u fetch_oxps.py "$OXZ_CACHE"; then
        echo "❌ Fetching the test OXPs failed!" >&2
        popd
        return 1
    fi
    if ! $PYTHON_CMD -u launch_snapshot.py --path="$LAUNCH_PATH" --test_output="$TEST_OUTPUT" \
            --load="$script_dir/../Resources/Scenarios/oolite-standard.oolite-save" --addons="$OXZ_CACHE"; then
        output_log "$OOLITE_LOG"
        echo "❌ Oolite test failed!" >&2
        echo "   If this is a windows build try creating a new release of the Windows dependencies in the GitHub UI here:" >&2
        echo "   https://github.com/OoliteProject/oolite_windeps_build/releases" >&2
        echo "   Then rerun this build." >&2
        popd
        return 1
    fi
    output_log "$OOLITE_LOG"
    echo "✅ Smoke test passed"

    # 2. JavaScript tests (tests/js).
    if ! $PYTHON_CMD -u run_js_tests.py --path="$LAUNCH_PATH" --test_output="$TEST_OUTPUT/js"; then
        output_log "$TEST_OUTPUT/js/Latest.log"
        echo "❌ JavaScript tests failed!" >&2
        popd
        return 1
    fi
    echo "✅ JavaScript tests passed"

    # 3. Parity probe, compared with the stored QuickJS output for this platform.
    local PROBE_DIR="$script_dir/../tools/js-parity"
    local BASELINE=""
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) BASELINE="$PROBE_DIR/baseline-quickjs.txt" ;;
        Darwin-arm64) BASELINE="$PROBE_DIR/baseline-quickjs-macos.txt" ;;
    esac
    local PROBE_OUT="$TEST_OUTPUT/probe.txt"
    if ! $PYTHON_CMD -u "$PROBE_DIR/run_probe.py" "$LAUNCH_PATH" "$PROBE_OUT" --check-leaks; then
        output_log "$PROBE_OUT.full.log"
        echo "❌ The parity probe did not finish cleanly!" >&2
        popd
        return 1
    fi
    if [[ -n "$BASELINE" ]]; then
        if ! "$PROBE_DIR/compare.sh" "$BASELINE" "$PROBE_OUT"; then
            echo "❌ The parity probe's output differs from $(basename "$BASELINE")!" >&2
            echo "   If the change is intended, update the baseline (see tools/js-parity/README.md)." >&2
            popd
            return 1
        fi
    elif grep -q "script.javaScript.exception" "$PROBE_OUT"; then
        grep "script.javaScript.exception" "$PROBE_OUT" >&2
        echo "❌ The parity probe reported JavaScript exceptions!" >&2
        popd
        return 1
    else
        echo "ℹ️  No probe baseline for $(uname -s) $(uname -m); checked for exceptions only."
    fi
    echo "✅ Parity probe passed"

    echo "✅ Oolite test completed successfully"
    popd
}
