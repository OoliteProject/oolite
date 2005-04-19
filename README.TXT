Oolite-Linux
============

This repository contains the files required to build Oolite for Linux,
GNUstep and OpenGL. It is possibly easily portable to FreeBSD. It
won't yet work on Windows due to the lack of OpenGL support in the
Windows implementation of GNUstep. However, if this is fixed, it
will probably need very little effort to port.

0. Pre-requisites

- Objective-C. On Fedora Core, 'up2date -i gcc-objc' installs.

- GNUstep Development libraries. I advise you build GNUstep from source
since some prepackaged versions don't have a new enough NSOpenGLView.
It builds easily from source so don't panic.

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

Major tasks left
================

- Crashing: What's here crashes with depressing frequency. I tend
  to get floating point exceptions mostly.
- Runtime error when pressing F2 when docked.
- Load New Commander file dialogue.
- Sound: The GNUstep sound server appears to have some inadequacies
  at present - using some other library may be necessary.
- OpenGL....APPLE functions (optimizations) need a suitable replacement.
- Full screen modes: not implemented at all at present, Carbon
  API calls need replacing with the equivalent GNUstep or X Window System
  xlib function calls.
- Music. I suspect we can use Xine for music; xine provides a library
  that I think is cross-platform.
- Speech. This is a more 'who cares?' requirement. I don't know of
  a *nix open source speech synth.

Building
========
Type:
make.

Running
=======
Type:
openapp oolite

or
openapp oolite.debug
if you built with 'make debug=yes'.

Suggestions
===========
I suggest you go through some of the GNUstep tutorials and make sure these
build and run successfully to ensure your build and runtime environment
is sane. Also, there's a little (and rather nasty) environment tester
on ftp.alioth.net/oolite/gl-gnustep.tar.gz. If you're having problems
I recommend you get this running first; it's relatively simple and should
expose any problems your installation has without possible Oolite problems
clouding your view.

