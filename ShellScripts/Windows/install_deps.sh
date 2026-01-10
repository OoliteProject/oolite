#!/bin/bash

# No parameters: build both clang and gcc in that order (end setup will be for gcc)
# One parameter gcc = build gcc only (end setup will be for gcc)
# One parameter clang = build clang only (end setup will be for clang)

install() {
	# First parameter is package name
	# Second optional parameter is gcc or clang
    echo "Installing $1 package"

    if [ -z "$2" ]; then
		fullname=$1
    else
		fullname="${1}_${2}"
    fi

    packagename="$MINGW_PACKAGE_PREFIX-$fullname*any.pkg.tar.zst"
	filename=$(ls $packagename 2>/dev/null)

	# package file eg. mingw-w64-x86_64-libobjc2-2.3-3-any.pkg.tar.zst
    if [ -z "$filename" ]; then
        echo "❌ No file matching $packagename found." >&2
        return 1
    fi

    if ! pacman -U $filename --noconfirm ; then
	    echo "❌ $filename install failed!" >&2
	    return 1
	fi
}

run_script() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ../common/checkout_submodules_fn.sh
    checkout_submodules

    pacman -S dos2unix --noconfirm
    pacman -S pactoys --noconfirm
    pacboy -S binutils --noconfirm
    pacboy -S uutils-coreutils --noconfirm

    cd ../../build/packages
    echo "Installing common libraries"
    package_names=(spidermonkey SDL)
    for packagename in "${package_names[@]}"; do
        install $packagename
    done

    pacman -S git --noconfirm
    pacboy -S libpng --noconfirm
    pacboy -S openal --noconfirm
    pacboy -S libvorbis --noconfirm
    pacboy -S pcaudiolib --noconfirm
    pacboy -S espeak-ng --noconfirm
    pacman -S make --noconfirm
    pacboy -S nsis --noconfirm

    if [[ -z "$1" || "$1" == "clang" ]]; then
        pacboy -S clang --noconfirm
        pacboy -S lld --noconfirm

        echo "Installing GNUStep libraries with clang"
        export cc=$MINGW_PREFIX/bin/clang
        export cxx=$MINGW_PREFIX/bin/clang++
        clang_package_names=(libobjc2 gnustep-make gnustep-base)
        for packagename in "${clang_package_names[@]}"; do
            install $packagename clang
        done
    	pacman -Q > installed-packages-clang.txt
    else
        echo "Installing GNUStep libraries with gcc"
        export cc=$MINGW_PREFIX/bin/gcc
        export cxx=$MINGW_PREFIX/bin/g++
        gcc_package_names=(gnustep-make gnustep-base)
        for packagename in "${gcc_package_names[@]}"; do
            install $packagename gcc
        done
    	pacman -Q > installed-packages-gcc.txt
    fi

    echo "source $MINGW_PREFIX/share/GNUstep/Makefiles/GNUstep.sh" > /etc/profile.d/GNUstep.sh

    if ! grep -q "# Custom history settings" ~/.bashrc; then
        cat >> ~/.bashrc <<'EOF'
# Custom history settings
WIN_HOME=$(cygpath "$USERPROFILE")
export HISTFILE=$WIN_HOME/.bash_history
export HISTSIZE=5000
export HISTFILESIZE=10000
shopt -s histappend
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
EOF
    fi
    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
