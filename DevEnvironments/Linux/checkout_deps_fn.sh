checkout_deps() {
    pushd "$(dirname "$0")"
    source ./install_package.sh
    install_package git

    cd ../..

    echo "Cloning GNUStep libraries"
    git clone --filter=blob:none https://github.com/gnustep/libobjc2.git
    git clone --filter=blob:none https://github.com/gnustep/tools-make.git
    git clone --filter=blob:none https://github.com/gnustep/libs-base.git
    popd
}
