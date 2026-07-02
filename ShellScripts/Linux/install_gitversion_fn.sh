install_gitversion() {
    local outputdir="$1"

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source ../common/download_github_release_fn.sh

    download_github_release gitversion_tgz "GitTools" "GitVersion" "linux-x64" "$outputdir"
    tar xfz ${gitversion_tgz} --directory "$outputdir"
    chmod +x "$outputdir/gitversion"
    mv "$outputdir/gitversion" /usr/local/bin/gitversion
    rm -f ${gitversion_tgz}

    popd
}