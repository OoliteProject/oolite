parse_manifest() {
    local -n _ver_full="$1"
    local -n _ver_quad="$2"
    local -n _githash="$3"
    local -n _buildtime="$4"
    local -n _app_date="$5"
    local input_file="$6"

    if [[ ! -f "$input_file" ]]; then  # Ensure the manifest file exists before parsing
        echo "❌ Manifest file '$input_file' not found." >&2
        return 1
    fi

    get_manifest_value() {  # Helper function to extract a string inside quotes for a given key
        local key="$1"
        grep -E "^[[:space:]]*${key}[[:space:]]*=" "$input_file" | sed -E 's/.*"[[:space:]]*([^"]*)[[:space:]]*".*/\1/'
    }

    _ver_full=$(get_manifest_value "version")
    _ver_quad=$(get_manifest_value "version_quad")
    _githash=$(get_manifest_value "git_commit_hash")
    _buildtime=$(get_manifest_value "build_time")
    local clean_date="${_buildtime//./-}"
    _app_date=$(date -u -d "${clean_date:0:10}" +"%Y-%m-%d" 2>/dev/null || echo "")
}