#!/bin/bash -x

echo "I am $0 $@"

run_script() {
    # First parameter is a suffix for the build type eg. test, dev
    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    cd ../..
    # Deleting these prevents odd linking errors
    rm -rf oolite.app
    rm -rf obj.spk
    source ShellScripts/common/get_version.sh

    mkdir -p build
    cd build
    cp ../installers/flatpak/space.oolite.Oolite.* ./

    local MANIFEST="space.oolite.Oolite.yaml"

    if [ -n "${SEMVER}" ] && [ -n "${PROJECTNAME}" ]; then
        ENV_BLOCK="env:\n        SEMVER: \"$SEMVER\"\n        PROJECTNAME: \"$PROJECTNAME\"\n        VERSION: \"$SEMVER\""
        # Swap the comment
        sed -i "s|#[[:space:]]*CI builds add an env block here|$ENV_BLOCK|g" "$MANIFEST" || return 1
    fi

    # check manifest
    if command -v flatpak-builder-lint >/dev/null 2>&1; then
        if ! flatpak-builder-lint manifest "$MANIFEST"; then
            echo "❌ Flatpak manifest lint failed!" >&2
            cat $MANIFEST
            echo "❌ Flatpak manifest lint failed!" >&2
            return 1
        fi
    else
        echo "Native linter not found. Falling back to Flatpak container..."
        if ! flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest "$MANIFEST"; then
            echo "❌ Flatpak manifest lint failed!" >&2
            return 1
        fi
    fi

    echo "Creating Flatpak..."
    if ! flatpak remote-add \
      --user \
      --if-not-exists \
      flathub https://flathub.org/repo/flathub.flatpakrepo; then
        echo "❌ Flatpak adding Flathub remote failed!" >&2
        return 1
    fi

    local TOTAL_LINES=$(wc -l < $MANIFEST)
    local START_LINE=$((TOTAL_LINES - 3))
    sed -i "${START_LINE},\$d" $MANIFEST
    cat <<EOF >> $MANIFEST
      - type: dir
        path: ../
EOF

    # show effective manifest
    flatpak-builder --show-manifest $MANIFEST

    if ! flatpak-builder \
      --user \
      --force-clean \
      --repo=repo \
      --install-deps-from=flathub \
      --disable-rofiles-fuse \
      build-dir \
      $MANIFEST; then
        echo "❌ Flatpak build failed!" >&2
        return 1
    fi

    local SUFFIX
   	if (( $# == 1 )); then
        SUFFIX="_${1}-${VER_FULL}"
    else
        SUFFIX="-$VER_FULL"
    fi
    local ARCH=$(uname -m)
    FILENAME="space.oolite.Oolite${SUFFIX}-${ARCH}.flatpak"
    echo "Creating Flatpak $FILENAME..."
    if ! flatpak build-bundle \
      repo \
      "$FILENAME" \
      space.oolite.Oolite; then
        echo "❌ Flatpak bundle creation failed!" >&2
        return 1
    fi
    DEBUGLNAME="space.oolite.Oolite.Debug${SUFFIX}-${ARCH}.flatpak"
    if ! flatpak build-bundle \
      --runtime \
      repo \
      "$DEBUGLNAME" \
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

