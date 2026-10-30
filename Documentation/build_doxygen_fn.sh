#!/bin/bash

build_doxygen() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    PKG_OK=$(command -v doxygen)
    if [ "" = "$PKG_OK" ]; then
      echo "❌ Doxygen executable not found!" >&2
      return 1
    fi

    cd ..
    mkdir -p build/documentation/docs/api
    cd build/documentation/
    curl -L https://github.com/jothepro/doxygen-awesome-css/archive/refs/tags/v2.4.1.tar.gz -o doxygen-awesome-css.tar.gz
    tar -xvzf doxygen-awesome-css.tar.gz --strip-components=1

    cp -r ../../Documentation/* ./

    # Flatten docs/md/ up to docs/ in the BUILD TREE ONLY (repo sources stay
    # put). Page URLs therefore stay top-level (/advice/, /privacy/, ...) on
    # both ReadTheDocs and local builds, while build_mds_fn.sh keeps reading
    # the sources from docs/md/.
    mv docs/md/*.md docs/
    mv docs/md/assets/* docs/assets/
    rm -rf docs/md

    if ! doxygen; then
        echo "❌ Doxygen build failed!" >&2
        return 1
    fi
    echo "✅ Doxygen build completed successfully"
    popd
}
