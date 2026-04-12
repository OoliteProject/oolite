#!/bin/bash
# First optional parameter is install location. Defaults to build/mozilla_js.
# Second optional parameter is command to use to escalate privileges if needed. Defaults to not using root.

run_script() {
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    mkdir -p ../../build
    cd ../../build

    # Define the target directory
    local TARGET_RAW="${1:-./mozilla_js}"
    local ESCALATE="${2:-}"
    $ESCALATE mkdir -p "$TARGET_RAW"
    local TARGET=$(cd "$TARGET" && pwd)

    # The URL to your specific GitHub release asset
    local RELEASE_URL="https://github.com/YOUR_USER/YOUR_REPO/releases/download/v0.0.1/mozilla-js-static-lib.tar.gz"

    # 1. Create the local directory structure if it doesn't exist
    $ESCALATE mkdir -p "$TARGET/lib"
    $ESCALATE mkdir -p "$TARGET/include"

    echo "Installing Mozilla JS static library to $TARGET"

    # 2. Download and extract directly into $HOME/.local
    # -L follows redirects (needed for GitHub)
    # --strip-components=0 is used because your tarball already has lib/ and include/
    if ! $ESCALATE curl -L "$RELEASE_URL" | tar -xz -C "$TARGET"; then
        echo "❌ Mozilla JS library download and install failed!" >&2
        return 1
    fi

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

