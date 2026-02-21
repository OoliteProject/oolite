#!/bin/bash

source /app/share/GNUstep/Makefiles/GNUstep.sh

TIMESTAMP=$(git log -1 --format=%ct)
# Convert to __DATE__ format (e.g., Feb 20 2026)
CPP_DATE=$(date -d "@$TIMESTAMP" +"%b %e %Y")
# Convert to ISO 8601 format (e.g., 2026-02-20)
FLATPAK_DATE=$(date -d "@$TIMESTAMP" -I)

export ADDITIONAL_CFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
export ADDITIONAL_OBJCFLAGS="-DBUILD_DATE='\"$CPP_DATE\"'"
make -f Makefile release-deployment -j$FLATPAK_BUILDER_N_JOBS

cp -r oolite.app/* /app/bin

if [[ -z "$VERSION_OVERRIDE" ]]; then
    source ShellScripts/common/get_version.sh
    FLATPAK_VERSION="$VERSION"
else
    FLATPAK_VERSION="$VERSION_OVERRIDE"
fi

FLATPAK_METAINFO=/app/share/metainfo/space.oolite.Oolite.metainfo.xml
install -D installers/flatpak/space.oolite.Oolite.metainfo.xml $FLATPAK_METAINFO
FLATPAK_VER_INFO="release version=\"${FLATPAK_VERSION}\" date=\"${FLATPAK_DATE}\""
echo "Oolite Flatpak version info: ${FLATPAK_VER_INFO}"
sed -i "/<releases>/a \\    <${FLATPAK_VER_INFO}/>" $FLATPAK_METAINFO

FLATPAK_DESKTOP=/app/share/applications/space.oolite.Oolite.desktop
install -D installers/FreeDesktop/oolite.desktop $FLATPAK_DESKTOP
desktop-file-edit --set-key=Exec --set-value=run_oolite.sh $FLATPAK_DESKTOP
desktop-file-edit --set-key=Icon --set-value=space.oolite.Oolite $FLATPAK_DESKTOP

install -D installers/flatpak/oolite-logo1.svg /app/share/icons/hicolor/scalable/apps/space.oolite.Oolite.svg
