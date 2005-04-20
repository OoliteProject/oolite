/* GameController
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

¥	to copy, distribute, display, and perform the work
¥	to make derivative works

Under the following conditions:

¥	Attribution. You must give the original author credit.

¥	Noncommercial. You may not use this work for commercial purposes.

¥	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/


#ifdef GNUSTEP
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <AppKit/NSOpenGL.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define MODE_WINDOWED		100
#define MODE_FULL_SCREEN	200

#define DISPLAY_MIN_COLOURS	32
#define DISPLAY_MIN_WIDTH  800	
#define DISPLAY_MIN_HEIGHT	600
#define DISPLAY_MAX_WIDTH	2400
#define DISPLAY_MAX_HEIGHT	1800

#define MINIMUM_GAME_TICK   0.25
// * reduced from 0.5s for tgape * //


@class Universe, MyOpenGLView, TextureStore;

// dajt: is defined as BOOL in main.m
extern int debug;

@interface GameController : NSObject
{
    IBOutlet NSTextField	*splashProgressTextField;
    IBOutlet NSView			*splashView;
    IBOutlet MyOpenGLView   *gameView;
    IBOutlet NSWindow		*gameWindow;

    Universe	*universe;
    NSDate		*old_time;
    double		delta_t;
    
	int		my_mouse_x, my_mouse_y;

#ifdef GNUSTEP
   // TODO: What should go here?
   // dajt: CGMouseDelta is just an integer - we can use a Cocoa compat header file to define it
#else   
	CGMouseDelta mouse_dx, mouse_dy;
#endif
   
	NSString	*playerFileToLoad;
	
    NSTimer		*timer;
	
	/*  GDC example code */
	
    NSMutableArray         *displayModes;

    unsigned int  width, height;
    unsigned int  colorBits;
    unsigned int  depthBits;
    unsigned int  refresh;
    BOOL          fullscreen;
    NSDictionary *originalDisplayMode;
    NSDictionary *fullscreenDisplayMode;
	
    NSOpenGLContext *fullScreenContext;
	
	BOOL		stayInFullScreenMode;

	/*  end of GDC */
	
	TextureStore	*oldTextureStore;
	
	SEL			pauseSelector;
	NSObject*	pauseTarget;
	
	BOOL		game_is_paused;
	
}

- (BOOL) game_is_paused;
- (void) pause_game;
- (void) unpause_game;

- (IBAction) goFullscreen:(id) sender;
- (void) exitFullScreenMode;
- (BOOL) inFullScreenMode;

- (void) pauseFullScreenModeToPerform:(SEL) selector onTarget:(id) target;
- (void) exitApp;

- (BOOL) setDisplayWidth:(unsigned int) d_width Height:(unsigned int)d_height Refresh:(unsigned int) d_refresh;
- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh;
- (NSArray *) displayModes;
- (int) indexOfCurrentDisplayMode;

- (void) getDisplayModes;

- (void) updateTiming;

- (NSString *) playerFileToLoad;
- (void) setPlayerFileToLoad:(NSString *)filename;

#ifdef GNUSTEP
// dajt: need this to create the window and view
- (void) applicationWillFinishLaunching: (NSNotification *) notification;
#endif

// dajt: added to make things a bit neater
- (void) applicationDidFinishLaunching: (NSNotification*) notification;

- (void) loadPlayerIfRequired;

- (void) beginSplashScreen;
- (void) logProgress:(NSString*) message;
- (void) endSplashScreen;

- (void) doStuff: (id)sender;

- (void) startAnimationTimer;
- (void) stopAnimationTimer;

- (MyOpenGLView *) gameView;
- (void) setGameView:(NSView *)view;
- (Universe *) universe;
- (void) setUniverse:(Universe *) theUniverse;

- (void)windowDidResize:(NSNotification *)aNotification;

- (void) playiTunesPlaylist:(NSString *)playlist_name;
- (void) pauseiTunes;

@end


