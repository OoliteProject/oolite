/*

OpenGLSprite.h
Created by Giles Williams on 2004-04-03.

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
