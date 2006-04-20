/*
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

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "MyOpenGLView.h"

#import "GameController.h"
#import "Universe.h"
#import "JoystickHandler.h" // TODO: Not here!
#import "SDL_syswm.h"
#import "OOSound.h"
#import "OOFileManager.h" // to find savedir

#ifdef WIN32
#import "TextureStore.h"
#endif

#include <ctype.h>

@implementation MyOpenGLView

+ (NSMutableDictionary *) getNativeSize
{
   SDL_SysWMinfo  dpyInfo;
   NSMutableDictionary *mode=[[NSMutableDictionary alloc] init];

   SDL_VERSION(&dpyInfo.version);
   if(SDL_GetWMInfo(&dpyInfo))
   {
#if defined(LINUX) && ! defined (WIN32)
      [mode setValue: [NSNumber numberWithInt: DisplayWidth(dpyInfo.info.x11.display, 0)]
              forKey: kCGDisplayWidth];
      [mode setValue: [NSNumber numberWithInt: DisplayHeight(dpyInfo.info.x11.display, 0)]
              forKey: kCGDisplayHeight];
      [mode setValue: [NSNumber numberWithInt: 0] forKey: kCGDisplayRefreshRate];
#else
      NSLog(@"Unknown architecture, defaulting to 1024x768");
      [mode setValue: [NSNumber numberWithInt: 1024] forKey: (NSString *)kCGDisplayWidth];
      [mode setValue: [NSNumber numberWithInt: 768] forKey: (NSString *)kCGDisplayHeight];
      [mode setValue: [NSNumber numberWithInt: 0] forKey: (NSString *)kCGDisplayRefreshRate];
#endif
   }
   else
   {
      NSLog(@"SDL_GetWMInfo failed, defaulting to 1024x768 for native size");
      [mode setValue: [NSNumber numberWithInt: 1024] forKey: (NSString *)kCGDisplayWidth];
      [mode setValue: [NSNumber numberWithInt: 768] forKey: (NSString *)kCGDisplayHeight];
      [mode setValue: [NSNumber numberWithInt: 0] forKey: (NSString *)kCGDisplayRefreshRate];
   }
   return mode;
}

- (id) init
{
	self = [super init];

   // TODO: This code up to and including stickHandler really ought
   // not to be in this class.
	NSLog(@"initialising SDL");
	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK) < 0)
	{
		NSLog(@"Unable to init SDL: %s\n", SDL_GetError());
		[self dealloc];
		return nil;
   }
	else if (Mix_OpenAudio(44100, AUDIO_S16LSB, 2, 2048) < 0)
	{
		NSLog(@"Mix_OpenAudio: %s\n", Mix_GetError());
		[self dealloc];
		return nil;
	}

	Mix_AllocateChannels(MAX_CHANNELS);
   stickHandler=[[JoystickHandler alloc] init];
   // end TODO

	SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 5);
	SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 5);
	SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 5);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

   NSLog(@"CREATING MODE LIST");
   [self populateFullScreenModelist];
	currentSize = 0;

   // Find what the full screen and windowed settings are.
   [self loadFullscreenSettings];
   [self loadWindowSize];

	int videoModeFlags = SDL_HWSURFACE | SDL_OPENGL;
	if (fullScreen)
   {
		videoModeFlags |= SDL_FULLSCREEN;
      NSSize fs=[self modeAsSize: currentSize];
	   surface = SDL_SetVideoMode(fs.width, fs.height, 32, videoModeFlags);
   }
   else
   {
      videoModeFlags |= SDL_RESIZABLE;
	   surface = SDL_SetVideoMode(currentWindowSize.width,
                                 currentWindowSize.height,
                                 32, videoModeFlags);
   }

	bounds.size.width = surface->w;
	bounds.size.height = surface->h;

	if (fullScreen)
	{
		if (SDL_ShowCursor(SDL_QUERY) == SDL_ENABLE)
			SDL_ShowCursor(SDL_DISABLE);
	}
	else
	{
		if (SDL_ShowCursor(SDL_QUERY) == SDL_DISABLE)
			SDL_ShowCursor(SDL_ENABLE);
	}

	virtualJoystickPosition = NSMakePoint(0.0,0.0);

	typedString = [[NSMutableString alloc] initWithString:@""];
	allowingStringInput = NO;
	isAlphabetKeyDown = NO;

	timeIntervalAtLastClick = [NSDate timeIntervalSinceReferenceDate];

	m_glContextInitialized = NO;

   return self;
}

- (void) dealloc
{
	if (typedString)
		[typedString release];

	if (surface != 0)
	{
		SDL_FreeSurface(surface);
		surface = 0;
	}

	SDL_Quit();

	[super dealloc];
}

- (void) setStringInput: (enum StringInput) value
{
	allowingStringInput = value;
}

- (void) allowStringInput: (BOOL) value
{
	if (value)
		allowingStringInput = gvStringInputAlpha;
	else
		allowingStringInput = gvStringInputNo;
}

-(enum StringInput) allowingStringInput
{
	return allowingStringInput;
}


- (NSString *) typedString
{
	return typedString;
}

- (void) resetTypedString
{
	[typedString setString:@""];
}

- (void) setTypedString:(NSString*) value
{
//	NSLog(@"DEBUG setTypedString:%@",value);
	[typedString setString:value];
}

- (NSRect) bounds
{
	return bounds;
}

- (NSSize) viewSize
{
	return viewSize;
}

- (GLfloat) display_z
{
	return display_z;
}


- (GameController *) gameController
{
	return gameController;
}

- (void) setGameController:(GameController *) controller
{
	gameController = controller;
}

- (BOOL) inFullScreenMode
{
	return fullScreen;
}

#ifdef GNUSTEP
- (void) setFullScreenMode:(BOOL)fsm
{
	fullScreen = fsm;

   // Save the settings for later.
   [[NSUserDefaults standardUserDefaults]
      setBool: fullScreen forKey:@"fullscreen"];
   [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) toggleScreenMode
{
   [self setFullScreenMode: !fullScreen];
   if(fullScreen)
      [self initialiseGLWithSize:[self modeAsSize: currentSize]];
   else
      [self initialiseGLWithSize: currentWindowSize];
}

- (void) setDisplayMode:(int)mode  fullScreen:(BOOL)fsm
{
   [self setFullScreenMode: fsm];
   currentSize=mode;
   if(fullScreen)
      [self initialiseGLWithSize: [self modeAsSize: mode]];
}

- (int) indexOfCurrentSize
{
   return currentSize;
}

- (void) setScreenSize: (int)sizeIndex
{
   currentSize=sizeIndex;
   if(fullScreen)
   	[self initialiseGLWithSize: [self modeAsSize: currentSize]];
}

- (NSMutableArray *)getScreenSizeArray
{
   return screenSizes;
}

- (NSSize) modeAsSize:(int)sizeIndex
{
   NSDictionary *mode=[screenSizes objectAtIndex: sizeIndex];
   return NSMakeSize([[mode objectForKey: (NSString *)kCGDisplayWidth] intValue],
                     [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue]);
}

#endif

- (void) display
{
	[self drawRect: NSMakeRect(0, 0, viewSize.width, viewSize.height)];
}

- (void) drawRect:(NSRect)rect
{
	if ((viewSize.width != surface->w)||(viewSize.height != surface->h)) // resized
	{
		m_glContextInitialized = NO;
		viewSize.width = surface->w;
		viewSize.height = surface->h;
		//NSLog(@"DEBUG resized to %.0f x %.0f", viewSize.width, viewSize.height);
	}

    if (m_glContextInitialized == NO)
	{
		NSLog(@"drawRect calling initialiseGLWithSize");
		[self initialiseGLWithSize:viewSize];
	}

	if (surface == 0)
		return;

	// do all the drawing!
	//
	if ([gameController universe])
		[[gameController universe] drawFromEntity:0];
	else
	{
		// not set up yet, draw a black screen
		NSLog(@"no universe, clearning surface");
		glClearColor( 0.0, 0.0, 0.0, 0.0);
		glClear( GL_COLOR_BUFFER_BIT);
	}

	SDL_GL_SwapBuffers();
}

- (void) initialiseGLWithSize:(NSSize) v_size
{
	int videoModeFlags;
	GLfloat	sun_ambient[] =	{0.0, 0.0, 0.0, 1.0};
	GLfloat	sun_diffuse[] =	{1.0, 1.0, 1.0, 1.0};
	GLfloat	sun_specular[] = 	{1.0, 1.0, 1.0, 1.0};
	GLfloat	sun_center_position[] = {4000000.0, 0.0, 0.0, 1.0};
	GLfloat	stars_ambient[] =	{0.25, 0.2, 0.25, 1.0};

	viewSize = v_size;
	if (viewSize.width/viewSize.height > 4.0/3.0)
		display_z = 480.0 * viewSize.width/viewSize.height;
	else
		display_z = 640.0;

//	NSLog(@">>>>> display_z = %.1f", display_z);

	float	ratio = 0.5;
	float   aspect = viewSize.height/viewSize.width;

	if (surface != 0)
		SDL_FreeSurface(surface);

	NSLog(@"Creating a new surface of %d x %d", (int)v_size.width, (int)v_size.height);
	videoModeFlags = SDL_HWSURFACE | SDL_OPENGL;
	if (fullScreen == YES)
		videoModeFlags |= SDL_FULLSCREEN;
   else
      videoModeFlags |= SDL_RESIZABLE;

	surface = SDL_SetVideoMode((int)v_size.width, (int)v_size.height, 32, videoModeFlags);

	if (fullScreen)
	{
		if (SDL_ShowCursor(SDL_QUERY) == SDL_ENABLE)
			SDL_ShowCursor(SDL_DISABLE);
	}
	else
	{
		if (SDL_ShowCursor(SDL_QUERY) == SDL_DISABLE)
			SDL_ShowCursor(SDL_ENABLE);
	}

	glShadeModel(GL_FLAT);
	glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    SDL_GL_SwapBuffers();

	glClearDepth(MAX_CLEAR_DEPTH);
	glViewport( 0, 0, viewSize.width, viewSize.height);

	squareX = 0.0;
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();	// reset matrix
	glFrustum( -ratio, ratio, -aspect*ratio, aspect*ratio, 1.0, MAX_CLEAR_DEPTH);	// set projection matrix

	glMatrixMode( GL_MODELVIEW);

	glEnable( GL_DEPTH_TEST);		// depth buffer
	glDepthFunc( GL_LESS);			// depth buffer

	glFrontFace( GL_CCW);			// face culling - front faces are AntiClockwise!
	glCullFace( GL_BACK);			// face culling
	glEnable( GL_CULL_FACE);		// face culling

	glEnable( GL_BLEND);								// alpha blending
	glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);	// alpha blending

	if ([gameController universe])
	{
      Universe *uni=[gameController universe];
		Entity* the_sun = [uni sun];
		Vector sun_pos = (the_sun)? the_sun->position : make_vector(0.0f,0.0f,0.0f);
		sun_center_position[0] = sun_pos.x;
		sun_center_position[1] = sun_pos.y;
		sun_center_position[2] = sun_pos.z;
		[uni setLighting];
	}
	else
	{
		glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
		glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);
		glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
		glLightfv(GL_LIGHT1, GL_POSITION, sun_center_position);
		glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient);
		//
		// light for demo ships display..
		GLfloat	white[] = { 1.0, 1.0, 1.0, 1.0};	// white light
		glLightfv(GL_LIGHT0, GL_AMBIENT, white);
		glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
		glLightfv(GL_LIGHT0, GL_SPECULAR, white);

   	glEnable(GL_LIGHT1);		// lighting
	   glEnable(GL_LIGHT0);		// lighting
   }
   glEnable(GL_LIGHTING);		// lighting

	// world's simplest OpenGL optimisations...
	glHint(GL_TRANSFORM_HINT_APPLE, GL_FASTEST);
	glDisable(GL_NORMALIZE);
	glDisable(GL_RESCALE_NORMAL);

#ifdef WIN32
	Universe *universe = [gameController universe];
	if (universe)
	{
		NSLog(@"WIN32: clearing texture store cache");
		[[universe textureStore] reloadTextures]; // clears the cached references
		PlayerEntity *player = (PlayerEntity *)[universe entityZero];
		if (player)
		{
			NSLog(@"WIN32: resetting text texture");
			[[player hud] setPlayer:player]; // resets the reference to the asciitext texture
		}

		NSLog(@"WIN32: resetting entity textures");
		int i;
		Entity **elist = universe->sortedEntities;
		for (i = 0; i < universe->n_entities; i++)
		{
			Entity *e = elist[i];
			[e reloadTextures];
		}
	}
#endif

	m_glContextInitialized = YES;
}

- (void) snapShot
{
	SDL_Surface* tmpSurface;
    int w = viewSize.width;
    int h = viewSize.height;

	if (w & 3)
		w = w + 4 - (w & 3);

//    long nPixels = w * h + 1;

   // save in the oolite-saves directory.
   NSString* originalDirectory = [[NSFileManager defaultManager] currentDirectoryPath];
   [[NSFileManager defaultManager] chdirToDefaultCommanderPath];

	int imageNo = 1;

	NSString	*pathToPic = [NSString stringWithFormat:@"oolite-%03d.bmp",imageNo];
	while ([[NSFileManager defaultManager] fileExistsAtPath:pathToPic])
	{
		imageNo++;
		pathToPic = [NSString stringWithFormat:@"oolite-%03d.bmp",imageNo];
	}

	NSLog(@">>>>> Snapshot %d x %d file chosen = %@", w, h, pathToPic);

	unsigned char *puntos = (unsigned char*)malloc(surface->w * surface->h * 3);
//	SDL_Surface *screen;
	glReadPixels(0,0,surface->w,surface->h,GL_RGB,GL_UNSIGNED_BYTE,puntos);

	int pitch = surface->w * 3;
	unsigned char *aux=  (unsigned char*)malloc( pitch );
	short h2=surface->h/2;
	unsigned char *p1=puntos;
	unsigned char *p2=puntos+((surface->h-1)*pitch); //go to last line
	int i;
	for(i=0; i<h2; i++){
		memcpy(aux,p1,pitch);
		memcpy(p1,p2,pitch);
		memcpy(p2,aux,pitch);
		p1+=pitch;
		p2-=pitch;
	}
	free(aux);

	tmpSurface=SDL_CreateRGBSurfaceFrom(puntos,surface->w,surface->h,24,surface->w*3,0xFF,0xFF00,0xFF0000,0x0);
	SDL_SaveBMP(tmpSurface, [pathToPic cString]);
	SDL_FreeSurface(tmpSurface);
	free(puntos);

	[[NSFileManager defaultManager] changeCurrentDirectoryPath:originalDirectory];
}

/*     Turn the Cocoa ArrowKeys into our arrow key constants. */
- (int) translateKeyCode: (int) input
{
	int key = input;
	switch ( input )
	{
		case NSUpArrowFunctionKey:
			key = gvArrowKeyUp;
			break;

		case NSDownArrowFunctionKey:
			key = gvArrowKeyDown;
			break;

		case NSLeftArrowFunctionKey:
			key = gvArrowKeyLeft;
			break;

		case NSRightArrowFunctionKey:
			key = gvArrowKeyRight;
			break;

		case NSF1FunctionKey:
			key = gvFunctionKey1;
			break;

		case NSF2FunctionKey:
			key = gvFunctionKey2;
			break;

		case NSF3FunctionKey:
			key = gvFunctionKey3;
			break;

		case NSF4FunctionKey:
			key = gvFunctionKey4;
			break;

		case NSF5FunctionKey:
			key = gvFunctionKey5;
			break;

		case NSF6FunctionKey:
			key = gvFunctionKey6;
			break;

		case NSF7FunctionKey:
			key = gvFunctionKey7;
			break;

		case NSF8FunctionKey:
			key = gvFunctionKey8;
			break;

		case NSF9FunctionKey:
			key = gvFunctionKey9;
			break;

		case NSF10FunctionKey:
			key = gvFunctionKey10;
			break;

		case NSF11FunctionKey:
			key = gvFunctionKey11;
			break;

		case NSHomeFunctionKey:
			key = gvHomeKey;
			break;

		default:
			break;
	}
	return key;
}

