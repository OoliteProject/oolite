#!/bin/bash
# Windows post-build: stripping and DLL dependency copying.
#
# Sourced by ShellScripts/common/post_build.sh; defines post_build_platform().

post_build_platform() {
    local progpath="$1"
    local progdir="$2"
    local resourcesdir="$3"  # unused on Windows
    local strip_bin="$4"
    # 5th argument (gnustep_folder) is not meaningful on Windows.

    # Strip binary if requested
    if [[ "$strip_bin" == "yes" ]]; then
        # Windows: Standard GNU strip is safest for PE/COFF
        strip "$progpath"
    fi

    # Determine and copy DLL dependencies
    local unix_prefix
    unix_prefix=$(cygpath -u "$MINGW_PREFIX")
    ldd "$progpath" | grep "$unix_prefix" | awk '{print $3}' | xargs -I {} cp -rfu {} "$progdir"

    return 0
}
