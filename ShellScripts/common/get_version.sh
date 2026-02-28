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
VER_DATE=$(date +%y%m%d)
VER_GITREV=$(git rev-list --count HEAD)
VER_GITHASH=$(git rev-parse --short=7 HEAD)
VER_FULL="$VER_MAJ.$VER_MIN.$VER_REV.$VER_GITREV-$VER_DATE-$VER_GITHASH"
BUILDTIME=$(date "+%Y.%m.%d %H:%M")


echo "OOLITE_VERSION=$VER_FULL" > OOLITE_VERSION.txt

echo "$VER_FULL"

popd > /dev/null