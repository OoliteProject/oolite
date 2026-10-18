#!/bin/bash
# Processes Oolite data files after compilation.
#
# Platform-specific work (binary stripping, dependency copying, bundle
# layout) lives in per-platform function scripts sourced from here —
# ShellScripts/{Darwin,Linux,Windows}/post_build_fn.sh — each defining
# post_build_platform(). This file stays the shared dispatcher plus the
# platform-independent steps.

run_script() {
    local origprogpath="$1"
    local progdir="$2"
    local host_os="$3"
    local debug="$4"
    local deployment_release="$5"
    local espeak="$6"
    local strip_bin="$7"
    local ver_full="$8"
    local ver_quad="$9"
    local ver_githash="${10}"
    local buildtime="${11}"
    local gnustep_folder="${12}"
    local stamp_file="${13}"
    local info_plist="${14}"  # macOS bundle Info.plist (unused off-darwin)

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    source "generate_manifest_fn.sh"
    cd ../..

    set -x
    local appname=$(basename "$origprogpath")
    local appdir=$(dirname "$origprogpath")

    # cp -u is a GNU extension; BSD cp (darwin) aborts on it. A helper keeps
    # the call sites shared while each platform gets the right spelling.
    if [[ "$host_os" == "darwin" ]]; then
        cp_update() { cp -Rf "$@"; }
    else
        cp_update() { cp -rfu "$@"; }
    fi

    # darwin builds a .app bundle: binary in Contents/MacOS, resources in
    # Contents/Resources. Other hosts keep the flat layout.
    local progpath resourcesdir
    if [[ "$host_os" == "darwin" ]]; then
        progpath="$progdir/Contents/MacOS/$appname"
        resourcesdir="$progdir/Contents/Resources"
        mkdir -p "$progdir/Contents/MacOS" "$resourcesdir"
    else
        progpath="$progdir/$appname"
        resourcesdir="$progdir/Resources"
        mkdir -p "$resourcesdir"
    fi

    if [[ ! -f "$origprogpath" ]]; then
        echo "❌ 'Oolite binary at '$origprogpath' does not exist!" >&2
        return 1
    fi
    # The binary is always fresh from the build, so the update-skip of -u is
    # never taken; darwin uses plain -f.
    if [[ "$host_os" == "darwin" ]]; then
        if ! cp -f "$origprogpath" "$progpath"; then
            echo "❌ Failed to copy '$origprogpath' to '$progpath'!" >&2
            return 1
        fi
    else
        if ! cp -fu "$origprogpath" "$progpath"; then
            echo "❌ Failed to copy '$origprogpath' to '$progpath'!" >&2
            return 1
        fi
    fi
    generate_manifest "$resourcesdir/manifest.plist" "$deployment_release" "$ver_full" "$ver_quad" "$ver_githash" "$buildtime"
    if [[ "$deployment_release" == "no" ]]; then
        local addonsdir
        if [[ "$host_os" == "darwin" ]]; then
            # Oolite looks for AddOns next to the bundle, not inside it.
            addonsdir="$(dirname "$progdir")/AddOns"
        else
            addonsdir="$progdir/AddOns"
        fi
        mkdir -p "$addonsdir"
        rm -rf "$addonsdir/Basic-debug.oxp"
        cp -rf DebugOXP/Debug.oxp "$addonsdir/Basic-debug.oxp"
    fi

    # Voice Data
    if [[ "$espeak" == "yes" ]]; then
        if [[ "$host_os" == "windows" ]]; then
            # Windows espeak-ng-data
            cp_update "$MINGW_PREFIX/share/espeak-ng-data" "$resourcesdir"
        else
            # Linux search paths for espeak-ng-data
            local SEARCH_PATHS=(
                "/usr/local/share/espeak-ng-data"
                "/usr/lib/$(uname -m 2>/dev/null || echo x86_64)-linux-gnu/espeak-ng-data"
                "/usr/share/espeak-ng-data"
                "/app/share/espeak-ng-data"
            )
            if [[ "$host_os" == "darwin" ]]; then
                # Homebrew keg (or the /opt/homebrew default when brew is
                # unavailable in the environment). The brew entry is a
                # symlink into the Cellar; BSD cp -R would copy the link
                # itself, so resolve it first (and clear any previously
                # copied link).
                local espeak_data_dir
                espeak_data_dir=$(readlink -f "$(command -v brew > /dev/null 2>&1 && brew --prefix || echo /opt/homebrew)/share/espeak-ng-data")
                SEARCH_PATHS+=("$espeak_data_dir")
            fi
            local found_data=false
            local path
            for path in "${SEARCH_PATHS[@]}"; do
                if [[ -d "$path" ]]; then
                    # -rf: the destination may be the directory left by a
                    # previous build (rm -f would fail noisily on it); on a
                    # nonexistent path rm -rf is as silent as rm -f.
                    rm -rf "$resourcesdir/espeak-ng-data"
                    cp_update "$path" "$resourcesdir"
                    found_data=true
                    break
                fi
            done

            if [[ "$found_data" == false ]]; then
                echo "❌ espeak-ng-data not found in any known location!" >&2
                return 1
            fi
        fi

    fi

    # Replace specific voices with Oolite-specific versions
    rm -f "$resourcesdir/espeak-ng-data/voices/!v/f2"
    rm -f "$resourcesdir/espeak-ng-data/voices/default"
    cp_update Resources/. "$resourcesdir"
    rm -f "$resourcesdir/AIReference.html" "$resourcesdir/*.icns"

    # Stripping and dependency copying are entirely host-specific.
    local platform_dir
    case "$host_os" in
        darwin)
            platform_dir="Darwin"
            ;;
        windows | cygwin)
            platform_dir="Windows"
            ;;
        *)
            platform_dir="Linux"
            ;;
    esac
    source "$script_dir/../$platform_dir/post_build_fn.sh"
    if ! post_build_platform "$progpath" "$progdir" "$resourcesdir" "$strip_bin" "$gnustep_folder" "$info_plist"; then
        return 1
    fi

    echo "✅ Oolite post-build completed successfully"
    touch "$appdir/$stamp_file"
    popd > /dev/null
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
