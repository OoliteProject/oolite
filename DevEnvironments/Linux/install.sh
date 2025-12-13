#!/bin/bash
# No parameters: build target = release
# One parameter: build target

run_script() {
    # First optional parameter is build target. Default target is release.
    pushd "$(dirname "$0")"
    source ./install_package_fn.sh

    install_package base-devel
    install_package clang
    install_package lldb
    install_package cmake
    install_package png-dev
    install_package zlib-dev
    install_package nspr-dev
    install_package espeak-ng-dev
    install_package vorbis-dev
    install_package openal-dev
    install_package opengl-dev
    install_package glu-dev
    install_package sdl12-compat
    install_package x11-dev

    export CC=clang
    export CXX=clang++

    cd ../..

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
    sudo cmake --install .
    cd ../..

    cd tools-make
    make distclean
    if ! ./configure --with-library-combo=ng-gnu-gnu --with-runtime-abi=gnustep-2.2; then
        echo "❌ tools-make configure failed!" >&2
        return 1
    fi
    make
    sudo make install
    cd ..

    cd libs-base
    make distclean
    source /usr/local/share/GNUstep/Makefiles/GNUstep.sh
    if ! ./configure; then
        echo "❌ libs-base configure failed!" >&2
        return 1
    fi
    if ! make -j16; then
        echo "❌ libs-base make failed!" >&2
        return 1
    fi
    sudo make install
    cd ..

    cd oolite
    if [[ -z "$1" ]]; then
        TARGET=release
    else
        TARGET=$1
    fi

	if make -f Makefile $TARGET -j$(nproc); then
		echo "✅ Oolite build completed successfully"
	else
		echo "❌ Oolite build failed" >&2
		return 1
	fi

	popd
}

run_script $1
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

