 #!/bin/bash
# Installs the Homebrew packages needed to build Oolite on macOS (Apple Silicon).
# Requires Xcode or the Xcode command line tools, and Homebrew (https://brew.sh).

set -euo pipefail

if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Install it from https://brew.sh first." >&2
    exit 1
fi

packages=(
    # Build tools (bash 4+, GNU coreutils and gitversion are used by the build scripts)
    bash coreutils gitversion jq meson ninja pkgconf
    # Documentation
    doxygen graphviz pandoc typst weasyprint
    # Libraries
    sdl3 libpng openal-soft libvorbis nspr espeak-ng
)

brew install "${packages[@]}"
echo "✅ Homebrew packages installed. Next run ShellScripts/macOS/build_mozilla_js.sh"
