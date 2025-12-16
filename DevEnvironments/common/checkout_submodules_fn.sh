checkout_submodules() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ../..

    # Run only if any submodule is uninitialized (leading '-')
    if git submodule status --recursive | grep -qE '^-'; then
        echo "Checking out submodules"
        git submodule update --init --recursive
        git checkout -- .gitmodules
    fi

    popd
}
