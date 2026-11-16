#!/bin/bash
#
# Helpers for naming packages after the JavaScript engine they were built with (issue #580), so
# SpiderMonkey and QuickJS packages of the same version can be released side by side.

# Prints the js_engine option that a meson build directory was set up with.
meson_js_engine() {
    local build_dir="$1"
    meson configure "$build_dir" | awk '$1 == "js_engine" { print $2; exit }'
}

# Prints the package name suffix for a JavaScript engine: nothing for SpiderMonkey, so its package
# names are unchanged, and "-quickjs" for QuickJS.
js_engine_pkg_suffix() {
    local engine="$1"
    if [[ "$engine" == "quickjs" ]]; then
        echo "-quickjs"
    fi
}
