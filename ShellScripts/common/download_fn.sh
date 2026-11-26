download() {
    # Download file if missing/not executable
    # Parameter one: download URL
    # Parameter two: destination filepath
    # Parameter three: optional +x to make executable
    local download_url="$1"
    local filepath="$2"
    local make_exec="${3:-}"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/curl_fn.sh"

    # Determine if we need to download
    local need_download=0
    if [[ "$make_exec" == "+x" ]]; then
        [[ ! -x "$filepath" ]] && need_download=1
    else
        [[ ! -f "$filepath" ]] && need_download=1
    fi

    # Download if missing/not executable
    if [[ "$need_download" -eq 1 ]]; then
        echo "📥 Downloading $download_url to $filepath..."

        # -f: fail on HTTP errors (e.g. 404)
        # -sS: silent mode, but show error if it fails
        # -L: follow redirects
        if ! curl -fsSL -o "$filepath" "$download_url"; then
            echo "❌ Error downloading $download_url to $filepath!" >&2
            return 1
        fi

        if [[ "$make_exec" == "+x" ]]; then
            chmod +x "$filepath"
        fi
    fi
}