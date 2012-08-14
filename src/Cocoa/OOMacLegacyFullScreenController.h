/*

OOMacLegacyFullScreenController.h

Full-screen controller used in 32-bit Mac builds.


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

#import "OOFullScreenController.h"

#if OOLITE_MAC_OS_X && !OOLITE_64_BIT

#define OO_MAC_USE_LEGACY_FULL_SCREEN 1


@protocol OOMacLegacyFullScreenControllerDelegate;


@interface OOMacLegacyFullScreenController: OOFullScreenController
{
@private
	id <OOMacLegacyFullScreenControllerDelegate> _delegate;
	
	NSMutableArray			*_displayModes;
	
	OOUInteger				_width, _height;
	OOUInteger				_refresh;
	NSDictionary			*_originalDisplayMode;
	NSDictionary			*_fullScreenDisplayMode;
	
	NSOpenGLContext			*_fullScreenContext;
	
	OOUInteger				_state;
	
	BOOL					_stayInFullScreenMode;
	BOOL					_callSuspendAction;
	BOOL					_switchRez;
	BOOL					_switchRezDeferred;
}

@property (nonatomic, assign) id <OOMacLegacyFullScreenControllerDelegate> delegate;

// The legacy full screen controller takes over event dispatch. Delegate's -handleFullScreenFrameTick is called each frame.
- (void) runFullScreenModalEventLoop;

// Suspend full screen mode at the end of the event loop and call delegate's -handleFullScreenSuspendedAction.
- (void) suspendFullScreen;

@end


@protocol OOMacLegacyFullScreenControllerDelegate

// Note: unlike standard delegate pattern, these are required.
- (void) handleFullScreenSuspendedAction;
- (void) handleFullScreenFrameTick;

@end

#endif
