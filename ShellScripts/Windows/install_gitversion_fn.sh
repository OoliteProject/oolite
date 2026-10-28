install_gitversion() {
    local outputdir="${1:-.}"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local gitversion_zip
    download_github_release gitversion_zip "GitTools" "GitVersion" "win-x64" "$outputdir"
    if ! unzip -o "${gitversion_zip}" -d "$outputdir"; then
        echo "❌ Could not unpack gitversion zip!" >&2
        return 1
    fi
    chmod +x "$outputdir/gitversion.exe"
    if ! mv "$outputdir/gitversion.exe" "$MINGW_PREFIX/bin/gitversion.exe"; then
        echo "❌ Could not move gitversion to $MINGW_PREFIX/bin!" >&2
        return 1
    fi
    rm -f "${gitversion_zip}"
}
