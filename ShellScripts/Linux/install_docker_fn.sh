#!/bin/bash

# Installs Docker, which mk.sh pkg-appimage needs to build the AppImage in a container. Called via
# install_packages_root.sh.
#
# Only the distribution's package is installed. Starting the service and adding a user to the docker group, which
# gives that user root access to the machine, are left to the user.

install_docker() {
    if command -v docker > /dev/null; then  # another Docker, such as docker-ce, could conflict with the package
        echo "✅ Docker is already installed: $(command -v docker)"
    else
        echo "📦 Installing Docker..."
        install_package docker || return 1
    fi
    echo "ℹ️ If ./mk.sh pkg-appimage cannot use Docker, start it and let your user run it:"
    echo "     sudo systemctl enable --now docker"
    echo "     sudo usermod -aG docker <user>   # gives <user> root access; log out and in again afterwards"
}
