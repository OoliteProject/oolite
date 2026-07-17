#!/bin/bash -x

create_flatpak() {
    local build_type="$1"
    local github_repository="$2" # GitHub repository (set by GitHub Actions)

    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    cd ../..
    flatpak_dir="build/flatpak"
    mkdir -p "$flatpak_dir"
    source ShellScripts/common/get_version.sh
    run_script "$flatpak_dir"
    local githash ver_full ver_quad ver_gitrev cpp_date app_date buildtime builder
    source "$flatpak_dir/.meson_version"
    cd "$flatpak_dir"

    cp ../../installers/flatpak/space.oolite.Oolite.* ./
    mkdir -p shared-modules/glu
    if ! curl -o shared-modules/glu/glu-9.json -L https://github.com/flathub/shared-modules/raw/refs/heads/master/glu/glu-9.json; then
        echo "❌ Flatpak download of glu shared module failed!" >&2
        return 1
    fi

    local manifest="space.oolite.Oolite.yaml"
    if ! sed -i "s|^[[:space:]]*- \./mk.sh.*|      - ./mk.sh flatpak-internal $build_type --ver-full=\"$ver_full\" --buildtime=\"$buildtime\" --github-repository=\"$github_repository\"|" "$manifest"; then
        echo "❌ Replacement of ./mk.sh line in $manifest failed!" >&2
        return 1
    fi
    tail -n 12 $manifest

#    local lint_exceptions=$(mktemp /tmp/oolite-lint-XXXXXX.json)
#    cat <<EOF > "$lint_exceptions"
#{
#  "space.oolite.Oolite": [
#    "finish-args-has-dev-input"
#  ]
#}
#EOF
#    trap 'rm -f "$lint_exceptions"' RETURN EXIT
#    if command -v flatpak-builder-lint >/dev/null 2>&1; then  # check manifest
#        if ! flatpak-builder-lint manifest "$manifest" --exceptions --user-exceptions="$lint_exceptions"; then
#            echo "❌ Flatpak manifest lint failed!" >&2
#            cat "$manifest"
#            echo "❌ Flatpak manifest lint failed!" >&2
#            return 1
#        fi
#    else
#        echo "Native linter not found. Falling back to Flatpak container..."
#        if ! flatpak run --filesystem="$lint_exceptions" --command=flatpak-builder-lint org.flatpak.Builder manifest "$manifest" --exceptions --user-exceptions="$lint_exceptions"; then
#            echo "❌ Flatpak manifest lint failed!" >&2
#            return 1
#        fi
#    fi
#    rm -f "$lint_exceptions"  # Clean up
#    trap - RETURN EXIT

    echo "Creating Flatpak..."
    if ! flatpak remote-add \
      --user \
      --if-not-exists \
      flathub https://flathub.org/repo/flathub.flatpakrepo; then
        echo "❌ Flatpak adding Flathub remote failed!" >&2
        return 1
    fi

    if ! sed -i "/- type: git/{
        N;
        /url:.*oolite\.git/{
            N;N;
            c\\
      - type: dir\\
        path: ../../
        }
    }" "$manifest"; then
        echo "❌ Replacement of Oolite git repo source lines in $manifest failed!" >&2
        return 1
    fi
    tail -n 12 $manifest

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

    local ARCH=$(uname -m)
    local filename="space.oolite.Oolite-$ver_full-$build_type-$ARCH.flatpak"
    echo "Creating Flatpak $filename..."
    if ! flatpak build-bundle \
      repo \
      "../$filename" \
      space.oolite.Oolite; then
        echo "❌ Flatpak bundle creation failed!" >&2
        return 1
    fi
    local debugname="space.oolite.Oolite.Debug${suffix}-${ARCH}.flatpak"
    if ! flatpak build-bundle \
      --runtime \
      repo \
      "../$debugname" \
      space.oolite.Oolite.Debug; then
        echo "❌ Flatpak bundle creation failed!" >&2
        return 1
    fi

    popd
}
