#!/bin/bash
# Parameter one: "system", "home", or "build" (defaults to home).
# Parameter two: escalate command (defaults to sudo for 'system').

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    echo "Building GNUStep libraries"

    source dep_location_fn.sh
    local lib_subdir target escalate
    dep_location lib_subdir target escalate "gnustep" $1 $2


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
    if ! cmake -DCMAKE_INSTALL_PREFIX="$target" -DCMAKE_INSTALL_LIBDIR="$lib_subdir" -DTESTS=on -DCMAKE_BUILD_TYPE=Release -DGNUSTEP_INSTALL_TYPE=NONE -DEMBEDDED_BLOCKS_RUNTIME=ON -DOLDABI_COMPAT=OFF ../; then
        echo "❌ libobjc2 cmake configure failed!" >&2
        return 1
    fi

    if ! cmake --build .; then
        echo "❌ libobjc2 cmake build failed!" >&2
        return 1
    fi
    $escalate cmake --install .
    cd ../..

    cd tools-make
    make clean

    local lib_dir="$target/$lib_subdir"
    export CPPFLAGS="-I$target/include"
    export LDFLAGS="-L$lib_dir"

    if ! ./configure --prefix="$target" --with-library-combo=ng-gnu-gnu --with-runtime-abi=gnustep-2.2 "--with-libdir=$lib_subdir"; then
        echo "❌ tools-make configure failed!" >&2
        return 1
    fi
    make
    $escalate make install
    cd ..

    cd libs-base
    make clean

    export LD_LIBRARY_PATH="$lib_dir:$LD_LIBRARY_PATH"
    source "$target/share/GNUstep/Makefiles/GNUstep.sh"
    if ! ./configure; then
        echo "❌ libs-base configure failed!" >&2
        return 1
    fi
    if ! make -j$(nproc); then
        echo "❌ libs-base make failed!" >&2
        return 1
    fi
    $escalate make install

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

