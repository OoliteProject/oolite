#!/bin/bash
# Installs Gitversion. Called from build-flatpak GitHub Actions workflow.

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/install_gitversion_fn.sh" && install_gitversion "$@"
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
