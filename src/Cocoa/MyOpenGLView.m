/*

MyOpenGLView.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "Entity.h"
#import "PlanetEntity.h"
#import "ResourceManager.h"
#import "GuiDisplayGen.h"
#import <Carbon/Carbon.h>
#import "JoystickHandler.h"


static NSString * kOOLogKeyCodeOutOfRange	= @"input.keyMapping.codeOutOfRange";
static NSString * kOOLogKeyUp				= @"input.keyMapping.keyPress.keyUp";
static NSString * kOOLogKeyDown				= @"input.keyMapping.keyPress.keyDown";


@interface MyOpenGLView(Internal)

- (int) translateKeyCode: (int) input;
- (void)performLateSetup;

@end


@implementation MyOpenGLView

- (id) initWithFrame:(NSRect)frameRect
{
	// Pixel Format Attributes for the View-based (non-FullScreen) NSOpenGLContext
	NSOpenGLPixelFormatAttribute attrs[] =
	{
//		// Specify that we want a full-screen OpenGL context.
//		NSOpenGLPFAFullScreen,
		// and that we want a windowed OpenGL context.
		NSOpenGLPFAWindow,
		
		// We may be on a multi-display system (and each screen may be driven by a different renderer), so we need to specify which screen we want to take over.
		// For this demo, we'll specify the main screen.
		NSOpenGLPFAScreenMask, CGDisplayIDToOpenGLDisplayMask(kCGDirectMainDisplay),
		
		// Specifying "NoRecovery" gives us a context that cannot fall back to the software renderer.
		//This makes the View-based context a compatible with the fullscreen context, enabling us to use the "shareContext"
		// feature to share textures, display lists, and other OpenGL objects between the two.
		NSOpenGLPFANoRecovery,
		
		// Attributes Common to FullScreen and non-FullScreen
		NSOpenGLPFACompliant,
		
		NSOpenGLPFAColorSize, 32,
		NSOpenGLPFADepthSize, 32,
		NSOpenGLPFADoubleBuffer,
		NSOpenGLPFAAccelerated,
		0
	};
	
	// Create our non-FullScreen pixel format.
	NSOpenGLPixelFormat* pixelFormat = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs] autorelease];
	
	self = [super initWithFrame:frameRect pixelFormat:pixelFormat];
	
	virtualJoystickPosition = NSMakePoint(0.0,0.0);
	
	typedString = [[NSMutableString alloc] initWithString:@""];
	allowingStringInput = gvStringInputNo;
	isAlphabetKeyDown = NO;
		
	timeIntervalAtLastClick = [NSDate timeIntervalSinceReferenceDate];
	
	return self;
}


- (void) dealloc
{
	if (typedString)
		[typedString release];
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
	[typedString setString:value];
}


- (NSSize) viewSize
{
	return viewSize;
}


- (GLfloat) display_z
{
	return display_z;
}


- (GameController *)gameController
{
	return gameController;
}


- (void) setGameController:(GameController *) controller
{
	gameController = controller;
}


- (void) updateScreen
{
	[self drawRect:NSMakeRect(0, 0, viewSize.width, viewSize.height)];
}


- (void) drawRect:(NSRect)rect
{
	if ((viewSize.width != [self frame].size.width)||(viewSize.height != [self frame].size.height)) // resized
	{
		m_glContextInitialized = NO;
		viewSize = [self frame].size;
	}
	
	if (!m_glContextInitialized)  [self initialiseGLWithSize:viewSize];
	
	// do all the drawing!
	if (UNIVERSE != nil)  [UNIVERSE drawUniverse];
	else
	{
		// not set up yet, draw a black screen
		glClearColor(0.0, 0.0, 0.0, 0.0);
		glClear(GL_COLOR_BUFFER_BIT);
	}
	
	[[self openGLContext] flushBuffer];
}


- (void) initialiseGLWithSize:(NSSize) v_size
{
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
	
	float	ratio = 0.5;
	float   aspect = viewSize.height/viewSize.width;
	
	glShadeModel(GL_FLAT);
	glClearColor(0.0, 0.0, 0.0, 0.0);
	glClear(GL_COLOR_BUFFER_BIT);
	[[self openGLContext] flushBuffer];
	
	glClearDepth(MAX_CLEAR_DEPTH);
	glViewport( 0, 0, viewSize.width, viewSize.height);
	
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
		[UNIVERSE setLighting];
	}
	else
	{	
		glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
		glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);
		glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
		glLightfv(GL_LIGHT1, GL_POSITION, sun_center_position);
		glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient);
		
		glEnable(GL_LIGHT1);		// lighting

	}
	glEnable(GL_LIGHTING);		// lighting
	
	
	// world's simplest OpenGL optimisations...
#if GL_APPLE_transform_hint
	glHint(GL_TRANSFORM_HINT_APPLE, GL_FASTEST);
#endif
	
	glDisable(GL_NORMALIZE);
	glDisable(GL_RESCALE_NORMAL);
		
	m_glContextInitialized = YES;
}


- (void) snapShot
{
	int w = viewSize.width;
	int h = viewSize.height;
	
	if (w & 3)
		w = w + 4 - (w & 3);
	
	long nPixels = w * h + 1;	

	unsigned char   *red = (unsigned char *) malloc( nPixels);
	unsigned char   *green = (unsigned char *) malloc( nPixels);
	unsigned char   *blue = (unsigned char *) malloc( nPixels);
	
	NSString	*filepath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
	int imageNo = 0;
	NSString	*pathToPic = nil;
		
	do 
	{
		imageNo++;
		pathToPic = [filepath stringByAppendingPathComponent:[NSString stringWithFormat:@"oolite-%03d.png",imageNo]];
	} while ([[NSFileManager defaultManager] fileExistsAtPath:pathToPic]);
			
	OOLog(@"snapshot", @">>>>> Snapshot %d x %d file path chosen = %@", w, h, pathToPic);
	
	NSBitmapImageRep* bitmapRep = 
		[[NSBitmapImageRep alloc]
			initWithBitmapDataPlanes:NULL	// --> let the class allocate it
			pixelsWide:			w
			pixelsHigh:			h
			bitsPerSample:		8			// each component is 8 bits (1 byte)
			samplesPerPixel:	3			// number of components (R, G, B)
			hasAlpha:			NO			// no transparency
			isPlanar:			NO			// data integrated into single plane
			colorSpaceName:		NSDeviceRGBColorSpace
			bytesPerRow:		3*w			// can no longer let the class figure it out
			bitsPerPixel:		24			// can no longer let the class figure it out
		];

	unsigned char *pixels = [bitmapRep bitmapData];
		
	glReadPixels(0,0, w,h, GL_RED,   GL_UNSIGNED_BYTE, red);
	glReadPixels(0,0, w,h, GL_GREEN, GL_UNSIGNED_BYTE, green);
	glReadPixels(0,0, w,h, GL_BLUE,  GL_UNSIGNED_BYTE, blue);

	int x,y;
	for (y = 0; y < h; y++)
	{
		long index = (h - y - 1)*w;
		for (x = 0; x < w; x++)		// set bitmap pixels
		{
			*pixels++ = red[index];
			*pixels++ = green[index];
			*pixels++ = blue[index++];
		}
	}
	
	[[bitmapRep representationUsingType:NSPNGFileType properties:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSImageInterlaced, NULL]]
		writeToFile:pathToPic atomically:YES];			// save PNG representation of image
	
	// free allocated objects and memory
	[bitmapRep release];
	free(red);
	free(green);
	free(blue);
	
}


- (BOOL) acceptsFirstResponder
{
	return YES;
}


- (void) keyUp:(NSEvent *)theEvent
{
	NSString	*stringValue = nil;
	int			key;
	int			keycode;
	
	stringValue = [theEvent charactersIgnoringModifiers];
	
	/*	Bug: exception when releasing accent key.
		Analysis: Dead keys (accents and similar) return an empty string.
		Fix: reject zero-length strings. This is the Wrong Thing - we should
		really be using KeyTranslate()/UCKeyTranslate() to find out what the
		string would be if you pressed the key and then space.
		-- Ahruman 20070714
	*/
	if ([stringValue length] < 1)  return;
	
	key = [stringValue characterAtIndex:0];
	keycode = [theEvent keyCode] & 255;
	
	supressKeys = NO;
	
	key = keycodetrans[keycode];	// retrieve the character we got for pressing the hardware at key location 'keycode'
	
	OOLog(kOOLogKeyUp, @"Key up: stringValue = \"%@\", keyCode = %d, key = %u", stringValue, keycode, key);
	
	// Special handling of command keys used in full-screen mode.
	if ([theEvent modifierFlags] & NSCommandKeyMask)
	{
		switch (key)
		{
			case 'q':
				commandQ = NO;
				break;
				
			case 'f':
				commandF = NO;
				break;
		}
		// Pass through to allow clearing of normal key as well.
	}
	
	isAlphabetKeyDown = NO;
	if ((key >= 0)&&(key < [self numKeys])&&(keys[key]))
	{
		keys[key] = NO;
	}
	else
	{
		if (key > [self numKeys])
			OOLog(kOOLogKeyCodeOutOfRange, @"Translated key: %d out of range", key);
	}
}


