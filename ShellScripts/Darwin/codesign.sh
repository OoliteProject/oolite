#!/bin/bash
# darwin release gate: Developer ID distribution signing.
#
# Signs every Mach-O inside an .app bundle, then seals the bundle, with a
# Developer ID Application identity for distribution + notarization (see
# notarize.sh for the notarization half). This is a STANDALONE release gate,
# not part of the build: the build's post-build (post_build_fn.sh) ad-hoc
# signs every bundle it produces, and any later byte edit invalidates an
# arm64 signature — so distribution signing always runs last, on a finished
# bundle.
#
# Environment:
#   MACOS_SIGNING_IDENTITY   Developer ID Application identity, exactly as
#                            shown by `security find-identity -v -p
#                            codesigning` (the full name or its 40-char SHA-1).
#                            Apple Development identities can sign locally but
#                            can NEVER be notarized; the ad-hoc identity '-'
#                            is refused here — ad-hoc is the local-run path,
#                            not a release pass.
#
# Entitlements: deliberately none. Oolite embeds SpiderMonkey 1.8.5 built
# interpreter-only (no JIT), so hardened runtime needs no
# com.apple.security.cs exceptions; granting any would only widen the
# attack surface.
#
# Enumeration: nested Mach-O first, bundle seal last. Every regular file is
# probed with file(1) and only "Mach-O" answers are signed — macOS 26 find
# rejects the any-bit '-perm /111' spelling ("illegal mode string"), and an
# executability filter is the wrong tool anyway (it misses LTO'd/stripped
# oddities and signs data files that merely carry +x). Per-file signatures
# are atomic (one Mach-O, no nested code), so file ORDER is irrelevant;
# only the composite signature — the bundle seal — must come last, and does.
#
# Fail-hard discipline: set -euo pipefail, no `|| true`, no stderr
# suppression. A silently skipped signature is invisible until it is
# somebody else's machine: SIGKILL at launch, or a notarization rejection
# hours later.
#
# Usage: codesign.sh [path/to/Oolite.app]
#        (default: build/meson_deployment/oolite.app)

set -euo pipefail

die() {
    echo "❌ $1" >&2
    exit 1
}

identity="${MACOS_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    cat >&2 <<'EOF'
❌ MACOS_SIGNING_IDENTITY is not set!
   Export the Developer ID Application identity to sign with, e.g.:
       export MACOS_SIGNING_IDENTITY="Developer ID Application: <name> (<team id>)"
   (Requires Apple Developer Program membership. Without it this gate is
   BLOCKED: ad-hoc sign locally and record the gate as blocked instead.)
EOF
    exit 1
fi
if [[ "$identity" == "-" ]]; then
    echo "❌ Refusing the ad-hoc identity '-' — codesign.sh is the distribution gate." >&2
    echo "   Ad-hoc signing is done directly (codesign --force --sign - <bundle>)," >&2
    echo "   never through this script: it must not be mistaken for a release pass." >&2
    exit 1
fi
case "$identity" in
    *"Developer ID Application"*) ;;
    *)
        echo "⚠️  '$identity' does not look like a Developer ID Application identity." >&2
        echo "   It signs, but notarization (notarize.sh) will refuse it." >&2
        ;;
esac

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
bundle="${1:-$repo_root/build/meson_deployment/oolite.app}"

[[ -d "$bundle" ]] || die "Bundle '$bundle' does not exist — build it first (./mk.sh build deployment)."
[[ -f "$bundle/Contents/Info.plist" ]] || die "'$bundle' has no Contents/Info.plist — not an .app bundle."
command -v codesign >/dev/null || die "codesign not found (install Xcode command line tools)."
command -v file >/dev/null || die "file(1) not found."

# The identity must already be in a keychain codesign can reach; matching
# here turns a typo into an immediate, quoted error instead of a codesign
# failure mid-loop. grep -F: identity names contain regex metacharacters.
if ! security find-identity -v -p codesigning | grep -Fq -- "$identity"; then
    echo "❌ Signing identity not found among valid codesigning identities:" >&2
    security find-identity -v -p codesigning >&2
    die "Export MACOS_SIGNING_IDENTITY exactly as listed above."
fi

# NUL-delimited manifest via a temp file: a pipe would hide find's exit
# status from set -e (the loop would silently end on a traversal error).
macho_list=$(mktemp)
trap 'rm -f "$macho_list"' EXIT
if ! find "$bundle" -type f -print0 > "$macho_list"; then
    die "find could not enumerate '$bundle' — bundle is incomplete or unreadable!"
fi

signed=0
while IFS= read -r -d '' macho_file; do
    if ! file_desc=$(file -b -- "$macho_file"); then
        die "file(1) failed on '$macho_file'!"
    fi
    case "$file_desc" in
        *Mach-O*) ;;
        *) continue ;;
    esac
    echo "ℹ️  Signing Mach-O: $macho_file"
    if ! codesign --force --options runtime --timestamp --sign "$identity" "$macho_file"; then
        die "Failed to sign '$macho_file'!"
    fi
    signed=$((signed + 1))
done < "$macho_list"

if [[ "$signed" -eq 0 ]]; then
    die "No Mach-O found under '$bundle' — wrong path or an empty bundle!"
fi
echo "ℹ️  Signed $signed nested Mach-O file(s); sealing the bundle."

if ! codesign --force --options runtime --timestamp --sign "$identity" "$bundle"; then
    die "Failed to seal '$bundle'!"
fi
if ! codesign --verify --deep --strict --verbose=2 "$bundle"; then
    die "Signature verification failed for '$bundle'!"
fi

echo "✅ '$bundle' signed with hardened runtime + timestamped Developer ID — ready for notarize.sh"
