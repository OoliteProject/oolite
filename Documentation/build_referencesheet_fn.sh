#!/bin/bash

build_referencesheet() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    PKG_OK=$(command -v typst)
    if [ "" = "$PKG_OK" ]; then
      echo "❌ Typst not found!" >&2
      return 1
    fi

    cd ..
    mkdir -p build/documentation/docs/assets/pdfs
    cd build/documentation/docs/assets/pdfs

    rm -f reference.pdf
    if ! typst compile ../../../../../Documentation/docs/typst/reference.typ reference.pdf; then
        echo "❌ PDF conversion with Typst failed!" >&2
        return 1
    fi
    echo "✅ PDF conversion completed successfully"
    popd
}
