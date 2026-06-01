#!/bin/bash


HERE="$(dirname "$(readlink -f "$0")")"

HELP=false
DEBUG=false
# Loop through all arguments
for arg in "$@"; do
  case "$arg" in
    -help|--help)
      HELP=true
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
    if [[ "$HELP" == true ]]; then
        # Colors
        B='\033[1m'
        G='\033[32m'
        N='\033[0m'

        echo "This run_oolite.sh script enables Oolite to be configured to use alternative locations by setting various environment variables:"
        echo ""
        printf "${B}%-22s | %-8s | %-48s${N}\n" "Environment Variable" "Value" "Game Folder"
        printf "%-22s-+-%-8s-+-%-48s\n" "----------------------" "--------" "------------------------------------------------"
        printf "${G}%-22s${N} | %-8s | %-48s\n" "OO_DIRTYPE" "xdg" "\$HOME/.local/share/Oolite"
        printf "${G}%-22s${N} | %-8s | %-48s\n" "OO_DIRTYPE" "legacy" "\$HOME (old folder structure - not recommended)"

        echo ""
        echo "More intricate setups are possible by specifying individual environment variables for different folders:"
        echo ""

        printf "${B}%-25s | %-40s | %-40s${N}\n" "Environment Variable" "Description" "Default Path (if unset)"
        printf "%-25s-+-%-40s-+-%-40s\n" "-------------------------" "----------------------------------------" "----------------------------------------"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_SAVEDIR" "Directory for saved games" "\$GAME_DATA/SavedGames"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_SNAPSHOTSDIR" "Directory for screenshots/snapshots" "\$GAME_DATA/Snapshots"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_LOGSDIR" "Directory for game log files" "\$GAME_DATA/.logs"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_MANAGEDADDONSDIR" "Directory for OXPs managed by the game" "\$GAME_DATA/.ManagedAddOns"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_USERADDONSDIR" "User-specified directory for OXPs" "\$GAME_DATA/AddOns"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_ADDONSEXTRACTDIR" "Directory for extracted OXPs" "\${OO_USERADDONSDIR:-\$GAME_DATA/AddOns}"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_ADDITIONALADDONSDIRS" "List of extra addon search paths" ""
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_GNUSTEPDIR" "GNUstep directory" "\$GAME_DATA/.GNUstep"
        printf "${G}%-25s${N} | %-40s | %-40s\n" "OO_GNUSTEPDEFAULTSDIR" "User preferences defaults file location" "\$GAME_DATA"
        echo ""
        echo ""
        echo "The following options can be passed to the Oolite executable:"
        echo ""
    fi
    "$OO_EXEDIR/oolite" "$@"
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

    export GNUSTEP_CONFIG_FILE=$(mktemp -t oolite_gnustep_XXXX --suffix=.conf)
    cp "$HERE/Resources/GNUstep.conf.orig" "$GNUSTEP_CONFIG_FILE"
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
