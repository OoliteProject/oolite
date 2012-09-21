/*

OOBreakPatternEntity.m

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

#import "OOBreakPatternEntity.h"
#import "OOColor.h"
#import "Universe.h"
#import "OOMacroOpenGL.h"


@interface OOBreakPatternEntity (Private)

- (void) setInnerColorComponents:(GLfloat[4])color1 outerColorComponents:(GLfloat[4])color2;

@end


@implementation OOBreakPatternEntity

- (id) initWithPolygonSides:(NSUInteger)sides startAngle:(float)startAngleDegrees aspectRatio:(float)aspectRatio
{
	sides = MIN(MAX((NSUInteger)3, sides), (NSUInteger)kOOBreakPatternMaxSides);
	
	if ((self = [super init]))
	{
		_vertexCount = (sides + 1) * 2;
		float angle = startAngleDegrees * M_PI / 180.0f;
		float deltaAngle = M_PI * 2.0f / sides;
		float xAspect = fmin(1.0f, aspectRatio);
		float yAspect = fmin(1.0f, 1.0f / aspectRatio);
		
		NSUInteger vi = 0;
		for (NSUInteger i = 0; i < sides; i++)
		{
			float s = sin(angle) * xAspect;
			float c = cos(angle) * yAspect;
			
			_vertexPosition[vi++] = (Vector) { s * 50, c * 50, -40 };
			_vertexPosition[vi++] = (Vector) { s * 40, c * 40, 0 };
			
			angle += deltaAngle;
		}
		
		_vertexPosition[vi++] = _vertexPosition[0];
		_vertexPosition[vi++] = _vertexPosition[1];
		
		[self setInnerColorComponents:(GLfloat[]){ 1.0f, 0.0f, 0.0f, 0.5f }
				 outerColorComponents:(GLfloat[]){ 0.0f, 0.0f, 1.0f, 0.25f }];
		
		[self setStatus:STATUS_EFFECT];
		[self setScanClass:CLASS_NO_DRAW];
		
		isImmuneToBreakPatternHide = YES;
	}
	
	return self;
}


+ (instancetype) breakPatternWithPolygonSides:(NSUInteger)sides startAngle:(float)startAngleDegrees aspectRatio:(float)aspectRatio
{
	return [[[self alloc] initWithPolygonSides:sides startAngle:startAngleDegrees aspectRatio:aspectRatio] autorelease];
}


- (void) setInnerColor:(OOColor *)color1 outerColor:(OOColor *)color2
{
	GLfloat inner[4], outer[4];
	[color1 getRed:&inner[0] green:&inner[1] blue:&inner[2] alpha:&inner[3]];
	[color2 getRed:&outer[0] green:&outer[1] blue:&outer[2] alpha:&outer[3]];
	[self setInnerColorComponents:inner outerColorComponents:outer];
}


- (void) setInnerColorComponents:(GLfloat[4])color1 outerColorComponents:(GLfloat[4])color2
{
	GLfloat *colors[2] = { color1, color2 };
	
	for (NSUInteger i = 0; i < _vertexCount; i++)
	{
		GLfloat *color = colors[i & 1];
		memcpy(&_vertexColor[i], color, sizeof (GLfloat) * 4);
	}
}


- (void) setLifetime:(double)lifetime
{
	_lifetime = lifetime;
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	[self applyVelocityWithTimeDelta:delta_t];
	
	_lifetime -= BREAK_PATTERN_RING_SPEED * delta_t;
	if (_lifetime < 0.0)
	{
		[UNIVERSE removeEntity:self];
	}
}


- (void) generateDisplayList
{
	OO_ENTER_OPENGL();
	
	OOGL(_displayListName = glGenLists(1));
	if (_displayListName != 0)
	{
		OOGL(glNewList(_displayListName, GL_COMPILE));
		[self drawEntity:YES:NO];	//	immediate YES	translucent NO
		OOGL(glEndList());
	}
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	// check if has been hidden.
	if (!isImmuneToBreakPatternHide) return;

	OO_ENTER_OPENGL();
	
	if (translucent || immediate)
	{
		if (immediate)
		{
			OOGL(glPushAttrib(GL_ENABLE_BIT));
			
			OOGL(glShadeModel(GL_SMOOTH));
			OOGL(glDisable(GL_LIGHTING));
			OOGL(glDisable(GL_TEXTURE_2D));
			
			OOGL(glEnableClientState(GL_VERTEX_ARRAY));
			OOGL(glVertexPointer(3, GL_FLOAT, 0, _vertexPosition));
			OOGL(glEnableClientState(GL_COLOR_ARRAY));
			OOGL(glColorPointer(4, GL_FLOAT, 0, _vertexColor));
			
			OOGL(glDrawArrays(GL_TRIANGLE_STRIP, 0, _vertexCount));
			
			OOGL(glDisableClientState(GL_VERTEX_ARRAY));
			OOGL(glDisableClientState(GL_COLOR_ARRAY));
			
			OOGL(glPopAttrib());
		}
		else
		{
			if (_displayListName == 0)
			{
				[self generateDisplayList];
			}
			else
			{
				// Don't call on first frame, because view orientation may be wrong.
				OOGL(glCallList(_displayListName));
			}
		}
	}
	
	CheckOpenGLErrors(@"OOBreakPatternEntity after drawing %@", self);
}


- (BOOL) canCollide
{
	return NO;
}


- (BOOL) isBreakPattern
{
	return YES;
}

@end


@implementation Entity (OOBreakPatternEntity)

- (BOOL) isBreakPattern
{
	return NO;
}

@end
