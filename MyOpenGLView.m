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
//#import <OpenGL/glext.h>

#import "MyOpenGLView.h"

#import "GameController.h"
//#import "AppDelegate.h"
#import "Universe.h"
#import "TextureStore.h"
#import "Entity.h"
#import "PlanetEntity.h"
#import "OpenGLSprite.h"
#import "ResourceManager.h"

@interface MyOpenGLView(Internal)

- (int) translateKeyCode: (int) input;

@end


@implementation MyOpenGLView

- (id) initWithFrame:(NSRect)frameRect
{
	//NSLog(@"-- initWithFrame MyOpenGLView");
	
	// Pixel Format Attributes for the View-based (non-FullScreen) NSOpenGLContext
    NSOpenGLPixelFormatAttribute attrs[] = {

        // Specifying "NoRecovery" gives us a context that cannot fall back to the software renderer.
		//This makes the View-based context a compatible with the fullscreen context, enabling us to use the "shareContext"
		// feature to share textures, display lists, and other OpenGL objects between the two.
        NSOpenGLPFANoRecovery,

        // Attributes Common to FullScreen and non-FullScreen
        NSOpenGLPFAColorSize, 32,
        NSOpenGLPFADepthSize, 32,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        0
    };
    long rendererID;

    // Create our non-FullScreen pixel format.
    NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];

    // Just as a diagnostic, report the renderer ID that this pixel format binds to.  CGLRenderers.h contains a list of known renderers
	// and their corresponding RendererID codes.
    [pixelFormat getValues:&rendererID forAttribute:NSOpenGLPFARendererID forVirtualScreen:0];
    //NSLog(@" init! NSOpenGLView pixelFormat RendererID = %08x", (unsigned)rendererID);

    self = [super initWithFrame:frameRect pixelFormat:pixelFormat];

	virtualJoystickPosition = NSMakePoint(0.0,0.0);
	
	typedString = [[NSMutableString alloc] initWithString:@""];
	allowingStringInput = NO;
	isAlphabetKeyDown = NO;
		
    return self;
}

- (void) dealloc
{
	if (typedString)
		[typedString release];
	[super dealloc];
}

- (void) allowStringInput: (BOOL) value
{
	allowingStringInput = value;
}

-(BOOL) allowingStringInput
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

- (void)drawRect:(NSRect)rect
{    
//	AppDelegate	*deleg = (AppDelegate *)[NSApp delegate];
	
	if ((viewSize.width != [self frame].size.width)||(viewSize.height != [self frame].size.height)) // resized
	{
		m_glContextInitialized = NO;
		viewSize = [self frame].size;
		
		//NSLog(@"DEBUG resized to %.0f x %.0f", viewSize.width, viewSize.height);
	}
	
    if (!m_glContextInitialized)
		[self initialiseGLWithSize:viewSize];
    
	// do all the drawing!
	//
	if ([gameController universe])
		[[gameController universe] drawFromEntity:0];
	else
	{
		// not set up yet, draw a black screen
		glClearColor( 0.0, 0.0, 0.0, 0.0);
		glClear( GL_COLOR_BUFFER_BIT);
	}
    //
	////
	
	[[self openGLContext] flushBuffer];
}

- (void) initialiseGLWithSize:(NSSize) v_size
{
//	AppDelegate	*deleg = (AppDelegate *)[NSApp delegate];
	GLfloat	sun_ambient[] =	{0.1, 0.1, 0.1, 1.0};
	GLfloat	sun_diffuse[] =	{1.0, 1.0, 1.0, 1.0};
	GLfloat	sun_specular[] = 	{1.0, 1.0, 1.0, 1.0};
	GLfloat	sun_center_position[] = {4000000.0, 0.0, 0.0, 1.0};

	viewSize = v_size;
	if (viewSize.width/viewSize.height > 4.0/3.0)
		display_z = 480.0 * viewSize.width/viewSize.height;
	else
		display_z = 640.0;
		
//	NSLog(@">>>>> display_z = %.1f", display_z);
	
	float	ratio = 0.5;
	float   aspect = viewSize.height/viewSize.width;
	
	glShadeModel(GL_FLAT);
	glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    [[self openGLContext] flushBuffer];
	
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
		Vector sun_pos = [[[gameController universe] sun] getPosition];
		sun_center_position[0] = sun_pos.x;
		sun_center_position[1] = sun_pos.y;
		sun_center_position[2] = sun_pos.z;
	}
	
	glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
	glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);
	glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
	glLightfv(GL_LIGHT1, GL_POSITION, sun_center_position);

	glEnable(GL_LIGHTING);		// lighting
	glEnable(GL_LIGHT1);		// lighting
	
	// world's simplest OpenGL optimisations...
	glHint(GL_TRANSFORM_HINT_APPLE, GL_FASTEST);
	glDisable(GL_NORMALIZE);
	glDisable(GL_RESCALE_NORMAL);
		
	m_glContextInitialized = YES;
}

