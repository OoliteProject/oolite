/*

SkyEntity.h

Entity subclass implementing the game backdrop of stars and nebulae.

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

#import <Foundation/Foundation.h>

#import "Entity.h"

#define SKY_POINTS		2
#define SKY_BILLBOARDS	3

#define BILLBOARD_DEPTH	50000.0
// 50 km away!

#define SKY_N_STARS				480
#define SKY_N_BLOBS				128
#define SKY_MAX_STARS			4800
#define SKY_MAX_BLOBS			1280
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

@class OOColor;

@interface SkyEntity : Entity
{
	int sky_type;

	OOColor *sky_color;
	
	GLuint  star_textureName;
	GLuint  blob_textureName;

	SkyStarsData starsData;
	SkyBlobsData blobsData;
	
	double blob_cluster_chance;
	double blob_alpha;
	double blob_scale;
	double blob_scale_prime;
	
	double delta;
	
	int n_stars, n_blobs;
	
}

- (id) initWithColors:(OOColor *) col1:(OOColor *) col2;
- (id) initWithColors:(OOColor *) col1:(OOColor *) col2 andSystemInfo:(NSDictionary *) systeminfo;
- (id) initAsWitchspace;
- (void) set_up_billboards:(OOColor *) col1:(OOColor *) col2;

- (OOColor *) sky_color;

@end
