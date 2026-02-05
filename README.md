[![build-all](https://github.com/OoliteProject/oolite/actions/workflows/build-all.yaml/badge.svg)](https://github.com/OoliteProject/oolite/actions/workflows/build-all.yaml)

[![GitHub release](https://img.shields.io/github/release/OoliteProject/Oolite.svg)](https://github.com/OoliteProject/Oolite/releases/latest)

| Windows                                                                                                                                                                   | Linux                                                                                                                                                                                   | OSX                                                                                                                                                                                   |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/OoliteInstall-1.92-win.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest) | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/Oolite_1.92-x86_64.AppImage.svg)](https://github.com/OoliteProject/oolite/releases/latest)      |                 |
 [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/OoliteInstall-1.92-win-test.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest) | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/Oolite_test_1.92-x86_64.AppImage.svg)](https://github.com/OoliteProject/oolite/releases/latest)         | OSX is not supported for v1.92 |
|[![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/Oolite-1.92-Deployment-to-Test-Release.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest)                                                                                                                                                                           | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/space.oolite.Oolite_1.92.flatpak.svg)](https://github.com/OoliteProject/oolite/releases/latest) |                                                                                                                                                                                       |
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
Oolite repository and its submodules:

```bash
git clone --filter=blob:none --recurse-submodules https://github.com/OoliteProject/oolite.git
cd oolite
```

### Windows

After installing git and checking out the Oolite repository and its submodules, double click `Run Me`
in ShellScripts/Windows or run in a command prompt:

```cmd
ShellScripts\Windows\setup.cmd
```

This will install MSYS2 which provides various MinGW environments. You will need to enter the
install location for MSYS2 and whether you want the Clang build (recommended) or GCC build.

The Clang build uses the UCRT64 environment, while the GCC build uses the MINGW64 environment.

### Linux

After installing git and checking out the Oolite repository and its submodules, run the following
to check out the dependencies of Oolite that need to be built from source:

```bash
ShellScripts/Linux/checkout_deps.sh
```

Next run the following to install required packages and build dependencies (you can replace sudo
with other methods that escalate privileges if you prefer):

```bash
sudo ShellScripts/Linux/install_deps_root.sh
```

### Building Oolite

Next run this in your bash or MSYS2 prompt to build Oolite:

```bash
ShellScripts/common/build_oolite.sh release
```

The completed build (executable and games files) can be found in the Oolite.app directory.

Subsequently, you can clean and build as follows:

```bash
make -f Makefile clean
make -f Makefile release -j$(nproc)
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

- If you get errors like `fatal error: jsapi.h: No such file or directory`, there was probably an issue with checking
  out the submodules.

- If you can't see any textures, try deleting the following files, and compile again although these are already excluded
  from modern builds.

```bash
rm deps/Linux-deps/include/png.h
rm deps/Linux-deps/include/pngconf.h
```

- If you get compiler errors, you can try compiling with:

```bash
make -f Makefile release OBJCFLAGS="-fobjc-exceptions -Wno-format-security" -j$(nproc)
```

## Contents of repository

Oolite for all platforms can be built from this repository. Here is a quick
guide to the source tree.

- **debian**:  Files to enable automatic setup under Linux using dpkg (Debian package manager) tools
- **DebugOXP**:  [Debug.oxp](http://wiki.alioth.net/index.php/Debug_OXP), the expansion pack that enables console
  support in debug and test release builds
- **deps**
    - **Cocoa-deps**:  Dependencies for Mac OS X
    - **Cross-platform-deps**:  Dependencies for platforms other than Mac OS X
    - **Linux-deps**:  Dependencies for Linux on x86 and x86_64 processors
    - **URLs**:  URLs used for binary dependencies on Mac OS X
    - **Windows-deps**:  Dependencies for Windows on x86 and x86_64 processors
- **Doc**:  Documentation (including user guides)
- **ShellScripts**:  Scripts to build from source on Windows and Linux
- **installers**:  Files used to create various installers
- **Mac-specific**:  Additional projects used only on Mac OS X
    - **DataFormatters**:  Debugger configurations for Xcode
    - **DebugBundle**:  Implements
      the [Debug menu and in-app console](http://wiki.alioth.net/index.php/Debug_OXP#Mac_OS_X-specific_features)
    - **OCUnitTest**:  A small number of unit tests
    - **Oolite-docktile:**  An embedded plug-in which implements the Oolite dock menu when Oolite is not running
    - **Oolite-importer**:  A Spotlight importer to make saved games and OXPs searchable
- **Oolite.xcodeproj**:  The OS X Xcode project to build Oolite
- **Resources**:  Game assets and resource files for Mac and GNUstep application bundles
- **Schemata**:  Plist schema files for the [OXP Verifier](http://wiki.alioth.net/index.php/OXP_howto#OXP_Verifier)
- **src**:  Objective-C and C sources, incuding header files
    - **BSDCompat**:  Support for BSDisms that gnu libc doesn't have (strl*)
    - **Cocoa**:  Files that are only compiled on Mac OS X
    - **Core**:  Files that are compiled on all platforms
    - **SDL**:  Files that are only compiled for platforms that use SDL
- **tests**:  A mixed bag of test cases for manual testing and ad-hoc code tests.
- **tools**:  Various tools for preparing files, builds, releases etc.
