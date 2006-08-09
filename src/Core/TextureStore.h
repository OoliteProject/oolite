//
//  TextureStore.h
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

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"

#define OOLITE_EXCEPTION_TEXTURE_NOT_FOUND		@"OoliteTextureNotFoundException"
#define OOLITE_EXCEPTION_TEXTURE_NOT_UNDERSTOOD	@"OoliteTextureNotUnderstoodException"
#define OOLITE_EXCEPTION_FATAL					@"OoliteFatalException"


extern int debug;

@class OOColor;

@interface TextureStore : NSObject
{
}

+ (GLuint) getTextureNameFor:(NSString *)filename;
+ (GLuint) getImageNameFor:(NSString *)filename;
+ (GLuint) getTextureNameFor:(NSString *)filename inFolder:(NSString*) foldername;
+ (NSString*) getNameOfTextureWithGLuint:(GLuint) value;
+ (NSSize) getSizeOfTexture:(NSString *)filename;

+ (GLuint) shaderProgramFromDictionary:(NSDictionary *) shaderDict;

+ (void) reloadTextures;

// routines to create textures...

+ (GLuint) getPlanetTextureNameFor:(NSDictionary*)planetinfo intoData:(unsigned char **)textureData;
+ (GLuint) getCloudTextureNameFor:(OOColor*) color: (GLfloat) impress: (GLfloat) bias intoData:(unsigned char **)textureData;

void fillRanNoiseBuffer();

void fillSquareImageDataWithBlur(unsigned char * imageBuffer, int width, int nplanes);

void addNoise(float * buffer, int p, int n, float scale);
void fillSquareImageDataWithSmoothNoise(unsigned char * imageBuffer, int width, int nplanes);
void fillSquareImageDataWithCloudTexture(unsigned char * imageBuffer, int width, int nplanes, OOColor* cloudcolor, float impress, float bias);
void fillSquareImageWithPlanetTex(unsigned char * imageBuffer, int width, int nplanes, float impress, float bias,
	OOColor* seaColor,
	OOColor* paleSeaColor,
	OOColor* landColor,
	OOColor* paleLandColor);

@end
