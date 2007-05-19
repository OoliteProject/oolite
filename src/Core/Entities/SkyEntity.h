/*

SkyEntity.h

Entity subclass implementing the game backdrop of stars and nebulae.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOSelfDrawingEntity.h"


#define BILLBOARD_DEPTH			50000.0

#define SKY_MAX_STARS			4800
#define SKY_MAX_BLOBS			1280
#define SKY_BLOB_CLUSTER_CHANCE	0.80
#define SKY_BLOB_ALPHA			0.10
#define SKY_BLOB_SCALE			10.0


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

@interface SkyEntity: OOSelfDrawingEntity
{
	OOColor			*sky_color;
	
	SkyStarsData	starsData;
	SkyBlobsData	blobsData;
	
	double			blob_cluster_chance;
	double			blob_alpha;
	double			blob_scale;
	double			blob_scale_prime;
	
	int				n_stars, n_blobs;
	
}

- (id) initWithColors:(OOColor *) col1:(OOColor *) col2 andSystemInfo:(NSDictionary *) systeminfo;
- (id) initAsWitchspace;
- (void) set_up_billboards:(OOColor *) col1:(OOColor *) col2;

- (OOColor *) sky_color;

@end
