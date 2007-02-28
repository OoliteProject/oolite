/*

GameController.h
Created by Giles Williams on 2004-04-03.

Main application controller class.

For Oolite
Copyright (C) 2004  Giles C Williams

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

#define MODE_WINDOWED		100
#define MODE_FULL_SCREEN	200

#define DISPLAY_MIN_COLOURS	32
#ifndef GNUSTEP
#define DISPLAY_MIN_WIDTH	640
#define DISPLAY_MIN_HEIGHT	480
#else
// *** Is there a reason for this difference? -- Jens
#define DISPLAY_MIN_WIDTH	800
#define DISPLAY_MIN_HEIGHT	600
#endif
#define DISPLAY_MAX_WIDTH	2400
#define DISPLAY_MAX_HEIGHT	1800

#define MINIMUM_GAME_TICK   0.25
// * reduced from 0.5s for tgape * //


@class Universe, MyOpenGLView, TextureStore;

extern int debug;

@interface GameController : NSObject
{
#ifndef GNUSTEP
    IBOutlet NSTextField	*splashProgressTextField;
    IBOutlet NSView			*splashView;
    IBOutlet NSWindow		*gameWindow;
#else
	NSRect					fsGeometry;
	MyOpenGLView			*switchView;
#endif
	IBOutlet MyOpenGLView	*gameView;

	Universe				*universe;

	NSTimeInterval			last_timeInterval;
	double					delta_t;

	int						my_mouse_x, my_mouse_y;

	NSString				*playerFileDirectory;
	NSString				*playerFileToLoad;
	NSMutableArray			*expansionPathsToInclude;

	NSTimer					*timer;

	/*  GDC example code */

	NSMutableArray			*displayModes;

	unsigned int			width, height;
	unsigned int			refresh;
	BOOL					fullscreen;
	NSDictionary			*originalDisplayMode;
	NSDictionary			*fullscreenDisplayMode;

#ifndef GNUSTEP
	NSOpenGLContext			*fullScreenContext;
#endif

	BOOL					stayInFullScreenMode;

	/*  end of GDC */

//	TextureStore			*oldTextureStore;

	SEL						pauseSelector;
	NSObject				*pauseTarget;

	BOOL					game_is_paused;
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification;
- (BOOL) game_is_paused;
- (void) pause_game;
- (void) unpause_game;

#ifndef GNUSTEP
- (IBAction) goFullscreen:(id) sender;
#else
- (void) setFullScreenMode:(BOOL)fsm;
#endif
- (void) exitFullScreenMode;
- (BOOL) inFullScreenMode;

- (void) pauseFullScreenModeToPerform:(SEL) selector onTarget:(id) target;
- (void) exitApp;

- (BOOL) setDisplayWidth:(unsigned int) d_width Height:(unsigned int)d_height Refresh:(unsigned int) d_refresh;
- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh;
- (NSArray *) displayModes;
- (int) indexOfCurrentDisplayMode;

- (void) getDisplayModes;

- (NSString *) playerFileToLoad;
- (void) setPlayerFileToLoad:(NSString *)filename;

- (NSString *) playerFileDirectory;
- (void) setPlayerFileDirectory:(NSString *)filename;

- (void) loadPlayerIfRequired;

- (void) beginSplashScreen;
- (void) logProgress:(NSString*) message;
- (void) endSplashScreen;

- (void) doStuff: (id)sender;

- (void) startAnimationTimer;
- (void) stopAnimationTimer;

- (MyOpenGLView *) gameView;
- (void) setGameView:(MyOpenGLView *)view;
- (Universe *) universe;
- (void) setUniverse:(Universe *) theUniverse;

- (void)windowDidResize:(NSNotification *)aNotification;

- (void) playiTunesPlaylist:(NSString *)playlist_name;
- (void) pauseiTunes;

@end

