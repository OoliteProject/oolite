/*

MyOpenGLView.m

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

#import "MyOpenGLView.h"

#import "GameController.h"
#import "Universe.h"
#import "Entity.h"
#import "OOPlanetEntity.h"
#import "ResourceManager.h"
#import "GuiDisplayGen.h"
#import <Carbon/Carbon.h>
#import "NSFileManagerOOExtensions.h"
#import "OOGraphicsResetManager.h"
#import "PlayerEntity.h"

#ifndef NDEBUG
#import <Foundation/NSDebug.h>
#endif


static NSString * kOOLogKeyCodeOutOfRange	= @"input.keyMapping.codeOutOfRange";
static NSString * kOOLogKeyUp				= @"input.keyMapping.keyPress.keyUp";
static NSString * kOOLogKeyDown				= @"input.keyMapping.keyPress.keyDown";


static void GetDesiredCursorState(OOMouseInteractionMode mode, BOOL *outHidden, BOOL *outObscured);
static void ApplyCursorState(OOMouseInteractionMode mode);
static void UnapplyCursorState(OOMouseInteractionMode mode);


@interface MyOpenGLView(Internal)

- (int) translateKeyCode:(int)input;

- (void) recenterVirtualJoystick;

@end


#if !OOLITE_MAC_OS_X_10_7
@interface NSView (Lion)

- (BOOL) wantsBestResolutionOpenGLSurface;
- (void) setWantsBestResolutionOpenGLSurface:(BOOL)flag;

- (NSPoint) convertPointToBacking:(NSPoint)aPoint;
- (NSPoint) convertPointFromBacking:(NSPoint)aPoint;
- (NSSize) convertSizeToBacking:(NSSize)aSize;
- (NSSize) convertSizeFromBacking:(NSSize)aSize;
- (NSRect) convertRectToBacking:(NSRect)aRect;
- (NSRect) convertRectFromBacking:(NSRect)aRect;

@end
#endif


@implementation MyOpenGLView

- (id) initWithFrame:(NSRect)frameRect
{
#ifndef NDEBUG
	if (NSZombieEnabled)
	{
		OOLog(@"debug.zombieEnabled", @"*** ZOMBIES WILL EAT YOUR BRAIN ***");
	}
#endif
	
	// Pixel Format Attributes for the View-based (non-FullScreen) NSOpenGLContext
	NSOpenGLPixelFormatAttribute attrs[] =
	{
		// Specify that we want a windowed OpenGL context.
		// Must be first or we'll hit an assert in the legacy fullscreen controller.
		NSOpenGLPFAWindow,
		
		// We may be on a multi-display system (and each screen may be driven by a different renderer), so we need to specify which screen we want to take over.
		// For this demo, we'll specify the main screen.
		NSOpenGLPFAScreenMask, CGDisplayIDToOpenGLDisplayMask(kCGDirectMainDisplay),
		
		// Specifying "NoRecovery" gives us a context that cannot fall back to the software renderer.
		// This makes the View-based context a compatible with the fullscreen context, enabling us to use the "shareContext"
		// feature to share textures, display lists, and other OpenGL objects between the two.
		NSOpenGLPFANoRecovery,
		
		// Attributes Common to FullScreen and non-FullScreen
		NSOpenGLPFACompliant,
		
		NSOpenGLPFAColorSize, 32,
		NSOpenGLPFADepthSize, 32,
		NSOpenGLPFADoubleBuffer,
		NSOpenGLPFAAccelerated,
#if FSAA
		// Need a preference or other sane way to activate this
		NSOpenGLPFAMultisample,
		NSOpenGLPFASampleBuffers, 1,
		NSOpenGLPFASamples,4,
#endif
		0
	};
	
	// Create our non-FullScreen pixel format.
	NSOpenGLPixelFormat *pixelFormat = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs] autorelease];
	
	if ((self = [super initWithFrame:frameRect pixelFormat:pixelFormat]))
	{
		if ([self respondsToSelector:@selector(setAcceptsTouchEvents:)])
		{
			[self setAcceptsTouchEvents:YES];
		}
		
		if ([self respondsToSelector:@selector(setWantsBestResolutionOpenGLSurface:)])
		{
			// Enable high resolution on Retina displays.
			[self setWantsBestResolutionOpenGLSurface:YES];
		}
		
		_pixelFormatAttributes = [[NSData alloc] initWithBytes:attrs length:sizeof attrs];
		virtualJoystickPosition = NSMakePoint(0.0,0.0);
		
		typedString = [[NSMutableString alloc] initWithString:@""];
		allowingStringInput = gvStringInputNo;
		isAlphabetKeyDown = NO;
			
		timeIntervalAtLastClick = [NSDate timeIntervalSinceReferenceDate];
		
		_virtualScreen = [[self openGLContext] currentVirtualScreen];
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(typedString);
	DESTROY(_pixelFormatAttributes);
	
	[super dealloc];
}


- (void) setStringInput:(enum StringInput)value
{
	allowingStringInput = value;
}


- (void) allowStringInput:(BOOL)value
{
	if (value)
	{
		allowingStringInput = gvStringInputAlpha;
	}
	else
	{
		allowingStringInput = gvStringInputNo;
	}
}

- (enum StringInput) allowingStringInput
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


- (void) setTypedString:(NSString *)value
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


- (GLfloat) x_offset
{
	return x_offset;
}


- (GLfloat) y_offset
{
	return y_offset;
}


- (GameController *) gameController
{
	return gameController;
}


- (void) setGameController:(GameController *) controller
{
	gameController = controller;
}


- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode
{
	UnapplyCursorState(oldMode);
	ApplyCursorState(newMode);
}


- (void) updateScreen
{
	if ([[self window] isVisible])
	{
		[self drawRect:NSMakeRect(0, 0, viewSize.width, viewSize.height)];
	}
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
		OOGL(glClearColor(0.0, 0.0, 0.0, 0.0));
		OOGL(glClear(GL_COLOR_BUFFER_BIT));
	}
	
	[[self openGLContext] flushBuffer];
}


- (void) noteMovedToBadDisplay
{
	NSRunInformationalAlertPanel(DESC(@"oolite-mac-bad-display"), @"%@", nil, nil, nil, DESC(@"oolite-mac-bad-display-2"));
}


- (void) update
{
	NSOpenGLContext *context = [self openGLContext];
	
	[context update];
	int virtualScreen = [context currentVirtualScreen];
	if (virtualScreen != _virtualScreen)
	{
		@try
		{
			[[OOGraphicsResetManager sharedManager] resetGraphicsState];
			_virtualScreen = virtualScreen;
		}
		@catch (NSException *exception)
		{
			/*	Graphics reset failed, most likely because of OpenGL context
				incompatibility. Reset to previous "virtual screen" (i.e.,
				renderer). OS X's OpenGL implementation will take care of
				copying 
			*/
			[context setCurrentVirtualScreen:_virtualScreen];
			[[OOGraphicsResetManager sharedManager] resetGraphicsState];	// If this throws, we're screwed.
			
			if ([[self gameController] inFullScreenMode])
			{
				[[self gameController] pauseFullScreenModeToPerform:@selector(noteMovedToBadDisplay) onTarget:self];
			}
			else
			{
				[self noteMovedToBadDisplay];
			}
		}
	}
}


