#!/bin/bash

build_doxygen() {
    pkg_ok=$(command -v doxygen)
    if [ "" = "$pkg_ok" ]; then
      echo "❌ Doxygen executable not found!" >&2
      return 1
    fi

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
