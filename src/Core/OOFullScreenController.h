/*

OOFullScreenController.h

Abstract base class for full screen mode controllers. Concrete implementations
exist for different target platforms.


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
#import "OOMouseInteractionMode.h"

@class MyOpenGLView;


#if OOLITE_MAC_OS_X
#define kOODisplayWidth			((NSString *)kCGDisplayWidth)
#define kOODisplayHeight		((NSString *)kCGDisplayHeight)
#define kOODisplayRefreshRate	((NSString *)kCGDisplayRefreshRate)
#define kOODisplayBitsPerPixel	((NSString *)kCGDisplayBitsPerPixel)
#define kOODisplayIOFlags		((NSString *)kCGDisplayIOFlags)
#else
#define kOODisplayWidth			(@"Width")
#define kOODisplayHeight		(@"Height")
#define kOODisplayRefreshRate	(@"RefreshRate")
#endif


#define DISPLAY_MIN_COLOURS		32
#define DISPLAY_MIN_WIDTH		640
#define DISPLAY_MIN_HEIGHT		480
#define DISPLAY_MAX_WIDTH		7680		// 8K gaming, yay!!
#define DISPLAY_MAX_HEIGHT		4320


@interface OOFullScreenController: NSObject
{
@private
	MyOpenGLView			*_gameView;
}

- (id) initWithGameView:(MyOpenGLView *)view;

#if OOLITE_PROPERTY_SYNTAX

@property (nonatomic, readonly) MyOpenGLView *gameView;
@property (nonatomic, getter=inFullScreenMode) BOOL fullScreenMode;
@property (nonatomic, readonly) NSArray *displayModes;
@property (nonatomic, readonly) NSDictionary *currentDisplayMode;
@property (nonatomic, readonly) NSUInteger indexOfCurrentDisplayMode;

#else

- (MyOpenGLView *) gameView;

- (BOOL) inFullScreenMode;
- (void) setFullScreenMode:(BOOL)value;

- (NSArray *) displayModes;
- (NSDictionary *) currentDisplayMode;
- (NSUInteger) indexOfCurrentDisplayMode;

#endif

- (BOOL) setDisplayWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(NSUInteger)refresh;
- (NSDictionary *) findDisplayModeForWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(NSUInteger)d_refresh;

- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode;

@end
