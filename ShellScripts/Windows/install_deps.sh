#!/bin/bash -e

# Installs required dependencies
# No parameters: build clang only
# One parameter gcc = build gcc only
# One parameter clang = build clang only

run_script() {
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    source "$script_dir/install_gitversion_fn.sh"
    source "$script_dir/install_typst_fn.sh"
    pushd "$script_dir"

    pacman -Syu --noconfirm
    pacman -S --noconfirm dos2unix git jq pactoys unzip
    pacboy -S --noconfirm binutils curl espeak-ng icu libffi libpng libvorbis mesa meson ninja nsis ntldd openal pcaudiolib python-pip sdl3 shared-mime-info
    pacboy -S --noconfirm doxygen graphviz
    mkdir -p ../../build/packages
    cd ../../build
    install_gitversion "."
    install_typst "."

    if [[ -z "$1" || "$1" == "clang" ]]; then
        pacboy -S clang --noconfirm
        pacboy -S lld --noconfirm
        pacman -Q > installed-packages-clang.txt
    else
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