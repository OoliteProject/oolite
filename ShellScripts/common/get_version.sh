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
TIMESTAMP=$(git log -1 --format=%ct)

# Date conversions use UTC for consistency
# Convert to __DATE__ format (e.g., Feb 20 2026)
CPP_DATE=$(date -u -d "@$TIMESTAMP" +"%b %e %Y")
# Convert to YYYY-MM-DD
APP_DATE=$(date -u -d "@$TIMESTAMP" +"%Y-%m-%d")
# Convert to YYMMDD format (e.g., 260313)
VER_DATE=$(date -u -d "@$TIMESTAMP" +"%y%m%d")

if [[ -z "${SEMVER}" ]] || [[ -z "${PROJECTNAME}" ]]
then
    # Variables not passed in. Calculate the classic way.

    VERSION=$(${GITVERSION} /showvariable SemVer)$(git diff --quiet || echo "+dirty."$(${GITVERSION} /showvariable UncommittedChanges))
    VER_MAJ=$(${GITVERSION} /showvariable Major)
    VER_MIN=$(${GITVERSION} /showvariable Minor)
    VER_REV=$(${GITVERSION} /showvariable Patch)
    if [[ "" == "$VER_REV" ]]; then
        VER_REV="0"
    fi

    VER_GITREV=$(git rev-list --count HEAD)
    VER_GITHASH=$(git rev-parse --short=7 HEAD)
    VER_FULL="${VERSION}"
    BUILDTIME=$(date "+%Y.%m.%d %H:%M")
else
    # Variables passed in. Make use of them.

    VER_FULL="${SEMVER}"
fi

echo "OOLITE_VERSION=$VER_FULL" > OOLITE_VERSION.txt
echo "$VER_FULL"

popd > /dev/null
