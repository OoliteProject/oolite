#!/bin/bash
# darwin release gate: notarization, stapling and the Gatekeeper verdict.
#
# Ship path: ditto-zip the signed bundle, submit to Apple notary service and
# wait, staple the ticket onto the bundle, then prove Gatekeeper accepts it.
# Run AFTER codesign.sh — notarization consumes the bundle's Developer ID
# signature; it cannot create one.
#
# Environment:
#   MACOS_NOTARY_PROFILE   Keychain profile name for notarytool credentials
#                          (created once with `xcrun notarytool store-credentials`).
#
# Fail-hard discipline: set -euo pipefail, no `|| true`, no stderr
# suppression. Every step below is a gate; a passed step is printed, a
# failed step aborts with the fix in the message. There is no such thing as
# a "mostly notarized" app.
#
# Usage: notarize.sh [path/to/Oolite.app]
#        (default: build/meson_deployment/oolite.app)

set -euo pipefail

die() {
    echo "❌ $1" >&2
    exit 1
}

profile="${MACOS_NOTARY_PROFILE:-}"
if [[ -z "$profile" ]]; then
    cat >&2 <<'EOF'
❌ MACOS_NOTARY_PROFILE is not set!
   Store App Store Connect API credentials once:
       xcrun notarytool store-credentials <profile> --key ... --issuer ... --key-id ...
   then export MACOS_NOTARY_PROFILE=<profile>.
   (Requires Apple Developer Program membership. Without it this gate is
   BLOCKED: record it as blocked instead of shipping unsigned.)
EOF
    exit 1
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
bundle="${1:-$repo_root/build/meson_deployment/oolite.app}"

[[ -d "$bundle" ]] || die "Bundle '$bundle' does not exist — build and sign it first."
[[ -f "$bundle/Contents/Info.plist" ]] || die "'$bundle' has no Contents/Info.plist — not an .app bundle."
command -v ditto >/dev/null || die "ditto not found."
command -v xcrun >/dev/null || die "xcrun not found (install Xcode command line tools)."
command -v spctl >/dev/null || die "spctl not found."

# Pre-flight 1: the existing signature must verify before we spend a
# notary round-trip (minutes) on something codesign can reject in seconds.
if ! codesign --verify --deep --strict "$bundle"; then
    die "'$bundle' does not pass codesign --verify — run codesign.sh first."
fi

# Pre-flight 2: the signature must be a Developer ID Application one.
# Ad-hoc and Apple Development signatures cannot be notarized; catching it
# here keeps the failure local and immediate instead of a notary rejection
# after the wait. codesign writes its display output to stderr by design;
# 2>&1 MERGES it for inspection, nothing is suppressed.
sig_info=$(codesign --display --verbose=2 "$bundle" 2>&1) || die "codesign --display failed on '$bundle'."
if ! printf '%s\n' "$sig_info" | grep -q "Authority=Developer ID Application"; then
    echo "❌ '$bundle' is not signed with a Developer ID Application identity!" >&2
    printf '%s\n' "$sig_info" >&2
    die "Re-sign with codesign.sh (MACOS_SIGNING_IDENTITY) before notarizing."
fi

# Notarytool takes a zip, not a bundle; --keepParent keeps Oolite.app as the
# archive root so the notarized artifact unzips exactly as it will ship.
zip_path="${bundle}.zip"
rm -f "$zip_path"
if ! ditto -c -k --keepParent "$bundle" "$zip_path"; then
    die "ditto could not archive '$bundle'!"
fi
echo "ℹ️  Archive for submission: $zip_path"

if ! xcrun notarytool submit "$zip_path" --wait --keychain-profile "$profile"; then
    cat >&2 <<'EOF'
❌ Notarization FAILED or did not complete!
   Fetch Apple's processing log for the submission id printed above:
       xcrun notarytool log <submission id> --keychain-profile <profile>
   Fix the reported issue, re-run codesign.sh if the bundle changed, then retry.
EOF
    exit 1
fi

if ! xcrun stapler staple "$bundle"; then
    die "stapler could not attach the notarization ticket to '$bundle'!"
fi
if ! xcrun stapler validate "$bundle"; then
    die "stapler rejected the ticket on '$bundle'!"
fi

# Final verdict: the Gatekeeper policy evaluation a customer's machine runs.
if ! spctl -a -vv "$bundle"; then
    die "Gatekeeper (spctl) REJECTED '$bundle'!"
fi

echo "✅ '$bundle' notarized, stapled and Gatekeeper-accepted — shippable"
