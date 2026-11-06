#!/bin/bash

build_documentation() {
    local include_doxygen="${1:-YES}"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ./build_mds_fn.sh
    source ./build_referencesheet_fn.sh
    source ./build_doxygen_fn.sh

    cd ..
    rm -rf build/documentation
    mkdir -p build/documentation/docs/assets/pdfs
    cd build/documentation
    cp -rf ../../Documentation/* ./
    rm -f *.sh

    # Flatten docs/md/ up to docs/ so Page URLs stay top-level (/advice/, /privacy/, ...)
    mv docs/md/*.md docs/
    mv docs/md/assets/* docs/assets/
    rm -rf docs/md

    if ! build_mds; then
        popd
        return 1
    fi

    if ! build_referencesheet; then
        popd
        return 1
    fi

    if [[ "$include_doxygen" == "YES" ]]; then
        if ! build_doxygen; then
            popd
            return 1
        fi
    fi
    popd
}
