install_gitversion() {
    local installdir="${1:-/usr/local/bin}"
    local tmpdir="${2:-/tmp}"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local gitversion_tgz
    download_github_release gitversion_tgz "GitTools" "GitVersion" "linux-x64" "$tmpdir"
    if ! tar xfz ${gitversion_tgz} --directory "$tmpdir"; then
        echo "❌ Could not unpack gitversion tgz!" >&2
        return 1
    fi
    chmod +x "$tmpdir/gitversion"
    if ! mv "$tmpdir/gitversion" "$installdir/gitversion"; then
        echo "❌ Could not move gitversion to $installdir!" >&2
        return 1
    fi
    rm -f ${gitversion_tgz}
}