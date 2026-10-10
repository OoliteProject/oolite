#!/bin/bash
# darwin post-build: bundle completion.
#
# Sourced by ShellScripts/common/post_build.sh; defines post_build_platform().
# Installs the templated Info.plist (meson-substituted, see root meson.build),
# the app icon, bundles every non-system dylib into Contents/Frameworks with
# @rpath rewiring, strips Homebrew/MacPorts rpaths, and ad-hoc re-signs every
# Mach-O — any byte edit invalidates arm64 code signatures, and a stale one
# means SIGKILL at launch.

# Load-command prefixes that must be bundled: Homebrew, MacPorts and
# /usr/local source installs. System paths (/System/*, /usr/lib/*) stay.
_COPY_DEPS_PREFIX='^(/opt/homebrew|/usr/local|/opt/local)/'

# copy_deps <mach-o>
#
# Recursive dependency bundler. For every /opt/homebrew, /usr/local or
# /opt/local load command of <mach-o>: rewrite it to @rpath/<base>, copy the
# dylib into $COPY_DEPS_FW, retarget its id, give the copy an @loader_path
# rpath so its own (rewritten) @rpath loads resolve inside the bundle, strip
# brew-prefixed rpaths from the copy, then recurse into the copy.
#
# Globals set by post_build_platform() before the first call:
#   COPY_DEPS_FW   Contents/Frameworks directory (created)
#   COPY_DEPS_DONE space-separated list of basenames already visited this run
#                  (bash-3.2-safe dedup: no associative arrays)
#
# The load-command rewrite happens BEFORE the dedup check: the main binary is
# freshly linked on every build, so its load commands are always absolute brew
# paths again even when every dylib is already copied. Dedup only prevents
# re-copying/recursion.
copy_deps() {
    # Every per-call scalar is local: copy_deps recurses into the copies, and
    # shared globals (_cd_target first among them) would be clobbered by the
    # callee — the caller's remaining -change calls would silently no-op
    # against the wrong file (install_name_tool -change exits 0 when the old
    # name is absent). COPY_DEPS_FW / COPY_DEPS_DONE stay global on purpose.
    local _cd_target="$1"
    local _cd_loads _cd_deps _cd_dep _cd_base _cd_rp
    if ! _cd_loads=$(otool -L "$_cd_target"); then
        echo "❌ copy_deps: 'otool -L $_cd_target' failed!" >&2
        return 1
    fi
    # grep exits non-zero on zero matches — the normal terminal case of the
    # recursion (all-system deps), not an error.
    _cd_deps=$(printf '%s\n' "$_cd_loads" \
        | awk 'NR>1 {print $1}' \
        | grep -E "$_COPY_DEPS_PREFIX" || true)
    for _cd_dep in $_cd_deps; do
        _cd_base=$(basename "$_cd_dep")
        # Rewrite this dependent's load command on every visit (see above).
        if ! install_name_tool -change "$_cd_dep" "@rpath/$_cd_base" "$_cd_target"; then
            echo "❌ copy_deps: could not rewrite '$_cd_dep' in '$_cd_target'!" >&2
            return 1
        fi
        case " $COPY_DEPS_DONE " in
            *" $_cd_base "*) continue ;;
        esac
        COPY_DEPS_DONE="$COPY_DEPS_DONE $_cd_base"
        # -L: the keg path may be a symlink into the Cellar; copy the target.
        if ! cp -fL "$_cd_dep" "$COPY_DEPS_FW/$_cd_base"; then
            echo "❌ copy_deps: could not copy '$_cd_dep'!" >&2
            return 1
        fi
        if ! install_name_tool -id "@rpath/$_cd_base" "$COPY_DEPS_FW/$_cd_base"; then
            echo "❌ copy_deps: could not set id of '$_cd_base'!" >&2
            return 1
        fi
        # The copy resolves its own @rpath loads against ITS rpaths, not the
        # executable's: point it at its own directory. Add only if absent so
        # re-runs on existing copies stay quiet-and-idempotent.
        if ! otool -l "$COPY_DEPS_FW/$_cd_base" \
            | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }' \
            | grep -Fxq "@loader_path"; then
            if ! install_name_tool -add_rpath "@loader_path" "$COPY_DEPS_FW/$_cd_base"; then
                echo "❌ copy_deps: could not add @loader_path rpath to '$_cd_base'!" >&2
                return 1
            fi
        fi
        # Brew rpaths must never win over the bundle (they would silently
        # resolve loads outside it on machines that have Homebrew).
        for _cd_rp in $(otool -l "$COPY_DEPS_FW/$_cd_base" \
            | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }' \
            | grep -E "$_COPY_DEPS_PREFIX" || true); do
            if ! install_name_tool -delete_rpath "$_cd_rp" "$COPY_DEPS_FW/$_cd_base"; then
                echo "❌ copy_deps: could not delete rpath '$_cd_rp' from '$_cd_base'!" >&2
                return 1
            fi
        done
        copy_deps "$COPY_DEPS_FW/$_cd_base" || return 1
    done
    # Post-condition of this function: no bundling-prefix load command may
    # survive on the target (a silent install_name_tool no-op would fail this).
    if otool -L "$_cd_target" | awk 'NR>1 {print $1}' | grep -qE "$_COPY_DEPS_PREFIX"; then
        echo "❌ copy_deps: '$_cd_target' still loads dylibs outside the bundle after rewriting!" >&2
        return 1
    fi
    return 0
}