- (void) initialiseGLWithSize:(NSSize)v_size
{
	viewSize = v_size;
	if (viewSize.width/viewSize.height > 4.0/3.0) {
		display_z = 480.0 * viewSize.width/viewSize.height;
		x_offset = 240.0 * viewSize.width/viewSize.height;
		y_offset = 240.0;
	} else {
		display_z = 640.0;
		x_offset = 320.0;
		y_offset = 320.0 * viewSize.height/viewSize.width;
	}
	
	if ([self respondsToSelector:@selector(convertSizeToBacking:)])
	{
		// High resolution mode support.
		v_size = [self convertSizeToBacking:v_size];
	}
	
	[self openGLContext];	// Force lazy setup if needed.
	[[self gameController] setUpBasicOpenGLStateWithSize:v_size];
	[[self openGLContext] flushBuffer];
	
	m_glContextInitialized = YES;
}


- (NSData *)pixelFormatAttributes
{
	return _pixelFormatAttributes;
}


#ifdef MAC_OS_X_VERSION_10_7	// If building against 10.7 SDK, where relevant symbols are defined...
- (void) viewDidMoveToWindow
{
	/*	Subscribe to NSWindowDidChangeBackingPropertiesNotification on systems
		which support it (10.7 and later). This notification fires when the
		scale factor or colour space of the window's backing store changes.
		We use it to track scale factor changes.
	*/
	if (&NSWindowDidChangeBackingPropertiesNotification != NULL && [self.window respondsToSelector:@selector(backingScaleFactor)])
	{
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(backingPropertiesChanged:)
													 name:NSWindowDidChangeBackingPropertiesNotification
												   object:self.window];
		
		// Also, ensure the initial state makes sense.
		[self backingPropertiesChanged:nil];
	}
}


