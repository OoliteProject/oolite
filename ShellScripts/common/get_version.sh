#!/bin/bash
#
# Calculates the Oolite version number if not passed via env variables.
# Output goes into the OOLITE_VERSION.txt file and to stdout.
#

GITVERSION=/usr/local/bin/gitversion
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
pushd "$SCRIPT_DIR" > /dev/null

mkdir -p ../../build
cd ../../build

# Timestamp of last commit/push
if [[ -z "${GETVERSION_TIMESTAMP}" ]]; then
    # Run timestamp exactly once and export it for any subsequent child scripts
    export GETVERSION_TIMESTAMP=$(git log -1 --format=%ct)
fi
# Date conversions use UTC for consistency
# Convert to __DATE__ format (e.g., Feb 20 2026)
CPP_DATE=$(date -u -d "@$GETVERSION_TIMESTAMP" +"%b %e %Y")
# Convert to YYYY-MM-DD
APP_DATE=$(date -u -d "@$GETVERSION_TIMESTAMP" +"%Y-%m-%d")
# Convert to YYMMDD format (e.g., 260313)
VER_DATE=$(date -u -d "@$GETVERSION_TIMESTAMP" +"%y%m%d")
# Convert to YYYY.MM.DD HH:MM format (e.g., 2026.06.21 07:56)
BUILDTIME=$(date -u -d "@$GETVERSION_TIMESTAMP" "+%Y.%m.%d %H:%M")

if [[ -z "${GITVERSION_JSON}" ]]; then
    # Run GitVersion exactly once and export it for any subsequent child scripts
    export GITVERSION_JSON=$(${GITVERSION})
fi

if [[ -z "${VER_FULL}" ]]; then
    VER_MAJ=$(echo "$GITVERSION_JSON" | jq -r '.Major')
    VER_MIN=$(echo "$GITVERSION_JSON" | jq -r '.Minor')
    VER_REV=$(echo "$GITVERSION_JSON" | jq -r '.Patch')
    if [[ "" == "$VER_REV" ]]; then
        VER_REV="0"
    fi
    VER_DIST=$(echo "$GITVERSION_JSON" | jq -r '.VersionSourceDistance')
    VER_SEMVER=$(echo "$GITVERSION_JSON" | jq -r '.SemVer')
    VER_UNCOMMITTED=$(echo "$GITVERSION_JSON" | jq -r '.UncommittedChanges')

    if git diff --quiet; then
        VER_FULL=$VER_SEMVER
    else
        VER_FULL="${VER_SEMVER}+dirty.${VER_UNCOMMITTED}"
    fi

    VER_NSIS="$VER_MAJ.$VER_MIN.$VER_REV.$VER_DIST"
    VER_GITREV=$(git rev-list --count HEAD)
    VER_GITHASH=$(git rev-parse --short=7 HEAD)

    echo "OOLITE_VERSION=$VER_FULL" > OOLITE_VERSION.txt
fi

echo "$VER_FULL"
popd > /dev/null
