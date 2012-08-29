/*

OOCrosshairs.m
Oolite


Copyright (C) 2008 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCrosshairs.h"
#import "OOColor.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "MyOpenGLView.h"
#import "OOMacroOpenGL.h"


@interface OOCrosshairs (Private)

- (void) setUpDataWithPoints:(NSArray *)points
					   scale:(GLfloat)scale
					   color:(OOColor *)color
				overallAlpha:(GLfloat)alpha;

- (void) setUpDataForOnePoint:(NSArray *)pointInfo
						scale:(GLfloat)scale
				   colorComps:(float[4])colorComps
				 overallAlpha:(GLfloat)alpha
						 data:(GLfloat *)ioBuffer;

@end


@implementation OOCrosshairs

- (id) initWithPoints:(NSArray *)points
				scale:(GLfloat)scale
				color:(OOColor *)color
		 overallAlpha:(GLfloat)alpha
{
	if ((self = [super init]))
	{
		if (alpha > 0.0f && (color == nil || [color alphaComponent] != 0.0f))
		{
			[self setUpDataWithPoints:points scale:scale color:color overallAlpha:alpha];
		}
	}
	
	return self;
}


- (void) dealloc
{
	free(_data);
	
	[super dealloc];
}


- (void) render
{
	if (_data != NULL)
	{
		OO_ENTER_OPENGL();
		
		OOGL(glPushAttrib(GL_ENABLE_BIT));
		OOGL(glDisable(GL_LIGHTING));
		OOGL(glDisable(GL_TEXTURE_2D));
		OOGL(glPushMatrix());
		OOGL(glTranslatef(0, 0, [[UNIVERSE gameView] display_z]));
		
		OOGL(glVertexPointer(2, GL_FLOAT, sizeof (GLfloat) * 6, _data));
		OOGL(glColorPointer(4, GL_FLOAT, sizeof (GLfloat) * 6, _data + 2));
		
		OOGL(glEnableClientState(GL_VERTEX_ARRAY));
		OOGL(glEnableClientState(GL_COLOR_ARRAY));
		
		OOGL(glDrawArrays(GL_LINES, 0, _count * 2));
		
		OOGL(glDisableClientState(GL_VERTEX_ARRAY));
		OOGL(glDisableClientState(GL_COLOR_ARRAY));
		
		OOGL(glPopMatrix());
		OOGL(glPopAttrib());
	}
}


- (void) setUpDataWithPoints:(NSArray *)points
					   scale:(GLfloat)scale
					   color:(OOColor *)color
				overallAlpha:(GLfloat)alpha
{
	NSUInteger				i;
	float					colorComps[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
	GLfloat					*data = NULL;
	
	_count = [points count];
	if (_count == 0)  return;
	
	_data = malloc(sizeof (GLfloat) * 12 * _count);	// 2 coordinates, 4 colour components for each endpoint of each line segment
	[color getRed:&colorComps[0] green:&colorComps[1] blue:&colorComps[2] alpha:&colorComps[3]];
	
	// Turn NSArray into GL-friendly element array
	data = _data;
	for (i = 0; i < _count; i++)
	{
		[self setUpDataForOnePoint:[points oo_arrayAtIndex:i]
							 scale:scale
						colorComps:colorComps
					  overallAlpha:alpha
							  data:data];
		data += 12;
	}
}


- (void) setUpDataForOnePoint:(NSArray *)pointInfo
						scale:(GLfloat)scale
				   colorComps:(float[4])colorComps
				 overallAlpha:(GLfloat)alpha
						 data:(GLfloat *)ioBuffer
{
	GLfloat					x1, y1, a1, x2, y2, a2;
	GLfloat					r, g, b, a;
	
	if ([pointInfo count] >= 6)
	{
		a1 = [pointInfo oo_floatAtIndex:0];
		x1 = [pointInfo oo_floatAtIndex:1] * scale;
		y1 = [pointInfo oo_floatAtIndex:2] * scale;
		a2 = [pointInfo oo_floatAtIndex:3];
		x2 = [pointInfo oo_floatAtIndex:4] * scale;
		y2 = [pointInfo oo_floatAtIndex:5] * scale;
		r = colorComps[0];
		g = colorComps[1];
		b = colorComps[2];
		a = colorComps[3];
		
		/*	a1/a2 * a is hud.plist and crosshairs.plist - specified alpha,
			which must be clamped to 0..1 so the plist-specified alpha can't
			"escape" the overall alpha range. The result of scaling this by
			overall HUD alpha is then clamped again for robustness.
		 */
		a1 = OOClamp_0_1_f(OOClamp_0_1_f(a1 * a) * alpha);
		a2 = OOClamp_0_1_f(OOClamp_0_1_f(a2 * a) * alpha);
	}
	else
	{
		// Bad entry, write red point in middle.
		x1 = -0.01f;
		x2 = 0.01f;
		y1 = y2 = 0.0f;
		r = 1.0f;
		g = b = 0.0f;
		a1 = a2 = 1.0;
	}
	
	*ioBuffer++ = x1;
	*ioBuffer++ = y1;
	*ioBuffer++ = r;
	*ioBuffer++ = g;
	*ioBuffer++ = b;
	*ioBuffer++ = a1;
	
	*ioBuffer++ = x2;
	*ioBuffer++ = y2;
	*ioBuffer++ = r;
	*ioBuffer++ = g;
	*ioBuffer++ = b;
	*ioBuffer++ = a2;
	
	(void)ioBuffer;
}

@end
