#!/bin/bash
# Processes Oolite data files after compilation

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir" > /dev/null

    source "generate_manifest_fn.sh"
    cd ../..

    set -x
    local appname=$(basename "$ORIGPROGPATH")
    local appdir=$(dirname "$ORIGPROGPATH")
    local progpath="$PROGDIR/$appname"
    mkdir -p "$PROGDIR/Resources"

    generate_manifest "$PROGDIR/Resources/manifest.plist"

    if [[ ! -f "$ORIGPROGPATH" ]]; then
        echo "❌ 'Oolite binary at '$ORIGPROGPATH' does not exist!" >&2
        return 1
    fi
    if ! cp -fu "$ORIGPROGPATH" "$progpath"; then
        echo "❌ Failed to copy '$ORIGPROGPATH' to '$progpath'!" >&2
        return 1
    fi
    cp -fu "$ORIGPROGPATH" "$progpath"
    ShellScripts/common/mkmanifest.sh > "$PROGDIR/Resources/manifest.plist"
    cp -fu src/Cocoa/Info-Oolite.plist "$PROGDIR/Resources/Info-gnustep.plist"

    # Voice Data
    if [[ "$ESPEAK" == "yes" ]]; then
        if [[ "$HOST_OS" == "windows" ]]; then
            # Windows espeak-ng-data
            cp -rfu "$MINGW_PREFIX/share/espeak-ng-data" "$PROGDIR/Resources"
        else
            # Linux search paths for espeak-ng-data
            local SEARCH_PATHS=(
                "/usr/local/share/espeak-ng-data"
                "/usr/lib/x86_64-linux-gnu/espeak-ng-data"
                "/usr/share/espeak-ng-data"
                "/app/share/espeak-ng-data"
            )
            local found_data=false
            local path
            for path in "${SEARCH_PATHS[@]}"; do
                if [[ -d "$path" ]]; then
                    cp -rfu "$path" "$PROGDIR/Resources"
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
    rm -f "$PROGDIR/Resources/espeak-ng-data/voices/!v/f2"
    rm -f "$PROGDIR/Resources/espeak-ng-data/voices/default"
    cp -rfu Resources/. "$PROGDIR/Resources"
    rm -f "$PROGDIR/Resources/AIReference.html" "$PROGDIR/Resources/*.icns"

    # Strip binary if requested
    if [[ "$STRIP_BIN" == "yes" ]]; then
        if [[ "$HOST_OS" == "windows" ]]; then
            # Windows: Standard GNU strip is safest for PE/COFF
            strip "$progpath"
        else
            # Linux
            local debugpath="$PROGDIR/$appname.debug"
            # Extract symbols to file
            objcopy --only-keep-debug "$progpath" "$debugpath"
            # Compress the debug sections in the symbol file
            objcopy --compress-debug-sections=zlib-gnu "$debugpath"
            # strip the binary
            strip  -R .comment "$progpath"
            # Add the debug link
            objcopy --add-gnu-debuglink="$debugpath" "$progpath"
        fi
    elif [[ "$HOST_OS" == "linux" ]]; then
        # Compress the debug sections in the binary
        objcopy --compress-debug-sections=zlib-gnu "$progpath"
    fi

    if [[ "$HOST_OS" == "windows" ]]; then
        # Determine and copy DLL dependencies
        local unix_prefix=$(cygpath -u "$MINGW_PREFIX")
        ldd "$progpath" | grep "$unix_prefix" | awk '{print $3}' | xargs -I {} cp -rfu {} "$PROGDIR"
    else
        # Copy Linux-specific wrapper script
        cp -fu ShellScripts/Linux/run_oolite.sh "$PROGDIR"
        local gnustep_conf="$GNUSTEP_FOLDER/etc/GNUstep/GNUstep.conf"
        if [ ! -f "$gnustep_conf" ] && [ "$GNUSTEP_FOLDER" = "/usr" ] && [ -f "/etc/GNUstep/GNUstep.conf" ]; then
            gnustep_conf="/etc/GNUstep/GNUstep.conf"
        fi
        install -D "$gnustep_conf" "$PROGDIR/Resources/GNUstep.conf.orig" || { echo "$err_msg GNUstep config" >&2; return 1; }

        # If we're using GNUstep libraries that aren't in a system folder copy them
        ldd "$progpath" | \
            grep -E "libgnustep-base|libobjc\.so\." | \
            grep -vE "^[[:space:]]*.*=>[[:space:]]*/(usr/(local/)?|lib(64)?/)" | \
            awk '{print $3}' | \
            xargs -I {} cp -Lrfu {} "$PROGDIR/"
    fi

    echo "✅ Oolite post-build completed successfully"
    touch "$appdir/$STAMP_FILE"
    popd > /dev/null
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi