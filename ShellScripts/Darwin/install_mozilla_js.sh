#!/bin/bash
# Install the SpiderMonkey js185 arm64-macOS static library for Oolite.
# Darwin twin of ShellScripts/Linux/install_mozilla_js.sh: same parameter
# contract ("system", "home", or "build"), same target layout.
# Parameter one: "system", "home", or "build" (defaults to home).
# Parameter two: escalate command (defaults to sudo for 'system').

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

    source "$script_dir/../Linux/dep_location_fn.sh"
    local lib_subdir target escalate
    dep_location lib_subdir target escalate "mozilla_js" $1 $2

    local release_url="https://github.com/OoliteProject/mozillajs-macos/releases/download/0.0.1/mozjs-js185-macos-arm64.tar.gz"

    echo "Installing Mozilla JS library (arm64, interpreter-only) to $target"
    [[ -n "$escalate" ]] && echo "Using escalation: $escalate"

    local temp_staging=$(mktemp -d)
    trap 'rm -rf "$temp_staging"' EXIT

    if ! curl -fL "$release_url" | tar -xz -C "$temp_staging"; then
        echo "❌ Mozilla JS library download or extract failed!" >&2
        return 1
    fi

    if ! [[ -d "$temp_staging/include" ]]; then
        echo "❌ Mozilla JS library extract empty!" >&2
        return 1
    fi

    if ! $escalate cp -R "$temp_staging/include/"* "$target/include/"; then
        echo "❌ Mozilla JS library header install failed!" >&2
        return 1
    fi
    mkdir -p "$target/$lib_subdir"
    if ! $escalate cp -R "$temp_staging/lib/"* "$target/$lib_subdir/"; then
        echo "❌ Mozilla JS library install failed!" >&2
        return 1
    fi

    echo "✅ Installation complete."
}

run_script "$@"
status=$?

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