- (void) backingPropertiesChanged:(NSNotification *)notification
{
	GLSetDisplayScaleFactor(self.window.backingScaleFactor);
}
#endif


- (BOOL) snapShot:(NSString *)filename
{
	BOOL snapShotOK = YES;
	int w = viewSize.width;
	int h = viewSize.height;
	
	if (w & 3)
		w = w + 4 - (w & 3);
	
	long nPixels = w * h + 1;	
	
	unsigned char   *red = (unsigned char *)malloc(nPixels);
	unsigned char   *green = (unsigned char *)malloc(nPixels);
	unsigned char   *blue = (unsigned char *)malloc(nPixels);
	
	// backup the previous directory
	NSString *originalDirectory = [[NSFileManager defaultManager] currentDirectoryPath];
	// use the snapshots directory
	NSString *snapshotsDirectory = [[[GameController sharedController] snapshotsURLCreatingIfNeeded:YES] path];
	if (![[NSFileManager defaultManager] changeCurrentDirectoryPath:snapshotsDirectory])
	{
		NSBeep();
		OOLog(@"savedSnapshot.defaultPath.chdir.failed", @"Could not navigate to %@", snapshotsDirectory);
		snapShotOK = NO;
		goto FAIL;
	}
	
	BOOL				withFilename = (filename != nil);
	static unsigned		imageNo = 0;
	unsigned			tmpImageNo = 0;
	NSString			*pathToPic = nil;
	NSString			*baseName = @"oolite";
	
	if (withFilename) 
	{
		baseName = filename;
		pathToPic = [filename stringByAppendingString:@".png"];
	}
	else
	{
		tmpImageNo = imageNo;
	}
	
	if (withFilename && [[NSFileManager defaultManager] fileExistsAtPath:pathToPic])
	{
		OOLog(@"screenshot.filenameExists", @"Snapshot \"%@.png\" already exists - adding numerical sequence.", pathToPic);
		pathToPic = nil;
	}
	
	if (pathToPic == nil) 
	{
		do
		{
			tmpImageNo++;
			pathToPic = [NSString stringWithFormat:@"%@-%03d.png", baseName, tmpImageNo];
		} while ([[NSFileManager defaultManager] fileExistsAtPath:pathToPic]);
	}
	
	if (!withFilename)
	{
		imageNo = tmpImageNo;
	}
	
	OOLog(@"screenshot", @"Saved screen shot \"%@\" (%u x %u pixels).", pathToPic, w, h);
	
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
		
	OOGL(glReadPixels(0,0, w,h, GL_RED,   GL_UNSIGNED_BYTE, red));
	OOGL(glReadPixels(0,0, w,h, GL_GREEN, GL_UNSIGNED_BYTE, green));
	OOGL(glReadPixels(0,0, w,h, GL_BLUE,  GL_UNSIGNED_BYTE, blue));
	
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
	
FAIL:
	free(red);
	free(green);
	free(blue);
	
	// return to the previous directory
	[[NSFileManager defaultManager] changeCurrentDirectoryPath:originalDirectory];
	return snapShotOK;
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
	
	supressKeys = NO;
	
	keycode = [theEvent keyCode] & 255;
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
	
	/*	HACK: treat f12 as alias to cmd-F for compatibility with helpful forum
		advice etc.
	*/
	if (key == NSF12FunctionKey)
	{
		commandF = NO;
		f12 = NO;
		return;
	};
	
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
	
	/*	HACK: treat f12 as alias to cmd-F for compatibility with helpful forum
		advice etc.
	*/
	if (key == NSF12FunctionKey)
	{
		if (!f12)
		{
			f12 = YES;
			[gameController performSelector:@selector(toggleFullScreenAction:) withObject:nil afterDelay:0.0];
		}
		
		return;
	};
	
	if ((key >= 0)&&(key < [self numKeys])&&(!keys[key]))
	{
		keys[key] = YES;
		
		if (allowingStringInput)
		{
			if ((key == gvDeleteKey) && [typedString length] > 0)
			{
				// delete
				[typedString deleteCharactersInRange:NSMakeRange([typedString length] - 1, 1)];
			}

			isAlphabetKeyDown = NO;

			// limited input for planet find screen
			if (allowingStringInput == gvStringInputAlpha)
			{
				if (isalpha(key))
				{
					isAlphabetKeyDown = YES;
					// convert to lower case
					[typedString appendFormat:@"%c", tolower(key)];
				}
			}
			
			// full input for load-save screen or 'all' input
			if (allowingStringInput >= gvStringInputLoadSave)
			{
				// except '/' for loadsave
				if (isprint(key) && key != '/')
				{
					isAlphabetKeyDown = YES;
					[typedString appendFormat:@"%c", key];
				}
				else if (key == '/' && allowingStringInput == gvStringInputAll)
				{
					isAlphabetKeyDown = YES;
					[typedString appendFormat:@"%c", key];
				}
			}
			
		}
	}
	else
	{
		if (key > [self numKeys])
		{
			OOLog(kOOLogKeyCodeOutOfRange, @"Translated key: %d out of range", key);
		}
	}
} 

