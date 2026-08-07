#!/bin/bash -e

# No parameters: build clang only
# One parameter gcc = build gcc only
# One parameter clang = build clang only

install() {
    # First parameter is package name
    # Second optional parameter is gcc or clang
    echo "Installing $1 package"

    local fullname
    if [[ -z "$2" ]]; then
        fullname=$1
    else
        fullname="${1}_${2}"
    fi

    local packagename="$MINGW_PACKAGE_PREFIX-$fullname*any.pkg.tar.zst"
    local filename=$(ls $packagename 2>/dev/null)

    # package file eg. mingw-w64-x86_64-libobjc2-2.3-3-any.pkg.tar.zst
    if [[ -z "$filename" ]]; then
        echo "❌ No file matching $packagename found!" >&2
        return 1
    fi

    if ! pacman -U $filename --noconfirm ; then
        echo "❌ $filename install failed!" >&2
        return 1
    fi
}

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/../common/download_github_release_fn.sh"
    pushd "$script_dir"

    local oolite_deps_url="https://api.github.com/repos/OoliteProject/oolite_windeps_build/releases/latest"

    pacman -Syu --noconfirm
    pacman -S --noconfirm dos2unix git pactoys unzip
    pacboy -S --noconfirm binutils espeak-ng jq libpng libvorbis mesa meson ninja nsis openal pcaudiolib python-pip sdl3
    mkdir -p ../../build/packages
    cd ../../build
    # install gitversion
    local gitversion_zip
    local outputdir="."
    download_github_release gitversion_zip "GitTools" "GitVersion" "win-x64" "$outputdir"
    unzip -o ${gitversion_zip} -d "$outputdir"
    chmod +x "$outputdir/gitversion.exe"
    mv "$outputdir/gitversion.exe" "$MINGW_PREFIX/bin/gitversion.exe"
    rm -f ${gitversion_zip}

    cd packages
    curl -s "$oolite_deps_url" | \
    grep -oP '"browser_download_url": "\K[^"]+' | \
    while read -r url; do
        raw_filename="${url##*/}"
        clean_filename=$(printf '%b' "${raw_filename//%/\\x}")
        echo "Downloading: $clean_filename"
        curl -L "$url" -o "$clean_filename"
    done

    echo "Installing common packages"
    local package_names=(spidermonkey)
    for packagename in "${package_names[@]}"; do
        if ! install $packagename; then
            return 1
        fi
    done

    if [[ -z "$1" || "$1" == "clang" ]]; then
        pacboy -S clang --noconfirm
        pacboy -S lld --noconfirm

        echo "Installing GNUStep libraries with clang"
        export cc=$MINGW_PREFIX/bin/clang
        export cxx=$MINGW_PREFIX/bin/clang++
        local clang_package_names=(libobjc2 gnustep-make gnustep-base)
        for packagename in "${clang_package_names[@]}"; do
            if ! install $packagename clang; then
                return 1
            fi
        done
        pacman -Q > installed-packages-clang.txt
    else
        echo "Installing GNUStep libraries with gcc"
        export cc=$MINGW_PREFIX/bin/gcc
        export cxx=$MINGW_PREFIX/bin/g++
        local gcc_package_names=(gnustep-make gnustep-base)
        for packagename in "${gcc_package_names[@]}"; do
            if ! install $packagename gcc; then
                return 1
            fi
        done
        pacman -Q > installed-packages-gcc.txt
    fi

    if ! grep -q "# Custom history settings" ~/.bashrc; then
        cat >> ~/.bashrc <<'EOF'
# Custom history settings
WIN_HOME=$(cygpath "$USERPROFILE")
export HISTFILE=$WIN_HOME/.bash_history
export HISTSIZE=5000
export HISTFILESIZE=10000
shopt -s histappend
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
EOF
    fi
    popd
}

run_script "$@"
status=$?

# Exit only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit $status
fi