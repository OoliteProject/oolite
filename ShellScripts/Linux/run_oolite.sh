#!/bin/bash

launch_guarded() {
    "$@"
    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        exit 0
    fi

    local APP_NAME="${ARGV0:-Application}"
    local MSG="<b>$APP_NAME failed to start.</b>\n\nExit Code: $EXIT_CODE\n\nRun from terminal to see details."

    if command -v notify-send > /dev/null; then
        notify-send \
            --urgency=critical \
            --app-name="$APP_NAME" \
            --icon=dialog-error \
            "Application Error" \
            "The application exited with code $EXIT_CODE."
    else
        # Fallback to Console (stderr) if libnotify is missing
        echo "------------------------------------------------" >&2
        echo "ERROR: $APP_NAME exited with code $EXIT_CODE" >&2
        echo "------------------------------------------------" >&2
    fi

    exit $EXIT_CODE
}

find_exe_launch() {
    if [[ -z "$OO_EXECUTABLE" ]]; then
        HERE="$(dirname "$(readlink -f "$0")")"
        OO_EXECUTABLE="$HERE/oolite"
        if [[ ! -f "$OO_EXECUTABLE" ]]; then
            OO_EXECUTABLE="$HERE/oolite.app/oolite"
        fi
    fi
    launch_guarded "$OO_EXECUTABLE" "$@"
}

# Check if we are running inside a Flatpak
if [[ -n "$FLATPAK_ID" ]]; then
    GAME_DATA="$HOME/.var/app/$FLATPAK_ID"
    OO_EXECUTABLE="/app/bin/oolite"

# Check if we are running inside an AppImage
elif [[ -n "$APPIMAGE" ]]; then
    # Get the folder where AppRun is in the AppImage
    HERE="$(dirname "$(readlink -f "${0}")")"
    export LD_LIBRARY_PATH="$HERE/usr/lib:$LD_LIBRARY_PATH"
    export PATH="$HERE/usr/bin:$PATH"
    OO_EXECUTABLE="$HERE/usr/bin/oolite"

    if [[ -n "$OO_DIRTYPE" ]]; then
        if [[ "${OO_DIRTYPE,,}" == "xdg" ]]; then
            GAME_DATA="$HOME/.local/share/Oolite"
        elif [[ "${OO_DIRTYPE,,}" == "legacy" ]]; then
            launch_guarded "$OO_EXECUTABLE" "$@"
        fi
    else
        # Get the folder containing the AppImage file
        HERE="$(dirname "$APPIMAGE")"
        GAME_DATA="$HERE/GameData"
    fi

# Check if OO_DIRTYPE set
elif [[ -n "$OO_DIRTYPE" ]]; then
    if [[ "${OO_DIRTYPE,,}" == "xdg" ]]; then
        GAME_DATA="$HOME/.local/share/Oolite"
    elif [[ "${OO_DIRTYPE,,}" == "legacy" ]]; then
        find_exe_launch "$@"
    fi
else
    # Use script directory
    HERE="$(dirname "$(readlink -f "$0")")"
    GAME_DATA="$HERE/GameData"
fi

mkdir -p "$GAME_DATA"

export OO_SAVEDIR="${OO_SAVEDIR:-$GAME_DATA/SavedGames}"
mkdir -p "$OO_SAVEDIR"
export OO_SNAPSHOTSDIR="${OO_SNAPSHOTSDIR:-$GAME_DATA/Snapshots}"
mkdir -p "$OO_SNAPSHOTSDIR"
export OO_LOGSDIR="${OO_LOGSDIR:-$GAME_DATA/.logs}"
mkdir -p "$OO_LOGSDIR"
export OO_MANAGEDADDONSDIR="${OO_MANAGEDADDONSDIR:-$GAME_DATA/.ManagedAddOns}"
mkdir -p "$OO_MANAGEDADDONSDIR"

if [[ -z "$OO_ADDONSEXTRACTDIR" ]]; then
    export OO_ADDONSEXTRACTDIR="${OO_USERADDONSDIR:-$GAME_DATA/AddOns}"
elif [[ -n "$OO_USERADDONSDIR" ]]; then
    if [[ ",$OO_ADDITIONALADDONSDIRS," != *",$OO_USERADDONSDIR,"* ]]; then
        export OO_ADDITIONALADDONSDIRS="${OO_ADDITIONALADDONSDIRS}${OO_ADDITIONALADDONSDIRS:+,}$OO_USERADDONSDIR"
    fi
fi
mkdir -p "$OO_ADDONSEXTRACTDIR"
if [ -n "$OO_ADDITIONALADDONSDIRS" ]; then
    (IFS=,; mkdir -p $OO_ADDITIONALADDONSDIRS)
fi

OO_GNUSTEPDIR="${OO_GNUSTEPDIR:-$GAME_DATA/.GNUstep}"
mkdir -p "$OO_GNUSTEPDIR"
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

TEMP_CONF=$(mktemp -t oolite_gnustep_XXXX --suffix=.conf)

# Copy the original config to the temp file (if it exists)
if [ -f "$ORIGINAL_CONF" ]; then
    cp "$ORIGINAL_CONF" "$TEMP_CONF"
else
    echo "No system config found at $ORIGINAL_CONF. Starting with empty config."
    touch "$TEMP_CONF"
fi

echo "" >> "$TEMP_CONF"
echo "# --- Overrides added by launcher script ---" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_APPS=$OO_GNUSTEPDIR/Applications" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_ADMIN_APPS=$OO_GNUSTEPDIR/Applications/Admin" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_WEB_APPS=$OO_GNUSTEPDIR/WebApplications" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_TOOLS=$OO_GNUSTEPDIR/Tools" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_ADMIN_TOOLS=$OO_GNUSTEPDIR/Tools/Admin" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_LIBRARY=$OO_GNUSTEPDIR/Library" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_HEADERS=$OO_GNUSTEPDIR/Library/Headers" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_LIBRARIES=$OO_GNUSTEPDIR/Library/Libraries" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_DOC=$OO_GNUSTEPDIR/Library/Documentation" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_DOC_MAN=$OO_GNUSTEPDIR/Library/Documentation/man" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DIR_DOC_INFO=$OO_GNUSTEPDIR/Library/Documentation/info" >> "$TEMP_CONF"
echo "GNUSTEP_USER_DEFAULTS_DIR=$OO_GNUSTEPDEFAULTSDIR" >> "$TEMP_CONF"

export GNUSTEP_CONFIG_FILE="$TEMP_CONF"

find_exe_launch "$@"
rm "$TEMP_CONF"
