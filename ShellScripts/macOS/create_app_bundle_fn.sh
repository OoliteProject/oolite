#!/bin/bash
# Helpers used by post_build.sh to turn the macOS build into a self-contained .app bundle.
#
# Layout:
#   oolite.app/Contents/Info.plist
#   oolite.app/Contents/MacOS/oolite
#   oolite.app/Contents/Resources/...   game data, as Resources/ on other platforms
#   oolite.app/Contents/AddOns/...      bundled OXPs (Basic-debug.oxp in non-deployment builds)
#   oolite.app/Contents/Frameworks/...  non-system dylibs, so the app runs without Homebrew

# Writes Contents/Info.plist from Resources/Info-gnustep.plist.
#   $1 = template plist, $2 = output plist, $3 = executable name, $4 = full version, $5 = version quad
create_info_plist() {
    local template="$1"
    local output="$2"
    local exe_name="$3"
    local ver_full="$4"
    local ver_quad="$5"

    local short_version="${ver_full#v}"
    short_version="${short_version%%[-+]*}"  # e.g. 1.93.1-foo+dirty.3 -> 1.93.1
    local min_macos
    min_macos=$(sw_vers -productVersion | cut -d. -f1).0  # bundled Homebrew dylibs target this macOS

    cp "$template" "$output" || return 1
    # Keys used only by the old Cocoa front end
    local key
    for key in NSMainNibFile NSPrincipalClass NSDockTilePlugIn SUPublicDSAKeyFile LSMinimumSystemVersionByArchitecture; do
        plutil -remove "$key" "$output" 2> /dev/null
    done
    plutil -replace CFBundleExecutable -string "$exe_name" "$output" &&
        plutil -replace CFBundleShortVersionString -string "$short_version" "$output" &&
        plutil -replace CFBundleVersion -string "${ver_quad// /}" "$output" &&
        plutil -replace LSMinimumSystemVersion -string "$min_macos" "$output" &&
        plutil -replace NSHighResolutionCapable -bool YES "$output" &&
        plutil -lint "$output" > /dev/null
}

# Is this a library that must be bundled (i.e. not part of macOS)?
_is_bundleable_lib() {
    [[ "$1" != /usr/lib/* && "$1" != /System/* && "$1" != @* ]]
}

# Copies every non-system dylib the executable needs (recursively) into Contents/Frameworks and
# rewrites the load commands to use @rpath, which resolves to Contents/Frameworks.
#   $1 = executable, $2 = Frameworks directory
bundle_dylibs() {
    local exe="$1"
    local frameworks="$2"
    mkdir -p "$frameworks" || return 1

    local pending=("$exe")
    local processed=" "
    while ((${#pending[@]} > 0)); do
        local binary="${pending[0]}"
        pending=("${pending[@]:1}")
        [[ "$processed" == *" $binary "* ]] && continue
        processed+="$binary "

        local dep
        while read -r dep; do
            _is_bundleable_lib "$dep" || continue
            local name
            name=$(basename "$dep")
            local bundled="$frameworks/$name"
            if [[ ! -f "$bundled" ]]; then
                cp -L "$dep" "$bundled" || { echo "❌ Failed to bundle $dep" >&2; return 1; }
                chmod u+w "$bundled"
                install_name_tool -id "@rpath/$name" "$bundled" 2> /dev/null || return 1
                pending+=("$bundled")
            fi
            install_name_tool -change "$dep" "@rpath/$name" "$binary" 2> /dev/null || return 1
        done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -v "^$(otool -D "$binary" | tail -n +2)$")
    done

    # Replace build-machine rpaths with the bundle's Frameworks folder
    local rpath
    while read -r rpath; do
        install_name_tool -delete_rpath "$rpath" "$exe" 2> /dev/null
    done < <(otool -l "$exe" | awk '/cmd LC_RPATH/{getline; getline; print $2}')
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$exe" || return 1
    local lib
    for lib in "$frameworks"/*.dylib; do
        install_name_tool -add_rpath "@loader_path" "$lib" 2> /dev/null
    done
    return 0
}

# Ad-hoc signs the bundle (required for arm64 binaries after install_name_tool changes them).
# An ad-hoc signature is enough to run a local build, but Gatekeeper blocks a downloaded copy
# until the user allows it in System Settings > Privacy & Security (issue #779). Stopping that
# needs a Developer ID Application certificate (Apple Developer Program), signing with
# --options runtime --timestamp, then notarising and stapling the DMG (xcrun notarytool,
# xcrun stapler). CI would need the certificate and notarisation credentials as secrets.
#   $1 = .app path
sign_app_bundle() {
    codesign --force --sign - "$1"/Contents/Frameworks/*.dylib 2> /dev/null
    codesign --force --sign - "$1"
}
