#!/bin/bash

# This script must be run as root (for example with sudo).


run_script() {
    local skip_wayland=false

    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -s|--skip-wayland) skip_wayland=true; shift ;;
            *) shift ;;
        esac
    done

    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi


    local SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$SCRIPT_DIR"

    source ./install_package_fn.sh

    if ! install_package base-devel; then
        return 1
    fi
    if ! install_package clang; then
        return 1
    fi
    if ! install_package cmake; then
        return 1
    fi
    if ! install_package gnutls-dev; then
        return 1
    fi
    # Check Python
    if ! python3 --version >/dev/null 2>&1; then
        if ! install_package python; then
            return 1
        fi
    fi
    if [[ $skip_wayland == false ]]; then
        if [[ ${CURRENT_DISTRO,,} == "arch" ]]; then
            # 1. Initialize the pacman keyring
            # This creates the trust database and local signing keys
            pacman-key --init
            pacman-key --populate archlinux

            # 2. Add Chaotic-AUR keys
            # Note the added --allow-weak-key-signatures to bypass the SHA1 rejection
            pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
            pacman-key --lsign-key 3056513887B78AEB

            # 3. Download and Install keyrings/mirrorlists
            # We use --noprogressbar for cleaner script logs
            pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
            pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

            # 4. Idempotent check for pacman.conf
            if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
                echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf
            fi

            # Force a sync so pacman knows about the new repo
            pacman -Sy
        fi
        if ! install_package xwfb-run; then
            return 1
        fi
    fi
    if ! install_package icu-dev; then
        return 1
    fi
    if ! install_package ffi-dev; then
        return 1
    fi
    if ! install_package xslt-dev; then
        return 1
    fi
    if ! install_package png-dev; then
        return 1
    fi
    if ! install_package zlib-dev; then
        return 1
    fi
    if ! install_package nspr-dev; then
        return 1
    fi
    if ! install_package espeak-ng-dev; then
        return 1
    fi
    if [ ! -d /usr/share/espeak-ng-data ]; then
        if [ ! -d /usr/local/share/espeak-ng-data ]; then
            if [ ! -d /usr/lib/x86_64-linux-gnu/espeak-ng-data ]; then
                echo "❌ espeak-ng-data not in /usr/share, /usr/local/share or /usr/lib/x86_64-linux-gnu!"
                return 1
            fi
        fi
    fi
    if ! install_package vorbis-dev; then
        return 1
    fi
    if ! install_package openal-dev; then
        return 1
    fi
    if ! install_package opengl-dev; then
        return 1
    fi
    if ! install_package glu-dev; then
        return 1
    fi
    if ! install_package sdl3; then
        return 1
    fi
    if ! install_package x11-dev; then
        return 1
    fi
    # For building AppImage
    if ! install_package appimage; then
        return 1
    fi
    # For building Flatpak
    if ! install_package flatpak; then
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

