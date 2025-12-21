checkout_deps() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ../..

    echo "Cloning GNUStep libraries"
    git clone --filter=blob:none https://github.com/gnustep/libobjc2.git
    git clone --filter=blob:none https://github.com/gnustep/tools-make.git
    git clone --filter=blob:none https://github.com/gnustep/libs-base.git
    popd
}
