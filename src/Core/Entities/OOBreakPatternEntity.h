/*

OOBreakPatternEntity.h

Entity implementing tunnel effect for hyperspace and stations.


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "Entity.h"

@class OOColor;


enum
{
	kOOBreakPatternMaxSides			= 128,
	kOOBreakPatternMaxVertices		= (kOOBreakPatternMaxSides + 1) * 2
};


@interface OOBreakPatternEntity: Entity
{
@private
	Vector					_vertexPosition[kOOBreakPatternMaxVertices];
	GLfloat					_vertexColor[kOOBreakPatternMaxVertices][4];
	NSUInteger				_vertexCount;
	GLuint					_displayListName;
	double					_lifetime;
}

+ (instancetype) breakPatternWithPolygonSides:(NSUInteger)sides startAngle:(float)startAngleDegrees aspectRatio:(float)aspectRatio;

- (void) setInnerColor:(OOColor *)color1 outerColor:(OOColor *)color2;

- (void) setLifetime:(double)lifetime;

@end


@interface Entity (OOBreakPatternEntity)

- (BOOL) isBreakPattern;

@end
