install_weasyprint() {
    local venv_dir="$1"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/create_venv_fn.sh"

    create_venv "$venv_dir"

    if ! python3 -m pip install --upgrade weasyprint; then
        echo "❌ WeasyPrint install failed or Pango dependencies not installed!" >&2
        deactivate
        return 1
    fi

    if ! python3 -m weasyprint --version >/dev/null 2>&1; then
        echo "❌ WeasyPrint install failed or Pango dependencies not installed!" >&2
        deactivate
        return 1
    fi
    deactivate
}
