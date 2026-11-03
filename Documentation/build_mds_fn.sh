#!/bin/bash

build_mds() {
    local python_cmd="$1"

    local pandoc_bin
    if command -v pandoc >/dev/null 2>&1; then
        pandoc_bin="pandoc"
    elif [ -f "$HOME/.local/bin/pandoc" ]; then
        pandoc_bin="$HOME/.local/bin/pandoc"
    else
        echo "❌ Pandoc not found!" >&2
        return 1
    fi

    if [[ "$(uname -s)" != "Darwin" || -n "$FLATPAK_DEST" ]]; then
        if ! "$python_cmd" -m weasyprint --version >/dev/null 2>&1; then
            echo "❌ WeasyPrint or Pango libraries not found in environment!" >&2
            if command -v deactivate >/dev/null 2>&1; then
                deactivate
            fi
            return 1
        fi
    fi

    cd docs/
    # LICENSE.md lives at the repo root; stage it alongside the other
    # sources (mirrors build_documentation.sh, which copies it into docs/)
    if ! cp "../../../LICENSE.md" "license.md"; then
        echo "❌ Could not stage LICENSE.md!" >&2
        return 1
    fi

    declare -A DOCS=(
        ["index.md"]="OoliteReadMe.pdf"
        ["advice.md"]="AdviceForNewCommanders.pdf"
        ["privacy.md"]="Privacy.pdf"
        ["license.md"]="License.pdf"
    )

    local src
    local dest
    for src in "${!DOCS[@]}"; do
        dest="${DOCS[$src]}"

        echo "📄 Converting $src..."
        if ! "$pandoc_bin" "$src" -o "assets/pdfs/$dest" \
            --pdf-engine=weasyprint \
            --css=css/extra.css; then
            echo "❌ Failed to convert $src" >&2
            return 1
        fi
    done
    cd ..
    echo "✅ Markdown to PDF conversion successful"
}