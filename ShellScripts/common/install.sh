#!/bin/bash
# Processes Oolite data files after compilation

run_script() {
    local stageprogpath="$1"
    local bindir="$2"
    local datadir="$3"
    local host_os="$4"
    local deployment_release="$5"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    cd ../..

    set -x
    local appname=$(basename "$stageprogpath")
    local progdir=$(dirname "$stageprogpath")
    local installdir="${INSTALLDIR:-$MESON_INSTALL_DESTDIR_PREFIX}"
    local fullbindir="$installdir/$bindir"
    local fulldatadir="$installdir/$datadir/oolite"  # don't use appname here as Obj-C has oolite specifically
    local progpath="$fullbindir/$appname"
    if ! mkdir -p "$fullbindir"; then
        echo "❌ Failed to create folder '$fullbindir'!" >&2
        return 1
    fi
    if ! mkdir -p "$fulldatadir"; then
        echo "❌ Failed to create folder '$fulldatadir'!" >&2
        return 1
    fi
    if ! cp -fu "$stageprogpath" "$progpath"; then
        echo "❌ Failed to copy '$stageprogpath' to '$progpath'!" >&2
        return 1
    fi
    if [[ "$host_os" == "linux" ]]; then
        local run_oolite_src="$progdir/run_oolite.sh"
        local run_oolite_dst="$fullbindir/run_oolite.sh"
        if ! cp -fu "$run_oolite_src" "$run_oolite_dst"; then
            echo "❌ Failed to copy '$run_oolite_src' to '$run_oolite_dst'!" >&2
            return 1
        fi
    fi
    local resources_src="$progdir/Resources/."
    local resources_dst="$fulldatadir/Resources"
    if ! cp -rfu "$resources_src" "$resources_dst"; then
        echo "❌ Failed to copy '$resources_src' to '$resources_dst'!" >&2
        return 1
    fi
    if [[ -d "$progdir/AddOns" ]]; then
        local addons_src="$progdir/AddOns/."
        local addons_dst="$fulldatadir/AddOns"
        if ! cp -rfu "$addons_src" "$addons_dst"; then
            echo "❌ Failed to copy '$addons_src' to '$addons_dst'!" >&2
            return 1
        fi
    fi
    echo "✅ Oolite install completed successfully"
    popd > /dev/null
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi