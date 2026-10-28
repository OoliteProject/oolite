install_typst() {
    local outputdir="${1:-.}"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"

    local arch="$(uname -m 2>/dev/null || echo x86_64)"
    local typst_zip
    download_github_release typst_zip "typst" "typst" "${arch}-pc-windows-msvc.zip" "$outputdir"
    if ! unzip -o "${typst_zip}" -d "$outputdir"; then
        echo "❌ Could not unpack typst zip!" >&2
        return 1
    fi
    chmod +x "$outputdir"/typst-*/typst.exe
    if ! mv "$outputdir"/typst-*/typst.exe "$MINGW_PREFIX/bin/typst.exe"; then
        echo "❌ Could not move typst to $MINGW_PREFIX/bin!" >&2
        return 1
    fi
    rm -rf "$outputdir"/typst-*
    rm -f "${typst_zip}"
}
