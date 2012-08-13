/*

OOFullScreenController.h

Abstract base class for full screen mode controllers. Concrete implementations
exist for different target platforms.


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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


#if OOLITE_MAC_OS_X && !OOLITE_64_BIT
#define OOLITE_MAC_LEGACY_FULLSCREEN	1
#endif


@interface OOFullScreenController: NSObject

#if OOLITE_PROPERTY_SYNTAX

@property (nonatomic, getter=inFullScreenMode) BOOL fullScreenMode;
@property (nonatomic, readonly) NSArray *displayModes;
@property (nonatomic, readonly) OOUInteger indexOfCurrentDisplayMode;

#else

- (BOOL) inFullScreenMode;
- (void) setFullScreenMode:(BOOL)value;

- (NSArray *) displayModes;
- (OOUInteger) indexOfCurrentDisplayMode;

#endif

- (BOOL) setDisplayWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh;
- (NSDictionary *) findDisplayModeForWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)d_refresh;

@end
