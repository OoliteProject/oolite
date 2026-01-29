#!/bin/bash

build_referencesheet() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    PKG_OK=$(command -v soffice)
    if [ "" = "$PKG_OK" ]; then
      echo "❌ LibreOffice soffice not found!" >&2
      return 1
    fi

    cd ..
    source ShellScripts/common/get_version.sh
    mkdir -p build/documentation/docs
    cd build/documentation/
    cp ../../Doc/OoliteRS.odt ./

    rm -rf docs/OoliteRS.pdf
    if ! soffice --headless --convert-to pdf --outdir ./docs OoliteRS.odt; then
        echo "❌ PDF conversion with soffice failed!" >&2
        return 1
    fi
    echo "✅ PDF conversion completed successfully"
    popd
}
