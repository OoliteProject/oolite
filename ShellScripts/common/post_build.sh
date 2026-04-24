#!/bin/bash
# Processes Oolite data files after compilation

run_script() {
    # All variables declared local to avoid global scope pollution
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR" > /dev/null

    cd ../..

    local EXT=""
    local OS_EXT=""
    if [[ "$GNUSTEP_HOST_OS" == "mingw32" ]]; then
        # Windows only executable extension
        OS_EXT=".exe"
       # Debug extension if needed
        if [[ "$DEBUG" == "yes" ]]; then
            EXT=".dbg"
        fi
    fi

    # Paths and binary names
    local PROGDIR="${OBJC_PROGRAM_NAME}.app"
    local SRC_BIN="${OBJC_PROGRAM_NAME}${OS_EXT}"
    local DEST_BIN="${OBJC_PROGRAM_NAME}${EXT}${OS_EXT}"

    mkdir -p "$PROGDIR/Resources"

    ShellScripts/common/mkmanifest.sh > "$PROGDIR/Resources/manifest.plist"

    cp -fu src/Cocoa/Info-Oolite.plist "$PROGDIR/Resources/Info-gnustep.plist"
    cp -fu "$GNUSTEP_OBJ_DIR_NAME/$SRC_BIN" "$PROGDIR/$DEST_BIN"

    # Voice Data
    if [[ "$ESPEAK" == "yes" ]]; then
        if [[ "$GNUSTEP_HOST_OS" == "mingw32" ]]; then
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
        if [[ "$GNUSTEP_HOST_OS" == "mingw32" ]]; then
            # Windows: Standard GNU strip is safest for PE/COFF
            strip "$PROGDIR/$DEST_BIN"
        else
            # Linux
            cp -f "$GNUSTEP_OBJ_DIR_NAME/$SRC_BIN" "$PROGDIR/$DEST_BIN"
            # Extract symbols to file
            objcopy --only-keep-debug "$PROGDIR/$DEST_BIN" "$PROGDIR/$DEST_BIN.debug"
            # Compress the debug sections in the symbol file
            objcopy --compress-debug-sections=zlib-gnu "$PROGDIR/$DEST_BIN.debug"
            # strip the binary
            strip  -R .comment "$PROGDIR/$DEST_BIN"
            # Add the debug link
            objcopy --add-gnu-debuglink="$PROGDIR/$DEST_BIN.debug" "$PROGDIR/$DEST_BIN"
        fi
    elif [[ "$GNUSTEP_HOST_OS" == "linux-gnu" ]]; then
        # Compress the debug sections in the binary
        objcopy --compress-debug-sections=zlib-gnu "$PROGDIR/$DEST_BIN"
    fi

    if [[ "$GNUSTEP_HOST_OS" == "mingw32" ]]; then
        # Determine and copy DLL dependencies
        ldd "$PROGDIR/$DEST_BIN" | grep "$MINGW_PREFIX" | awk '{print $3}' | xargs -I {} cp -rfu {} "$PROGDIR"
    else
        # Copy Linux-specific wrapper script
        cp -fu ShellScripts/Linux/run_oolite.sh "$PROGDIR"
        cp -fu ShellScripts/Linux/splash-launcher "$PROGDIR"

        # If we're using GNUstep libraries that aren't in a system folder copy them
        ldd "$PROGDIR/$DEST_BIN" | \
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