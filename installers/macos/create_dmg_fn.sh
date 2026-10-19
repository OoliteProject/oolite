#!/bin/bash

#
# Creates a macOS disk image (.dmg) containing Oolite.app and a link to /Applications,
# so the app can be installed by dragging it across.

create_dmg() {
    local build_type="$1"  # Typically one of "deployment", "test", "dev"
    local app_folder="$2"  # App bundle relative to the build folder, e.g. meson_dev/oolite.app

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    local build_dir=$(cd "$script_dir/../../build" &> /dev/null && pwd)
    local app_path="$build_dir/$app_folder"

    if [[ ! -f "$app_path/Contents/Info.plist" ]]; then
        echo "❌ App bundle '$app_path' not found. Run ./mk.sh build $build_type first." >&2
        return 1
    fi

    local ver_full
    if ! ver_full=$(plutil -extract version raw "$app_path/Contents/Resources/manifest.plist"); then
        echo "❌ Failed to read the version from the app bundle's manifest.plist!" >&2
        return 1
    fi
    local arch=$(uname -m)
    local out_name="Oolite-$ver_full-$build_type-$arch.dmg"
    local out_path="$build_dir/$out_name"
    local volume_name="Oolite $ver_full"
    if [[ "$build_type" != "deployment" ]]; then
        volume_name+=" ($build_type)"
    fi

    # Stage the disk image contents
    local staging="$build_dir/dmg_$build_type"
    rm -rf "$staging"
    mkdir -p "$staging"
    if ! ditto "$app_path" "$staging/Oolite.app"; then
        echo "❌ Failed to copy '$app_path' to the disk image staging folder!" >&2
        return 1
    fi
    ln -s /Applications "$staging/Applications"

    echo "Creating $out_name..."
    rm -f "$out_path"
    if ! hdiutil create -volname "$volume_name" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$out_path"; then
        echo "❌ hdiutil failed to create $out_path!" >&2
        rm -rf "$staging"
        return 1
    fi
    rm -rf "$staging"

    if ! hdiutil verify "$out_path" > /dev/null; then
        echo "❌ $out_path failed verification!" >&2
        return 1
    fi
    echo "✅ Created $out_path"
}
