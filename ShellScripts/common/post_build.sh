#!/bin/bash

# Processes Oolite data files after compilation

run_script() {
    local origprogpath="$1"
    local progdir="$2"
    local host_os="$3"
    local debug_monitor="$4"
    local espeak="$5"
    local strip_bin="$6"
    local ver_full="$7"
    local ver_quad="$8"
    local ver_githash="$9"
    local buildtime="${10}"
    local gnustep_folder="${11}"
    local stamp_file="${12}"
    local build_docs="${13:-yes}"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    source "generate_manifest_fn.sh"
    cd ../..
    source Documentation/build_documentation_fn.sh

    if [[ "$host_os" == "darwin" ]]; then
        cp() { gcp "$@"; }  # GNU cp from Homebrew coreutils; BSD cp has no -u
    fi

    set -x
    local appname=$(basename "$origprogpath")
    local appdir=$(dirname "$origprogpath")
    local progpath="$progdir/$appname"
    local resourcesdir="$progdir/Resources"
    local addonsdir="$progdir/AddOns"
    if [[ "$host_os" == "darwin" ]]; then
        # macOS application bundle layout
        source ShellScripts/macOS/create_app_bundle_fn.sh
        rm -rf "$progdir/$appname" "$progdir/Resources" "$progdir/AddOns" "$progdir/$appname.dSYM"  # old flat layout
        progpath="$progdir/Contents/MacOS/$appname"
        resourcesdir="$progdir/Contents/Resources"
        addonsdir="$progdir/Contents/AddOns"
        mkdir -p "$progdir/Contents/MacOS"
        rm -f "$progpath"  # always start from the linked binary, as bundling rewrites it
    fi
    mkdir -p "$resourcesdir"

    if [[ ! -f "$origprogpath" ]]; then
        echo "❌ 'Oolite binary at '$origprogpath' does not exist!" >&2
        return 1
    fi
    if ! cp -fu "$origprogpath" "$progpath"; then
        echo "❌ Failed to copy '$origprogpath' to '$progpath'!" >&2
        return 1
    fi
    generate_manifest "$resourcesdir/manifest.plist" "$debug_monitor" "$ver_full" "$ver_quad" "$ver_githash" "$buildtime"
    mkdir -p "$addonsdir"
    rm -rf "$addonsdir/Basic-debug.oxp"
    cp -rf DebugOXP/Debug.oxp "$addonsdir/Basic-debug.oxp"

    # Voice Data
    if [[ "$espeak" == "yes" ]]; then
        if [[ "$host_os" == "windows" ]]; then
            # Windows espeak-ng-data
            cp -rfu "$MINGW_PREFIX/share/espeak-ng-data" "$resourcesdir"
        else
            # Linux search paths for espeak-ng-data
            local SEARCH_PATHS=(
                "/usr/local/share/espeak-ng-data"
                "/usr/lib/$(uname -m 2>/dev/null || echo x86_64)-linux-gnu/espeak-ng-data"
                "/usr/share/espeak-ng-data"
                "/app/share/espeak-ng-data"
            )
            if [[ "$host_os" == "darwin" ]]; then
                SEARCH_PATHS=("$(realpath "$(brew --prefix)/share/espeak-ng-data")")  # Homebrew links it from the Cellar
            fi
            local found_data=false
            local path
            for path in "${SEARCH_PATHS[@]}"; do
                if [[ -d "$path" ]]; then
                    cp -rfu "$path" "$resourcesdir"
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
    cp -rfu Resources/. "$resourcesdir"
    rm -f "$resourcesdir/AIReference.html" "$resourcesdir/*.icns"

    # Strip binary if requested
    if [[ "$strip_bin" == "yes" ]]; then
        if [[ "$host_os" == "windows" ]]; then
            # Windows: Standard GNU strip is safest for PE/COFF
            strip "$progpath.exe"
        elif [[ "$host_os" == "darwin" ]]; then
            # macOS: keep symbols in a dSYM bundle next to the app
            dsymutil "$progpath" -o "$progdir.dSYM"
            strip -S "$progpath"
        else
            # Linux
            local debugpath="$progdir/$appname.debug"
            # Extract symbols to file
            objcopy --only-keep-debug "$progpath" "$debugpath"
            # Compress the debug sections in the symbol file
            objcopy --compress-debug-sections=zlib-gnu "$debugpath"
            # strip the binary
            strip  -R .comment "$progpath"
            # Add the debug link
            objcopy --add-gnu-debuglink="$debugpath" "$progpath"
        fi
    elif [[ "$host_os" == "linux" ]]; then
        # Compress the debug sections in the binary
        objcopy --compress-debug-sections=zlib-gnu "$progpath"
    fi

    if [[ "$host_os" == "windows" ]]; then
        # Determine and copy DLL dependencies, walking the transitive closure:
        # a newly-copied DLL may itself depend on other MINGW_PREFIX DLLs that
        # are not direct dependencies of the binary (e.g. libtre-5.dll pulls in
        # libsystre-0.dll). Repeat ldd over newly-staged DLLs until a fixed
        # point is reached (no new DLL gets copied in a pass).
        local unix_prefix=$(cygpath -u "$MINGW_PREFIX")
        local -A staged_dlls=()
        local pending=("$progpath")
        while [[ ${#pending[@]} -gt 0 ]]; do
            local next_pending=()
            local dep
            for dep_target in "${pending[@]}"; do
                while IFS= read -r dep; do
                    [[ -z "$dep" ]] && continue
                    local depname=$(basename "$dep")
                    if [[ -z "${staged_dlls[$depname]+x}" ]]; then
                        staged_dlls[$depname]=1
                        cp -rfu "$dep" "$progdir"
                        next_pending+=("$progdir/$depname")
                    fi
                done < <(ldd "$dep_target" | grep "$unix_prefix" | awk '{print $3}')
            done
            pending=("${next_pending[@]}")
        done
    elif [[ "$host_os" == "darwin" ]]; then
        # Apple Foundation is used, so there is no GNUstep runtime to bundle, but the Homebrew
        # libraries are copied in so the app runs on Macs without Homebrew.
        if ! create_info_plist Resources/Info-gnustep.plist "$progdir/Contents/Info.plist" "$appname" "$ver_full" "$ver_quad"; then
            echo "❌ Failed to create Info.plist!" >&2
            return 1
        fi
        rm -f "$resourcesdir/Info-gnustep.plist"
        if ! bundle_dylibs "$progpath" "$progdir/Contents/Frameworks"; then
            echo "❌ Failed to bundle libraries!" >&2
            return 1
        fi
        if ! sign_app_bundle "$progdir"; then
            echo "❌ Failed to sign app bundle!" >&2
            return 1
        fi
    else
        # Copy Linux-specific wrapper script
        cp -fu ShellScripts/Linux/run_oolite.sh "$progdir"
        local gnustep_conf="$gnustep_folder/etc/GNUstep/GNUstep.conf"
        if [ ! -f "$gnustep_conf" ] && [ "$gnustep_folder" = "/usr" ] && [ -f "/etc/GNUstep/GNUstep.conf" ]; then
            gnustep_conf="/etc/GNUstep/GNUstep.conf"
        fi
        # The game no longer links GNUstep-base (meson.build sets gnustep_folder to ''), so there is
        # usually no GNUstep.conf to copy; run_oolite.sh copes with GNUstep.conf.orig being absent.
        if [ -f "$gnustep_conf" ]; then
            install -D "$gnustep_conf" "$resourcesdir/GNUstep.conf.orig" || { echo "$err_msg GNUstep config" >&2; return 1; }
        fi

        # If we're using GNUstep libraries that aren't in a system folder copy them
        ldd "$progpath" | \
            grep -E "libgnustep-base|libobjc\.so\." | \
            grep -vE "^[[:space:]]*.*=>[[:space:]]*/(usr/(local/)?|lib(64)?/)" | \
            awk '{print $3}' | \
            xargs -I {} cp -Lrfu {} "$progdir/"
    fi

    if [[ "$build_docs" == "yes" ]]; then
        if ! build_documentation "NO"; then
            echo "❌ Documentation build failed! Configure with -Ddocs=disabled to build without it." >&2
            popd
            return 1
        fi
        local docdir="$progdir"
        if [[ "$host_os" == "darwin" ]]; then
            # Files in the bundle root break its signature, so the PDFs go next to the app instead
            # and create_dmg_fn.sh puts them in a Documentation folder on the disk image
            rm -f "$progdir"/*.pdf
            docdir="$(dirname "$progdir")/Documentation"
            mkdir -p "$docdir"
        fi
        cp -fu build/documentation/docs/assets/pdfs/* "$docdir"
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
