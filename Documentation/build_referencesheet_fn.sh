#!/bin/bash

build_referencesheet() {
    pkg_ok=$(command -v typst)
    if [[ -z "$pkg_ok" ]]; then
      echo "❌ Typst not found!" >&2
      return 1
    fi

    local -r prev_xtrace=$-
    set -x
    local outputfile="docs/assets/pdfs/OoliteRS.pdf"
    rm -f "$outputfile"
    if ! typst compile ../../Documentation/docs/typst/reference.typ "$outputfile"; then
        echo "❌ Typst to PDF conversion failed!" >&2
        [[ "$prev_xtrace" =~ x ]] || set +x
        return 1
    fi
    echo "✅ Typst to PDF conversion successful"
}
