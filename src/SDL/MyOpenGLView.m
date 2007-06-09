/*

MyOpenGLView.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "MyOpenGLView.h"

#import "GameController.h"
#import "Universe.h"
#import "JoystickHandler.h" // TODO: Not here!
#import "SDL_syswm.h"
#import "OOSound.h"
#import "NSFileManagerOOExtensions.h" // to find savedir
#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "PlanetEntity.h"
#import "OOGraphicsResetManager.h"

#ifdef WIN32
#import "TextureStore.h"
#endif

#define kOOLogUnconvertedNSLog @"unclassified.MyOpenGLView"

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


	// Generate the window caption, containing the version number and the date the executable was compiled.
	static char windowCaption[128];
	NSString *versionString = [NSString stringWithFormat:@"Oolite Version %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
	
	strcpy (windowCaption, [versionString UTF8String]);
	strcat (windowCaption, " - "__DATE__);
	SDL_WM_SetCaption (windowCaption, "OOLITE");	// Set window title.


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
	if (UNIVERSE)  [UNIVERSE drawFromEntity:0];
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

	if (UNIVERSE)
	{
		Entity* the_sun = [UNIVERSE sun];
		Vector sun_pos = (the_sun)? the_sun->position : make_vector(0.0f,0.0f,0.0f);
		sun_center_position[0] = sun_pos.x;
		sun_center_position[1] = sun_pos.y;
		sun_center_position[2] = sun_pos.z;
		[UNIVERSE setLighting];
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
	if (UNIVERSE)
	{
		[[OOGraphicsResetManager sharedManager] resetGraphicsState];
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


- (void)pollControls
{
	SDL_Event				event;
	SDL_KeyboardEvent		*kbd_event;
	SDL_MouseButtonEvent	*mbtn_event;
	SDL_MouseMotionEvent	*mmove_event;
	int						mxdelta, mydelta;

   while (SDL_PollEvent(&event))
   {
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

	    // Macro KEYCODE_DOWN_EITHER. Detect the keypress state (with shift or without) and assign appropriate values to the
	    // keys array. This way Oolite can use more keys, since now key '3', for example is a different keypress to '#'.
	    #define KEYCODE_DOWN_EITHER(a,b)	do { \
	    				  	    if (shift) { keys[a] = YES; keys[b] = NO; } else { keys[a] = NO; keys[b] = YES; } \
	    					} while (0)
	    					
            //NSLog(@"Keydown keysym.sym: %d\n", kbd_event->keysym.sym);
            switch (kbd_event->keysym.sym) {
               case SDLK_1: KEYCODE_DOWN_EITHER (33, gvNumberKey1); break;	// ! or 1
               case SDLK_2: KEYCODE_DOWN_EITHER (64, gvNumberKey2); break;	// @ or 2
               case SDLK_3: KEYCODE_DOWN_EITHER (35, gvNumberKey3); break;	// # or 3
               case SDLK_4: KEYCODE_DOWN_EITHER (36, gvNumberKey4); break;	// $ or 4
               case SDLK_5: KEYCODE_DOWN_EITHER (37, gvNumberKey5); break;	// % or 5
               case SDLK_6: KEYCODE_DOWN_EITHER (94, gvNumberKey6); break;	// ^ or 6
               case SDLK_7: KEYCODE_DOWN_EITHER (38, gvNumberKey7); break;	// & or 7
               case SDLK_8: KEYCODE_DOWN_EITHER (42, gvNumberKey8); break;	// * or 8
               case SDLK_9: KEYCODE_DOWN_EITHER (40, gvNumberKey9); break;	// ( or 9
               case SDLK_0: KEYCODE_DOWN_EITHER (41, gvNumberKey0); break;	// ) or 0
               case SDLK_MINUS: KEYCODE_DOWN_EITHER (95, 45); break;		// _ or -
               case SDLK_COMMA: KEYCODE_DOWN_EITHER (60, 44); break;		// < or ,
               case SDLK_EQUALS: KEYCODE_DOWN_EITHER (43, 61); break;		// + or =
               case SDLK_PERIOD: KEYCODE_DOWN_EITHER (62, 46); break;		// > or .
               case SDLK_SLASH: KEYCODE_DOWN_EITHER (63, 47); break;		// ? or /
               case SDLK_a: KEYCODE_DOWN_EITHER (65, 97); break;		// A or a
               case SDLK_b: KEYCODE_DOWN_EITHER (66, 98); break;		// B or b
               case SDLK_c: KEYCODE_DOWN_EITHER (67, 99); break;		// C or c
               case SDLK_d: KEYCODE_DOWN_EITHER (68, 100); break;		// D or d
               case SDLK_e: KEYCODE_DOWN_EITHER (69, 101); break;		// E or e
               case SDLK_f: KEYCODE_DOWN_EITHER (70, 102); break;		// F or f
               case SDLK_g: KEYCODE_DOWN_EITHER (71, 103); break;		// G or g
               case SDLK_h: KEYCODE_DOWN_EITHER (72, 104); break;		// H or h
               case SDLK_i: KEYCODE_DOWN_EITHER (73, 105); break;		// I or i
               case SDLK_j: KEYCODE_DOWN_EITHER (74, 106); break;		// J or j
               case SDLK_k: KEYCODE_DOWN_EITHER (75, 107); break;		// K or k
               case SDLK_l: KEYCODE_DOWN_EITHER (76, 108); break;		// L or l
               case SDLK_m: KEYCODE_DOWN_EITHER (77, 109); break;		// M or m
               case SDLK_n: KEYCODE_DOWN_EITHER (78, 110); break;		// N or n
               case SDLK_o: KEYCODE_DOWN_EITHER (79, 111); break;		// O or o
               case SDLK_p: KEYCODE_DOWN_EITHER (80, 112); break;		// P or p
               case SDLK_q: KEYCODE_DOWN_EITHER (81, 113); break;		// Q or q
               case SDLK_r: KEYCODE_DOWN_EITHER (82, 114); break;		// R or r
               case SDLK_s: KEYCODE_DOWN_EITHER (83, 115); break;		// S or s
               case SDLK_t: KEYCODE_DOWN_EITHER (84, 116); break;		// T or t
               case SDLK_u: KEYCODE_DOWN_EITHER (85, 117); break;		// U or u
               case SDLK_v: KEYCODE_DOWN_EITHER (86, 118); break;		// V or v
               case SDLK_w: KEYCODE_DOWN_EITHER (87, 119); break;		// W or w
               case SDLK_x: KEYCODE_DOWN_EITHER (88, 120); break;		// X or x
               case SDLK_y: KEYCODE_DOWN_EITHER (89, 121); break;		// Y or y
               case SDLK_z: KEYCODE_DOWN_EITHER (90, 122); break;		// Z or z
               case SDLK_BACKSLASH: KEYCODE_DOWN_EITHER (166, 92); break;	// | or \
               case SDLK_BACKQUOTE: KEYCODE_DOWN_EITHER (126, 96); break;	// ~ or `
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

               case SDLK_KP_MINUS: keys[45] = YES; break; // numeric keypad - key
               case SDLK_KP_PLUS: keys[43] = YES; break; // numeric keypad + key

               case SDLK_KP1: keys[310] = YES; break;
               case SDLK_KP3: keys[311] = YES; break;

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
            
            #define KEYCODE_UP_BOTH(a,b)	do { \
            			  		    keys[a] = NO; keys[b] = NO; \
            					} while (0)
            
            switch (kbd_event->keysym.sym) {
               case SDLK_1: KEYCODE_UP_BOTH (33, gvNumberKey1); break;		// ! and 1
               case SDLK_2: KEYCODE_UP_BOTH (64, gvNumberKey2); break;		// @ and 2
               case SDLK_3: KEYCODE_UP_BOTH (35, gvNumberKey3); break;		// # and 3
               case SDLK_4: KEYCODE_UP_BOTH (36, gvNumberKey4); break;		// $ and 4
               case SDLK_5: KEYCODE_UP_BOTH (37, gvNumberKey5); break;		// % and 5
               case SDLK_6: KEYCODE_UP_BOTH (94, gvNumberKey6); break;		// ^ and 6
               case SDLK_7: KEYCODE_UP_BOTH (38, gvNumberKey7); break;		// & and 7
               case SDLK_8: KEYCODE_UP_BOTH (42, gvNumberKey8); break;		// * and 8
               case SDLK_9: KEYCODE_UP_BOTH (40, gvNumberKey9);break;		// ( and 9
               case SDLK_0: KEYCODE_UP_BOTH (41, gvNumberKey0); break;		// ) and 0
               case SDLK_MINUS: KEYCODE_UP_BOTH (95, 45); break;		// _ and -
               case SDLK_COMMA: KEYCODE_UP_BOTH (60, 44); break;		// < and ,
               case SDLK_EQUALS: KEYCODE_UP_BOTH (43, 61); break;		// + and =
               case SDLK_PERIOD: KEYCODE_UP_BOTH (62, 46); break;		// > and .
               case SDLK_SLASH: KEYCODE_UP_BOTH (63, 47); break;		// ? and /
               case SDLK_a: KEYCODE_UP_BOTH (65, 97); break;			// A and a
               case SDLK_b: KEYCODE_UP_BOTH (66, 98); break;			// B and b
               case SDLK_c: KEYCODE_UP_BOTH (67, 99); break;			// C and c
               case SDLK_d: KEYCODE_UP_BOTH (68, 100); break;			// D and d
               case SDLK_e: KEYCODE_UP_BOTH (69, 101); break;			// E and e
               case SDLK_f: KEYCODE_UP_BOTH (70, 102); break;			// F and f
               case SDLK_g: KEYCODE_UP_BOTH (71, 103); break;			// G and g
               case SDLK_h: KEYCODE_UP_BOTH (72, 104); break;			// H and h
               case SDLK_i: KEYCODE_UP_BOTH (73, 105); break;			// I and i
               case SDLK_j: KEYCODE_UP_BOTH (74, 106); break;			// J and j
               case SDLK_k: KEYCODE_UP_BOTH (75, 107); break;			// K and k
               case SDLK_l: KEYCODE_UP_BOTH (76, 108); break;			// L and l
               case SDLK_m: KEYCODE_UP_BOTH (77, 109); break;			// M and m
               case SDLK_n: KEYCODE_UP_BOTH (78, 110); break;			// N and n
               case SDLK_o: KEYCODE_UP_BOTH (79, 111); break;			// O and o
               case SDLK_p: KEYCODE_UP_BOTH (80, 112); break;			// P and p
               case SDLK_q: KEYCODE_UP_BOTH (81, 113); break;			// Q and q
               case SDLK_r: KEYCODE_UP_BOTH (82, 114); break;			// R and r
               case SDLK_s: KEYCODE_UP_BOTH (83, 115); break;			// S and s
               case SDLK_t: KEYCODE_UP_BOTH (84, 116); break;			// T and t
               case SDLK_u: KEYCODE_UP_BOTH (85, 117); break;			// U and u
               case SDLK_v: KEYCODE_UP_BOTH (86, 118); break;			// V and v
               case SDLK_w: KEYCODE_UP_BOTH (87, 119); break;			// W and w
               case SDLK_x: KEYCODE_UP_BOTH (88, 120); break;			// X and x
               case SDLK_y: KEYCODE_UP_BOTH (89, 121); break;			// Y and y
               case SDLK_z: KEYCODE_UP_BOTH (90, 122); break;			// Z and z
               case SDLK_BACKSLASH: KEYCODE_UP_BOTH (166, 92); break;		// | and \
               case SDLK_BACKQUOTE: KEYCODE_UP_BOTH (126, 96); break;		// ~ and `
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

               case SDLK_KP_MINUS: keys[45] = NO; break; // numeric keypad - key
               case SDLK_KP_PLUS: keys[43] = NO; break; // numeric keypad + key

               case SDLK_KP1: keys[310] = NO; break;
               case SDLK_KP3: keys[311] = NO; break;

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


- (BOOL)pollShiftKey
{
	return 0 != (SDL_GetModState() & (KMOD_LSHIFT | KMOD_RSHIFT));
}

@end
