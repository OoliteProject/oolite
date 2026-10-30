#!/bin/bash

build_mds() {
    # Define local variables at the top of the function
    local SCRIPT_DIR
    local PYTHON_CMD
    local PANDOC_BIN
    local VENV_DIR="../.venv"
    local PDF_DIR="assets/pdfs"
    local SRC
    local DEST

    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR" > /dev/null || return 1

    # 1. Check Python
    if python3 --version >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif python --version >/dev/null 2>&1; then
        PYTHON_CMD="python"
    else
        echo "❌ Python not found!" >&2
        popd > /dev/null
        return 1
    fi

    # 2. Check Pandoc
    if command -v pandoc >/dev/null 2>&1; then
        PANDOC_BIN="pandoc"
    elif [ -f "$HOME/.local/bin/pandoc" ]; then
        PANDOC_BIN="$HOME/.local/bin/pandoc"
    else
        echo "❌ Pandoc not found!" >&2
        popd > /dev/null
        return 1
    fi

    # 3. Check Virtual Environment folder
    if [ ! -d "$VENV_DIR" ]; then
        echo "❌ Virtual environment folder ($VENV_DIR) not found!" >&2
        popd > /dev/null
        return 1
    else
        # Try to activate based on OS structure
        if [ -f "$VENV_DIR/Scripts/activate" ]; then
            source "$VENV_DIR/Scripts/activate"
        elif [ -f "$VENV_DIR/bin/activate" ]; then
            source "$VENV_DIR/bin/activate"
        else
            echo "❌ Activation script not found in $VENV_DIR!" >&2
            popd > /dev/null
            return 1
        fi
    fi

    # 4. Check WeasyPrint package
    if ! "$PYTHON_CMD" -m weasyprint --version >/dev/null 2>&1; then
        echo "❌ WeasyPrint or Pango libraries not found in environment!" >&2
        if command -v deactivate >/dev/null 2>&1; then
            deactivate
        fi
        popd > /dev/null
        return 1
    fi

    # Prepare Directories (docs/ is mkdocs' docs_dir; files under it
    # are copied to the site, so PDFs land at <base_url>/assets/pdfs/)
    mkdir -p "docs/$PDF_DIR"

    cd "docs/md" || {
        popd > /dev/null
        return 1
    }

    # LICENSE.md lives at the repo root; stage it alongside the other
    # sources (mirrors build_documentation.sh, which copies it into docs/)
    if ! cp "../../../LICENSE.md" "license.md"; then
        echo "❌ Could not stage LICENSE.md!" >&2
        popd > /dev/null
        return 1
    fi

    declare -A DOCS=(
        ["index.md"]="OoliteReadMe.pdf"
        ["advice.md"]="AdviceForNewCommanders.pdf"
        ["privacy.md"]="Privacy.pdf"
        ["license.md"]="License.pdf"
    )

    for SRC in "${!DOCS[@]}"; do
        DEST="${DOCS[$SRC]}"

        echo "📄 Converting $SRC..."
        if ! "$PANDOC_BIN" "$SRC" -o "../$PDF_DIR/$DEST" \
            --pdf-engine=weasyprint \
            --css=../css/extra.css; then
            echo "❌ Failed to convert $SRC" >&2
            popd > /dev/null
            return 1
        fi
    done

    # Remove the staged LICENSE.md copy; it is re-staged on every run
    rm -f "license.md"

    echo "✅ PDF task finished"

    # Final cleanup
    if command -v deactivate >/dev/null 2>&1; then
        deactivate
    fi
    popd > /dev/null
}