/* Capture shift, ctrl, opt and command press & release */
- (void)flagsChanged:(NSEvent *)theEvent
{
	NSUInteger flags = [theEvent modifierFlags];
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


- (void) mouseDragged:(NSEvent *)theEvent
{
	[self mouseMoved:theEvent];
}


- (void) otherMouseDragged:(NSEvent *)theEvent
{
	[self mouseMoved:theEvent];
}


- (void) rightMouseDown:(NSEvent *)theEvent
{
	[self recenterVirtualJoystick];
}


- (void) rightMouseUp:(NSEvent *)theEvent
{
	[self recenterVirtualJoystick];
}


- (void) touchesEndedWithEvent:(NSEvent *)theEvent
{
	[self recenterVirtualJoystick];
}


- (void) recenterVirtualJoystick
{
	if ([PLAYER guiScreen] == GUI_SCREEN_MAIN)
	{
		[[GameController sharedController] recenterVirtualJoystick];
	}
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
			
		case NSDeleteCharacter:
			key = gvDeleteKey;
			break;
			
		case NSInsertFunctionKey:
			key = gvInsertKey;
			break;
			
		case NSEndFunctionKey:
			key = gvEndKey;
			break;
			
		case NSPageUpFunctionKey:
			key = gvPageUpKey;
			break;
			
		case NSPageDownFunctionKey:
			key = gvPageDownKey;
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


- (void) clearKey: (int)theKey
{
	if (theKey >= 0 && theKey < [self numKeys])
	{
		keys[theKey] = NO;
	}
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


+ (BOOL)pollShiftKey
{
	#define KEYMAP_GET(m, index) ((((uint8_t*)(m))[(index) >> 3] & (1L << ((index) & 7))) ? 1 : 0)
	
	KeyMap				map;
	
	GetKeys(map);
	return KEYMAP_GET(map, 56) || KEYMAP_GET(map, 60);	// Left shift or right shift -- although 60 shouldn't occur.
}


#ifndef NDEBUG
// General image-dumping method.
- (void) dumpRGBAToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 4)  return;
	
	NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bytes
																	   pixelsWide:width
																	   pixelsHigh:height
																	bitsPerSample:8
																  samplesPerPixel:4
																		 hasAlpha:YES
																		 isPlanar:NO
																   colorSpaceName:NSCalibratedRGBColorSpace
																	  bytesPerRow:rowBytes
																	 bitsPerPixel:32];
	
	if (bitmap != nil)
	{
		[bitmap autorelease];
		
		NSString *filepath = [[[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
		[[bitmap representationUsingType:NSPNGFileType properties:nil] writeToFile:filepath atomically:YES];
	}
}

- (void) dumpRGBToFileNamed:(NSString *)name
					  bytes:(uint8_t *)bytes
					  width:(NSUInteger)width
					 height:(NSUInteger)height
				   rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 3)  return;
	
	NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bytes
																	   pixelsWide:width
																	   pixelsHigh:height
																	bitsPerSample:8
																  samplesPerPixel:3
																		 hasAlpha:NO
																		 isPlanar:NO
																   colorSpaceName:NSCalibratedRGBColorSpace
																	  bytesPerRow:rowBytes
																	 bitsPerPixel:24];
	
	if (bitmap != nil)
	{
		[bitmap autorelease];
		
		NSString *filepath = [[[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
		[[bitmap representationUsingType:NSPNGFileType properties:nil] writeToFile:filepath atomically:YES];
	}
}


- (void) dumpGrayToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width)  return;
	
	NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bytes
																	   pixelsWide:width
																	   pixelsHigh:height
																	bitsPerSample:8
																  samplesPerPixel:1
																		 hasAlpha:NO
																		 isPlanar:NO
																   colorSpaceName:NSCalibratedWhiteColorSpace
																	  bytesPerRow:rowBytes
																	 bitsPerPixel:8];
	
	if (bitmap != nil)
	{
		[bitmap autorelease];
		
		NSString *filepath = [[[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
		[[bitmap representationUsingType:NSPNGFileType properties:nil] writeToFile:filepath atomically:YES];
	}
}


- (void) dumpGrayAlphaToFileNamed:(NSString *)name
							bytes:(uint8_t *)bytes
							width:(NSUInteger)width
						   height:(NSUInteger)height
						 rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 2)  return;
	
	NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bytes
																	   pixelsWide:width
																	   pixelsHigh:height
																	bitsPerSample:8
																  samplesPerPixel:2
																		 hasAlpha:YES
																		 isPlanar:NO
																   colorSpaceName:NSCalibratedWhiteColorSpace
																	  bytesPerRow:rowBytes
																	 bitsPerPixel:16];
	
	if (bitmap != nil)
	{
		[bitmap autorelease];
		
		NSString *filepath = [[[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
		[[bitmap representationUsingType:NSPNGFileType properties:nil] writeToFile:filepath atomically:YES];
	}
}


- (void) dumpRGBAToRGBFileNamed:(NSString *)rgbName
			   andGrayFileNamed:(NSString *)grayName
						  bytes:(uint8_t *)bytes
						  width:(NSUInteger)width
						 height:(NSUInteger)height
					   rowBytes:(NSUInteger)rowBytes
{
	if ((rgbName == nil && grayName == nil) || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 4)  return;
	
	uint8_t				*rgbBytes, *rgbPx, *grayBytes, *grayPx, *srcPx;
	NSUInteger			x, y;
	BOOL				trivalAlpha = YES;
	
	rgbPx = rgbBytes = malloc(width * height * 3);
	if (rgbBytes == NULL)  return;
	
	grayPx = grayBytes = malloc(width * height);
	if (grayBytes == NULL)
	{
		free(rgbBytes);
		return;
	}
	
	for (y = 0; y < height; y++)
	{
		srcPx = bytes + rowBytes * y;
		
		for (x = 0; x < width; x++)
		{
			*rgbPx++ = *srcPx++;
			*rgbPx++ = *srcPx++;
			*rgbPx++ = *srcPx++;
			trivalAlpha = trivalAlpha && ((*srcPx == 0xFF) || (*srcPx == 0x00));	// Look for any "interesting" pixels in alpha.
			*grayPx++ = *srcPx++;
		}
	}
	
	[self dumpRGBToFileNamed:rgbName
					   bytes:rgbBytes
					   width:width
					  height:height
					rowBytes:width * 3];
	free(rgbBytes);
	
	if (!trivalAlpha)
	{
		[self dumpGrayToFileNamed:grayName
							bytes:grayBytes
							width:width
						   height:height
						 rowBytes:width];
	}
	free(grayBytes);
}

#endif


static void GetDesiredCursorState(OOMouseInteractionMode mode, BOOL *outHidden, BOOL *outObscured)
{
	NSCParameterAssert(outHidden != NULL && outObscured != NULL);
	
	*outHidden = (mode == MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL);
	*outObscured = (mode == MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL);
}


static void ApplyCursorState(OOMouseInteractionMode mode)
{
	BOOL hidden, obscured;
	GetDesiredCursorState(mode, &hidden, &obscured);
	if (hidden)  [NSCursor hide];
	if (obscured)  [NSCursor setHiddenUntilMouseMoves:YES];
}


static void UnapplyCursorState(OOMouseInteractionMode mode)
{
	BOOL hidden, obscured;
	GetDesiredCursorState(mode, &hidden, &obscured);
	if (hidden)  [NSCursor unhide];
	if (obscured)  [NSCursor setHiddenUntilMouseMoves:NO];
}


- (void) setGammaValue: (float) value
{
	// no-op
}

- (float) gammaValue
{
	return 1.0;
}

@end
