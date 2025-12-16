SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source $SCRIPT_DIR/os_detection.sh

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

        "gnutls-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libgnutls28-dev" ;;
                redhat) PKG_NAME="gnutls-devel" ;;
                arch) PKG_NAME="gnutls" ;;
            esac ;;

        "icu-dev")
            case "$CURRENT_DISTRO" in
                redhat) PKG_NAME="libicu-devel" ;;
            esac ;;

        "ffi-dev")
            case "$CURRENT_DISTRO" in
                redhat) PKG_NAME="libffi-devel" ;;
            esac ;;

        "xslt-dev")
            case "$CURRENT_DISTRO" in
                debian) PKG_NAME="libxml2-dev libxslt1-dev" ;;
                redhat) PKG_NAME="libxml2-devel libxslt-devel" ;;
                arch) PKG_NAME="libxml2 libxslt" ;;
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
                debian) PKG_NAME="libespeak-ng-dev" ;;
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

        "fuse") PKG_NAME="fuse3" ;;

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
