/*

OOSound.h

Dispatch header to select the appropriate implementation of OOSound.

Add new OS imports here. The -DOS_NAME flag in the GNUmakefile
will select which one gets compiled.


== Overview of Oolite sound architecture ==
There are four public sound classes:
* OOSound: represents a sound, i.e. some data that can be played.
* OOMusic: subclass of OOSound with support for looping, and the special
           constraint that only one OOMusic may play at a time.
* OOSoundSource: a thing that can play a sound. Each sound played is
           conceptually played through a sound source, although this can be
		   implicit using OOSound's -play method.
* OOSoundReferencePoint: a point in space relative to which a sound source is
           positioned. Since positional sound is not implemented, this serves
		   no practical purpose.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOCocoa.h"

#define OOLITE_OPENAL 1

#if OOLITE_OPENAL
	#import "OOALSound.h"
	#import "OOALMusic.h"
	#import "OOBasicSoundReferencePoint.h"
#else
#if OOLITE_SDL
	#import "OOSDLSound.h"
	#import "SDLMusic.h"
	#import "OOBasicSoundReferencePoint.h"
#else
	#import "OOCASound.h"
	#import "OOCAMusic.h"
	#import "OOCASoundReferencePoint.h"
#endif
#endif

#import "OOSoundSource.h"