- (void) keyDown:(NSEvent *)theEvent
{
	NSString	*stringValue = nil;
	int			key;
	int			keycode;
	
	stringValue = [theEvent charactersIgnoringModifiers];
	
	/*	Bug: exception when pressing accent key.
		Analysis: Dead keys (accents and similar) return an empty string.
		Fix: reject zero-length strings. This is the Wrong Thing - we should
		really be using KeyTranslate()/UCKeyTranslate() to find out what the
		string would be if you pressed the key and then space.
		-- Ahruman 20070714
	*/
	if ([stringValue length] < 1)  return;
	
	key = [stringValue characterAtIndex:0];
	keycode = [theEvent keyCode] & 255;
	
	key = [self translateKeyCode:key];
	
	OOLog(kOOLogKeyDown, @"Key down: stringValue = \"%@\", keyCode = %d, key = %u", stringValue, keycode, key);
	
	// Special handling of command keys used in full-screen mode.
	if ([theEvent modifierFlags] & NSCommandKeyMask)
	{
		switch (key)
		{
			case 'q':
				commandQ = YES;
				break;
				
			case 'f':
				commandF = YES;
				break;
		}
		
		return;
	}
	
	keycodetrans[keycode] = key;	// record the chracter we got for pressing the hardware at key location 'keycode'
	
	if ((key >= 0)&&(key < [self numKeys])&&(!keys[key]))
	{
		keys[key] = YES;
		
		if (allowingStringInput)
		{
			// limited input for planet find screen
			if (allowingStringInput == gvStringInputAlpha)
			{
				if (isalpha(key))
				{
					isAlphabetKeyDown = YES;
					// convert to lowercase
					[typedString appendFormat:@"%c", tolower(key)];
				}
				else
					isAlphabetKeyDown = NO;
				if (key == NSDeleteCharacter)
				{
					//delete
					[typedString setString:@""];
				}
			}
			
			// full input for load-save screen
			if (allowingStringInput == gvStringInputAll)
			{
				if (isprint(key) && key != '/')
				{
					isAlphabetKeyDown = YES;
					// convert to lowercase
					[typedString appendFormat:@"%c", key];
				}
				else
					isAlphabetKeyDown = NO;
				if ((key == NSDeleteCharacter) && [typedString length])
				{
					//delete
					[typedString deleteCharactersInRange:NSMakeRange([typedString length] - 1, 1)];
				}
			}
			
		}
	}
	else
	{
		if (key > [self numKeys])
			OOLog(kOOLogKeyCodeOutOfRange, @"Translated key: %d out of range", key);
	}
} 

