install_typst() {
    local outputdir="${1:-/tmp}"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local arch="$(uname -m 2>/dev/null || echo x86_64)"
    local typst_txz
    download_github_release typst_txz "typst" "typst" "${arch}-unknown-linux-musl.tar.xz" "$outputdir"
    if ! tar xf ${typst_txz} --directory "$outputdir"; then
        echo "❌ Could not unpack typst archive!" >&2
        return 1
    fi
    chmod +x "$outputdir"/typst-*/typst
    if ! mv "$outputdir"/typst-*/typst /usr/local/bin/typst; then
        echo "❌ Could not move typst to /usr/local/bin!" >&2
        return 1
    fi
    rm -rf "$outputdir"/typst-*
    rm -f ${typst_txz}
}
