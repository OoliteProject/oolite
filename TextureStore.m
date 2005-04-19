//
//  TextureStore.m
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

#ifdef GNUSTEP
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <OpenGL/gl.h>

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
    NSBitmapImageRep	*bitmapImageRep;
    NSRect		textureRect = NSMakeRect(0.0,0.0,4.0,4.0);
    NSImage		*texImage, *image;
    NSSize		imageSize;
    NSData		*textureData;
    GLuint		texName;
	
	int			n_planes;
	int			n_bytes;
    
    if (![textureDictionary objectForKey:filename])
    {
        NSMutableDictionary*	texProps = [NSMutableDictionary dictionaryWithCapacity:3];  // autoreleased
        
        texImage = [ResourceManager imageNamed:filename inFolder:@"Textures"];
        if (!texImage)
        {
            NSLog(@"***** Couldn't find texture : %@", filename);
                return 0;
        }
        
        imageSize = [texImage size];
    
        while (textureRect.size.width < imageSize.width)
            textureRect.size.width *= 2.0;
        while (textureRect.size.height < imageSize.height)
            textureRect.size.height *= 2.0;
        
        textureRect.origin= NSMakePoint(0.0,0.0);
    
        //  NSLog(@"textureSize = %f %f",textureRect.size.width,textureRect.size.height);
    
        image = [[NSImage alloc] initWithSize:textureRect.size]; // is retained
        
        // draw the texImage into an image of an appropriate size
        //
        [image lockFocus];
        
		[[NSColor clearColor] set];
        NSRectFill(textureRect);
        
		[texImage drawAtPoint:NSMakePoint(0.0,0.0) fromRect:NSMakeRect(0.0,0.0,imageSize.width,imageSize.height) operation:NSCompositeSourceOver fraction:1.0];
        bitmapImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:textureRect];// is retained
        
		//  NSLog(@"TextureStore %@ texture has %d planes, %d bytes per plane", filename, [bitmapImageRep numberOfPlanes], [bitmapImageRep bytesPerPlane]);
		
		n_bytes = [bitmapImageRep bytesPerPlane];
		n_planes = 3;
		if (n_bytes > textureRect.size.width*textureRect.size.height*3)
			n_planes = 4;
		
		[image unlockFocus];
    
        textureData = [[NSData dataWithBytes:[bitmapImageRep bitmapData] length:(int)(textureRect.size.width*textureRect.size.height*n_planes)] retain];
                
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glGenTextures(1, &texName);			// get a new unique texture name
        glBindTexture(GL_TEXTURE_2D, texName);	// initialise it
    
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	// adjust this
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);	// adjust this
    
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
        
        [image autorelease]; // is released
        
        [bitmapImageRep autorelease];// is released
        
		[textureData autorelease];// is released (retain count has been incremented by adding it to the texProps dictionary) 
    
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

