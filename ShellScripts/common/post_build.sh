#!/bin/bash
# Processes Oolite data files after compilation

run_script() {
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ../..

    local OS_EXT=""
    if [ "$GNUSTEP_HOST_OS" = "mingw32" ]; then
        # Windows only executable extension
        OS_EXT=".exe"
    fi
    
    # Debug extension if needed
    local EXT=""
    if [ "$DEBUG" = "yes" ]; then
        EXT=".dbg"
    fi
    
    # Paths and binary names
    local PROGDIR="${OBJC_PROGRAM_NAME}.app"
    local SRC_BIN="${OBJC_PROGRAM_NAME}${OS_EXT}"
    local DEST_BIN="${OBJC_PROGRAM_NAME}${EXT}${OS_EXT}"

    mkdir -p "$PROGDIR/Resources"
    
    tools/mkmanifest.sh > "$PROGDIR/Resources/manifest.plist"
    
    local RESOURCE_DIRS=(
        "Resources/AIs"
        "Resources/Config"
        "Resources/Scenarios"
        "Resources/Scripts"
        "Resources/Shaders"
        "Resources/Binary/Images"
        "Resources/Binary/Models"
        "Resources/Binary/Music"
        "Resources/Binary/Sounds"
        "Resources/Binary/Textures"
        "Schemata"
    )
    for resdir in "${RESOURCE_DIRS[@]}"; do
        cp -rfu "$resdir" "$PROGDIR/Resources"
    done

    cp -fu Resources/README.TXT "$PROGDIR/Resources"
    cp -fu Resources/InfoPlist.strings "$PROGDIR/Resources"
    cp -fu src/Cocoa/Info-Oolite.plist "$PROGDIR/Resources/Info-gnustep.plist"
    cp -fu "$GNUSTEP_OBJ_DIR_NAME/$SRC_BIN" "$PROGDIR/$DEST_BIN"
    
    # Voice Data
    if [ "$ESPEAK" = "yes" ]; then
        if [ "$GNUSTEP_HOST_OS" = "mingw32" ]; then
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
            for path in "${SEARCH_PATHS[@]}"; do
                if [ -d "$path" ]; then
                    cp -rfu "$path" "$PROGDIR/Resources"
                    FOUND_DATA=true
                    break
                fi
            done

            if [ "$FOUND_DATA" = false ]; then
                echo "❌ espeak-ng-data not found in any known location!" >&2
                return 1
            fi
        fi

        # Replace specific voices with Oolite-specific versions
        rm -f "$PROGDIR/Resources/espeak-ng-data/voices/default"
        rm -f "$PROGDIR/Resources/espeak-ng-data/voices/!v/f2"
        cp -fu deps/Cross-platform-deps/espeak-data/voices/!v/f2 "$PROGDIR/Resources/espeak-ng-data/voices/!v/f2"
        cp -fu deps/Cross-platform-deps/espeak-data/voices/default "$PROGDIR/Resources/espeak-ng-data/voices/default"
    fi
    
    # Strip binary if requested
    if [ "$STRIP_BIN" = "yes" ]; then
        ${STRIP:-strip} "$PROGDIR/$DEST_BIN"
    fi
    
    if [ "$GNUSTEP_HOST_OS" = "mingw32" ]; then
        # Determine and copy DLL dependencies
        ldd "$PROGDIR/$DEST_BIN" | grep "$MINGW_PREFIX" | awk '{print $3}' | xargs -I {} cp -rfu {} "$PROGDIR"
    else
        # Copy Linux-specific wrapper script
        cp -fu ShellScripts/Linux/run_oolite.sh "$PROGDIR"
        cp -fu ShellScripts/Linux/splash-launcher "$PROGDIR"

        # If we're using GNUstep libraries that aren't in a system folder copy them
        ldd "$PROGDIR/$DEST_BIN" | \
            grep -E "libgnustep-base|libobjc\.so\." | \
            grep -vE "^/(usr/|usr/local/)?lib(64)?/" | \
            awk '{print $3}' | \
            xargs -I {} cp -Lrfu {} "$PROGDIR/"
    fi

    echo "✅ Oolite post-build completed successfully"
    popd
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

