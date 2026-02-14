#!/bin/bash

run_script() {
    # First parameter is a suffix for the build type eg. test, dev
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ../..
    # Deleting these prevents odd linking errors
    rm -rf oolite.app
    rm -rf obj.spk
    source ShellScripts/common/get_version.sh
    source ShellScripts/common/check_rename_fn.sh
    source ShellScripts/common/checkout_submodules_fn.sh

    if ! checkout_submodules; then
        return 1
    fi

    mkdir -p build
    cd build
    cp ../installers/flatpak/space.oolite.Oolite.* ./

    mkdir -p shared-modules/glu
    if ! curl -o shared-modules/glu/glu-9.json -L https://github.com/flathub/shared-modules/raw/refs/heads/master/glu/glu-9.json; then
        echo "❌ Flatpak download of glu shared module failed!" >&2
        return 1
    fi
    mkdir -p shared-modules/SDL
    if ! curl -o shared-modules/SDL/sdl12-compat.json -L https://github.com/flathub/shared-modules/raw/refs/heads/master/SDL/sdl12-compat.json; then
        echo "❌ Flatpak download of SDL shared module failed!" >&2
        return 1
    fi
    if ! curl -o shared-modules/SDL/sdl12-compat-cmake-version.patch -L https://github.com/flathub/shared-modules/raw/refs/heads/master/SDL/sdl12-compat-cmake-version.patch; then
        echo "❌ Flatpak download of SDL cmake patch failed!" >&2
        return 1
    fi

    if ! flatpak-builder-lint manifest space.oolite.Oolite.yaml; then
        echo "❌ Flatpak manifest lint failed!" >&2
        return 1
    fi

    echo "Creating Flatpak..."
    if ! flatpak remote-add \
      --user \
      --if-not-exists \
      flathub https://flathub.org/repo/flathub.flatpakrepo; then
        echo "❌ Flatpak adding Flathub remote failed!" >&2
        return 1
    fi

    sed -i "/- name: oolite/a \    build-options:\n      env:\n        VERSION_OVERRIDE: \"$VER\"" \
        space.oolite.Oolite.yaml
    TOTAL_LINES=$(wc -l < space.oolite.Oolite.yaml)
    START_LINE=$((TOTAL_LINES - 3))
    sed -i "${START_LINE},\$d" space.oolite.Oolite.yaml
    cat <<EOF >> space.oolite.Oolite.yaml
      - type: dir
        path: ../
EOF
    if ! flatpak-builder \
      --user \
      --force-clean \
      --repo=repo \
      --install-deps-from=flathub \
      --disable-rofiles-fuse \
      build-dir \
      space.oolite.Oolite.yaml; then
        echo "❌ Flatpak build failed!" >&2
        return 1
    fi

    if ! flatpak build-bundle \
      repo \
      space.oolite.Oolite.flatpak \
      space.oolite.Oolite; then
        echo "❌ Flatpak bundle creation failed!" >&2
        return 1
    fi

   	if (( $# == 1 )); then
        SUFFIX="${1}_${VER}"
    else
        SUFFIX="$VER"
    fi

    if ! check_rename "space.oolite.Oolite" "space.oolite.Oolite.flatpak" $SUFFIX; then
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

