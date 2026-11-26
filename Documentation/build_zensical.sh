#!/bin/bash
# Builds documentation site for local testing.
# Assumes you've run install_packages_root.sh and also install_zensical.sh.

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/build_zensical_fn.sh" && build_zensical
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi
