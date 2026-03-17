#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
pushd "$SCRIPT_DIR" > /dev/null

mkdir -p ../../build
cd ../../build

VERSION=$(cat ../src/Cocoa/oolite-version.xcconfig | cut -d '=' -f 2)
VER_MAJ=$(echo "$VERSION" | cut -d. -f1)
VER_MIN=$(echo "$VERSION" | cut -d. -f2)
VER_REV=$(echo "$VERSION" | cut -d. -f3)
if [ "" == "$VER_REV" ]; then
    VER_REV="0"
fi
TIMESTAMP=$(git log -1 --format=%ct)
# Date conversions use UTC for consistency
# Convert to __DATE__ format (e.g., Feb 20 2026)
CPP_DATE=$(date -u -d "@$TIMESTAMP" +"%b %e %Y")
# Convert to YYYY-MM-DD
APP_DATE=$(date -u -d "@$TIMESTAMP" +"%Y-%m-%d")
# Convert to YYMMDD format (e.g., 260313)
VER_DATE=$(date -u -d "@$TIMESTAMP" +"%y%m%d")

VER_GITREV=$(git rev-list --count HEAD)
VER_GITHASH=$(git rev-parse --short=7 HEAD)
VER_FULL="$VER_MAJ.$VER_MIN.$VER_REV.$VER_GITREV-$VER_DATE-$VER_GITHASH"
BUILDTIME=$(date "+%Y.%m.%d %H:%M")


echo "OOLITE_VERSION=$VER_FULL" > OOLITE_VERSION.txt

echo "$VER_FULL"

popd > /dev/null