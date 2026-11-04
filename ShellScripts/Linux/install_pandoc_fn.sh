install_pandoc() {
    local installdir="${1:-/usr/local/bin}"
    local tmpdir="${2:-/tmp}"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 && "${READTHEDOCS:-}" != "True" ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local pandoc_tgz
    download_github_release pandoc_tgz "jgm" "pandoc" "linux-amd64.tar.gz" "$tmpdir"
    if ! tar xfz ${pandoc_tgz} --directory "$tmpdir"; then
        echo "❌ Could not unpack pandoc tgz!" >&2
        return 1
    fi
    chmod +x "$tmpdir"/pandoc-*/bin/pandoc
    if ! mv "$tmpdir"/pandoc-*/bin/pandoc "$installdir/pandoc"; then
        echo "❌ Could not move pandoc to $installdir!" >&2
        return 1
    fi
    rm -rf "$tmpdir"/pandoc-*
    rm -f ${pandoc_tgz}
}
