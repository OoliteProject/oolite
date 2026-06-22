#!/bin/bash -x

echo "I am $0 $@"

run_script() {
    # First parameter is a suffix for the build type eg. test, dev
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    cd ../..
    # Deleting these prevents odd linking errors
    rm -rf oolite.app
    rm -rf obj.spk
    source ShellScripts/common/get_version.sh

    mkdir -p build
    cd build
    if ! command -v gitversion &> /dev/null; then
        echo "Installing gitversion..."
        source ../ShellScripts/common/download_github_fn.sh
        local outputdir="./"
        download_latest_release gitversion_tgz "GitTools" "GitVersion" "linux-x64" "$outputdir"
        tar xfz ${gitversion_tgz} --directory "$outputdir"
        chmod +x "$outputdir/gitversion"
        mv "$outputdir/gitversion" /usr/local/bin/gitversion
        rm -f ${gitversion_tgz}
    fi

    cp ../installers/flatpak/space.oolite.Oolite.* ./

    mkdir -p shared-modules/glu
    if ! curl -o shared-modules/glu/glu-9.json -L https://github.com/flathub/shared-modules/raw/refs/heads/master/glu/glu-9.json; then
        echo "❌ Flatpak download of glu shared module failed!" >&2
        return 1
    fi

    local manifest="space.oolite.Oolite.yaml"

    local env_block="env:\n        VER_FULL: \"$VER_FULL\"\n        BUILDER: \"$BUILDER\""
    # Swap the comment
    sed -i "s|#[[:space:]]*CI builds add an env block here|$env_block|g" "$manifest" || return 1

    # check manifest
    local lint_exceptions=$(mktemp /tmp/oolite-lint-XXXXXX.json)
    cat <<EOF > "$lint_exceptions"
{
  "space.oolite.Oolite": [
    "finish-args-has-dev-input"
  ]
}
EOF
    trap 'rm -f "$lint_exceptions"' RETURN EXIT

    if command -v flatpak-builder-lint >/dev/null 2>&1; then
        if ! flatpak-builder-lint manifest "$manifest" --exceptions --user-exceptions="$lint_exceptions"; then
            echo "❌ Flatpak manifest lint failed!" >&2
            cat "$manifest"
            echo "❌ Flatpak manifest lint failed!" >&2
            return 1
        fi
    else
        echo "Native linter not found. Falling back to Flatpak container..."
        if ! flatpak run --filesystem="$lint_exceptions" --command=flatpak-builder-lint org.flatpak.Builder manifest "$manifest" --exceptions --user-exceptions="$lint_exceptions"; then
            echo "❌ Flatpak manifest lint failed!" >&2
            return 1
        fi
    fi

    # 3. Clean up
    rm -f "$lint_exceptions"
    trap - RETURN EXIT

    echo "Creating Flatpak..."
    if ! flatpak remote-add \
      --user \
      --if-not-exists \
      flathub https://flathub.org/repo/flathub.flatpakrepo; then
        echo "❌ Flatpak adding Flathub remote failed!" >&2
        return 1
    fi

    local total_lines=$(wc -l < $manifest)
    local start_line=$((total_lines - 3))
    sed -i "${start_line},\$d" $manifest
    cat <<EOF >> $manifest
      - type: dir
        path: ../
EOF

    # show effective manifest
    flatpak-builder --show-manifest $manifest

    if ! flatpak-builder \
      --user \
      --force-clean \
      --repo=repo \
      --install-deps-from=flathub \
      --disable-rofiles-fuse \
      build-dir \
      $manifest; then
        echo "❌ Flatpak build failed!" >&2
        return 1
    fi

    local suffix
   	if (( $# == 1 )); then
        suffix="_${1}-${VER_FULL}"
    else
        suffix="-$VER_FULL"
    fi
    local ARCH=$(uname -m)
    local filename="space.oolite.Oolite${suffix}-${ARCH}.flatpak"
    echo "Creating Flatpak $filename..."
    if ! flatpak build-bundle \
      repo \
      "$filename" \
      space.oolite.Oolite; then
        echo "❌ Flatpak bundle creation failed!" >&2
        return 1
    fi
    local debugname="space.oolite.Oolite.Debug${suffix}-${ARCH}.flatpak"
    if ! flatpak build-bundle \
      --runtime \
      repo \
      "$debugname" \
      space.oolite.Oolite.Debug; then
        echo "❌ Flatpak bundle creation failed!" >&2
        return 1
    fi

    popd
}

run_script "$@"
status=$?


# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi

