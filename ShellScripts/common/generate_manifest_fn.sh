generate_manifest() {
    # Locate the xcconfig file
    local oolite_version_file="src/Cocoa/oolite-version.xcconfig"

    if [[ ! -f "$oolite_version_file" ]]; then
        echo "Error: $oolite_version_file not found." >&2
        popd > /dev/null
        return 1
    fi

    # Extract definition of $OOLITE_VERSION from the xcconfig
    source "$oolite_version_file"

    source ShellScripts/common/get_gitremote_fn.sh
    get_gitremote git_remote

    # Redirect the entire block output into the manifest_output file
    {
        echo "{"
        echo "    title = \"Oolite core\";"
        echo "    identifier = \"org.oolite.oolite\";"
        echo "    "
        echo "    version = \"$VER_FULL\";"
        echo "    git_remote_url = \"$git_remote\";"
        echo "    git_commit_hash = \"$VER_GITHASH\";"

        if [[ "$DEPLOYMENT_RELEASE_CONFIGURATION" == "yes" ]]; then
            echo "    debug_functionality_support = no;"
        else
            echo "    debug_functionality_support = yes;"
        fi

        echo "    required_oolite_version = \"$OOLITE_VERSION\";"
        echo "    "
        echo "    license = \"GPL 2+ / CC-BY-NC-SA 3.0 - see LICENSE.md for details\";"
        echo "    author = \"Giles Williams, Jens Ayton and contributors\";"
        echo "    information_url = \"https://oolite.space/\";"
        echo "}"
    } > "$1"
}