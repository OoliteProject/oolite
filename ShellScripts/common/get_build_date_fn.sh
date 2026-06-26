#!/bin/bash
#
# Calculates the Oolite build date
#

get_build_date() {
    local -n output_cpp_date=$1
    local -n output_app_date=$2
    local -n output_buildtime=$3
    local -n output_builder=$4
    # $5 is GITHUB_REPOSITORY environment variable from GitHub Actions

    # Run timestamp exactly once
    local getversion_timestamp=$(git log -1 --format=%ct)

    # Date conversions use UTC for consistency
    output_cpp_date=$(date -u -d "@$getversion_timestamp" +"%b %e %Y")
    output_app_date=$(date -u -d "@$getversion_timestamp" +"%Y-%m-%d")
    output_buildtime=$(date -u -d "@$getversion_timestamp" "+%Y.%m.%d %H:%M")

    if [[ "$5" == "OoliteProject/oolite" ]]; then
        output_builder="OoliteProject"
    else
        output_builder="unknown"
    fi
}