#!/bin/bash
# First optional parameter is install location. Defaults to build/gnustep.
# Second optional parameter is command to use to escalate privileges if needed. Defaults to not using root.

run_script() {
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source os_detection.sh

    echo "Building GNUStep libraries"

    mkdir -p ../../build
    cd ../../build

    local repos=(
        "https://github.com/gnustep/libobjc2.git"
        "https://github.com/gnustep/tools-make.git"
        "https://github.com/gnustep/libs-base.git"
    )

    for url in "${repos[@]}"; do
        # Extract the directory name from the URL (e.g., "libobjc2")
        local dir=$(basename "$url" .git)

        if [ -d "$dir" ]; then
            echo "Updating $dir..."
            git -C "$dir" pull
        else
            echo "Cloning $dir..."
            git clone --filter=blob:none "$url"
        fi
    done

    local GNUSTEP_DIR_RAW="${1:-./gnustep}"
    local ESCALATE="${2:-}"
    $ESCALATE mkdir -p "$GNUSTEP_DIR_RAW"
    local GNUSTEP_DIR=$(cd "$GNUSTEP_DIR_RAW" && pwd)
    local LIB_SUBDIR
    if [[ ${CURRENT_DISTRO,,} == "redhat" ]]; then
        LIB_SUBDIR="lib64"
    else
        LIB_SUBDIR="lib"
    fi


    export CC=clang
    export CXX=clang++

    cd libobjc2
    rm -rf build
    mkdir build
    cd build
    if ! cmake -DCMAKE_INSTALL_PREFIX="$GNUSTEP_DIR" -DCMAKE_INSTALL_LIBDIR="$LIB_SUBDIR" -DTESTS=on -DCMAKE_BUILD_TYPE=Release -DGNUSTEP_INSTALL_TYPE=NONE -DEMBEDDED_BLOCKS_RUNTIME=ON -DOLDABI_COMPAT=OFF ../; then
        echo "❌ libobjc2 cmake configure failed!" >&2
        return 1
    fi

    if ! cmake --build .; then
        echo "❌ libobjc2 cmake build failed!" >&2
        return 1
    fi
    $ESCALATE cmake --install .
    cd ../..

    cd tools-make
    make clean

    local LIB_DIR="$GNUSTEP_DIR/$LIB_SUBDIR"
    export CPPFLAGS="-I$GNUSTEP_DIR/include"
    export LDFLAGS="-L$LIB_DIR"

    if ! ./configure --prefix="$GNUSTEP_DIR" --with-library-combo=ng-gnu-gnu --with-runtime-abi=gnustep-2.2 "--with-libdir=$LIB_SUBDIR"; then
        echo "❌ tools-make configure failed!" >&2
        return 1
    fi
    make
    $ESCALATE make install
    cd ..

    cd libs-base
    make clean

    export LD_LIBRARY_PATH="$LIB_DIR:$LD_LIBRARY_PATH"
    source "$GNUSTEP_DIR/share/GNUstep/Makefiles/GNUstep.sh"
    if ! ./configure; then
        echo "❌ libs-base configure failed!" >&2
        return 1
    fi
    if ! make -j$(nproc); then
        echo "❌ libs-base make failed!" >&2
        return 1
    fi
    $ESCALATE make install

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

