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

# One-time date-flavour detection, done at source time: GNU date parses
# "@<epoch>" with -d; BSD date (macOS) reads epochs with -r and parses
# fixed-format strings with -j -f. Linux keeps the GNU paths throughout, so
# its output is unchanged.
if date -u -d "@0" "+%Y" > /dev/null 2>&1; then
    OOL_DATE_GNU=1
else
    OOL_DATE_GNU=0
fi

# _ool_date_fmt EPOCH FORMAT — format an epoch second as UTC.
_ool_date_fmt() {
    if [[ "$OOL_DATE_GNU" == 1 ]]; then
        date -u -d "@$1" "$2"
    else
        date -u -r "$1" "$2"
    fi
}

# _ool_date_to_epoch "YYYY-MM-DD HH:MM" — parse a naive UTC date string.
_ool_date_to_epoch() {
    if [[ "$OOL_DATE_GNU" == 1 ]]; then
        date -u -d "$1" "+%s"
    else
        date -u -j -f "%Y-%m-%d %H:%M" "$1" "+%s"
    fi
}

get_build_date() {
    # bash 3.2 has no namerefs: the caller passes variable NAMES and results
    # are written back with printf -v.
    local cpp_date_var="$1"
    local app_date_var="$2"
    local buildtime_var="$3"
    local builder_var="$4"
    local buildtime="$5"

    if [[ -z "$buildtime" ]]; then
        local getversion_timestamp
        getversion_timestamp=$(git log -1 --format=%ct)
        buildtime=$(_ool_date_fmt "$getversion_timestamp" "+%Y.%m.%d %H:%M")
    fi

    local clean_date="${buildtime//./-}"
    local epoch
    epoch=$(_ool_date_to_epoch "$clean_date")
    printf -v "$cpp_date_var" '%s' "$(_ool_date_fmt "$epoch" +"%b%e %Y")"
    printf -v "$app_date_var" '%s' "$(_ool_date_fmt "$epoch" +"%Y-%m-%d")"
    printf -v "$buildtime_var" '%s' "$buildtime"

    if [[ "$GITHUB_REPOSITORY" == "OoliteProject/oolite" ]]; then
        printf -v "$builder_var" '%s' "OoliteProject"
    else
        printf -v "$builder_var" '%s' "unknown"
    fi
}
