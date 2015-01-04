Grand Unified Source Tree for Oolite
====================================

Oolite for all platforms can be built from this repository. Here is a quick
guide to the source tree.

1. Guidelines
-------------
Nothing except makefiles/xcode projects, directories, and this readme file
should appear in the top level directory.
The deps directory should contain dependencies that are useful to carry along
to build binary packages. The dependencies directory should be named:
   Opsys-cpuarch-deps
Opsys should be exactly as reported by 'uname' with no flags (case
sensitive!). The cpuarch should be the cpu architecture reported by 'uname -p'
(except i686, i586 etc should be translated to x86). This allows build scripts
to automatically package up the right dependency tree in tarball installers.
Cocoa-deps is an exception, because a different build system is used under
Mac OS X.

2. Contents
-----------
autopackage       Directory for the apspec file for the Linux autopackage
Asset Source      Files used to create the various PNG and sound files
debian            Files to enable automatic setup under Linux using dpkg
                  (Debian package manager) tools
deps              Dependencies for all plaforms:
   Cocoa-deps     Dependencies for Mac OS X (macppc and macintel platforms)
   Linux-deps     Dependencies for Linux on x86 and x86_64 processors
   scripts        Scripts and script fragments for tarball/autopackage
Doc               Documentation (including user guides)
FreeDesktop       Files for GNOME/KDE desktop launchers
installers        Files used to create various installers
Oolite-importer   (OS X) The oolite Spotlight metadata importer
Oolite.xcodeproj  The OS X Xcode project to build Oolite
OSX-SDL           Project files for the SDL version of Oolite on OS X
                  (*very* seldom used, more of a curiosity)
Resources         Files that live in the application bundle's
                  Contents/Resources directory (AI, config, textures etc).
src               Objective-C and C sources, incuding header files:
   Core           Files that are compiled on all platforms
   SDL            Files that are only compiled for platforms that use SDL
   Cocoa          Files that are only compiled on Mac OS X without SDL
   BSDCompat      Support for BSDisms that gnu libc doesn't have (strl*)
tools             Various tools for preparing files, builds, releases etc.

3. Building
-----------
On Mac OS X, you will need the latest version of Xcode and OS X 10.4 (Tiger).
You will also need all the relevant frameworks (they come with Xcode). If you
don't yet have Xcode you can get it from the Apple Developer Connection (see
the Apple web site) - ADC membership to get Xcode is free, and it's a rather
nice IDE.
Then double click on the Xcode project in the Finder, and hit Build.

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
base SDL development kit. Then just type 'make', or, if you're using GNU make,
'make -f Makefile'.

If you want to make the Linux autopackage, after getting the Autopackage
development kit, just type 'makeinstaller', and a package file will be
deposited in the top level.

4. Running
----------
On OS X, you can run from Xcode by clicking on the appropriate icon
(or choosing 'Build and Run').
On Linux/BSD/Unix, in a terminal, type 'openapp oolite'

5. Git
------

The Oolite source is available from github.  Use

 git clone https://github.com/OoliteProject/oolite

to retrieve.  Then

 git submodule update --init

to fetch the various submodules.

If you've cloned the source from a forked repository instead, this may
not work - due to relative directory paths in .gitmodules, git tries
to download the submodules from the fork instead of the original oolite
repository.  A workaround is to copy the file .absolute_gitmodules
onto .gitmodules, then perform the submodules init, then replace
.gitmodules with the relative path version.  eg, on Unix:

$ cp .absolute_gitmodules .gitmodules
$ git submodule update --init
$ git checkout -- .gitmodules

You should now have access to the submodules, without git complaining
that .gitmodules has changed or including .gitmodules in pull requests.

