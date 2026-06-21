#!/bin/bash

# This script must be run as root (for example with sudo).
set -e


run_script() {
    # If current user ID is NOT 0 (root)
    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root to install dependencies. Rerun and escalate privileges (eg. sudo ...)"
        return 1
    fi


    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    pushd "$script_dir"

    source download_github_fn.sh

    # install gitversion
    local outputdir="../../build"
    mkdir -p "$outputdir"
    download_latest_release gitversion_tgz "GitTools" "GitVersion" "linux-x" "$outputdir"
    tar xfz ${gitversion_tgz} --directory "$outputdir"
    chmod +xr "$outputdir/gitversion"
    mv "$outputdir/gitversion" /usr/local/bin/gitversion
    rm -f ${gitversion_tgz}

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
    if ! install_package meson; then
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

