#!/bin/bash

launch_guarded() {
    # 1. Run the command and pass all arguments
    ./oolite "$@"
    local EXIT_CODE=$?

    # 2. If the command was successful, just return
    if [ $EXIT_CODE -eq 0 ]; then
        return 0
    fi

    # ---------------- Error Handling ----------------

    local APP_NAME="${ARGV0:-Application}"
    local MSG="<b>$APP_NAME failed to start.</b>\n\nExit Code: $EXIT_CODE\n\nRun from terminal to see details."

    # 3. Use the bundled notify-send
    # We use 'command -v' just in case the bundle failed or we are on a bare system
    if command -v notify-send > /dev/null; then
        notify-send \
            --urgency=critical \
            --app-name="$APP_NAME" \
            --icon=dialog-error \
            "Application Error" \
            "The application exited with code $EXIT_CODE."
    else
        # 4. Fallback to Console (stderr) if libnotify is somehow missing
        echo "------------------------------------------------" >&2
        echo "ERROR: $APP_NAME exited with code $EXIT_CODE" >&2
        echo "------------------------------------------------" >&2
    fi

    exit $EXIT_CODE
}

# Check if we are running inside a Flatpak
if [ -f "/.flatpak-info" ]; then
    FLATPAK_ID=$(cat /.flatpak-info | grep "app-id" | cut -d= -f2)
    GAME_DATA="$HOME/.var/app/$FLATPAK_ID"
# Check if OO_DIRTYPE set
elif [[ -n "$OO_DIRTYPE" ]]; then
    if [[ "${OO_DIRTYPE,,}" == "xdg" ]]; then
        GAME_DATA="$HOME/.local/share"
    elif [[ "${OO_DIRTYPE,,}" == "legacy" ]]; then
        launch_guarded "$@"
    fi
# Check if we are running inside an AppImage
elif [[ -n "$APPIMAGE" ]]; then
    # Get the folder containing the AppImage file
    HERE="$(dirname "$APPIMAGE")"
    GAME_DATA="${HERE}/GameData"
else
    # Use script directory
    HERE="$(dirname "$(readlink -f "$0")")"
    GAME_DATA="${HERE}/GameData"
fi

mkdir "$GAME_DATA"
cd "$GAME_DATA"

export OO_SAVEDIR="${OO_SAVEDIR:-${GAME_DATA}/SavedGames}"
mkdir -p "$OO_SAVEDIR"
export OO_SNAPSHOTSDIR="${OO_SNAPSHOTSDIR:-${GAME_DATA}/Snapshots}"
mkdir -p "$OO_SNAPSHOTSDIR"
export OO_LOGSDIR="${OO_LOGSDIR:-${GAME_DATA}/.logs}"
mkdir -p "$OO_LOGSDIR"
export OO_MANAGEDADDONSDIR="${OO_MANAGEDADDONSDIR:-${GAME_DATA}/.ManagedAddOns}"
mkdir -p "$OO_MANAGEDADDONSDIR"
export OO_ADDONSEXTRACTDIR="${OO_ADDONSEXTRACTDIR:-${GAME_DATA}/AddOns}"
mkdir -p "$OO_ADDONSEXTRACTDIR"
export HOME="${OO_GNUSTEPDIR:-${GAME_DATA}/.GNUstep}"
mkdir -p "$HOME"
OO_GNUSTEPDEFAULTSDIR="${OO_GNUSTEPDEFAULTSDIR:-${GAME_DATA}}"
mkdir -p "$OO_GNUSTEPDEFAULTSDIR"

# OO_ADDITIONALADDONSDIRS can be used to pass a comma separated list of additional OXP folders


# Find the current system configuration file
ORIGINAL_CONF=$(gnustep-config --variable=GNUSTEP_CONFIG_FILE)

# Fallback: If gnustep-config returns nothing, assume standard location
if [ -z "$ORIGINAL_CONF" ]; then
    ORIGINAL_CONF="/etc/GNUstep/GNUstep.conf"
fi

if [ -z "$ORIGINAL_CONF" ]; then
    ORIGINAL_CONF="/usr/local/etc/GNUstep/GNUstep.conf"
fi

TEMP_CONF=$(mktemp -t oolite_gnustep_XXXX.conf)

# Copy the original config to the temp file (if it exists)
if [ -f "$ORIGINAL_CONF" ]; then
    cp "$ORIGINAL_CONF" "$TEMP_CONF"
else
    echo "No system config found at $ORIGINAL_CONF. Starting with empty config."
    touch "$TEMP_CONF"
fi

echo "" >> "$TEMP_CONF"
echo "# --- Overrides added by launcher script ---" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DEFAULTS_DIR=$OO_GNUSTEPDEFAULTSDIR" >> "$TEMP_CONF"

export GNUSTEP_CONFIG_FILE="$TEMP_CONF"

launch_guarded "$@"
rm "$TEMP_CONF"
popd