- (void) setVirtualJoystick:(double) vmx :(double) vmy
{
	virtualJoystickPosition.x = vmx;
	virtualJoystickPosition.y = vmy;
}

- (NSPoint) virtualJoystickPosition
{
	return virtualJoystickPosition;
}


/////////////////////////////////////////////////////////////

- (void) clearKeys
{
	int i;
	for (i = 0; i < [self numKeys]; i++)
		keys[i] = NO;
}

- (void) clearMouse
{
	keys[gvMouseDoubleClick] = NO;
	keys[gvMouseLeftButton] = NO;
	doubleClick = NO;
}

- (BOOL) isAlphabetKeyDown
{
	return isAlphabetKeyDown = NO;;
}

// DJS: When entering submenus in the gui, it is not helpful if the
// key down that brought you into the submenu is still registered
// as down when we're in. This makes isDown return NO until a key up
// event has been received from SDL.
- (void) supressKeysUntilKeyUp
{
   supressKeys = YES;
   [self clearKeys];
}

- (BOOL) isDown: (int) key
{
   if ( supressKeys )
      return NO;
	if ( key < 0 )
		return NO;
	if ( key >= [self numKeys] )
		return NO;
	return keys[key];
}

- (BOOL) isOptDown
{
	return opt;
}

- (BOOL) isCtrlDown
{
	return ctrl;
}

- (BOOL) isCommandDown
{
	return command;
}

- (BOOL) isShiftDown
{
	return shift;
}

- (int) numKeys
{
	return NUM_KEYS;
}

- (void) pollControls: (id)sender
{
	SDL_Event event;
	SDL_KeyboardEvent* kbd_event;
	SDL_MouseButtonEvent* mbtn_event;
	SDL_MouseMotionEvent *mmove_event;
   int mxdelta, mydelta;
//	Uint32 startTicks;
//	Sint32 sleepTicks;

   while (SDL_PollEvent(&event)) {
      switch (event.type) {
         case SDL_JOYAXISMOTION:
         case SDL_JOYBUTTONUP:
         case SDL_JOYBUTTONDOWN:
            [stickHandler handleSDLEvent: &event];
            break;

         case SDL_MOUSEBUTTONDOWN:
            mbtn_event = (SDL_MouseButtonEvent*)&event;
            switch(mbtn_event->button)
            {
               case SDL_BUTTON_LEFT:
                  keys[gvMouseLeftButton] = YES;
                  break;
               case SDL_BUTTON_RIGHT:
                  // Cocoa version does this in the GameController
                  [self setVirtualJoystick:0.0 :0.0];
            }
            break;

         case SDL_MOUSEBUTTONUP:
            mbtn_event = (SDL_MouseButtonEvent*)&event;
            if (mbtn_event->button == SDL_BUTTON_LEFT)
            {
               //NSLog(@"LMB up");
               keys[gvMouseLeftButton] = NO;
            }
            break;

         case SDL_MOUSEMOTION:
         {
            // Delta mode is set when the game is in 'flight' mode.
            // In this mode, the mouse movement delta is used rather
            // than absolute position. This is because if the user
            // clicks the right button to recentre the virtual joystick,
            // if we are using absolute joystick positioning, as soon
            // as the player touches the mouse again, the virtual joystick
            // will snap back to the absolute position (which can be
            // annoyingly fatal in battle).
            if(mouseInDeltaMode)
            {
               // possible TODO - make virtual stick sensitivity configurable
               SDL_GetRelativeMouseState(&mxdelta, &mydelta);
               double mxd=(double)mxdelta / MOUSE_VIRTSTICKSENSITIVITY;
               double myd=(double)mydelta / MOUSE_VIRTSTICKSENSITIVITY;
               virtualJoystickPosition.x += mxd;
               virtualJoystickPosition.y += myd;

               // if we excceed the limits, revert changes
               if(fabs(virtualJoystickPosition.x) > MOUSEX_MAXIMUM)
               {
                  virtualJoystickPosition.x -= mxd;
               }
               if(fabs(virtualJoystickPosition.y) > MOUSEY_MAXIMUM)
               {
                  virtualJoystickPosition.y -= myd;
               }
            }
            else
            {
               // Windowed mode. Use the absolute position so the
               // Oolite mouse pointer appears under the X Window System
               // mouse pointer.
               mmove_event = (SDL_MouseMotionEvent*)&event;

               double mx = mmove_event->x - viewSize.width/2.0;
               double my = mmove_event->y - viewSize.height/2.0;

               if (display_z > 640.0)
               {
                  mx /= viewSize.width * MAIN_GUI_PIXEL_WIDTH / display_z;
                  my /= viewSize.height;
               }
               else
               {
                  mx /= MAIN_GUI_PIXEL_WIDTH * viewSize.width / 640.0;
                  my /= MAIN_GUI_PIXEL_HEIGHT * viewSize.width / 640.0;
               }

               [self setVirtualJoystick:mx :my];
            }
            break;
         }
         case SDL_KEYDOWN:
            kbd_event = (SDL_KeyboardEvent*)&event;

            if(allowingStringInput)
            {
               [self handleStringInput: kbd_event];
            }

            //NSLog(@"Keydown keysym.sym: %d\n", kbd_event->keysym.sym);
            switch (kbd_event->keysym.sym) {
               case SDLK_1: if (shift) { keys[33] = YES; keys[gvNumberKey1] = NO; } else { keys[33] = NO; keys[gvNumberKey1] = YES; } break;
               case SDLK_2: keys[gvNumberKey2] = YES; break;
               case SDLK_3: keys[gvNumberKey3] = YES; break;
               case SDLK_4: keys[gvNumberKey4] = YES; break;
               case SDLK_5: keys[gvNumberKey5] = YES; break;
               case SDLK_6: keys[gvNumberKey6] = YES; break;
               case SDLK_7: keys[gvNumberKey7] = YES; break;
               case SDLK_8: if (shift) { keys[42] = YES; keys[gvNumberKey8] = NO; } else { keys[42] = NO; keys[gvNumberKey8] = YES; } break;
               case SDLK_9: keys[gvNumberKey9] = YES; break;
               case SDLK_0: keys[gvNumberKey0] = YES; break;
               case SDLK_MINUS: if (shift) { keys[43] = NO; } else { keys[43] = YES; } break; // - key, don't know what Oolite# for underscore is
               case SDLK_COMMA: if (shift) { keys[44] = NO; } else { keys[44] = YES; } break;
               case SDLK_EQUALS: if (shift) { keys[45] = YES; } else { keys[45] = NO; } break; // + key, don't know what Oolite# for equals is
               case SDLK_PERIOD: if (shift) { keys[46] = NO; } else { keys[46] = YES; } break;
               case SDLK_SLASH: if (shift) { keys[47] = NO; } else { keys[47] = YES; } break;
               case SDLK_a: if (shift) { keys[65] = YES; keys[97] = NO; } else { keys[65] = NO; keys[97] = YES; } break;
               case SDLK_b: if (shift) { keys[66] = YES; keys[98] = NO; } else { keys[66] = NO; keys[98] = YES; } break;
               case SDLK_c: if (shift) { keys[67] = YES; keys[99] = NO; } else { keys[67] = NO; keys[99] = YES; } break;
               case SDLK_d: if (shift) { keys[68] = YES; keys[100] = NO; } else { keys[68] = NO; keys[100] = YES; } break;
               case SDLK_e: if (shift) { keys[69] = YES; keys[101] = NO; } else { keys[69] = NO; keys[101] = YES; } break;
               case SDLK_f: if (shift) { keys[70] = YES; keys[102] = NO; } else { keys[70] = NO; keys[102] = YES; } break;
               case SDLK_g: if (shift) { keys[71] = YES; keys[103] = NO; } else { keys[71] = NO; keys[103] = YES; } break;
               case SDLK_h: if (shift) { keys[72] = YES; keys[104] = NO; } else { keys[72] = NO; keys[104] = YES; } break;
               case SDLK_i: if (shift) { keys[73] = YES; keys[105] = NO; } else { keys[73] = NO; keys[105] = YES; } break;
               case SDLK_j: if (shift) { keys[74] = YES; keys[106] = NO; } else { keys[74] = NO; keys[106] = YES; } break;
               case SDLK_k: if (shift) { keys[75] = YES; keys[107] = NO; } else { keys[75] = NO; keys[107] = YES; } break;
               case SDLK_l: if (shift) { keys[76] = YES; keys[108] = NO; } else { keys[76] = NO; keys[108] = YES; } break;
               case SDLK_m: if (shift) { keys[77] = YES; keys[109] = NO; } else { keys[77] = NO; keys[109] = YES; } break;
               case SDLK_n: if (shift) { keys[78] = YES; keys[110] = NO; } else { keys[78] = NO; keys[110] = YES; } break;
               case SDLK_o: if (shift) { keys[79] = YES; keys[111] = NO; } else { keys[79] = NO; keys[111] = YES; } break;
               case SDLK_p: if (shift) { keys[80] = YES; keys[112] = NO; } else { keys[80] = NO; keys[112] = YES; } break;
               case SDLK_q: if (shift) { keys[81] = YES; keys[113] = NO; } else { keys[81] = NO; keys[113] = YES; } break;
               case SDLK_r: if (shift) { keys[82] = YES; keys[114] = NO; } else { keys[82] = NO; keys[114] = YES; } break;
               case SDLK_s: if (shift) { keys[83] = YES; keys[115] = NO; } else { keys[83] = NO; keys[115] = YES; } break;
               case SDLK_t: if (shift) { keys[84] = YES; keys[116] = NO; } else { keys[84] = NO; keys[116] = YES; } break;
               case SDLK_u: if (shift) { keys[85] = YES; keys[117] = NO; } else { keys[85] = NO; keys[117] = YES; } break;
               case SDLK_v: if (shift) { keys[86] = YES; keys[118] = NO; } else { keys[86] = NO; keys[118] = YES; } break;
               case SDLK_w: if (shift) { keys[87] = YES; keys[119] = NO; } else { keys[87] = NO; keys[119] = YES; } break;
               case SDLK_x: if (shift) { keys[88] = YES; keys[120] = NO; } else { keys[88] = NO; keys[120] = YES; } break;
               case SDLK_y: if (shift) { keys[89] = YES; keys[121] = NO; } else { keys[89] = NO; keys[121] = YES; } break;
               case SDLK_z: if (shift) { keys[90] = YES; keys[122] = NO; } else { keys[90] = NO; keys[122] = YES; } break;
               case SDLK_BACKSLASH: if (! shift) keys[92] = YES; break;
               case SDLK_BACKQUOTE: if (! shift) keys[96] = YES; break;
               case SDLK_HOME: keys[gvHomeKey] = YES; break;
               case SDLK_SPACE: keys[32] = YES; break;
               case SDLK_RETURN: keys[13] = YES; break;
               case SDLK_TAB: keys[9] = YES; break;
               case SDLK_KP8:
               case SDLK_UP: keys[gvArrowKeyUp] = YES; break;
               case SDLK_KP2:
               case SDLK_DOWN: keys[gvArrowKeyDown] = YES; break;
               case SDLK_KP4:
               case SDLK_LEFT: keys[gvArrowKeyLeft] = YES; break;
               case SDLK_KP6:
               case SDLK_RIGHT: keys[gvArrowKeyRight] = YES; break;

               case SDLK_KP_MINUS: keys[43] = YES; break; // numeric keypad - key
               case SDLK_KP_PLUS: keys[45] = YES; break; // numeric keypad + key

               case SDLK_F1: keys[gvFunctionKey1] = YES; break;
               case SDLK_F2: keys[gvFunctionKey2] = YES; break;
               case SDLK_F3: keys[gvFunctionKey3] = YES; break;
               case SDLK_F4: keys[gvFunctionKey4] = YES; break;
               case SDLK_F5: keys[gvFunctionKey5] = YES; break;
               case SDLK_F6: keys[gvFunctionKey6] = YES; break;
               case SDLK_F7: keys[gvFunctionKey7] = YES; break;
               case SDLK_F8: keys[gvFunctionKey8] = YES; break;
               case SDLK_F9: keys[gvFunctionKey9] = YES; break;
               case SDLK_F10: keys[gvFunctionKey10] = YES; break;

               case SDLK_LSHIFT:
               case SDLK_RSHIFT:
                  shift = YES;
                  break;

               case SDLK_LCTRL:
               case SDLK_RCTRL:
                  ctrl = YES;
                  break;

               case SDLK_F11:
                  if(!fullScreen)
                     break;
                  if(shift)
                  {
                     currentSize--;
                     if (currentSize < 0)
                        currentSize = [screenSizes count] - 1;
                  }
                  else
                  {
                     currentSize++;
                     if (currentSize >= [screenSizes count])
                        currentSize = 0;
                  }
                  [self initialiseGLWithSize: [self modeAsSize: currentSize]];
                  break;

               case SDLK_F12:
                  if (fullScreen == NO)
                  {
                     fullScreen = YES;
                     [self initialiseGLWithSize: [self modeAsSize: currentSize]];
                  }
                  else
                  {
                     // flip to user-selected size
                     fullScreen = NO;
                     [self initialiseGLWithSize: [self modeAsSize: currentSize]];
                  }
                  break;

               case SDLK_ESCAPE:
                  if (shift)
                  {
                     SDL_FreeSurface(surface);
                     [gameController exitApp];
                  }
                  else
                     keys[27] = YES;
            }
            break;

         case SDL_KEYUP:
            supressKeys = NO;    // DJS
            kbd_event = (SDL_KeyboardEvent*)&event;
            //printf("Keydown scancode: %d\n", kbd_event->keysym.scancode);
            switch (kbd_event->keysym.sym) {
               case SDLK_1: keys[33] = NO; keys[gvNumberKey1] = NO; break;
               case SDLK_2: keys[gvNumberKey2] = NO; break;
               case SDLK_3: keys[gvNumberKey3] = NO; break;
               case SDLK_4: keys[gvNumberKey4] = NO; break;
               case SDLK_5: keys[gvNumberKey5] = NO; break;
               case SDLK_6: keys[gvNumberKey6] = NO; break;
               case SDLK_7: keys[gvNumberKey7] = NO; break;
               case SDLK_8: keys[42] = NO; keys[gvNumberKey8] = NO; break;
               case SDLK_9: keys[gvNumberKey9] = NO; break;
               case SDLK_0: keys[gvNumberKey0] = NO; break;
               case SDLK_MINUS: keys[43] = NO; break; // - key, don't know what Oolite# for underscore is
               case SDLK_COMMA: keys[44] = NO; break;
               case SDLK_EQUALS: keys[45] = NO; break; // + key, don't know what Oolite# for equals is
               case SDLK_PERIOD: keys[46] = NO; break;
               case SDLK_SLASH: keys[47] = NO; break;
               case SDLK_a: keys[65] = NO; keys[97] = NO; break;
               case SDLK_b: keys[66] = NO; keys[98] = NO; break;
               case SDLK_c: keys[67] = NO; keys[99] = NO; break;
               case SDLK_d: keys[68] = NO; keys[100] = NO; break;
               case SDLK_e: keys[69] = NO; keys[101] = NO; break;
               case SDLK_f: keys[70] = NO; keys[102] = NO; break;
               case SDLK_g: keys[71] = NO; keys[103] = NO; break;
               case SDLK_h: keys[72] = NO; keys[104] = NO; break;
               case SDLK_i: keys[73] = NO; keys[105] = NO; break;
               case SDLK_j: keys[74] = NO; keys[106] = NO; break;
               case SDLK_k: keys[75] = NO; keys[107] = NO; break;
               case SDLK_l: keys[76] = NO; keys[108] = NO; break;
               case SDLK_m: keys[77] = NO; keys[109] = NO; break;
               case SDLK_n: keys[78] = NO; keys[110] = NO; break;
               case SDLK_o: keys[79] = NO; keys[111] = NO; break;
               case SDLK_p: keys[80] = NO; keys[112] = NO; break;
               case SDLK_q: keys[81] = NO; keys[113] = NO; break;
               case SDLK_r: keys[82] = NO; keys[114] = NO; break;
               case SDLK_s: keys[83] = NO; keys[115] = NO; break;
               case SDLK_t: keys[84] = NO; keys[116] = NO; break;
               case SDLK_u: keys[85] = NO; keys[117] = NO; break;
               case SDLK_v: keys[86] = NO; keys[118] = NO; break;
               case SDLK_w: keys[87] = NO; keys[119] = NO; break;
               case SDLK_x: keys[88] = NO; keys[120] = NO; break;
               case SDLK_y: keys[89] = NO; keys[121] = NO; break;
               case SDLK_z: keys[90] = NO; keys[122] = NO; break;
               case SDLK_BACKSLASH: keys[92] = NO; break;
               case SDLK_BACKQUOTE: keys[96] = NO; break;
               case SDLK_HOME: keys[gvHomeKey] = NO; break;
               case SDLK_SPACE: keys[32] = NO; break;
               case SDLK_RETURN: keys[13] = NO; break;
               case SDLK_TAB: keys[9] = NO; break;
               case SDLK_KP8:
               case SDLK_UP: keys[gvArrowKeyUp] = NO; break;
               case SDLK_KP2:
               case SDLK_DOWN: keys[gvArrowKeyDown] = NO; break;
               case SDLK_KP4:
               case SDLK_LEFT: keys[gvArrowKeyLeft] = NO; break;
               case SDLK_KP6:
               case SDLK_RIGHT: keys[gvArrowKeyRight] = NO; break;

               case SDLK_KP_MINUS: keys[43] = NO; break; // numeric keypad - key
               case SDLK_KP_PLUS: keys[45] = NO; break; // numeric keypad + key

               case SDLK_F1: keys[gvFunctionKey1] = NO; break;
               case SDLK_F2: keys[gvFunctionKey2] = NO; break;
               case SDLK_F3: keys[gvFunctionKey3] = NO; break;
               case SDLK_F4: keys[gvFunctionKey4] = NO; break;
               case SDLK_F5: keys[gvFunctionKey5] = NO; break;
               case SDLK_F6: keys[gvFunctionKey6] = NO; break;
               case SDLK_F7: keys[gvFunctionKey7] = NO; break;
               case SDLK_F8: keys[gvFunctionKey8] = NO; break;
               case SDLK_F9: keys[gvFunctionKey9] = NO; break;
               case SDLK_F10: keys[gvFunctionKey10] = NO; break;

               case SDLK_LSHIFT:
               case SDLK_RSHIFT:
                  shift = NO;
                  break;

               case SDLK_LCTRL:
               case SDLK_RCTRL:
                  ctrl = NO;
                  break;

               case SDLK_ESCAPE:
                  keys[27] = NO;
                  break;
            }
            break;

         case SDL_VIDEORESIZE:
         {
            SDL_ResizeEvent *rsevt=(SDL_ResizeEvent *)&event;
            NSSize newSize=NSMakeSize(rsevt->w, rsevt->h);
            [self initialiseGLWithSize: newSize];
            [self saveWindowSize: newSize];
            break;
         }

         // caused by INTR or someone hitting close
         case SDL_QUIT:
         {
            SDL_FreeSurface(surface);
            [gameController exitApp];
         }
      }
   }

   NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
   [gameController doStuff: nil];
   // Clean up any autoreleased objects that were created this time through the loop.
   [pool release];
}

// DJS: String input handler. Since for SDL versions we're also handling
// freeform typing this has necessarily got more complex than the non-SDL
// versions.
- (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event;
{
   SDLKey key=kbd_event->keysym.sym;

   // Del, Backspace
   if(key == SDLK_BACKSPACE || key == SDLK_DELETE)
   {
      if([typedString length] >= 1)
      {
         [typedString deleteCharactersInRange:
            NSMakeRange([typedString length]-1, 1)];
      }
      else
      {
         [self resetTypedString];
      }
   }

   // Note: if we start using this handler for anything other
   // than savegames, a more flexible mechanism is needed
   // for max. string length.
   if([typedString length] < 40)
   {
      // keys a-z
      if(key >= SDLK_a && key <= SDLK_z)
      {
         isAlphabetKeyDown=YES;
         if(shift)
         {
            key=toupper(key);
         }
         [typedString appendFormat:@"%c", key];
      }

      // keys 0-9, Space
      // Left-Shift seems to produce the key code for 0 :/
      if((key >= SDLK_0 && key <= SDLK_9) || key == SDLK_SPACE)
      {
         [typedString appendFormat:@"%c", key];
      }
   }
}

// Full screen mode enumerator.
- (void) populateFullScreenModelist
{
   int i;
   SDL_Rect **modes;
   NSMutableDictionary *mode;

   screenSizes=[[NSMutableArray alloc] init];
   [screenSizes retain];

   // The default resolution (slot 0) is the resolution we are
   // already in since this is guaranteed to work.
   mode=[MyOpenGLView getNativeSize];
   [screenSizes addObject: mode];

   modes=SDL_ListModes(NULL, SDL_FULLSCREEN|SDL_HWSURFACE);
   if(modes == (SDL_Rect **)NULL)
   {
      NSLog(@"SDL didn't return any screen modes");
      return;
   }

   if(modes == (SDL_Rect **)-1)
   {
      NSLog(@"SDL claims 'all resolutions available' which is unhelpful in the extreme");
      return;
   }

   int lastw=[[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
   int lasth=[[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
   for(i=0; modes[i]; i++)
   {
      // SDL_ListModes often lists a mode several times,
      // presumably because each mode has several refresh rates.
      // But the modes pointer is an SDL_Rect which can't represent
      // refresh rates. WHY!?
      if(modes[i]->w != lastw && modes[i]->h != lasth)
      {
         // new resolution, save it
         mode=[[NSMutableDictionary alloc] init];
         [mode setValue: [NSNumber numberWithInt: (int)modes[i]->w]
                 forKey: (NSString *)kCGDisplayWidth];
         [mode setValue: [NSNumber numberWithInt: (int)modes[i]->h]
                 forKey: (NSString *)kCGDisplayHeight];
         [mode setValue: [NSNumber numberWithInt: 0]
                 forKey: (NSString *)kCGDisplayRefreshRate];
         [screenSizes addObject: mode];
         NSLog(@"Added res %d x %d", modes[i]->w, modes[i]->h);
         lastw=modes[i]->w;
         lasth=modes[i]->h;
      }
   }
}

// Save and restore window sizes to/from defaults.
- (void) saveWindowSize: (NSSize) windowSize
{
   NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
   [defaults setInteger: (int)windowSize.width forKey: @"window_width"];
   [defaults setInteger: (int)windowSize.height forKey: @"window_height"];
   currentWindowSize=windowSize;
}

- (NSSize) loadWindowSize
{
   NSSize windowSize;
   NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
   if([defaults objectForKey:@"window_width"] &&
      [defaults objectForKey:@"window_height"])
   {
      windowSize=NSMakeSize([defaults integerForKey: @"window_width"],
                            [defaults integerForKey: @"window_height"]);
   }
   else
   {
      windowSize=NSMakeSize(800, 600);
   }
   currentWindowSize=windowSize;
   return windowSize;
}

- (int) loadFullscreenSettings
{
   currentSize=0;
   int width=0, height=0, refresh=0;

  	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	if ([userDefaults objectForKey:@"display_width"])
		width = [userDefaults integerForKey:@"display_width"];
	if ([userDefaults objectForKey:@"display_height"])
		height = [userDefaults integerForKey:@"display_height"];
	if ([userDefaults objectForKey:@"display_refresh"])
		refresh = [userDefaults integerForKey:@"display_refresh"];
   if([userDefaults objectForKey:@"fullscreen"])
      fullScreen=[userDefaults boolForKey:@"fullscreen"];

   if(width && height)
   {
      currentSize=[self findDisplayModeForWidth: width Height: height Refresh: refresh];
      return currentSize;
   }
   return currentSize;
}

- (int) findDisplayModeForWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
   int i, modeCount;
   NSDictionary *mode;
   unsigned int modeWidth, modeHeight, modeRefresh;

   modeCount = [screenSizes count];

	for (i = 0; i < modeCount; i++)
	{
      mode = [screenSizes objectAtIndex: i];
      modeWidth = [[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
      modeHeight = [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
      modeRefresh = [[mode objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
	   if ((modeWidth == d_width)&&(modeHeight == d_height)&&(modeRefresh == d_refresh))
      {
         NSLog(@"Found mode %@", mode);
		   return i;
      }
	}

   NSLog(@"Failed to find mode: width=%d height=%d refresh=%d", d_width, d_height, d_refresh);
   NSLog(@"Contents of list: %@", screenSizes);
	return 0;
}

- (NSSize) currentScreenSize
{
   NSDictionary *mode=[screenSizes objectAtIndex: currentSize];

   if(mode)
   {
      return NSMakeSize([[mode objectForKey: (NSString *)kCGDisplayWidth] intValue],
                        [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue]);
   }
   NSLog(@"Screen size unknown!");
   return NSMakeSize(800, 600);
}

- (JoystickHandler *) getStickHandler
{
   return stickHandler;
}

- (void) setMouseInDeltaMode: (BOOL) inDelta
{
   mouseInDeltaMode=inDelta;
}

@end
