#!/bin/bash
#
# Calculates the Oolite build date
#

SUITE_PARENT=$(basename "${BASH_SOURCE[1]}")  # Get the name of the script that is sourcing this file
ALLOWED_SCRIPT="get_version.sh"  # Define the ONLY script allowed to source this
if [[ "$SUITE_PARENT" != "$ALLOWED_SCRIPT" ]]; then
    echo "❌ This file can only be sourced by $ALLOWED_SCRIPT!" >&2
    unset SUITE_PARENT ALLOWED_SCRIPT
    return 1 2>/dev/null || exit 1
fi
unset SUITE_PARENT ALLOWED_SCRIPT

get_build_date() {
    local -n _cpp_date="$1"
    local -n _app_date="$2"
    local -n _buildtime="$3"
    local -n _builder="$4"
    local buildtime="$5"


    if [[ -z "$buildtime" ]]; then
        local getversion_timestamp=$(git log -1 --format=%ct)
        _buildtime=$(date -u -d "@$getversion_timestamp" "+%Y.%m.%d %H:%M")
    else
        _buildtime="$buildtime"
    fi

    local clean_date="${_buildtime//./-}"
    _cpp_date=$(date -u -d "$clean_date" +"%b%e %Y")
    _app_date=$(date -u -d "$clean_date" +"%Y-%m-%d")

    if [[ "$GITHUB_REPOSITORY" == "OoliteProject/oolite" ]]; then
        _builder="OoliteProject"
    else
        _builder="unknown"
    fi
}