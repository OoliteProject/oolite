checkout_submodules() {
    pushd "$(dirname "$0")"
    cd ../..

    if [ -z "$(ls -A "deps/Cross-platform-deps")" ]; then
        echo "Checking out Oolite's submodules"
        cp .absolute_gitmodules .gitmodules
        git submodule update --init
        git checkout -- .gitmodules
    fi
    popd
}
