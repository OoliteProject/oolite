/*

OODebugDrawing.m


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#import "OODebugGLDrawing.h"
#import "OOMacroOpenGL.h"
#import "OOMaterial.h"


#ifndef OODEBUGLDRAWING_DISABLE

OOINLINE void ApplyColor(OOColor *color)
{
	GLfloat				r, g, b, a;
	
	OO_ENTER_OPENGL();
	
	if (EXPECT_NOT(color == nil))  color = [OOColor lightGrayColor];
	[color getRed:&r green:&g blue:&b alpha:&a];
	OOGL(glColor4f(r, g, b, a));
}


void OODebugDrawColoredBoundingBoxBetween(Vector min, Vector max, OOColor *color)
{
	OODebugWFState state = OODebugBeginWireframe(YES);
	OO_ENTER_OPENGL();
	
	ApplyColor(color);
	OOGLBEGIN(GL_LINE_LOOP);
		glVertex3f(min.x, min.y, min.z);
		glVertex3f(max.x, min.y, min.z);
		glVertex3f(max.x, max.y, min.z);
		glVertex3f(min.x, max.y, min.z);
		glVertex3f(min.x, max.y, max.z);
		glVertex3f(max.x, max.y, max.z);
		glVertex3f(max.x, min.y, max.z);
		glVertex3f(min.x, min.y, max.z);
	OOGLEND();
	OOGLBEGIN(GL_LINES);
		glVertex3f(max.x, min.y, min.z);
		glVertex3f(max.x, min.y, max.z);
		glVertex3f(max.x, max.y, min.z);
		glVertex3f(max.x, max.y, max.z);
		glVertex3f(min.x, min.y, min.z);
		glVertex3f(min.x, max.y, min.z);
		glVertex3f(min.x, min.y, max.z);
		glVertex3f(min.x, max.y, max.z);
	OOGLEND();
	
	OODebugEndWireframe(state);
}


void OODebugDrawColoredLine(Vector start, Vector end, OOColor *color)
{	
	OODebugWFState state = OODebugBeginWireframe(YES);
	OO_ENTER_OPENGL();
	
	ApplyColor(color);
	
	OOGLBEGIN(GL_LINES);
		glVertex3f(start.x, start.y, start.z);
		glVertex3f(end.x, end.y, end.z);
	OOGLEND();
	
	OODebugEndWireframe(state);
}


void OODebugDrawBasis(Vector position, GLfloat scale)
{
	OODebugWFState state = OODebugBeginWireframe(YES);
	OO_ENTER_OPENGL();
	
	OOGLBEGIN(GL_LINES);
		glColor4f(1.0f, 0.0f, 0.0f, 1.0f);
		glVertex3f(position.x, position.y, position.z);
		glVertex3f(position.x + scale, position.y, position.z);
		
		glColor4f(0.0f, 1.0f, 0.0f, 1.0f);
		glVertex3f(position.x, position.y, position.z);
		glVertex3f(position.x, position.y + scale, position.z);
		
		glColor4f(0.0f, 0.0f, 1.0f, 1.0f);
		glVertex3f(position.x, position.y, position.z);
		glVertex3f(position.x, position.y, position.z + scale);
	OOGLEND();
	
	OODebugEndWireframe(state);
}


void OODebugDrawPoint(Vector position, OOColor *color)
{
	OODebugWFState state = OODebugBeginWireframe(YES);
	OO_ENTER_OPENGL();
	
	ApplyColor(color);
	OOGL(GLScaledPointSize(10));
	
	OOGLBEGIN(GL_POINTS);
		glVertex3f(position.x, position.y, position.z);
	OOGLEND();
	
	OODebugEndWireframe(state);
}


OODebugWFState OODebugBeginWireframe(BOOL ignoreZ)
{
	OO_ENTER_OPENGL();
	
	OODebugWFState state = { .material = [OOMaterial current] };
	[OOMaterial applyNone];
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_DEPTH_BUFFER_BIT | GL_LINE_BIT | GL_POINT_BIT | GL_CURRENT_BIT));
	
	OOGL(glDisable(GL_LIGHTING));
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glDisable(GL_FOG));
	if (ignoreZ)
	{
		OOGL(glDisable(GL_DEPTH_TEST));
		OOGL(glDepthMask(GL_FALSE));
	}
	else
	{
		OOGL(glEnable(GL_DEPTH_TEST));
		OOGL(glDepthMask(GL_TRUE));
	}
	
	OOGL(GLScaledLineWidth(1.0f));
	
	return state;
}


void OODebugEndWireframe(OODebugWFState state)
{
	OO_ENTER_OPENGL();
	OOGL(glPopAttrib());
	[state.material apply];
}

#endif
