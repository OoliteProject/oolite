[![Build Status (Mac)](https://api.travis-ci.org/OoliteProject/oolite.svg)](https://travis-ci.org/OoliteProject/oolite)

[![GitHub release](https://img.shields.io/github/release/OoliteProject/Oolite.svg)](https://github.com/OoliteProject/Oolite/releases/latest)
     

| Windows             | Linux               | OSX            |
|---------------------|---------------------|----------------|
| [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/Oolite-1.86_x64.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest) | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/oolite-1.86.linux-x86_64.tgz.svg)](https://github.com/OoliteProject/oolite/releases/latest) | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/oolite-1.86.zip.svg)](https://github.com/OoliteProject/oolite/releases/latest) |
[![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/Oolite-1.86_x86.exe.svg)](https://github.com/OoliteProject/oolite/releases/latest)| [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/oolite-1.86.linux-x86.tgz.svg)](https://github.com/OoliteProject/oolite/releases/latest) | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/Oolite-1.86-Mac-TestRelease.zip.svg)](https://github.com/OoliteProject/oolite/releases/latest) |
| | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/oolite-1.86-test.linux-x86_64.tgz.svg)](https://github.com/OoliteProject/oolite/releases/latest) | |
| | [![Github release](https://img.shields.io/github/downloads/OoliteProject/Oolite/latest/oolite-1.86-test.linux-x86.tgz.svg)](https://github.com/OoliteProject/oolite/releases/latest) | |


Oolite for all platforms can be built from this repository. Here is a quick
guide to the source tree.
 
For end-user documentation, see [oolite.org](http://www.oolite.org/) and
[Elite Wiki](http://wiki.alioth.net/index.php/Oolite_Main_Page).

## Contents
- **debian**:  Files to enable automatic setup under Linux using dpkg (Debian package manager) tools
- **DebugOXP**:  [Debug.oxp](http://wiki.alioth.net/index.php/Debug_OXP), the expansion pack that enables console support in debug and test release builds
- **deps**
   - **Cocoa-deps**:  Dependencies for Mac OS X
   - **Cross-platform-deps**:  Dependencies for platforms other than Mac OS X
   - **Linux-deps**:  Dependencies for Linux on x86 and x86_64 processors
   - **URLs**:  URLs used for binary dependecies on Mac OS X
   - **Windows-deps**:  Dependencies for Windows on x86 and x86_64 processors
- **Doc**:  Documentation (including user guides)
- **installers**:  Files used to create various installers
- **Mac-specific**:  Additional projects used only on Mac OS X
   - **DataFormatters**:  Debugger configurations for Xcode
   - **DebugBundle**:  Implements the [Debug menu and in-app console](http://wiki.alioth.net/index.php/Debug_OXP#Mac_OS_X-specific_features)
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

## Building
On Mac OS X, you will need the latest version of Xcode from the App Store.
Then double click on the Xcode project in the Finder, select one of the Oolite
targets from the Scheme pop-up, and hit Build and Run (the play button in the
toolbar).

For Windows, see the Oolite wiki:
http://wiki.alioth.net/index.php/Running_Oolite-Windows

On Linux, if you have the Debian package tools (installed by default with
Debian and Ubuntu), use dpkg-buildpackage.

On Linux, BSD and other Unix platforms without dpkg tools, you will need to
get GNUstep and SDL development libraries in addition to what is usually
installed by default if you choose to install the development
headers/libraries etc. when initially installing the OS. For most Linux
distros, GNUstep and SDL development libraries come prepackaged - just
apt-get/yum install the relevant files. You may also need to install Mozilla
Spidermonkey (libmozjs). On others you may need to build them from source. In
particular, you need the SDL_Mixer library, which doesn't always come with the
base SDL development kit. Then just type `make`, or, if you're using GNU make,
`make -f Makefile`. On some systems, such as Gentoo, you may need to run
`make -f Makefile OBJCFLAGS=-fobjc-exceptions`.

## Running
On OS X, you can run from Xcode by clicking on the appropriate icon
(or choosing 'Run' from the 'Product' menu).
On Linux/BSD/Unix, in a terminal, type `openapp oolite`

## Git
The Oolite source is available from github.
Use `git clone https://github.com/OoliteProject/oolite`
to retrieve. Then `git submodule update --init`
to fetch the various submodules.

If you've cloned the source from a forked repository instead, this may
not work - due to relative directory paths in .gitmodules, git tries
to download the submodules from the fork instead of the original oolite
repository.  A workaround is to copy the file .absolute_gitmodules
onto .gitmodules, then perform the submodules init, then replace
.gitmodules with the relative path version.  eg, on Unix:

```
$ cp .absolute_gitmodules .gitmodules
$ git submodule update --init
$ git checkout -- .gitmodules
```

You should now have access to the submodules, without git complaining
that .gitmodules has changed or including .gitmodules in pull requests.
