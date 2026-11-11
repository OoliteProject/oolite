install_zensical() {
    # Installs Zensical
    # Parameter one: Python virtualenv folder
    local venv_dir="$1"

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/create_venv_fn.sh"

    create_venv "$venv_dir"

    if python3 -m zensical --version >/dev/null 2>&1; then
        echo "✅ Zensical is already installed."
        deactivate
        return 0
    fi

    local req_file="$script_dir/../../Documentation/requirements.txt"
    if ! python3 -m pip install -r "$req_file"; then
        echo "❌ Could not install Zensical and its requirements!" >&2
        deactivate
        return 1
    fi
    deactivate
}
