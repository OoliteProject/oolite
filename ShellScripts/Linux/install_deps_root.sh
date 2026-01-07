#!/bin/bash

# This script must be run as root (for example with sudo).


run_script() {
    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi


    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ./install_package_fn.sh
    if ! install_package base-devel; then
        return 1
    fi
    if ! install_package clang; then
        return 1
    fi
    if ! install_package lldb; then
        return 1
    fi
    if ! install_package cmake; then
        return 1
    fi
    if ! install_package gnutls-dev; then
        return 1
    fi
    if ! install_package icu-dev; then
        return 1
    fi
    if ! install_package ffi-dev; then
        return 1
    fi
    if ! install_package xslt-dev; then
        return 1
    fi
    if ! install_package png-dev; then
        return 1
    fi
    if ! install_package zlib-dev; then
        return 1
    fi
    if ! install_package nspr-dev; then
        return 1
    fi
    if ! install_package espeak-ng-dev; then
        return 1
    fi
    if [ ! -d /usr/share/espeak-ng-data ]; then
        if [ ! -d /usr/local/share/espeak-ng-data ]; then
            if [ ! -d /usr/lib/x86_64-linux-gnu/espeak-ng-data ]; then
                echo "❌ espeak-ng-data not in /usr/share, /usr/local/share or /usr/lib/x86_64-linux-gnu!"
                return 1
            fi
        fi
    fi
    if ! install_package vorbis-dev; then
        return 1
    fi
    if ! install_package openal-dev; then
        return 1
    fi
    if ! install_package opengl-dev; then
        return 1
    fi
    if ! install_package glu-dev; then
        return 1
    fi
    if ! install_package sdl12-compat; then
        return 1
    fi
    if ! install_package x11-dev; then
        return 1
    fi
    # For building AppImage
    if ! install_package file; then
        return 1
    fi
    if ! install_package fuse; then
        return 1
    fi
    # For building Flatpak
    if ! install_package flatpak; then
        return 1
    fi

    export CC=clang
    export CXX=clang++

    if ! cd ../../build; then
        echo "❌ build folder doesn't exist!" >&2
        return 1
    fi

    cd libobjc2
    rm -rf build
    mkdir build
    cd build
    if ! cmake -DTESTS=on -DCMAKE_BUILD_TYPE=Release -DGNUSTEP_INSTALL_TYPE=NONE -DEMBEDDED_BLOCKS_RUNTIME=ON -DOLDABI_COMPAT=OFF ../; then
        echo "❌ libobjc2 cmake configure failed!" >&2
        return 1
    fi

    if ! cmake --build .; then
        echo "❌ libobjc2 cmake build failed!" >&2
        return 1
    fi
    cmake --install .
    cd ../..

    cd tools-make
    make clean

    # Bash
    if [[ ${CURRENT_DISTRO,,} == "redhat" ]]; then
        LIB_PARAM="--with-libdir=lib64"
    else
        LIB_PARAM=""
    fi

    if ! ./configure --with-library-combo=ng-gnu-gnu --with-runtime-abi=gnustep-2.2 ${LIB_PARAM:+"$LIB_PARAM"}; then
        echo "❌ tools-make configure failed!" >&2
        return 1
    fi
    make
    make install
    cd ..

    cd libs-base
    make clean
    source /usr/local/share/GNUstep/Makefiles/GNUstep.sh
    if ! ./configure; then
        echo "❌ libs-base configure failed!" >&2
        return 1
    fi
    if ! make -j$(nproc); then
        echo "❌ libs-base make failed!" >&2
        return 1
    fi
    make install

	popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

