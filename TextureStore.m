//
//  TextureStore.m
/*
 *
 *  Oolite (Linux/Windows + SDL)
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

#ifdef GNUSTEP
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#ifdef LINUX
#include "oolite-linux.h"
#else
#import <OpenGL/gl.h>
#endif

#import "ResourceManager.h"

#import "TextureStore.h"


@implementation TextureStore

- (id) init
{
    self = [super init];
    //
    textureDictionary = [[NSMutableDictionary dictionaryWithCapacity:5] retain];
    //
    return self;
}

- (void) dealloc
{
    if (textureDictionary) [textureDictionary release];
    //
    [super dealloc];
}

- (GLuint) getTextureNameFor:(NSString *)filename
{
#ifndef GNUSTEP
	NSBitmapImageRep	*bitmapImageRep = nil;
	NSImage				*texImage;
#else
	SDLImage			*texImage;
#endif
	NSRect		textureRect;
	NSSize		imageSize;
	NSData		*textureData;
	GLuint		texName;
		
	int			texture_h = 4;
	int			texture_w = 4;
	int			image_h, image_w;
	int			n_planes, im_bytes, tex_bytes;
	
	int			im_bytesPerRow;

	int			texi = 0; 
	
	if (![textureDictionary objectForKey:filename])
	{
		NSMutableDictionary*	texProps = [NSMutableDictionary dictionaryWithCapacity:3];	// autoreleased
#ifndef GNUSTEP		   
		texImage = [ResourceManager imageNamed:filename inFolder:@"Textures"];
#else
		texImage = [ResourceManager surfaceNamed:filename inFolder:@"Textures"];
#endif
		if (!texImage)
		{
			NSLog(@"***** Couldn't find texture : %@", filename);
						NSException* myException = [NSException
								exceptionWithName: @"OoliteException"
								reason: [NSString stringWithFormat:@"Oolite couldn't find texture : %@ on any search-path.", filename]
								userInfo: nil];
						[myException raise];
						return 0;
		}

#ifndef GNUSTEP		   
		imageSize = [texImage size];
#else
		imageSize = NSMakeSize([texImage surface]->w, [texImage surface]->h);
#endif
		image_w = imageSize.width;
		image_h = imageSize.height;

		while (texture_w < image_w)
			texture_w *= 2;
		while (texture_h < image_h)
			texture_h *= 2;
		textureRect=NSMakeRect(0.0, 0.0, texture_w, texture_h);		 

#ifndef GNUSTEP	   
		NSArray* reps = [texImage representations];
		int i;
		for (i = 0; ((i < [reps count]) && !bitmapImageRep); i++)
		{
				NSObject* imageRep = [reps objectAtIndex:i];
				if ([imageRep isKindOfClass:[NSBitmapImageRep class]])
						bitmapImageRep = (NSBitmapImageRep*)imageRep;
		}
		if (!bitmapImageRep)
		{
			NSLog(@"***** Couldn't find a representation for texture : %@ %@", filename, texImage);
			NSException* myException = [NSException
					exceptionWithName: @"OoliteException"
					reason: [NSString stringWithFormat:@"Oolite couldn't find a NSBitMapImageRep for texture : %@ : %@.", filename, texImage]
					userInfo: nil];
			[myException raise];
			return 0;
		}
		
		n_planes = [bitmapImageRep samplesPerPixel];
		im_bytesPerRow = [bitmapImageRep bytesPerRow];
		unsigned char* imageBuffer = [bitmapImageRep bitmapData];
#else
		n_planes = [texImage surface]->format->BytesPerPixel;
		im_bytesPerRow = [texImage surface]->pitch;
		unsigned char* imageBuffer = [texImage surface]->pixels;
#endif

		im_bytes = image_w * image_h * n_planes;
		tex_bytes = texture_w * texture_h * n_planes;

		if ((texture_w > image_w)||(texture_h > image_h))		// we need to scale the image to the texture dimensions
		{
			unsigned char textureBuffer[tex_bytes];
			
			// do bilinear scaling
			int x, y, n;
			float texel_w = (float)image_w / (float)texture_w;
			float texel_h = (float)image_h / (float)texture_h;
//						NSLog(@"scaling image %@ : %@\n scale (%d  x %d) to (%d x %d) scale (%.3f x %.3f)", filename, texImage, image_w, image_h, texture_w, texture_h, texel_w, texel_h);

			for ( y = 0; y < texture_h; y++)
			{
				float y_lo = texel_h * y;
				float y_hi = y_lo + texel_h - 0.001;
				int y0 = floor(y_lo);
				int y1 = floor(y_hi);

				float py0 = 1.0;
				float py1 = 0.0;
				if (y1 > y0)
				{
					py0 = (y1 - y_lo) / texel_h;
					py1 = 1.0 - py0;
				}
				
				for ( x = 0; x < texture_w; x++)
				{
					float x_lo = texel_w * x;
					float x_hi = x_lo + texel_w - 0.001;
					int x0 = floor(x_lo);
					int x1 = floor(x_hi);
					float acc = 0;
					
					float px0 = 1.0;
					float px1 = 0.0;
					if (x1 > x0)
					{
						px0 = (x1 - x_lo) / texel_w;
						px1 = 1.0 - px0;
					}
					
					int	xy00 = y0 * im_bytesPerRow + n_planes * x0;
					int	xy01 = y0 * im_bytesPerRow + n_planes * x1;
					int	xy10 = y1 * im_bytesPerRow + n_planes * x0;
					int	xy11 = y1 * im_bytesPerRow + n_planes * x1;
			
					for (n = 0; n < n_planes; n++)
					{
						acc = py0 * (px0 * imageBuffer[ xy00 + n] + px1 * imageBuffer[ xy10 + n])
								+ py1 * (px0 * imageBuffer[ xy01 + n] + px1 * imageBuffer[ xy11 + n]);
						textureBuffer[ texi++] = (char)acc;		// float -> char
					}
				}
			}
			textureData = [NSData dataWithBytes:textureBuffer length: tex_bytes];	// copies the data
			
		}
		else
		{
			// no scaling required - we will use the image data directly
			textureData = [NSData dataWithBytes:imageBuffer length: im_bytes];		// copies the data
		}
					   
		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
		glGenTextures(1, &texName);						// get a new unique texture name
		glBindTexture(GL_TEXTURE_2D, texName);	// initialise it
	
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);		// adjust this
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);		// adjust this
	
		if (n_planes == 4)
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureRect.size.width, textureRect.size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, [textureData bytes]);
		else
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureRect.size.width, textureRect.size.height, 0, GL_RGB, GL_UNSIGNED_BYTE, [textureData bytes]);
	
		// add to dictionary
		//
		[texProps setObject:textureData forKey:@"textureData"];
		[texProps setObject:[NSNumber numberWithInt:texName] forKey:@"texName"];
		[texProps setObject:[NSNumber numberWithInt:textureRect.size.width] forKey:@"width"];
		[texProps setObject:[NSNumber numberWithInt:textureRect.size.height] forKey:@"height"];

		[textureDictionary setObject:texProps forKey:filename];
	}
	else
	{
		texName = (GLuint)[(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"texName"] intValue];
	}
	return texName;
}

- (NSSize) getSizeOfTexture:(NSString *)filename
{
    NSSize size = NSMakeSize(0.0, 0.0);	// zero size
    if ([textureDictionary objectForKey:filename])
    {
        size.width = [(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"width"] intValue];
        size.height = [(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"height"] intValue];
    }
    return size;
}

- (void) reloadTextures
{
	[textureDictionary removeAllObjects];
	return;
}

@end
