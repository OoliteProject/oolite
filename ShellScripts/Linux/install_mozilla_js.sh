#!/bin/bash
# Parameter one: "system", "home", or "build" (defaults to home).
# Parameter two: Escalate command (defaults to sudo for 'system').

run_script() {
    # Get the directory where the script is located
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

    source "$script_dir/dep_location_fn.sh"
    dep_location LIB_SUBDIR TARGET ESCALATE "mozilla_js" $1 $2

    # The URL to your specific GitHub release asset
    local release_url="https://github.com/OoliteProject/mozillajs-linux/releases/download/0.0.1/mozilla-js-static-lib.tar.gz"

    echo "Installing Mozilla JS static library to $TARGET"
    [[ -n "$ESCALATE" ]] && echo "Using escalation: $ESCALATE"

    # Download and extract
    # Curl downloads as current user, Tar extracts using escalation

    local temp_staging=$(mktemp -d)
    trap 'rm -rf "$temp_staging"' EXIT

    if ! curl -L "$release_url" | tar -xz -C "$temp_staging"; then
        echo "❌ Mozilla JS library download or extract failed!" >&2
        return 1
    fi

    if ! [[ -d "$temp_staging/include" ]]; then
        echo "❌ Mozilla JS library extract empty!" >&2
        return 1
    fi

    # Move headers to include
    if ! $ESCALATE cp -r "$temp_staging/include/"* "$TARGET/include/"; then
        echo "❌ Mozilla JS library header install failed!" >&2
        return 1
    fi
    # Move libs from 'lib' in tarball to 'lib64' on system
    if ! $ESCALATE cp -r "$temp_staging/lib/"* "$TARGET/$LIB_SUBDIR/"; then
        echo "❌ Mozilla JS library lib install failed!" >&2
        return 1
    fi

    echo "✅ Installation complete."
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi