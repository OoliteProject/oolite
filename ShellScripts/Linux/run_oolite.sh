#!/bin/bash


HERE="$(dirname "$(readlink -f "$0")")"

DEBUG=false
SHOW_SPLASH=true
# Loop through all arguments
for arg in "$@"; do
  case "$arg" in
    -nosplash|--nosplash|-help|--help)
      SHOW_SPLASH=false
      ;;
    debug)
      DEBUG=true
      shift
      ;;
  esac
done

notify_failure() {
    if [[ -n "$FLATPAK_ID" ]]; then
        local MSG="<b>$FLATPAK_ID failed to start!</b>\n\nExit Code: $EXIT_CODE"
        gdbus call --session \
            --dest org.freedesktop.portal.Desktop \
            --object-path /org/freedesktop/portal/desktop \
            --method org.freedesktop.portal.Notification.AddNotification \
            "oolite_launch" \
            "{'title': <'Application Error'>, 'body': <'$MSG'>}"
    else
        local APP_NAME="${ARGV0:-Application}"
        local MSG="<b>$APP_NAME failed to start!</b>\n\nExit Code: $EXIT_CODE\n\nRun from terminal to see details."

        if command -v notify-send > /dev/null; then
            notify-send \
                --urgency=critical \
                --app-name="$APP_NAME" \
                --icon=dialog-error \
                "Application Error" \
                "$MSG"
        else
            # Fallback to Console (stderr) if libnotify is missing
            echo "------------------------------------------------" >&2
            echo "ERROR: $APP_NAME exited with code $EXIT_CODE" >&2
            echo "------------------------------------------------" >&2
        fi
    fi
}

launch_guarded() {
    if [[ "$1" == "packageinfo" ]]; then
        cat "$OO_EXEDIR/Resources/manifest.plist"
        exit 0
    fi
    if [[ "$DEBUG" == true ]]; then
        exec gdb --args "$OO_EXEDIR/oolite" "$@" -nosplash
    fi
    if [[ "$SHOW_SPLASH" == true ]]; then
        "$OO_EXEDIR/splash-launcher" "$OO_EXEDIR/Resources/Images/splash.bmp" &
        "$OO_EXEDIR/oolite" "$@" -nosplash
    else
        # already has -nosplash
        "$OO_EXEDIR/oolite" "$@"
    fi
    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        exit 0
    fi

    notify_failure
    exit $EXIT_CODE
}

find_exedir() {
    if [[ -z "$OO_EXEDIR" ]]; then
        OO_EXEDIR="$HERE"
        if [[ ! -f "$OO_EXEDIR/oolite" ]]; then
            OO_EXEDIR="$HERE/oolite.app"
        fi
    fi
}

make_gnustepconf_template() {
    export GNUSTEP_CONFIG_FILE=$(mktemp -t oolite_gnustep_XXXX --suffix=.conf)
    sed -e "s|@BASEDIR@|$BASEDIR|g" "$OO_EXEDIR/Resources/GNUstep.conf.template" > "$GNUSTEP_CONFIG_FILE"
}

# Check if we are running inside a Flatpak
if [[ -n "$FLATPAK_ID" ]]; then
    BASEDIR="/app"
    OO_EXEDIR="$BASEDIR/bin"
    GAME_DATA="$HOME/.var/app/$FLATPAK_ID"
    make_gnustepconf_template

# Check if we are running inside an AppImage
elif [[ -n "$APPIMAGE" ]]; then
    BASEDIR="$APPDIR"
    OO_EXEDIR="$BASEDIR/bin"
    export PATH="$OO_EXEDIR:$PATH"

    DEBUG_OXP=$(grep "debug_functionality_support" "$OO_EXEDIR/Resources/manifest.plist")
    if [[ "$DEBUG_OXP" == *"yes"* ]]; then
        INTERNAL_ADDONS="$OO_EXEDIR/AddOns"
        export OO_ADDITIONALADDONSDIRS="${OO_ADDITIONALADDONSDIRS}${OO_ADDITIONALADDONSDIRS:+,}$INTERNAL_ADDONS"
    fi

    if [[ -n "$OO_DIRTYPE" ]]; then
        if [[ "${OO_DIRTYPE,,}" == "xdg" ]]; then
            GAME_DATA="$HOME/.local/share/Oolite"
        elif [[ "${OO_DIRTYPE,,}" == "legacy" ]]; then
            launch_guarded "$@"
        fi
    else
        # Get the folder containing the AppImage file
        HERE="$(dirname "$APPIMAGE")"
        GAME_DATA="$HERE/GameData"
    fi
    make_gnustepconf_template