post_build_platform() {
    local progpath="$1"
    local progdir="$2"
    local resourcesdir="$3"
    local strip_bin="$4"
    local info_plist="$6" # templated plist from meson; gnustep_folder ($5) unused on darwin

    local binname
    binname=$(basename "$progpath")

    # Upgrades from the flat layout: a stray Resources/ next to Contents/
    # makes codesign reject the bundle ("unsealed contents").
    rm -rf "$progdir/Resources"

    # Real Info.plist, substituted by meson from installers/macos/Info.plist.in
    # (CFBundleShortVersionString @ver_full@; CFBundleVersion @ver_quad@ — the
    # dotted quad ResourceManager's OXP version gate compares against the core
    # manifest's required_oolite_version).
    if [[ -z "$info_plist" ]] || [[ ! -f "$info_plist" ]]; then
        echo "❌ Substituted Info.plist '$info_plist' missing — meson wiring broken!" >&2
        return 1
    fi
    if ! cp -f "$info_plist" "$progdir/Contents/Info.plist"; then
        echo "❌ Failed to install Info.plist into the bundle!" >&2
        return 1
    fi
    if ! plutil -lint "$progdir/Contents/Info.plist"; then
        echo "❌ Bundle Info.plist failed plutil -lint!" >&2
        return 1
    fi

    if [[ "$strip_bin" == "yes" ]]; then
        # Keep debug info in a .dSYM bundle next to the .app, then strip the
        # binary (BSD strip has no GNU objcopy debuglink equivalent).
        #
        # NEXT TO, not inside: codesign refuses to sign a bundle with any
        # bundle-root entry beside Contents/ ("unsealed contents present in
        # the bundle root"), and notarization rejects the same layouts — the
        # first deployment build failed exactly there. Also remove the
        # legacy in-bundle dSYM this script produced before the fix (the
        # bundle directory survives across builds).
        rm -rf "$progdir/$binname.dSYM"
        if ! dsymutil "$progpath" -o "$progdir/../$binname.dSYM"; then
            echo "❌ Failed to extract debug info from '$progpath'!" >&2
            return 1
        fi
        if ! strip -S "$progpath"; then
            echo "❌ Failed to strip '$progpath'!" >&2
            return 1
        fi
    fi

    # App icon: installers/macos/oolite.icns (generated with iconutil from the
    # checked-in Resources/oolite-icon.icns master). Copied here — AFTER the
    # shared post_build's quoted-glob 'rm -f "$resourcesdir/*.icns"' (a
    # literal-name no-op) has already run — so it survives every build.
    local fn_dir
    fn_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if ! cp -f "$fn_dir/../../installers/macos/oolite.icns" "$resourcesdir/oolite.icns"; then
        echo "❌ Failed to install the app icon into the bundle!" >&2
        return 1
    fi

    # Dependency bundling: everything non-system into Contents/Frameworks.
    local bundle_fw
    bundle_fw="$progdir/Contents/Frameworks"
    mkdir -p "$bundle_fw"
    COPY_DEPS_FW="$bundle_fw"
    COPY_DEPS_DONE=""
    if ! copy_deps "$progpath"; then
        return 1
    fi
    # Same for the binary itself: brew rpaths would resolve @rpath loads
    # outside the bundle (they precede @executable_path/../Frameworks in the
    # load-command list), so the "hidden Homebrew" launch would still leak.
    local _rp
    for _rp in $(otool -l "$progpath" \
        | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }' \
        | grep -E "$_COPY_DEPS_PREFIX" || true); do
        if ! install_name_tool -delete_rpath "$_rp" "$progpath"; then
            echo "❌ Could not delete rpath '$_rp' from the binary!" >&2
            return 1
        fi
    done
    echo "ℹ️  Bundled dylibs:$COPY_DEPS_DONE"

    # Ad-hoc re-sign every Mach-O under Contents (dylibs first, main binary
    # last), then seal the bundle. Enumerated explicitly: macOS 26 find
    # rejects the any-bit '-perm /111' spelling ("illegal mode string"), and
    # these two locations are the only Mach-O code in the bundle. NO
    # 2>/dev/null, NO || true: a silently skipped signature means SIGKILL at
    # launch (or notarization rejection hours later in Task 11).
    local macho_file
    for macho_file in "$bundle_fw"/*.dylib "$progpath"; do
        [ -e "$macho_file" ] || continue # empty-Frameworks glob, not an error
        if ! codesign --force --sign - "$macho_file"; then
            echo "❌ Failed to ad-hoc re-sign '$macho_file'!" >&2
            return 1
        fi
    done
    if ! codesign --force --sign - "$progdir"; then
        echo "❌ Failed to ad-hoc seal '$progdir'!" >&2
        return 1
    fi
    if ! codesign --verify --deep --strict "$progdir"; then
        echo "❌ Bundle signature verification failed for '$progdir'!" >&2
        return 1
    fi

    return 0
}
