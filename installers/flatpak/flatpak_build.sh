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

PROGDIR="oolite.app"
APPBIN="/app/bin"

cp -uf "$PROGDIR/run_oolite.sh" "$APPBIN"
cp -uf "$PROGDIR/oolite" "$APPBIN"
cp -uf "$PROGDIR/splash-launcher" "$APPBIN"
cp -rf "$PROGDIR/Resources" "$APPBIN"
cp -uf "ShellScripts/Linux/GNUstep.conf.template" "/app/bin/Resources"

if [[ -z "$VERSION_OVERRIDE" ]]; then
    source ShellScripts/common/get_version.sh
    FLATPAK_VERSION="$VERSION"
else
    FLATPAK_VERSION="$VERSION_OVERRIDE"
fi

FLATPAK_METAINFO=/app/share/metainfo/space.oolite.Oolite.metainfo.xml
install -D installers/flatpak/space.oolite.Oolite.metainfo.xml.template $FLATPAK_METAINFO
sed -i "s/@VER@/${FLATPAK_VERSION}/g" "$FLATPAK_METAINFO"
sed -i "s/@DATE@/${FLATPAK_DATE}/g" "$FLATPAK_METAINFO"

FLATPAK_DESKTOP=/app/share/applications/space.oolite.Oolite.desktop
install -D installers/FreeDesktop/oolite.desktop $FLATPAK_DESKTOP
desktop-file-edit --set-key=Exec --set-value=run_oolite.sh $FLATPAK_DESKTOP
desktop-file-edit --set-key=Icon --set-value=space.oolite.Oolite $FLATPAK_DESKTOP

install -D Resources/Binary/Textures/oolite-logo1.png /app/share/icons/hicolor/256x256/apps/space.oolite.Oolite.png
