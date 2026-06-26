#!/bin/bash
#
# Calculates the Oolite version number
#

# Get the name of the script that is sourcing this file
SUITE_PARENT=$(basename "${BASH_SOURCE[1]}")
# Define the ONLY script allowed to source this
ALLOWED_SCRIPT="mk.sh"
if [ "$SUITE_PARENT" != "$ALLOWED_SCRIPT" ]; then
    echo "❌ This file can only be sourced by $ALLOWED_SCRIPT!" >&2
    return 1 2>/dev/null || exit 1
fi

get_version() {
    local -n output_ver_full=$1
    local -n output_ver_nsis=$2
    local -n output_ver_gitrev=$3
    local -n output_ver_githash=$4

    if [[ -n "$5" ]]; then  # VER_FULL already populated
        return 0
    fi

    if ! command -v gitversion &> /dev/null; then
        echo "❌ gitversion binary not found!" >&2
        exit 1
    fi

    local gitversion_json=$(gitversion)
    local ver_maj=$(echo "$gitversion_json" | jq -r '.Major')
    local ver_min=$(echo "$gitversion_json" | jq -r '.Minor')
    local ver_rev=$(echo "$gitversion_json" | jq -r '.Patch')

    if [[ "" == "$ver_rev" ]]; then
        ver_rev="0"
    fi

    local ver_dist=$(echo "$gitversion_json" | jq -r '.VersionSourceDistance')
    local ver_semver=$(echo "$gitversion_json" | jq -r '.SemVer')
    local ver_uncommitted=$(echo "$gitversion_json" | jq -r '.UncommittedChanges')

    if git diff --quiet; then
        output_ver_full=$ver_semver
        output_ver_nsis="$ver_maj.$ver_min.$ver_rev.$ver_dist"
    else
        output_ver_full="${ver_semver}+dirty.${ver_uncommitted}"
        output_ver_nsis="$ver_maj.$ver_min.$ver_rev.$ver_uncommitted"
    fi

    output_ver_gitrev=$(git rev-list --count HEAD)
    output_ver_githash=$(git rev-parse --short=7 HEAD)
}