/* Capture shift, ctrl, opt and command press & release */
- (void)flagsChanged:(NSEvent *)theEvent
{
	int flags = [theEvent modifierFlags];
	opt = (flags & NSAlternateKeyMask) ? YES : NO;
	ctrl = (flags & NSControlKeyMask) ? YES : NO;
	command = (flags & NSCommandKeyMask) ? YES : NO;
	shift = ( flags & NSShiftKeyMask ) ? YES : NO;

}


- (void)mouseDown:(NSEvent *)theEvent
{
	if (doubleClick)
	{
		doubleClick = NO;
		keys[gvMouseDoubleClick] = NO;
	}
	keys[gvMouseLeftButton] = YES; // 'a' down
}


- (void)mouseUp:(NSEvent *)theEvent
{
	NSTimeInterval timeBetweenClicks = [NSDate timeIntervalSinceReferenceDate] - timeIntervalAtLastClick;
	timeIntervalAtLastClick += timeBetweenClicks;
	
	if (!doubleClick)
	{
		doubleClick = (timeBetweenClicks < MOUSE_DOUBLE_CLICK_INTERVAL);	// One fifth of a second
		keys[gvMouseDoubleClick] = doubleClick;
	}
	
	keys[gvMouseLeftButton] = NO;  // 'a' up
}


- (void)mouseMoved:(NSEvent *)theEvent
{
	double mx = [theEvent locationInWindow].x - viewSize.width/2.0;
	double my = [theEvent locationInWindow].y - viewSize.height/2.0;
		
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
	
	[self setVirtualJoystick:mx :-my];
}

/////////////////////////////////////////////////////////////
/*  Turn the Cocoa ArrowKeys into our arrow key constants. */
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


- (JoystickHandler *)getStickHandler
{
	return [JoystickHandler sharedStickHandler];
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
	return isAlphabetKeyDown = NO;
}

// DJS: When entering submenus in the gui, it is not helpful if the
// key down that brought you into the submenu is still registered
// as down when we're in. This makes isDown return NO until a key up
// event has been received from SDL.
- (void) supressKeysUntilKeyUp
{
	if (keys[gvMouseDoubleClick] == NO)
	{
		supressKeys = YES;
		[self clearKeys];
	}
	else
	{
		[self clearMouse];
	}
}


- (BOOL) isDown: (int) key
{
	if( supressKeys )
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


- (BOOL) isCommandQDown
{
	return commandQ;
}


- (BOOL) isCommandFDown
{
	return commandF;
}


- (void) clearCommandF
{
	commandF = NO;
}


- (BOOL)pollShiftKey
{
	#define KEYMAP_GET(m, index) ((((uint8_t*)(m))[(index) >> 3] & (1L << ((index) & 7))) ? 1 : 0)
	
	KeyMap				map;
	
	GetKeys(map);
	return KEYMAP_GET(map, 56) || KEYMAP_GET(map, 60);	// Left shift or right shift -- although 60 shouldn't occur.
}

@end
