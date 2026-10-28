install_pandoc() {
    local outputdir="${1:-.}"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local pandoc_zip
    download_github_release pandoc_zip "jgm" "pandoc" "windows-x86_64.zip" "$outputdir"
    if ! unzip -o "${pandoc_zip}" -d "$outputdir"; then
        echo "❌ Could not unpack pandoc zip!" >&2
        return 1
    fi
    chmod +x "$outputdir"/pandoc-*/pandoc.exe
    if ! mv "$outputdir"/pandoc-*/pandoc.exe "$MINGW_PREFIX/bin/pandoc.exe"; then
        echo "❌ Could not move pandoc to $MINGW_PREFIX/bin!" >&2
        return 1
    fi
    rm -rf "$outputdir"/pandoc-*
    rm -f "${pandoc_zip}"
}
