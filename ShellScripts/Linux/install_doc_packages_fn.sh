#!/bin/bash -e

# This script must be run as root (for example with sudo).

install_doc_packages() {
    local outputdir="${1:-/tmp}"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    source ./install_package_fn.sh
    source ./install_pandoc_fn.sh
    source ./install_weasyprint_fn.sh
    source ./install_typst_fn.sh

    install_package doxygen weasyprint-deps
    install_pandoc "$outputdir"
    install_weasyprint
    install_typst "$outputdir"

	popd
}
