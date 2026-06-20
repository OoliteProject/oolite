#!/bin/bash
# Processes Oolite data files after compilation

run_script() {
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR" > /dev/null

    cd ../..

    set -x
    PROGDIR="$(dirname "$PROGPATH")"
    mkdir -p "$PROGDIR/Resources"

    source "generate_manifest_fn.sh"
    generate_manifest "$PROGDIR/Resources/manifest.plist"

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
            local FOUND_DATA=false
            local path
            for path in "${SEARCH_PATHS[@]}"; do
                if [[ -d "$path" ]]; then
                    cp -rfu "$path" "$PROGDIR/Resources"
                    FOUND_DATA=true
                    break
                fi
            done

            if [[ "$FOUND_DATA" == false ]]; then
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
            strip "$PROGPATH"
        else
            # Linux
            DEBUGPATH="$PROGDIR/$(basename "$PROGPATH").debug"
            # Extract symbols to file
            objcopy --only-keep-debug "$PROGPATH" "$DEBUGPATH"
            # Compress the debug sections in the symbol file
            objcopy --compress-debug-sections=zlib-gnu "$DEBUGPATH"
            # strip the binary
            strip  -R .comment "$PROGPATH"
            # Add the debug link
            objcopy --add-gnu-debuglink="$DEBUGPATH" "$PROGPATH"
        fi
    elif [[ "$HOST_OS" == "linux" ]]; then
        # Compress the debug sections in the binary
        objcopy --compress-debug-sections=zlib-gnu "$PROGPATH"
    fi

    if [[ "$HOST_OS" == "windows" ]]; then
        # Determine and copy DLL dependencies
        UNIX_PREFIX=$(cygpath -u "$MINGW_PREFIX")
        ldd "$PROGPATH" | grep "$UNIX_PREFIX" | awk '{print $3}' | xargs -I {} cp -rfu {} "$PROGDIR"
    else
        # Copy Linux-specific wrapper script
        cp -fu ShellScripts/Linux/run_oolite.sh "$PROGDIR"
        local GNUSTEP_CONF="$GNUSTEP_FOLDER/etc/GNUstep/GNUstep.conf"
        if [ ! -f "$GNUSTEP_CONF" ] && [ "$GNUSTEP_FOLDER" = "/usr" ] && [ -f "/etc/GNUstep/GNUstep.conf" ]; then
            GNUSTEP_CONF="/etc/GNUstep/GNUstep.conf"
        fi
        install -D "$GNUSTEP_CONF" "$PROGDIR/Resources/GNUstep.conf.orig" || { echo "$err_msg GNUstep config" >&2; return 1; }

        # If we're using GNUstep libraries that aren't in a system folder copy them
        ldd "$PROGPATH" | \
            grep -E "libgnustep-base|libobjc\.so\." | \
            grep -vE "^[[:space:]]*.*=>[[:space:]]*/(usr/(local/)?|lib(64)?/)" | \
            awk '{print $3}' | \
            xargs -I {} cp -Lrfu {} "$PROGDIR/"
    fi

    echo "✅ Oolite post-build completed successfully"
    popd > /dev/null
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi