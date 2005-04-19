//
//  SkyEntity.h
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

#import "Entity.h"

#define SKY_POINTS		2
#define SKY_BILLBOARDS	3

#define BILLBOARD_DEPTH	50000.0
// 50 km away!

#define SKY_MAX_STARS			480
#define SKY_MAX_BLOBS			128
#define SKY_BLOB_CLUSTER_CHANCE	0.80
#define SKY_BLOB_ALPHA			0.10
#define SKY_BLOB_SCALE			10.0
#define SKY_BLOB_SCALE_PRIME	0.0005

typedef struct
{
	GLint	texture_uv_array[ 4 * SKY_MAX_STARS * 2];
	GLfloat vertex_array[4 * SKY_MAX_STARS * 3];
	GLfloat color_array[4 * SKY_MAX_STARS * 4];
} SkyStarsData;
	
typedef struct
{
	GLint	texture_uv_array[ 4 * SKY_MAX_BLOBS * 2];
	GLfloat vertex_array[4 * SKY_MAX_BLOBS * 3];
	GLfloat color_array[4 * SKY_MAX_BLOBS * 4];
} SkyBlobsData;

@class Entity;

@interface SkyEntity : Entity
{
	int sky_type;

	NSColor *sky_color;
	
	GLuint  star_textureName;
	GLuint  blob_textureName;

	SkyStarsData starsData;
	SkyBlobsData blobsData;
	
	double blob_cluster_chance;
	double blob_alpha;
	double blob_scale;
	double blob_scale_prime;
	
	double delta;
	
}

- (id) initWithColors:(NSColor *) col1:(NSColor *) col2;
- (id) initWithColors:(NSColor *) col1:(NSColor *) col2 andSystemInfo:(NSDictionary *) systeminfo;
- (id) initAsWitchspace;
- (void) set_up_billboards:(NSColor *) col1:(NSColor *) col2;

- (NSColor *) sky_color;

@end

