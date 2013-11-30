/*

OOExhaustPlumeEntity.h


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "ShipEntity.h"
#import "OOTexture.h"

typedef struct
{
	double					timeframe;		// universal time for this frame
	HPVector					position;
	Quaternion				orientation;
	Vector					k;				// direction vectors
} Frame;


enum
{
	kExhaustFrameCount = 16
};


@interface OOExhaustPlumeEntity: Entity <OOSubEntity>
{
@private
	Vector			_exhaustScale;
	OOHPScalar			_vertices[34 * 3];
	GLfloat			_glVertices[34 * 3];
	GLfloat			_exhaustBaseColors[34 * 4];
	Frame			_track[kExhaustFrameCount];
	OOTimeAbsolute	_trackTime;
	uint8_t			_nextFrame;
}

+ (id) exhaustForShip:(ShipEntity *)ship withDefinition:(NSArray *)definition;
- (id) initForShip:(ShipEntity *)ship withDefinition:(NSArray *)definition;

- (void) resetPlume;

- (Vector) scale;
- (void) setScale:(Vector)scale;

- (OOTexture *) texture;

+ (void) setUpTexture;
+ (OOTexture *) plumeTexture;
+ (void) resetGraphicsState;

@end


@interface Entity (OOExhaustPlume)

- (BOOL)isExhaust;

@end
