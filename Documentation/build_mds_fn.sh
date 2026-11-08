#!/bin/bash

build_mds() {
    if ! command -v typst >/dev/null 2>&1; then
        echo "❌ Typst not found!" >&2
        return 1
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
        # typst/markdown.typ renders the Markdown with the vendored cmarker package
        if ! typst compile --root . --input src="$src" typst/markdown.typ "assets/pdfs/$dest"; then
            echo "❌ Failed to convert $src" >&2
            return 1
        fi
    done
    cd ..
    echo "✅ Markdown to PDF conversion successful"
}
