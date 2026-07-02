#!/bin/bash

download_github_release() {
    local -n downloaded_file="$1"
    local owner="$2"
    local repository="$3"
    local filter="$4"
    local outputdir="${5:-.}"  # Default to current directory if not provided

    local repo="${owner}/${repository}"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    
    echo "Fetching latest release info for ${repo}..." >&2
    local release_json=$(curl -s "${api_url}")

    # Check if the repository was found/has releases
    if echo "${release_json}" | grep -q "Not Found"; then
        echo "❌ Repository not found or has no public releases at ${api_url}!" >&2
        return 1
    fi

    # Extract the download URL
    local download_url
    if [[ -n "${filter}" ]]; then
        download_url=$(echo "${release_json}" | jq -r ".assets[] | select(.name | contains(\"${filter}\")) | .browser_download_url" | head -n 1)
    else
        download_url=$(echo "${release_json}" | jq -r '.assets[0].browser_download_url')
    fi

    # Check if a URL was actually found
    if [[ -z "${download_url}" || "${download_url}" == "null" ]]; then
        echo "❌ Could not find a matching download URL!" >&2
        return 1
    fi

    # Extract filename from the URL
    local filename=$(basename "${download_url}")

    echo "Downloading latest release: ${filename}..." >&2
    curl -L -O --output-dir "${outputdir}" "${download_url}"

    downloaded_file="${outputdir}/${filename}"
}