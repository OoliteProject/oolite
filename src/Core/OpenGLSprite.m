/*

OpenGLSprite.m
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

#import "OpenGLSprite.h"
#import "OOColor.h"


@implementation OpenGLSprite

- (id) init
{
    self = [super init];
    return self;
}

- (id) initWithTextureName:(GLuint) textureName andSize:(NSSize) spriteSize
{
    self = [super init];
	
	textureData = nil;
	texName = textureName;
	size = spriteSize;
	
	textureCropRect = NSMakeRect( 0.0, 0.0, 1.0, 1.0);
	
    return self;
}

#ifndef GNUSTEP
- (id) initWithImage:(NSImage *)textureImage cropRectangle:(NSRect)cropRect size:(NSSize) spriteSize
{
    self = [super init];
    [self makeTextureFromImage:textureImage cropRectangle:cropRect size:spriteSize];
    return self;

}

- (id) initWithText:(NSString *)str
{
    return [self initWithText:str ofColor:[NSColor yellowColor]];
}

- (id) initWithText:(NSString *)str ofColor:(NSColor *) textColor
{
    NSImage	*image;
    NSSize	strsize;
    NSMutableDictionary *stringAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSFont fontWithName:@"ArialNarrow-Bold" size:18], NSFontAttributeName,
        [NSColor blackColor], NSForegroundColorAttributeName, NULL];

    strsize = [str sizeWithAttributes:stringAttributes];
    strsize.width += 3;
    strsize.height += 1;

    image= [[NSImage alloc] initWithSize:strsize];
    [image lockFocus];
    [stringAttributes setObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];	
    [str drawAtPoint:NSMakePoint(2,0) withAttributes:stringAttributes];
    [stringAttributes setObject:textColor forKey:NSForegroundColorAttributeName];	
    [str drawAtPoint:NSMakePoint(1,1) withAttributes:stringAttributes];
    [image unlockFocus];

    self = [super init];
    [self makeTextureFromImage:image cropRectangle:NSMakeRect(0, 0, [image size].width, [image size].height) size:[image size]];
    
	[image release];
	
    return self;
}
#endif

- (void) dealloc
{
	if (nil != textureData)
	{
		glDeleteTextures(1, &texName);	// clean up the texture from the 3d card's memory
		[textureData release];
	}
	
    [super dealloc];
}

- (NSSize) size
{
	return size;
}

- (void)blitToX:(float)x Y:(float)y Z:(float)z Alpha:(float)a
{
    if (a < 0.0)
        a = 0.0;	// clamp the alpha value
    if (a > 1.0)
        a = 1.0;	// clamp the alpha value
    glEnable(GL_TEXTURE_2D);
    glColor4f(1.0, 1.0, 1.0, a);
    
    // Note that the textured Quad is drawn ACW from the Top Left
    
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
    glBindTexture(GL_TEXTURE_2D, texName);
    glBegin(GL_QUADS);

    glTexCoord2f(0.0, 1.0-textureCropRect.size.height);
    glVertex3f(x, y+size.height, z);

    glTexCoord2f(0.0, 1.0);
    glVertex3f(x, y, z);

    glTexCoord2f(textureCropRect.size.width, 1.0);
    glVertex3f(x+size.width, y, z);

    glTexCoord2f(textureCropRect.size.width, 1.0-textureCropRect.size.height);
    glVertex3f(x+size.width, y+size.height, z);

    glEnd();
    glDisable(GL_TEXTURE_2D);
}

- (void)blitCentredToX:(float)x Y:(float)y Z:(float)z Alpha:(float)a
{
    float	xs = x - size.width / 2.0;
    float	ys = y - size.height / 2.0;
    [self blitToX:xs Y:ys Z:z Alpha:a];
}

- (void) setText:(NSString *)str
{
#ifndef GNUSTEP
	// TODO: merge implementation with initWithText:ofColor: (let both use a setText:ofColor:) -- Jens
    NSImage	*image;
    NSSize	strsize;

    NSMutableDictionary *stringAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSFont fontWithName:@"ArialNarrow-Bold" size:18], NSFontAttributeName,
        [NSColor blackColor], NSForegroundColorAttributeName, NULL];
        
    strsize = [str sizeWithAttributes:stringAttributes];
    strsize.width += 3;
    strsize.height += 1;

    image= [[NSImage alloc] initWithSize:strsize];
    [image lockFocus];
    [stringAttributes setObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];	
    [str drawAtPoint:NSMakePoint(2,0) withAttributes:stringAttributes];
    [stringAttributes setObject:[NSColor yellowColor] forKey:NSForegroundColorAttributeName];	
    [str drawAtPoint:NSMakePoint(1,1) withAttributes:stringAttributes];
    [image unlockFocus];

    self = [super init];
    [self makeTextureFromImage:image cropRectangle:NSMakeRect(0, 0, [image size].width, [image size].height) size:[image size]];
    
	[image release];
	
    //
    //NSLog(@"%@ message sprite [ %f, %f ]", str, [image size].width, [image size].height);
    //
#endif
}

#ifndef GNUSTEP
- (void)makeTextureFromImage:(NSImage *)texImage cropRectangle:(NSRect)cropRect size:(NSSize)spriteSize
{
    NSBitmapImageRep*	bitmapImageRep;
    NSRect		textureRect = NSMakeRect(0.0,0.0,OPEN_GL_SPRITE_MIN_WIDTH,OPEN_GL_SPRITE_MIN_HEIGHT);
    NSImage*		image;

    if (!texImage)
        return;

    size = spriteSize;
    textureCropRect = cropRect;

    while (textureRect.size.width < cropRect.size.width)
        textureRect.size.width *= 2;
    while (textureRect.size.height < cropRect.size.height)
        textureRect.size.height *= 2;
    
    textureRect.origin= NSMakePoint(0,0);
    textureCropRect.origin= NSMakePoint(0,0);

    textureSize = textureRect.size;

    image = [[NSImage alloc] initWithSize:textureRect.size];	// retained

    [image lockFocus];
    [[NSColor clearColor] set];
    NSRectFill(textureRect);
    [texImage drawInRect:textureCropRect fromRect:cropRect operation:NSCompositeSourceOver fraction:1.0];
    bitmapImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:textureRect];	// retained
    [image unlockFocus];

    [image release];											// released
    // normalise textureCropRect size to 0.0 -> 1.0
    textureCropRect.size.width /= textureRect.size.width;
    textureCropRect.size.height /= textureRect.size.height;

	int n_bytes = 4 * textureRect.size.width * textureRect.size.height;
	
    if (textureData)
        [textureData release];
    textureData = [[NSData dataWithBytes:[bitmapImageRep bitmapData] length:n_bytes] retain];
    [bitmapImageRep release];															// released
    
    if (texName !=0)
    {
        const GLuint	delTextures[1] = { texName };
        glDeleteTextures(1, delTextures);
        texName = 0;	// clean up the texture from the 3d card's memory
    }    
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glGenTextures(1, &texName);			// get a new unique texture name
    glBindTexture(GL_TEXTURE_2D, texName);	// initialise it

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureRect.size.width, textureRect.size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, [textureData bytes]);

}

- (void)replaceTextureFromImage:(NSImage *)texImage cropRectangle:(NSRect)cropRect
{
    NSBitmapImageRep*	bitmapImageRep;
    NSRect		textureRect = NSMakeRect(0.0,0.0,OPEN_GL_SPRITE_MIN_WIDTH,OPEN_GL_SPRITE_MIN_HEIGHT);
    NSImage*		image;

    if (!texImage)
        return;

    textureCropRect = cropRect;

    // correct size for texture to a power of two
    while (textureRect.size.width < cropRect.size.width)
        textureRect.size.width *= 2;
    while (textureRect.size.height < cropRect.size.height)
        textureRect.size.height *= 2;

    if ((textureRect.size.width != textureSize.width)||(textureRect.size.height != textureSize.height))
    {
        NSLog(@"***** ERROR! replacement texture isn't the same size as original texture");
        NSLog(@"***** cropRect %f x %f textureSize %f x %f",textureRect.size.width, textureRect.size.height, textureSize.width, textureSize.height);
        return;
    }

    textureRect.origin= NSMakePoint(0,0);
    textureCropRect.origin= NSMakePoint(0,0);

    image = [[NSImage alloc] initWithSize:textureRect.size];

    [image lockFocus];
    [[NSColor clearColor] set];
    NSRectFill(textureRect);
    [texImage drawInRect:textureCropRect fromRect:cropRect operation:NSCompositeSourceOver fraction:1.0];
    bitmapImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:textureRect];
    [image unlockFocus];

    [image release];
    // normalise textureCropRect size to 0.0 -> 1.0
    textureCropRect.size.width /= textureRect.size.width;
    textureCropRect.size.height /= textureRect.size.height;

    if (textureData)
        [textureData autorelease];
    textureData = [[NSData dataWithBytes:[bitmapImageRep bitmapData] length:textureSize.width*textureSize.height*4] retain];
    [bitmapImageRep release];

    glBindTexture(GL_TEXTURE_2D, texName);

    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, textureSize.width, textureSize.height, GL_RGBA, GL_UNSIGNED_BYTE, [textureData bytes]);

}

- (void)substituteTextureFromImage:(NSImage *)texImage
{
    NSBitmapImageRep*	bitmapImageRep;
    NSRect		cropRect = NSMakeRect(0.0,0.0,[texImage size].width,[texImage size].height);
    NSRect		textureRect = NSMakeRect(0.0,0.0,textureSize.width,textureSize.height);
    NSImage*		image;

    if (!texImage)
        return;

    image = [[NSImage alloc] initWithSize:textureSize];

    [image lockFocus];
    [[NSColor clearColor] set];
    NSRectFill(textureRect);
    [texImage drawInRect:textureRect fromRect:cropRect operation:NSCompositeSourceOver fraction:1.0];
    bitmapImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:textureRect];
    [image unlockFocus];

    [image release];
	
    // normalise textureCropRect size to 0.0 -> 1.0
    textureCropRect = NSMakeRect(0.0,0.0,1.0,1.0);

    if ([bitmapImageRep bitsPerPixel]==32)
    {
        if (textureData)
            [textureData autorelease];
        textureData = [[NSData dataWithBytes:[bitmapImageRep bitmapData] length:textureSize.width*textureSize.height*4] retain];

        glBindTexture(GL_TEXTURE_2D, texName);

        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, textureSize.width, textureSize.height, GL_RGBA, GL_UNSIGNED_BYTE, [textureData bytes]);
    }
    else if ([bitmapImageRep bitsPerPixel]==24)
    {
        if (textureData)
            [textureData autorelease];
        textureData = [[NSData dataWithBytes:[bitmapImageRep bitmapData] length:textureSize.width*textureSize.height*3] retain];

        glBindTexture(GL_TEXTURE_2D, texName);

        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, textureSize.width, textureSize.height, GL_RGB, GL_UNSIGNED_BYTE, [textureData bytes]);
    }
    [bitmapImageRep release];
}

#endif

#ifdef GNUSTEP
/* SDL interprets each pixel as a 32-bit number, so our masks must depend
   on the endianness (byte order) of the machine */
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
enum
{
	rmask = 0xff000000UL,
	gmask = 0x00ff0000UL,
	bmask = 0x0000ff00UL,
	amask = 0x000000ffUL
};
#else
enum
{
	rmask = 0x000000ffUL,
	gmask = 0x0000ff00UL,
	bmask = 0x00ff0000UL,
	amask = 0xff000000UL
};
#endif


- (id) initWithSurface:(SDLImage *)textureImage cropRectangle:(NSRect)cropRect size:(NSSize) spriteSize
{
    self = [super init];
    [self makeTextureFromSurface:textureImage cropRectangle:cropRect size:spriteSize];
    return self;
}

- (void)makeTextureFromSurface:(SDLImage *)texImage cropRectangle:(NSRect)cropRect size:(NSSize)spriteSize
{
    //NSBitmapImageRep *bitmapImageRep;
    NSRect textureRect = NSMakeRect(0.0,0.0,OPEN_GL_SPRITE_MIN_WIDTH,OPEN_GL_SPRITE_MIN_HEIGHT);
    SDL_Surface *surface;

    if (!texImage)
        return;

    SDL_Surface *texSurface = [texImage surface];
    SDL_SetAlpha(texSurface, 0, SDL_ALPHA_OPAQUE);
    //NSLog(@"makeTextureFromSurface: texImage dimensions: %d x %d", texSurface->w, texSurface->h);

    size = spriteSize;
    textureCropRect = cropRect;

    while (textureRect.size.width < cropRect.size.width)
        textureRect.size.width *= 2;
    while (textureRect.size.height < cropRect.size.height)
        textureRect.size.height *= 2;
    
    textureRect.origin= NSMakePoint(0,0);
    textureCropRect.origin= NSMakePoint(0,0);

    textureSize = textureRect.size;

    //image = [[NSImage alloc] initWithSize:textureRect.size];	// retained
    //NSLog(@"makeTextureFromSurface: texture surface dimensions: %d x %d", (int)textureRect.size.width, (int)textureRect.size.height);
    surface = SDL_CreateRGBSurface(SDL_SWSURFACE, (int)textureRect.size.width, (int)textureRect.size.height, 32, rmask, gmask, bmask, amask);

    //[image lockFocus];
    //[[OOColor clearColor] set];
    //NSRectFill(textureRect);
    SDL_FillRect(surface, (SDL_Rect *)0x00, SDL_MapRGBA(surface->format, 0, 0, 0, SDL_ALPHA_TRANSPARENT));

    //[texImage drawInRect:textureCropRect fromRect:cropRect operation:NSCompositeSourceOver fraction:1.0];
    //bitmapImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:textureRect];	// retained
    //[image unlockFocus];

    SDL_Rect srcRect, destRect;
   	srcRect.x = (int)cropRect.origin.x; srcRect.y = (int)cropRect.origin.y; srcRect.w = (int)cropRect.size.width; srcRect.h = (int)cropRect.size.height;
   	destRect.x = 0; destRect.y = 0;
    SDL_BlitSurface(texSurface, &srcRect, surface, &destRect);
    //NSLog(@"destRect x: %d, y: %d, w: %d, h: %d", destRect.x, destRect.y, destRect.w, destRect.h);

    //[image release]; // released

    // normalise textureCropRect size to 0.0 -> 1.0
    textureCropRect.size.width /= textureRect.size.width;
    textureCropRect.size.height /= textureRect.size.height;

//	int n_bytes = surface->format->BytesPerPixel * surface->w * surface->h;
	//unsigned char *buffer = malloc(n_bytes);
	SDL_LockSurface(surface);
	//memcpy(buffer, surface->pixels, n_bytes);

    if (textureData)
        [textureData release];
    //textureData = [[NSData dataWithBytes:[bitmapImageRep bitmapData] length:n_bytes] retain];
    //[bitmapImageRep release]; // released
    //textureData = [[NSData dataWithBytesNoCopy: buffer length: n_bytes] retain];
    textureData = [[NSData dataWithBytes:surface->pixels length:surface->w * surface->h * surface->format->BytesPerPixel] retain];

    SDL_UnlockSurface(surface);
    SDL_FreeSurface(surface);

    if (texName !=0)
    {
        const GLuint	delTextures[1] = { texName };
        glDeleteTextures(1, delTextures);
        texName = 0;	// clean up the texture from the 3d card's memory
    }    

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glGenTextures(1, &texName);			// get a new unique texture name
    glBindTexture(GL_TEXTURE_2D, texName);	// initialise it

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureRect.size.width, textureRect.size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, [textureData bytes]);
}
#endif

@end
