install_pandoc() {
    local outputdir="${1:-/tmp}"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local pandoc_tgz
    download_github_release pandoc_tgz "jgm" "pandoc" "linux-amd64.tar.gz" "$outputdir"
    if ! tar xfz ${pandoc_tgz} --directory "$outputdir"; then
        echo "❌ Could not unpack pandoc tgz!" >&2
        return 1
    fi
    chmod +x "$outputdir"/pandoc-*/bin/pandoc
    if ! mv "$outputdir"/pandoc-*/bin/pandoc /usr/local/bin/pandoc; then
        echo "❌ Could not move pandoc to /usr/local/bin!" >&2
        return 1
    fi
    rm -rf "$outputdir"/pandoc-*
    rm -f ${pandoc_tgz}
}
