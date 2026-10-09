#!/bin/bash
# Linux post-build: stripping (with GNU debuglink tooling) and GNUstep
# dependency copying.
#
# Sourced by ShellScripts/common/post_build.sh; defines post_build_platform().

post_build_platform() {
    local progpath="$1"
    local progdir="$2"
    local resourcesdir="$3"
    local strip_bin="$4"
    local gnustep_folder="$5"

    local appname
    appname=$(basename "$progpath")

    # Strip binary if requested
    if [[ "$strip_bin" == "yes" ]]; then
        # Extract symbols to file
        local debugpath="$progdir/$appname.debug"
        objcopy --only-keep-debug "$progpath" "$debugpath"
        # Compress the debug sections in the symbol file
        objcopy --compress-debug-sections=zlib-gnu "$debugpath"
        # strip the binary
        strip -R .comment "$progpath"
        # Add the debug link
        objcopy --add-gnu-debuglink="$debugpath" "$progpath"
    else
        # Compress the debug sections in the binary
        objcopy --compress-debug-sections=zlib-gnu "$progpath"
    fi

    # Copy Linux-specific wrapper script
    cp -fu ShellScripts/Linux/run_oolite.sh "$progdir"
    local gnustep_conf="$gnustep_folder/etc/GNUstep/GNUstep.conf"
    if [ ! -f "$gnustep_conf" ] && [ "$gnustep_folder" = "/usr" ] && [ -f "/etc/GNUstep/GNUstep.conf" ]; then
        gnustep_conf="/etc/GNUstep/GNUstep.conf"
    fi
    install -D "$gnustep_conf" "$resourcesdir/GNUstep.conf.orig" || { echo "❌ GNUstep config" >&2; return 1; }

    # If we're using GNUstep libraries that aren't in a system folder copy them
    ldd "$progpath" | \
        grep -E "libgnustep-base|libobjc\.so\." | \
        grep -vE "^[[:space:]]*.*=>[[:space:]]*/(usr/(local/)?|lib(64)?/)" | \
        awk '{print $3}' | \
        xargs -I {} cp -Lrfu {} "$progdir/"

    return 0
}
