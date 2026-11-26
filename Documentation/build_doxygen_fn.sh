#!/bin/bash

build_doxygen() {
    # Builds Doxygen html documentation. Called via build_documentation.
    pkg_ok=$(command -v doxygen)
    if [[ -z "$pkg_ok" ]]; then
      echo "❌ Doxygen executable not found!" >&2
      return 1
    fi

    source ../../ShellScripts/common/download_github_release_fn.sh

    mkdir -p docs/api
    local doxygen_awesome_tgz
    download_github_release doxygen_awesome_tgz "jothepro" "doxygen-awesome-css"
    mkdir -p doxygen-awesome
    if ! tar xvfz ${doxygen_awesome_tgz} --strip-components=1 -C doxygen-awesome; then
        echo "❌ Could not unpack doxygen awesome tgz!" >&2
        return 1
    fi
    if ! doxygen; then
        echo "❌ Doxygen build failed!" >&2
        return 1
    fi
    echo "✅ Doxygen build completed successfully"
}