else
    # Check if OO_DIRTYPE set
    if [[ -n "$OO_DIRTYPE" ]]; then
        if [[ "${OO_DIRTYPE,,}" == "xdg" ]]; then
            GAME_DATA="$HOME/.local/share/Oolite"
        elif [[ "${OO_DIRTYPE,,}" == "legacy" ]]; then
            find_exedir
            launch_guarded "$@"
        fi
    else
        # Use script directory
        GAME_DATA="$HERE/GameData"
    fi
    # Find the current system configuration file
    ORIGINAL_CONF=$(gnustep-config --variable=GNUSTEP_CONFIG_FILE)

    # Fallback: If gnustep-config returns nothing, assume standard location
    if [ -z "$ORIGINAL_CONF" ]; then
        ORIGINAL_CONF="/etc/GNUstep/GNUstep.conf"
    fi

    if [ -z "$ORIGINAL_CONF" ]; then
        ORIGINAL_CONF="/usr/local/etc/GNUstep/GNUstep.conf"
    fi

    GNUSTEP_CONFIG_FILE=$(mktemp -t oolite_gnustep_XXXX --suffix=.conf)
    # Copy the original config (if it exists) to the temp file
    if [ -f "$ORIGINAL_CONF" ]; then
        cp "$ORIGINAL_CONF" "$GNUSTEP_CONFIG_FILE"
    else
        echo "No system config found at $ORIGINAL_CONF. Starting with empty config."
        touch "$GNUSTEP_CONFIG_FILE"
    fi
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
# OO_ADDITIONALADDONSDIRS can be used to pass a comma separated list of additional OXP folders
if [ -n "$OO_ADDITIONALADDONSDIRS" ]; then
    (IFS=,; mkdir -p $OO_ADDITIONALADDONSDIRS)
fi

OO_GNUSTEPDIR="${OO_GNUSTEPDIR:-$GAME_DATA/.GNUstep}"
mkdir -p "$OO_GNUSTEPDIR"
OO_GNUSTEPDEFAULTSDIR="${OO_GNUSTEPDEFAULTSDIR:-${GAME_DATA}}"
mkdir -p "$OO_GNUSTEPDEFAULTSDIR"

echo "" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_CONFIG_FILE=$GNUSTEP_CONFIG_FILE" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_APPS=$OO_GNUSTEPDIR/Applications" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_ADMIN_APPS=$OO_GNUSTEPDIR/Applications/Admin" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_WEB_APPS=$OO_GNUSTEPDIR/WebApplications" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_TOOLS=$OO_GNUSTEPDIR/Tools" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_ADMIN_TOOLS=$OO_GNUSTEPDIR/Tools/Admin" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_LIBRARY=$OO_GNUSTEPDIR/Library" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_HEADERS=$OO_GNUSTEPDIR/Library/Headers" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_LIBRARIES=$OO_GNUSTEPDIR/Library/Libraries" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_DOC=$OO_GNUSTEPDIR/Library/Documentation" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_DOC_MAN=$OO_GNUSTEPDIR/Library/Documentation/man" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DIR_DOC_INFO=$OO_GNUSTEPDIR/Library/Documentation/info" >> "$GNUSTEP_CONFIG_FILE"
echo "GNUSTEP_USER_DEFAULTS_DIR=$OO_GNUSTEPDEFAULTSDIR" >> "$GNUSTEP_CONFIG_FILE"

find_exedir
launch_guarded "$@"
rm "$GNUSTEP_CONFIG_FILE"
