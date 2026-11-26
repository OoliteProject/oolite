#!/bin/bash

# Builds the Oolite AppImage in a throwaway archlinux container, with the same steps as the build-appimage job in
# .github/workflows/build-all.yaml. A local build then matches the published AppImages on any host distribution,
# including the libdecor-mini they bundle (install_libdecor_fn.sh), and nothing on the host is installed or replaced.
#
# Called via mk.sh pkg-appimage.
# Usage: ShellScripts/Linux/build_appimage_container.sh [build_type [mk.sh options...]]
#   build_type: deployment (default), test, dev or debug, as for ./mk.sh
#   options:    passed unchanged to ./mk.sh build and ./mk.sh appimage-arch in the container, e.g.
#               --setup-flags="-Djs_engine=quickjs". As in CI, the build also gets --setup-flags="-Ddocs=enabled",
#               before them. Paths in options are read in the container, from its copy of the working tree.
#
# Needs Docker, usable by the current user. The container works on a copy of the working tree (tracked files,
# untracked files that are not ignored, and .git for the version number), so the host's build folders are never
# touched. Only the AppImage is copied back, into build/, owned by the current user; the full log is written to
# build/appimage-container.log. Each run starts from a fresh container, so it downloads and builds all dependencies.
#
# Environment:
#   OOLITE_APPIMAGE_IMAGE  container image (default archlinux:latest, as in CI)
#   GITHUB_TOKEN           optional; passed on so GitHub downloads are not rate limited

set -euo pipefail

build_type="${1:-deployment}"
case "$build_type" in
    deployment|test|dev|debug) ;;
    -h|--help) sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "❌ Invalid build_type '$build_type'. Expected: deployment, test, dev or debug." >&2; exit 1 ;;
esac
shift $(( $# > 0 ? 1 : 0 ))
# As in CI, the SpiderMonkey library is only installed for a SpiderMonkey build (the default js_engine). As in
# meson, the last -Djs_engine wins.
js_engine="spidermonkey"
for option in "$@"; do
    if [[ "$option" == --setup-flags=* && " ${option#*=} " =~ .*[[:space:]]-Djs_engine=([a-z]+)[[:space:]] ]]; then
        js_engine="${BASH_REMATCH[1]}"
    fi
done

if ! command -v docker > /dev/null; then
    echo "❌ docker not found. Install it with: sudo ShellScripts/Linux/install_packages_root.sh --appimage" >&2
    exit 1
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
repo=$(git -C "$script_dir" rev-parse --show-toplevel)
outdir="$repo/build"
log="$outdir/appimage-container.log"
image="${OOLITE_APPIMAGE_IMAGE:-archlinux:latest}"
mkdir -p "$outdir"

# Runs inside the container, as root. These are the steps of the build-appimage CI job.
read -r -d '' container_script << 'EOF' || true
set -euo pipefail
mkdir /oolite && cd /oolite
tar -x
pacman -Syu --noconfirm
pacman -S --noconfirm --needed git
git config --global --add safe.directory /oolite
ShellScripts/Linux/install_packages_root.sh --core+appimage-arch
ShellScripts/Linux/build_gnustep.sh system
if [[ "$JS_ENGINE" == "spidermonkey" ]]; then
    ShellScripts/Linux/install_mozilla_js.sh system
    echo "/usr/local/lib" >> /etc/ld.so.conf
    ldconfig
fi
./mk.sh build "$BUILD_TYPE" --setup-flags="-Ddocs=enabled" "$@"
./mk.sh appimage-arch "$BUILD_TYPE" "$@"
for appimage in build/Oolite*.AppImage; do
    install -o "$HOST_UID" -g "$HOST_GID" -m 755 "$appimage" /out/
    echo "✅ build/${appimage##*/}"
done
EOF

echo "📦 Building the $build_type AppImage ($js_engine) in a $image container; log in $log"
start=$SECONDS
# INSTALL_LIBDECOR_MINI: the container is deleted afterwards, so libdecor-mini may replace its libdecor.
# APPIMAGE_EXTRACT_AND_RUN and ARCH: appimagetool is an AppImage and a container has no FUSE, so it unpacks itself
# instead, and it cannot detect the architecture when unpacked.
status=0
(cd "$repo" && { git ls-files -z -c -o --exclude-standard --deduplicate; printf '.git\0'; } \
    | tar -c --null --ignore-failed-read -T -) \
    | docker run --rm -i \
        -e INSTALL_LIBDECOR_MINI=true \
        -e APPIMAGE_EXTRACT_AND_RUN=1 \
        -e ARCH="$(uname -m)" \
        -e BUILD_TYPE="$build_type" \
        -e JS_ENGINE="$js_engine" \
        -e HOST_UID="$(id -u)" \
        -e HOST_GID="$(id -g)" \
        -e GITHUB_TOKEN \
        -v "$outdir:/out" \
        "$image" bash -c "$container_script" container-build "$@" > "$log" 2>&1 || status=$?
elapsed=$((SECONDS - start))

grep -E '^(✅|❌|⚠️)' "$log" || true
if [[ $status -ne 0 ]]; then
    echo "❌ Container build failed after $((elapsed / 60)) min $((elapsed % 60)) s (exit $status). See $log" >&2
    exit $status
fi
echo "⏱️ $((elapsed / 60)) min $((elapsed % 60)) s"
