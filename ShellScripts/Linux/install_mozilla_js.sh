#!/bin/bash

# Installs the Spidermonkey library
# Parameter one: "system", "home", or "build" (defaults to home)
# Parameter two: escalate command (defaults to sudo for 'system')

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

    source "$script_dir/../common/download_github_release_fn.sh"
    source "$script_dir/dep_location_fn.sh"
    local lib_subdir target escalate
    dep_location lib_subdir target escalate "mozilla_js" $1 $2

    echo "Installing Mozilla JS static library to $target"
    [[ -n "$escalate" ]] && echo "Using escalation: $escalate"

    # Download and extract
    # Curl downloads as current user, Tar extracts using escalation

    local temp_staging=$(mktemp -d)
    trap 'rm -rf "$temp_staging"' EXIT

    local mozilla_tgz
    download_github_release mozilla_tgz "OoliteProject" "mozillajs-linux" "static-lib" "$temp_staging"
    if ! tar xfz ${mozilla_tgz} --directory "$temp_staging"; then
        echo "❌ Could not unpack Mozilla JS library tgz!" >&2
        return 1
    fi

    if ! [[ -d "$temp_staging/include" ]]; then
        echo "❌ Mozilla JS library extract empty!" >&2
        return 1
    fi

    # Move headers to include
    if ! $escalate cp -r "$temp_staging/include/"* "$target/include/"; then
        echo "❌ Mozilla JS library header install failed!" >&2
        return 1
    fi
    # Move libs from 'lib' in tarball to 'lib64' on system
    if ! $escalate cp -r "$temp_staging/lib/"* "$target/$lib_subdir/"; then
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