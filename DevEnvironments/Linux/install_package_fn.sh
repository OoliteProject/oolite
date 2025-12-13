# Usage: install_package <generic_name>
install_package() {
    GENERIC_NAME=$1
    PKG_NAME=""

    # This CASE statement is the dictionary.
    # Add your packages here.
    case "$GENERIC_NAME" in
        "git") PKG_NAME="git" ;;

        "base-devel")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="build-essential" ;;
                redhat) PKG_NAME="gcc gcc-c++ make" ;;
                arch) PKG_NAME="base-devel" ;;
            esac ;;

        "clang")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="clang" ;;
                redhat) PKG_NAME="clang-devel" ;;
                arch)   PKG_NAME="clang" ;;
            esac ;;

        "lldb") PKG_NAME="lldb" ;;

        "cmake") PKG_NAME="cmake" ;;

        "xslt-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libxml2-dev libxslt1-dev" ;;
                redhat) PKG_NAME="libxml2-devel libxslt-devel" ;;
                arch) PKG_NAME="libxml2 libxslt" ;;
            esac ;;

        "gnutls-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libgnutls28-dev" ;;
                redhat) PKG_NAME="gnutls-devel" ;;
                arch) PKG_NAME="gnutls" ;;
            esac ;;

        "png-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libpng-dev" ;;
                redhat) PKG_NAME="libpng-devel" ;;
                arch)   PKG_NAME="libpng" ;;
            esac ;;

        "zlib-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="zlib1g-dev" ;;
                redhat) PKG_NAME="zlib-devel" ;;
                arch) PKG_NAME="zlib" ;;
            esac ;;

        "nspr-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libnspr4-dev" ;;
                redhat) PKG_NAME="nspr-devel" ;;
                arch) PKG_NAME="nspr" ;;
            esac ;;

        "espeak-ng-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libespeak-ng-libespeak-dev" ;;
                redhat) PKG_NAME="espeak-ng-devel" ;;
                arch) PKG_NAME="espeak-ng" ;;
            esac ;;

        "vorbis-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libvorbis-dev" ;;
                redhat) PKG_NAME="libvorbis-devel" ;;
                arch) PKG_NAME="libvorbis" ;;
            esac ;;

        "openal-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libopenal-dev" ;;
                redhat) PKG_NAME="openal-soft-devel" ;;
                arch) PKG_NAME="openal" ;;
            esac ;;

        "opengl-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libgl-dev" ;;
                redhat) PKG_NAME="mesa-libGL-devel" ;;
                arch) PKG_NAME="libglvnd" ;;
            esac ;;

        "glu-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libglu1-mesa-dev" ;;
                redhat) PKG_NAME="mesa-libGLU-devel" ;;
                arch) PKG_NAME="glu" ;;
            esac ;;

        "sdl12-compat")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libsdl1.2-compat-dev" ;;
                redhat) PKG_NAME="sdl12-compat-devel" ;;
                arch) PKG_NAME="sdl12-compat" ;;
            esac ;;

        "x11-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libx11-dev" ;;
                redhat) PKG_NAME="libX11-devel" ;;
                arch) PKG_NAME="libx11" ;;
            esac ;;

        *)
            echo "❌ I don't know how to translate '$GENERIC_NAME' for $CURRENT_DISTRO" >&2
            return 1
            ;;
    esac

    # Perform the Installation
    if [ -z "$PKG_NAME" ]; then
        echo "❌ Could not determine package name for $GENERIC_NAME" >&2
        return 1
    else
        echo "--> Installing $GENERIC_NAME ($PKG_NAME)..."
        if ! "${INSTALL_CMD[@]}" $PKG_NAME; then
            echo "❌ Could not install $GENERIC_NAME ($PKG_NAME)!" >&2
            return 1
        fi


    fi
}

# --- 1. Global Setup & OS Detection ---
# We detect the OS once at the start to avoid repeating it.

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_FAMILY="${ID} ${ID_LIKE}"
else
    echo "❌ /etc/os-release not found. Cannot detect OS." >&2
    exit 1
fi

# Determine the Installer Command based on the family
if [[ "$OS_FAMILY" == *"debian"* ]]; then
    # Debian, Ubuntu, Kali, Mint, Pop!_OS
    CURRENT_DISTRO="debian"
    INSTALL_CMD=(sudo apt-get install -y)
    UPDATE_CMD=(sudo apt-get update)

elif [[ "$OS_FAMILY" == *"arch"* ]]; then
    # Arch, Manjaro, EndeavourOS
    CURRENT_DISTRO="arch"
    INSTALL_CMD=(sudo pacman -S --noconfirm)
    UPDATE_CMD=(sudo pacman -Syu)

elif [[ "$OS_FAMILY" == *"fedora"* || "$OS_FAMILY" == *"rhel"* ]]; then
    # Fedora, CentOS, RHEL, AlmaLinux
    CURRENT_DISTRO="redhat"
    INSTALL_CMD=(sudo dnf install -y)
    UPDATE_CMD=(sudo dnf check-update) # Returns exit code 100 if updates exist, catch that later

else
    echo "❌ Unsupported distribution detected." >&2
    exit 1
fi

echo "Detected System: $CURRENT_DISTRO"

