#!/bin/bash

build_doxygen() {
    # Builds Doxygen html documentation. Called via build_documentation.
    pkg_ok=$(command -v doxygen)
    if [[ -z "$pkg_ok" ]]; then
      echo "❌ Doxygen executable not found!" >&2
      return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../ShellScripts/common/curl_fn.sh"

    mkdir -p docs/api
    curl -L https://github.com/jothepro/doxygen-awesome-css/archive/refs/tags/v2.4.1.tar.gz -o doxygen-awesome-css.tar.gz
    mkdir -p doxygen-awesome
    tar -xvzf doxygen-awesome-css.tar.gz --strip-components=1 -C doxygen-awesome
    if ! doxygen; then
        echo "❌ Doxygen build failed!" >&2
        return 1
    fi
    echo "✅ Doxygen build completed successfully"
}
