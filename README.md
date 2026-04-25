[![build-all](https://github.com/OoliteProject/oolite/actions/workflows/build-all.yaml/badge.svg)](https://github.com/OoliteProject/oolite/actions/workflows/build-all.yaml)

[![GitHub release](https://img.shields.io/github/release/OoliteProject/Oolite.svg)](https://github.com/OoliteProject/Oolite/releases/latest)

| Windows                                                                                                                                                                   | Linux                                                                                                                                                                                   | OSX                                                                                                                                                                                   |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/OoliteInstall-1.92.1-win.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest) | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/oolite-1.92.1-x86_64.AppImage.svg)](https://github.com/OoliteProject/oolite/releases/latest)      |                 |
 [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/OoliteInstall-1.92.1-win-test.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest) | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/oolite_test-1.92.1-x86_64.AppImage.svg)](https://github.com/OoliteProject/oolite/releases/latest)         | OSX is not supported for v1.92 |
|[![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/Oolite-1.92.1-Deployment-to-Test-Release.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest)                                                                                                                                                                           | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/space.oolite.Oolite-1.92.1-x86_64.flatpak.svg)](https://github.com/OoliteProject/oolite/releases/latest) |                                                                                                                                                                                       |
|                                                                                                                                                                           |    |                                                                                                                                                                                       |

![Oolite Screenshot](https://addons.oolite.space/i/gallery/oxp/large/another_commander-210210_LeavingCoriolisAgain.png)

Oolite can be heavily customized via expansions. These modify the gameplay, add ships, improve graphics - the
possibilities are almost endless:

![Oolite Customized](https://addons.oolite.space/i/gallery/oxp/large/another_commander_ViperNew02.png)

Please join the [Oolite Bulletin Board](https://bb.oolite.space/), a friendly community of Oolite fans
and developers!

## Installing Oolite

You can download the latest version from [here](https://github.com/OoliteProject/oolite/releases).

### Windows

The Windows NSIS installer is named `OoliteInstall-XXX-win.exe` where XXX is a version number.
Double click the downloaded file to run the installer.

### Linux

Linux has Flatpak and AppImage versions. The Flatpak is named `space.oolite.Oolite_XXX.flatpak`
where XXX is a version number. Many Linux package managers support Flatpak so you should be able to
double click the downloaded file to install it.

The AppImage is named `Oolite_XXX-x86_64.AppImage` where XXX is a version number. Download this
file to where you would like it stored, make it executable and run, for example by typing

```bash
chmod +x Oolite_XXX-x86_64.AppImage
./Oolite_XXX-x86_64.AppImage
```

## Playing Oolite

Information about playing Oolite can be found [here](https://oolite.readthedocs.io/en/latest/).

For more information, see also [oolite.space](http://www.oolite.space/) and
[Elite Wiki](http://wiki.alioth.net/index.php/Oolite_Main_Page).

## Building from Source

We welcome developers to work on Oolite! If you wish to build the project from source, please follow
the instructions below. Note that the scripts require sudo for activities like installing dependent
libraries built from source and for installing packages on some Linux distros. If you run into
difficulties, you can seek help on the [Oolite Bulletin Board](https://bb.oolite.space/).

API documentation is available [here](https://oolite.readthedocs.io/en/latest/api/html/).

### Git

The Oolite source is available from GitHub. The first step is to install git if you don't already
have it installed as it is required to obtain and build Oolite. With Git installed, check out the
Oolite repository:

```bash
git clone --filter=blob:none https://github.com/OoliteProject/oolite.git
cd oolite
```

### Windows

After installing git and checking out the Oolite repository, double click `Run Me`
in ShellScripts/Windows or run in a command prompt:

```cmd
ShellScripts\Windows\setup.cmd
```

This will install MSYS2 which provides various MinGW environments. You will need to enter the
install location for MSYS2 and whether you want the Clang build (recommended) or GCC build.

The Clang build uses the UCRT64 environment, while the GCC build uses the MINGW64 environment.

### Linux

After installing git and checking out the Oolite repository, run the following 
to install required packages (you can replace sudo with other methods that escalate privileges if 
you prefer):

```bash
sudo ShellScripts/Linux/install_packages_root.sh
```

Next run the following to build the GNUstep libraries needed by Oolite:

```bash
ShellScripts/Linux/build_gnustep.sh
```

Run the following to install the Mozilla JavaScript library needed by Oolite:

```bash
ShellScripts/Linux/install_mozilla_js.sh
```

By default, the above two commands will install to $HOME/.local, but you can supply an argument system or build
to specify /usr/local or the project build folder respectively. When installing to /usr/local, sudo is used by 
default, but you can supply a further argument to specify an alternative like doas.

### Building Oolite

Next run this in your Bash or MSYS2 prompt to build Oolite:

```bash
ShellScripts/common/build_oolite.sh release
```

The completed build (executable and games files) can be found in the oolite.app directory.

Subsequently, you can clean and build as follows:

```bash
make -f Makefile clean
make -f Makefile release -j$(nproc)
```

You can run a test from your Bash or MSYS2 prompt as follows:

```bash
make -f Makefile test
```

On Linux, you will need to run this beforehand: `source /usr/local/share/GNUstep/Makefiles/GNUstep.sh`

On Windows, this is set up be default in the shell: `source $MINGW_PREFIX/share/GNUstep/Makefiles/GNUstep.sh`

Other targets are release-deployment for a production release and release-snapshot for a debug release.

### Other Linux Make Targets

This target builds an AppImage for testing which can be found in build:

```bash
make -f Makefile pkg-appimage -j$(nproc)
```

The target pkg-appimage-deployment is the production release, while pkg-appimage-snapshot is for debugging.

This target builds a Flatpak which can be found in build:

```bash
make -f Makefile pkg-flatpak -j$(nproc)
```

### Mac OS

Intel-based Macs can run old builds of Oolite, but current Macs are unsupported. It is hoped that they can be supported
in future.

### Objective-C

Oolite is written in Objective-C although there is also some C and C++ code in the codebase. It was
originally coded on Mac, but was ported to Windows and Linux by way of the GNUstep runtime which
provides a similar API to what is available on Mac. Objective-C is supported by modern IDEs like
CLion and Visual Studio Code. The language can be easily picked up by programmers familiar with C
or C++ with which it is interoperable.

### Troubleshooting

- If you get compiler errors, you can try compiling with:

```bash
make -f Makefile release OBJCFLAGS="-fobjc-exceptions -Wno-format-security" -j$(nproc)
```

## Contents of repository

Oolite for all platforms can be built from this repository. Here is a quick
guide to the source tree.

- **DebugOXP**:  [Debug.oxp](http://wiki.alioth.net/index.php/Debug_OXP), the expansion pack that enables console
  support in debug and test release builds
- **Doc**:  Documentation (including user guides)
- **ShellScripts**:  Scripts to build from source on Windows and Linux
- **installers**:  Files used to create various installers
- **Resources**:  Game assets and resource files for Mac and GNUstep application bundles
- **Schemata**:  Plist schema files for the [OXP Verifier](http://wiki.alioth.net/index.php/OXP_howto#OXP_Verifier)
- **src**:  Objective-C and C sources, incuding header files
    - **BSDCompat**:  Support for BSDisms that gnu libc doesn't have (strl*)
    - **Cocoa**:  Files that are only compiled on Mac OS X
    - **Core**:  Files that are compiled on all platforms
    - **SDL**:  Files that are only compiled for platforms that use SDL
- **tests**:  A mixed bag of test cases for manual testing and ad-hoc code tests.
- **tools**:  Various historical tools for preparing files.
