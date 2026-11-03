#!/bin/bash
# Run Oolite's test tiers from this directory, inside a private virtualenv.
#
#     tests/run.sh unit        meson suites: oofnd, core, headers (needs ./mk.sh build test)
#     tests/run.sh component   Gherkin scenarios over the debug console
#     tests/run.sh gui         PyAutoGUI tier (real window; do not touch the mouse)
#     tests/run.sh smoke       launch_snapshot.py via mk.sh
#     tests/run.sh all         unit, component, smoke, then gui, stopping at the first failure
#     tests/run.sh venv        create/refresh the virtualenv only
#
# Extra arguments after the tier go to pytest (component, gui):
#     tests/run.sh component -k s1
#
# Environment: BUILD_TYPE (default test), OO_VENV (default build/.venv-tests), OO_APP_DIR.
# The venv lives under build/, which is git-ignored. Delete it to force a clean reinstall.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)
cd "$ROOT"

BUILD_TYPE=${BUILD_TYPE:-test}
VENV=${OO_VENV:-build/.venv-tests}
REQ_STAMP="$VENV/.requirements-stamp"
REQ_FILES=(tests/component/requirements.txt tests/gui/requirements.txt)

find_python() {
    local p
    for p in python3 python; do
        if "$p" --version > /dev/null 2>&1; then
            echo "$p"
            return
        fi
    done
    echo "tests/run.sh: no python3 on PATH" >&2
    return 1
}

# Windows Pythons put the interpreter in Scripts/, POSIX ones in bin/.
venv_python() {
    if [[ -x "$VENV/Scripts/python.exe" ]]; then
        echo "$VENV/Scripts/python.exe"
    else
        echo "$VENV/bin/python"
    fi
}

ensure_venv() {
    if [[ ! -x "$VENV/Scripts/python.exe" && ! -x "$VENV/bin/python" ]]; then
        echo "--> Creating virtualenv at $VENV"
        "$(find_python)" -m venv "$VENV"
    fi
    local py
    py=$(venv_python)
    # Reinstall only when a requirements file is newer than the last successful install.
    local stale=false f
    [[ -f "$REQ_STAMP" ]] || stale=true
    for f in "${REQ_FILES[@]}"; do
        [[ "$f" -nt "$REQ_STAMP" ]] && stale=true
    done
    if [[ "$stale" == true ]]; then
        echo "--> Installing test requirements into $VENV"
        local args=()
        for f in "${REQ_FILES[@]}"; do args+=(-r "$f"); done
        "$py" -m pip install --quiet --disable-pip-version-check "${args[@]}"
        touch "$REQ_STAMP"
    fi
}

require_build() {
    local app="${OO_APP_DIR:-build/meson_${BUILD_TYPE}/oolite.app}"
    if [[ ! -d "$app" ]]; then
        echo "tests/run.sh: no build at $app. Run ./mk.sh build $BUILD_TYPE first." >&2
        exit 1
    fi
}

run_unit() {
    require_build
    local suite
    for suite in oofnd core headers; do
        echo "--> meson test --suite $suite"
        meson test -C "build/meson_${BUILD_TYPE}" --suite "$suite" --print-errorlogs
    done
}

run_component() {
    require_build
    "$(venv_python)" -m pytest tests/component -x -q "$@"
}

run_gui() {
    require_build
    # A missing pyautogui or a non-Windows host must fail, never skip silently.
    OO_GUI_REQUIRE=1 "$(venv_python)" -m pytest tests/gui -x -q "$@"
}

run_smoke() {
    require_build
    ./mk.sh test "$BUILD_TYPE"
}

tier=${1:-}
[[ $# -gt 0 ]] && shift

case "$tier" in
    venv)      ensure_venv ;;
    unit)      run_unit ;;  # no Python needed; meson drives it
    component) ensure_venv; run_component "$@" ;;
    gui)       ensure_venv; run_gui "$@" ;;
    smoke)     run_smoke ;;
    all)       ensure_venv; run_unit; run_component; run_smoke; run_gui ;;
    *)
        sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        [[ -z "$tier" ]] || exit 2
        ;;
esac
