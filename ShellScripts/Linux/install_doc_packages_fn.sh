#!/bin/bash -e

# This script must be run as root (for example with sudo).

install_doc_packages() {
    local installdir="${1:-/usr/local}"
    local tmpdir="${2:-/tmp}"


    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    source ./install_pandoc_fn.sh
    source ./install_weasyprint_fn.sh
    source ./install_typst_fn.sh

    install_pandoc "$installdir" "$tmpdir"
    install_weasyprint
    install_typst "$installdir" "$tmpdir"

	popd
}
