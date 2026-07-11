generate_manifest() {
    local output_file="$1"
    local deployment_release="$2"
    local ver_full="$3"
    local ver_quad="$4"
    local ver_githash="$5"
    local build_time="$6"
    source ShellScripts/common/get_gitremote_fn.sh
    local git_remote
    get_gitremote git_remote

    # Redirect the entire block output into the manifest_output file
    {
        echo "{"
        echo "    title = \"Oolite core\";"
        echo "    identifier = \"org.oolite.oolite\";"
        echo "    "
        echo "    version = \"$ver_full\";"
        echo "    version_quad = \"$ver_quad\";"
        echo "    git_commit_hash = \"$ver_githash\";"
        echo "    build_time = \"$build_time\";"
        echo "    git_remote_url = \"$git_remote\";"

        if [[ "$deployment_release" == "yes" ]]; then
            echo "    debug_functionality_support = no;"
        else
            echo "    debug_functionality_support = yes;"
        fi
        IFS='.' read -r major minor rest <<< "$ver_full"
        local ver_short="$major.$minor"
        echo "    required_oolite_version = \"${ver_short}\";"
        echo "    "
        echo "    license = \"GPL 2+ / CC-BY-NC-SA 3.0 - see LICENSE.md for details\";"
        echo "    author = \"Giles Williams, Jens Ayton and contributors\";"
        echo "    information_url = \"https://oolite.space/\";"
        echo "}"
    } > "$output_file"
}
