# Usage: download <URL> <DESTINATION_PATH> ["+x"]
download() {
    local download_url="$1"
    local outputdir="$2"
    local make_exec="${3:-}"

    local filename=$(basename "${download_url}")
    local dest="$outputdir/$filename"
    # Determine if we need to download
    local need_download=0
    if [[ "$make_exec" == "+x" ]]; then
        [[ ! -x "$dest" ]] && need_download=1
    else
        [[ ! -f "$dest" ]] && need_download=1
    fi

    # Download if missing/not executable
    if [[ "$need_download" -eq 1 ]]; then
        echo "📥 Downloading $filename..."

        # Ensure target directory exists
        mkdir -p "$outputdir"

        # -f: fail on HTTP errors (e.g. 404)
        # -sS: silent mode, but show error if it fails
        # -L: follow redirects
        if ! curl -fsSL -O --output-dir "${outputdir}" "$download_url"; then
            echo "❌ Error downloading $filename from $download_url!" >&2
            return 1
        fi

        if [[ "$make_exec" == "+x" ]]; then
            chmod +x "$dest"
        fi
    fi
}