install_typst() {
    local installdir="${1:-/usr/local/bin}"
    local tmpdir="${2:-/tmp}"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 && "${READTHEDOCS:-}" != "True" ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local arch="$(uname -m 2>/dev/null || echo x86_64)"
    local typst_txz
    download_github_release typst_txz "typst" "typst" "${arch}-unknown-linux-musl.tar.xz" "$tmpdir"
    if ! tar xf ${typst_txz} --directory "$tmpdir"; then
        echo "❌ Could not unpack typst archive!" >&2
        return 1
    fi
    chmod +x "$tmpdir"/typst-*/typst
    if ! mv "$tmpdir"/typst-*/typst "$installdir/typst"; then
        echo "❌ Could not move typst to $installdir!" >&2
        return 1
    fi
    rm -rf "$tmpdir"/typst-*
    rm -f ${typst_txz}
}
