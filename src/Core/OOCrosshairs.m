//
//  OOCrosshairs.m
//  Oolite
//
//  Created by Jens Ayton on 2008-12-16.
//  Copyright 2008 Jens Ayton. All rights reserved.
//

#import "OOCrosshairs.h"
#import "OOColor.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "MyOpenGLView.h"


@interface OOCrosshairs (Private)

- (void) setUpDataWithPoints:(NSArray *)points
					   scale:(GLfloat)scale
					   color:(OOColor *)color
				overallAlpha:(GLfloat)alpha;

- (void) setUpDataForOnePoint:(NSArray *)pointInfo
						scale:(GLfloat)scale
				   colorComps:(GLfloat[4])colorComps
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
		glPushAttrib(GL_ENABLE_BIT);
		glDisable(GL_LIGHTING);
		glDisable(GL_TEXTURE_2D);
		glEnable(GL_LINE_SMOOTH);
		glPushMatrix();
		glTranslatef(0, 0, [[UNIVERSE gameView] display_z]);
		
#if 1
		glVertexPointer(2, GL_FLOAT, sizeof (GLfloat) * 6, _data);
		glColorPointer(4, GL_FLOAT, sizeof (GLfloat) * 6, _data + 2);
		
		glEnableClientState(GL_VERTEX_ARRAY);
		glEnableClientState(GL_COLOR_ARRAY);
		
		glDrawArrays(GL_LINES, 0, _count * 2);
		
		glDisableClientState(GL_VERTEX_ARRAY);
		glDisableClientState(GL_COLOR_ARRAY);
#else
		unsigned i;
		GLfloat *data = _data;
		glBegin(GL_LINES);
		for (i = 0; i < _count * 2; i++)
		{
			glColor4f(data[2], data[3], data[4], data[5]);
			glVertex2f(data[0], data[1]);
			data += 6;
		}
		glEnd();
#endif
		
		glPopMatrix();
		glPopAttrib();
	}
}


- (void) setUpDataWithPoints:(NSArray *)points
					   scale:(GLfloat)scale
					   color:(OOColor *)color
				overallAlpha:(GLfloat)alpha
{
	unsigned				i;
	GLfloat					colorComps[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
	GLfloat					*data = NULL;
	
	_count = [points count];
	if (_count == 0)  return;
	
	_data = malloc(sizeof (GLfloat) * 12 * _count);	// 2 coordinates, 4 colour components for each endpoint of each line segment
	[color getRed:&colorComps[0] green:&colorComps[1] blue:&colorComps[2] alpha:&colorComps[3]];
	
	// Turn NSArray into GL-friendly element array
	data = _data;
	for (i = 0; i < _count; i++)
	{
		[self setUpDataForOnePoint:[points arrayAtIndex:i]
							 scale:scale
						colorComps:colorComps
					  overallAlpha:alpha
							  data:data];
		data += 12;
	}
}


- (void) setUpDataForOnePoint:(NSArray *)pointInfo
						scale:(GLfloat)scale
				   colorComps:(GLfloat[4])colorComps
				 overallAlpha:(GLfloat)alpha
						 data:(GLfloat *)ioBuffer
{
	GLfloat					x1, y1, a1, x2, y2, a2;
	GLfloat					r, g, b, a;
	
	if ([pointInfo count] >= 6)
	{
		a1 = [pointInfo floatAtIndex:0];
		x1 = [pointInfo floatAtIndex:1] * scale;
		y1 = [pointInfo floatAtIndex:2] * scale;
		a2 = [pointInfo floatAtIndex:3];
		x2 = [pointInfo floatAtIndex:4] * scale;
		y2 = [pointInfo floatAtIndex:5] * scale;
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
}

@end