- (void) snapShot
{
    //NSRect boundsRect = [self bounds];
    int w = viewSize.width;
    int h = viewSize.height;
	
	if (w & 3)
		w = w + 4 - (w & 3);
	
    long nPixels = w * h + 1;	

	unsigned char   *red = (unsigned char *) malloc( nPixels);
	unsigned char   *green = (unsigned char *) malloc( nPixels);
	unsigned char   *blue = (unsigned char *) malloc( nPixels);
	
	NSString	*filepath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
	int imageNo = 1;

   // In the GNUstep source, representationUsingType is marked as
   // TODO: and does nothing but return NIL! So for GNUstep we fall
   // back to the methods used in oolite 1.30.
#ifdef GNUSTEP
	NSString	*pathToPic = 
      [filepath stringByAppendingPathComponent:
         [NSString stringWithFormat:@"oolite-%03d.tiff",imageNo]];
	while ([[NSFileManager defaultManager] fileExistsAtPath:pathToPic])
	{
		imageNo++;
		pathToPic = [filepath stringByAppendingPathComponent:[NSString stringWithFormat:@"oolite-%03d.tiff",imageNo]];
	}
#else   
	NSString	*pathToPic = [filepath stringByAppendingPathComponent:[NSString stringWithFormat:@"oolite-%03d.png",imageNo]];
		
	while ([[NSFileManager defaultManager] fileExistsAtPath:pathToPic])
	{
		imageNo++;
		pathToPic = [filepath stringByAppendingPathComponent:[NSString stringWithFormat:@"oolite-%03d.png",imageNo]];
	}
	
   NSString	*pathToPng = [[pathToPic stringByDeletingPathExtension] stringByAppendingPathExtension:@"png"];
#endif
	
	NSLog(@">>>>> Snapshot %d x %d file path chosen = %@", w, h, pathToPic);
	
    NSBitmapImageRep* bitmapRep = 
        [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:	nil		// --> let the class allocate it
            pixelsWide:			w
            pixelsHigh:			h
            bitsPerSample:		8		// each component is 8 bits (1 byte)
            samplesPerPixel:	3		// number of components (R, G, B)
            hasAlpha:			NO		// no transparency
            isPlanar:			NO		// data integrated into single plane
            colorSpaceName:		NSDeviceRGBColorSpace
            bytesPerRow:		0		// --> let the class figure it out
            bitsPerPixel:		0		// --> let the class figure it out
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
	
//	[[bitmapRep representationUsingType:NSTIFFFileType properties:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:NSTIFFCompressionNone], NSImageCompressionMethod, NULL]]
//		writeToFile:pathToTiff atomically:YES];			// save TIFF representation of Image
//	
//	[[bitmapRep representationUsingType:NSJPEGFileType properties:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:0.75], NSImageCompressionFactor, NULL]]
//		writeToFile:pathToJpeg atomically:YES];			// save JPEG representation of Image
#ifdef GNUSTEP
   NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(w,h)];
   [image addRepresentation:bitmapRep];
   [[image TIFFRepresentation] writeToFile:pathToPic atomically:YES];
   [image release];
#else
	[[bitmapRep representationUsingType:NSPNGFileType properties:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSImageInterlaced, NULL]]
		writeToFile:pathToPng atomically:YES];			// save PNG representation of Image
#endif
	
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

//- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
//{
//	if ([gameController inFullScreenMode])
//	{
//		NSLog(@"DEBUG [gameController inFullScreenMode] MyOpenGLView trying to performKeyEquivalent:%@", [theEvent description]);
//		return YES;	// simply ignores KeyEquivalent requests which would otherwise be passed to the main menu
//	}
//	else
//	{
////		NSLog(@"DEBUG [gameController in windowed mode] MyOpenGLView trying to performKeyEquivalent:%@", [theEvent description]);
//		return [super performKeyEquivalent: theEvent];
//	}
//}

- (void) keyUp:(NSEvent *)theEvent
{
	int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
	int keycode = [theEvent keyCode] & 255;
	
//	NSLog(@"DEBUG keyUp [theEvent charactersIgnoringModifiers] = %@ keyCode = %d",[theEvent charactersIgnoringModifiers],[theEvent keyCode]);
	
	//key = [self translateKeyCode: key];
	key = keycodetrans[keycode];	// retrieve the character we got for pressing the hardware at key location 'keycode'
	
	isAlphabetKeyDown = NO;
	if ( key >= 0 && key < [self numKeys] )
	{
		keys[key] = NO;
	}
	else
	{
		NSLog(@"***** translated key: %d out of range\n", key);
	}
}

- (void) keyDown:(NSEvent *)theEvent
{
	int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
	int keycode = [theEvent keyCode] & 255;
	
//	NSLog(@"DEBUG keyDown [theEvent charactersIgnoringModifiers] = %@ keyCode = %d",[theEvent charactersIgnoringModifiers],[theEvent keyCode]);
	
	key = [self translateKeyCode: key];
	
	keycodetrans[keycode] = key;	// record the chracter we got for pressing the hardware at key location 'keycode'
	
	if ((key >= 0)&&(key < [self numKeys]))
	{
		//NSLog( @"key : %d", key );
		keys[key] = YES;
		
		if (allowingStringInput)
		{
			if (((key > 64)&&(key < 91))||((key > 96)&&(key < 123)))
			{
				// alphanumeric
				isAlphabetKeyDown = YES;
				// convert to lowercase
				[typedString appendFormat:@"%c", (key | 64)];
				//NSLog(@"accumulated string '%@'",typedString);
			}
			else
				isAlphabetKeyDown = NO;
			if (key == NSDeleteCharacter)
			{
				//delete
				[typedString setString:@""];
			}
		}
	}
	else
	{
		NSLog(@"***** translated key: %d out of range\n", key);
	}
} 

/*     Capture shift, ctrl, opt and command press & release */
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
    keys[gvMouseLeftButton] = YES; // 'a' down
}

- (void)mouseUp:(NSEvent *)theEvent
{
	keys[gvMouseLeftButton] = NO;  // 'a' up
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    squareX = [theEvent locationInWindow].x - mouseDragStartPoint.x;
    squareY = [theEvent locationInWindow].y - mouseDragStartPoint.y;
    [self setNeedsDisplay:YES];
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

- (BOOL) isAlphabetKeyDown
{
	return isAlphabetKeyDown = NO;;
}

- (BOOL) isDown: (int) key
{
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

@end

