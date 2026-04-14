#!/bin/bash
# Parameter one: "system", "home", or "build" (defaults to home).
# Parameter two: Escalate command (defaults to sudo for 'system').

run_script() {
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    echo "Building GNUStep libraries"

    source dep_location_fn.sh
    dep_location LIB_SUBDIR TARGET ESCALATE "gnustep" $1 $2


    mkdir -p ../../build
    cd ../../build

    # Define libraries and their specific pinned commits
    # Format: ["URL"]="COMMIT_HASH"
    declare -A repos=(
        ["https://github.com/gnustep/libobjc2.git"]="b67709ad7851973fde127022d8ac6a710c82b1d5"
        ["https://github.com/gnustep/tools-make.git"]="50cf9619e672fb2ff6825f239b5a172c5dc55630"
        ["https://github.com/gnustep/libs-base.git"]="530ac3454f9c8af315d823736252cb45221943c1"
    )

    for url in "${!repos[@]}"; do
        local commit="${repos[$url]}"
        local dir=$(basename "$url" .git)

        if [[ -d "$dir" ]]; then
            echo "Updating $dir and checking out commit $commit..."
            # Fetch the latest objects to ensure we have the commit locally
            git -C "$dir" fetch --quiet
        else
            echo "Cloning $dir..."
            # We clone without checking out immediately to save time before the specific checkout
            git clone --filter=blob:none --no-checkout "$url" "$dir"
        fi

        # Checkout the specific pinned commit
        git -C "$dir" checkout "$commit" --quiet

        # Verify we are on the right hash
        local current_hash=$(git -C "$dir" rev-parse HEAD)
        echo "✅ $dir is now at ${current_hash:0:7}"
    done

    export CC=clang
    export CXX=clang++

    cd libobjc2
    rm -rf build
    mkdir build
    cd build
    if ! cmake -DCMAKE_INSTALL_PREFIX="$TARGET" -DCMAKE_INSTALL_LIBDIR="$LIB_SUBDIR" -DTESTS=on -DCMAKE_BUILD_TYPE=Release -DGNUSTEP_INSTALL_TYPE=NONE -DEMBEDDED_BLOCKS_RUNTIME=ON -DOLDABI_COMPAT=OFF ../; then
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

    local LIB_DIR="$TARGET/$LIB_SUBDIR"
    export CPPFLAGS="-I$TARGET/include"
    export LDFLAGS="-L$LIB_DIR"

    if ! ./configure --prefix="$TARGET" --with-library-combo=ng-gnu-gnu --with-runtime-abi=gnustep-2.2 "--with-libdir=$LIB_SUBDIR"; then
        echo "❌ tools-make configure failed!" >&2
        return 1
    fi
    make
    $ESCALATE make install
    cd ..

    cd libs-base
    make clean

    export LD_LIBRARY_PATH="$LIB_DIR:$LD_LIBRARY_PATH"
    source "$TARGET/share/GNUstep/Makefiles/GNUstep.sh"
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

