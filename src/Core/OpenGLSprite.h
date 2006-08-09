//
//  OpenGLSprite.h
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

#import "OOCocoa.h"
#import "OOOpenGL.h"

#ifdef GNUSTEP
#import "SDLImage.h"
#endif

#define	OPEN_GL_SPRITE_MIN_WIDTH	64.0
#define	OPEN_GL_SPRITE_MIN_HEIGHT	64.0

extern int debug;

@interface OpenGLSprite : NSObject {

    NSData*	textureData;
    GLuint	texName;

    NSRect	textureCropRect;
    NSSize	textureSize;
    NSSize	size;
}



- (id) init;
- (id) initWithTextureName:(GLuint) textureName andSize:(NSSize) spriteSize;
#ifndef GNUSTEP
- (id) initWithImage:(NSImage *)textureImage cropRectangle:(NSRect)cropRect size:(NSSize) spriteSize;
- (id) initWithText:(NSString *)str;
- (id) initWithText:(NSString *)str ofColor:(NSColor *) textColor;
#endif
- (void) dealloc;

- (NSSize)  size;

- (void)blitToX:(float)x Y:(float)y Z:(float)z Alpha:(float)a;
- (void)blitCentredToX:(float)x Y:(float)y Z:(float)z Alpha:(float)a;

- (void) setText:(NSString *)str;
#ifndef GNUSTEP
- (void)makeTextureFromImage:(NSImage *)texImage cropRectangle:(NSRect)cropRect size:(NSSize)spriteSize;

- (void)replaceTextureFromImage:(NSImage *)texImage cropRectangle:(NSRect)cropRect;
- (void)substituteTextureFromImage:(NSImage *)texImage;
#endif

#ifdef GNUSTEP
- (id) initWithSurface:(SDLImage *)textureImage cropRectangle:(NSRect)cropRect size:(NSSize) spriteSize;
- (void)makeTextureFromSurface:(SDLImage *)texImage cropRectangle:(NSRect)cropRect size:(NSSize)spriteSize;
#endif

@end
