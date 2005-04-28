Oolite-Linux
============

This repository contains the files required to build Oolite for Linux,
GNUstep and OpenGL. It is possibly easily portable to FreeBSD. It
won't yet work on Windows due to the lack of OpenGL support in the
Windows implementation of GNUstep. However, if this is fixed, it
will probably need very little effort to port. If you are considering
porting this to a platform other than Linux, please read PORTING.TXT
for the troubles that I've encountered - it may save you time.

0. Pre-requisites

- Objective-C. On Fedora Core, 'up2date -i gcc-objc' installs.

- GNUstep Development libraries. I advise you build GNUstep from source
since some prepackaged versions don't have a new enough NSOpenGLView.
It builds easily from source so don't panic.

Tip: Get the GNUstep Startup Version. Everything you need in one
package. Make sure you do:

PATH=$PATH:.

before running make when you build GNUstep Startup, because it depends
on running a shell script in the current directory.

I'm not sure what the minimum hardware is, however decent OpenGL
support is a must. I've only been able to personally test it on
two machines - a 2GHz P4 with a GeForce 4ti and an old Compaq
733MHz P3 with ATi Radeon Mobility. It ran fine on both machines.
I have heard reports of bad things happening with ATi graphics
cards, but only off one person (textures didn't display), and another
person with a Matrox graphics card had problems with the text.

Building
========
Type:
make

If this fails and you're certain you have GNUstep's development
stuff installed, make sure you have this in your .bashrc or
equivalent:

. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh

GNUstep tells you this if you build it but you won't have been told
if you've installed your distro's GNUstep binaries :-)

Running
=======
Type:
openapp oolite

or
openapp oolite.debug
if you built with 'make debug=yes'.

Troubleshooting
===============
I suggest you go through some of the GNUstep tutorials and make sure these
build and run successfully to ensure your build and runtime environment
is sane. Also, there's a little (and rather nasty) environment tester
on ftp.alioth.net/oolite/gl-gnustep.tar.gz. If you're having problems
I recommend you get this running first; it's relatively simple and should
expose any problems your installation has without possible Oolite problems
clouding your view.

Is it borked for you?
=====================
If you find it's borked, please post a message on the oolite-linux
forum (see http://aegidean.org/bb). Please provide a backtrace if you
have one, screenshots, and describe weirdness with sound. Also provide
log messages from the console. Better still, if you have a fix, send
us the patch!

Modifications from Stock OSX Oolite
===================================

Makefiles:
GNUmakefile and GNUmakefile.postamble.
The former controls compilation and linking, and the latter copies
data files (PNG images, plists, dat files) into oolite.app/Contents/Resources.
PlayerEntity_Additions.m, PlayerEntity_contracts.m, ShipEntity_AI.m -
   These just #include "PlayerEntity (contracts).m" etc. because
   spaces and brackets really suck in the Makefile and shell.
#ifdefs -
   All over the code you'll see #ifdef GNUSTEP ... #else .... #endif
   If you grep for these, you can see where work has to be done.
   I've usually put a TODO: comment line in these (many of them are not
   filled in). I've not #ifdef'd out any methods - I've left at least
   a stub if there's nothing to put in there (for example, speech).

Addition of Comparison.m/h from ObjectiveLib 
(see http://objectivelib.sourceforge.net). ObjectiveLib is an LGPL'd 
set of libraries to add functionality to GNUstep. Comparison.h/m 
implements a category of NSObject that adds isEqualTo:, isGreaterThan:,
isGreaterThanOrEqualTo:, isLessThan:, isLessThanOrEqualTo:, isNotEqualTo:
methods. It looked like a relatively simple category, so rather
than creating a dependency on the whole of ObjectiveLib, I decided
to just add these two files.

Addition of OOAlsaSound - The GNUstep sound daemon crashes with oolite,
so it was replaced with code that plays the sound on a separate thread
within the game. I have found ALSA to be poorly documented - there
are probably still problems with this code.
If you can do a better job *please do* and be sure to send me diffs.
I recommend you always use the latest svn head revision if you are going
to tinker with this. I won't feel in the least offended if you tell
me that my ALSA code is crap.

Major tasks left
================
- OpenGL....APPLE functions (optimizations) need a suitable replacement.
- Full screen modes: not implemented at all at present, Carbon
  API calls need replacing with the equivalent GNUstep or X Window System
  xlib function calls.
- Music. I suspect we can use Xine for music; xine provides a library
  that I think is cross-platform.
- Speech. This is a more 'who cares?' requirement. I don't know of
  a *nix open source speech synth.
- Keyboard shortcuts (equivalent of Cmd-Q et al.)

Notes for the terminally insane
===============================
See PORTING.TXT - it's useful to read this if you're tinkering on Linux
and not porting. It may save you grief.
