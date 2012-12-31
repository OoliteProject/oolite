/*

OOMacSystemStandardFullScreenController.h

Full-screen controller used in 64-bit Mac builds under Mac OS X 10.7 (on systems
with a single display, as determined at application startup) and always under
Mac OS X 10.8 or later.


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

#import "OOFullScreenController.h"

/*
	OOMacSystemStandardFullScreenController requires the Mac OS X 10.7 SDK.
*/
#if OOLITE_MAC_OS_X
#if OOLITE_64_BIT && defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
#define OO_MAC_SUPPORT_SYSTEM_STANDARD_FULL_SCREEN	1
#endif
#endif

#ifndef OO_MAC_SUPPORT_SYSTEM_STANDARD_FULL_SCREEN
#define OO_MAC_SUPPORT_SYSTEM_STANDARD_FULL_SCREEN	0
#endif


#if OO_MAC_SUPPORT_SYSTEM_STANDARD_FULL_SCREEN


@interface OOMacSystemStandardFullScreenController: OOFullScreenController

+ (BOOL) shouldUseSystemStandardFullScreenController;

@end

#endif
