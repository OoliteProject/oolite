#!/bin/bash

cp -r oolite.app/* /app/bin

if [ -z "$FLATPAK_VERSION" ]; then
    source ShellScripts/common/get_version.sh
    FLATPAK_VERSION="$VERSION"
fi

FLATPAK_METAINFO=/app/share/metainfo/space.oolite.Oolite.metainfo.xml
install -D installers/flatpak/space.oolite.Oolite.metainfo.xml $FLATPAK_METAINFO
sed -i "/<releases>/a \\    <release version=\"${FLATPAK_VERSION}\" date=\"$(date -I)\" />" $FLATPAK_METAINFO

FLATPAK_DESKTOP=/app/share/applications/space.oolite.Oolite.desktop
install -D installers/FreeDesktop/oolite.desktop $FLATPAK_DESKTOP
desktop-file-edit --set-key=Exec --set-value=run_oolite.sh $FLATPAK_DESKTOP
desktop-file-edit --set-key=Icon --set-value=space.oolite.Oolite $FLATPAK_DESKTOP

install -D Oolite-logo3.png /app/share/icons/hicolor/256x256/apps/space.oolite.Oolite.png
