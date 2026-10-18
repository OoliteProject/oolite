#!/bin/bash
#
# Calculates the Oolite version number and build dates
#


# Derive the repository root from this script's own location
# (<repo>/ShellScripts/common/) and normalize the working directory to it.
# Launchers like macOS Homebrew meson (run from Python.app) do not guarantee a
# repo cwd nor inherit GIT_DIR/GIT_WORK_TREE; under mk.sh on Linux this cd is
# a no-op (mk.sh already pushes to the repo root).
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$REPO_ROOT" || exit 1

if [[ -n "${MINGW_PREFIX+x}" ]]; then  # bash-3.2-safe replacement for `[[ -v MINGW_PREFIX ]]` (needs bash >= 4.3)
    WIN_PID=$(ps -p $$ | awk 'NR>1 {print $4}')
    PARENT_PROCESS=$(powershell.exe -Command "
        \$parentId = (gwmi Win32_Process -Filter 'ProcessId = $WIN_PID').ParentProcessId
        if (\$parentId) {
            Write-Output (gwmi Win32_Process -Filter \"ProcessId = \$parentId\").Name
        }
    " 2>/dev/null | tr -d '\r')
    if [ "$PARENT_PROCESS" = "python.exe" ] && ps | grep -q "meson"; then
        PARENT_PROCESS="meson"
    fi
else
    PARENT_PROCESS=$(ps -p $PPID -o comm= 2>/dev/null || true)
fi
# Accept either meson signal: MESON_BUILD_ROOT (set by meson itself) or the
# parent process comm. The comm check alone never matches on macOS, where
# Homebrew meson runs under Python.app, so the parent comm is not "meson".
if [[ -z "$MESON_BUILD_ROOT" ]] && [[ "$PARENT_PROCESS" != "meson" ]]; then
    SUITE_PARENT=$(basename "${BASH_SOURCE[1]}")  # Get the name of the script that is sourcing this file
    ALLOWED_SCRIPT="create_flatpak_fn.sh"  # Define the ONLY script allowed to source this
    if [[ "$SUITE_PARENT" != "$ALLOWED_SCRIPT" ]]; then
        echo "❌ Parent process is $PARENT_PROCESS, Bash parent is $SUITE_PARENT. This file can only be called by meson or sourced by $ALLOWED_SCRIPT!" >&2
        unset SUITE_PARENT ALLOWED_SCRIPT
        return 1 2>/dev/null || exit 1
    fi
    unset SUITE_PARENT ALLOWED_SCRIPT
fi


run_script() {
    local build_dir="$1"  # Input string arguments

    if [[ -z "$build_dir" ]]; then
        echo "❌ build_dir argument is required!" >&2
        return 1
    fi

    source "ShellScripts/common/get_build_date_fn.sh"
    local output_ver_githash=$(git -C "$REPO_ROOT" rev-parse --short=7 HEAD)
    local dirty_suffix=""
    git -C "$REPO_ROOT" diff --quiet || dirty_suffix="-dirty"
    local lookup_hash="${output_ver_githash}${dirty_suffix}"
    local output_ver_full=""
    local output_buildtime=""
    local version_file="$build_dir/.meson_version"
    if [[ -z "${VER_FULL-}" ]]; then
        if [[ -f "$version_file" ]]; then  # Check if cache exists and has a matching hash context
            local githash ver_full ver_quad ver_gitrev cpp_date app_date buildtime builder
            source "$version_file" 2>/dev/null
            if [[ "$ver_githash" == "$lookup_hash" ]]; then
                echo "$ver_full"
                return 0
            fi
        fi
    else
        output_ver_full="$VER_FULL"
    fi

    if [[ -z "$output_ver_full" ]]; then
        local exact_tag=""  # Check for an exact Git tag first on a clean tree
        if [[ -z "$dirty_suffix" ]]; then
            exact_tag=$(git -C "$REPO_ROOT" describe --tags --exact-match HEAD 2>/dev/null)
        fi
        if [[ -n "$exact_tag" ]]; then
            output_ver_full="$exact_tag"
        else
            # gitversion-free fallback (the gitversion binary is not available
            # everywhere): nearest tag, commit distance since it, and a -dirty
            # marker on modified trees; --always degrades to a short hash when
            # no tag exists at all.
            output_ver_full=$(git -C "$REPO_ROOT" describe --tags --always --dirty)
        fi
    fi

    local clean_ver="${output_ver_full#v}"  # Strip any leading 'v', prerelease tags (-alpha), or build metadata (+)
    clean_ver="${clean_ver%%-*}"  # Example: "v1.91.0-alpha.1+dirty.3" -> "1.91.0"
    clean_ver="${clean_ver%%+*}"
    local ver_maj=$(echo "$clean_ver" | cut -d. -f1)  # Parse out Major, Minor, Patch using standard dot delimiters
    local ver_min=$(echo "$clean_ver" | cut -d. -f2)
    local ver_rev=$(echo "$clean_ver" | cut -d. -f3)
    [[ -z "$ver_rev" ]] && ver_rev="0"

    if [[ -z "$dirty_suffix" ]]; then  # Use git for other metrics for clean repository
        local closest_tag=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null)  # Derive distance from closest Git tag
        local ver_dist="0"
        if [[ -n "$closest_tag" ]]; then
            ver_dist=$(git -C "$REPO_ROOT" rev-list --count "${closest_tag}..HEAD")
        else
            ver_dist=$(git -C "$REPO_ROOT" rev-list --count HEAD)
        fi
        output_ver_quad="$ver_maj.$ver_min.$ver_rev.$ver_dist"
    else
        # Dirty repo: get uncommitted file count. BSD wc pads its output with
        # spaces, which would corrupt the version quad; the arithmetic
        # expansion strips them (a no-op on GNU wc).
        local ver_uncommitted=$(($(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l)))
        output_ver_quad="$ver_maj.$ver_min.$ver_rev.$ver_uncommitted"
    fi

    local output_cpp_date output_app_date output_builder
    get_build_date output_cpp_date output_app_date output_buildtime output_builder "${BUILDTIME-}"

    cat << EOF > "$version_file"  # Write new values to the hidden cache file
ver_githash="$lookup_hash"
ver_full="$output_ver_full"
ver_quad="$output_ver_quad"
cpp_date="$output_cpp_date"
app_date="$output_app_date"
buildtime="$output_buildtime"
builder="$output_builder"
EOF

    echo "$output_ver_full"
}

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_script "$@"
    exit $?
fi
