get_gitremote() {
    # Accept a variable name as the first argument to use as a nameref return
    local -n _final_url=$1

    local raw_url resolved_git_dir upstream_url

    # 1. Get the immediate remote URL
    raw_url=$(git config --get remote.origin.url)

    # 2. Check if the URL is actually a local directory path
    if [[ -d "$raw_url" ]]; then
        # Dynamically find the correct git directory without subshells
        if [[ -d "$raw_url/.git" ]]; then
            resolved_git_dir="$raw_url/.git"
        else
            resolved_git_dir="$raw_url"
        fi

        # Query the resolved git directory for the original remote
        upstream_url=$(git --git-dir="$resolved_git_dir" config --get remote.origin.url 2>/dev/null)

        # If we successfully found an upstream URL, use it.
        if [[ -n "$upstream_url" ]]; then
            _final_url="$upstream_url"
        else
            _final_url="UNKNOWN"
        fi
    else
        # It's already a standard web URL (GitHub, GitLab, etc.)
        _final_url="$raw_url"
    fi
}