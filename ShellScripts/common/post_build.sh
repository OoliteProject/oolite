#!/bin/bash
# Processes Oolite data files after compilation

run_script() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ../..

    OS_EXT=""
    if [ "$GNUSTEP_HOST_OS" = "mingw32" ]; then
        # Windows only executable extension
        OS_EXT=".exe"
    fi
    
    # Debug extension if needed
    EXT=""
    if [ "$DEBUG" = "yes" ]; then
        EXT=".dbg"
    fi
    
    # Paths and binary names
    PROGDIR="${OBJC_PROGRAM_NAME}.app"
    SRC_BIN="${OBJC_PROGRAM_NAME}${OS_EXT}"
    DEST_BIN="${OBJC_PROGRAM_NAME}${EXT}${OS_EXT}"

    mkdir -p "$PROGDIR/Resources"
    
    tools/mkmanifest.sh > "$PROGDIR/Resources/manifest.plist"
    
    RESOURCE_DIRS=(
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
        if [ "$MODERN" = "yes" ]; then
            if [ "$GNUSTEP_HOST_OS" = "mingw32" ]; then
                # Windows modern espeak-ng-data
                cp -rfu "$MINGW_PREFIX/share/espeak-ng-data" "$PROGDIR/Resources"
            else
                # Linux modern search paths for espeak-ng-data
                SEARCH_PATHS=(
                    "/usr/local/share/espeak-ng-data"
                    "/usr/lib/x86_64-linux-gnu/espeak-ng-data"
                    "/usr/share/espeak-ng-data"
                    "/app/share/espeak-ng-data"
                )
                FOUND_DATA=false
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
        else
            # Legacy espeak-data
            if [ "$GNUSTEP_HOST_OS" = "mingw32" ] || [ "$USE_DEPS" = "yes" ]; then
                cp -rfu deps/Cross-platform-deps/espeak-data "$PROGDIR/Resources"
            fi
        fi
    fi
    
    # Strip binary if requested
    if [ "$STRIP_BIN" = "yes" ]; then
        ${STRIP:-strip} "$PROGDIR/$DEST_BIN"
    fi
    
    if [ "$GNUSTEP_HOST_OS" = "mingw32" ]; then
        if [ "$MODERN" = "yes" ]; then
            # Determine and copy DLL dependencies for modern Windows
            ldd "$PROGDIR/$DEST_BIN" | grep "$MINGW_PREFIX" | awk '{print $3}' | xargs -I {} cp -rfu {} "$PROGDIR"
        else
            # Copy legacy Windows DLLs
            if [ "$GNUSTEP_HOST_CPU" = "x86_64" ]; then
                cp -rfu deps/Windows-deps/x86_64/DLLs/*.dll "$PROGDIR"
            else
                cp -rfu deps/Windows-deps/x86/DLLs/*.dll "$PROGDIR"
            fi
    
            if [ "$DEBUG" = "no" ]; then
                rm -f "$PROGDIR/js32ECMAv5dbg.dll"
            fi
            rm -f "$PROGDIR/js32ECMAv5.dll"
        fi
    else
        # Copy Linux-specific wrapper script
        cp -fu ShellScripts/Linux/run_oolite.sh "$PROGDIR"
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

