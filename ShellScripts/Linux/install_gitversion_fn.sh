install_gitversion() {
    local outputdir="$1"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local gitversion_tgz
    download_github_release gitversion_tgz "GitTools" "GitVersion" "linux-x64" "$outputdir"
    if ! tar xfz ${gitversion_tgz} --directory "$outputdir"; then
        echo "❌ Could not unpack gitversion tgz!" >&2
        return 1
    fi
    chmod +x "$outputdir/gitversion"
    if ! mv "$outputdir/gitversion" /usr/local/bin/gitversion; then
        echo "❌ Could not move gitversion to /usr/local/bin!" >&2
        return 1
    fi
    rm -f ${gitversion_tgz}
}