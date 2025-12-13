checkout_submodules() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ../..
    if [ -z "$(ls -A "deps/Cross-platform-deps")" ]; then
        echo "Checking out Oolite's submodules"
        git submodule update --init
        git checkout -- .gitmodules
    fi

    popd
}
