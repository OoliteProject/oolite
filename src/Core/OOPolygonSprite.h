/*

OOPolygonSprite.h
Oolite

Two-dimensional polygon object for UI things such as missile icons.


Copyright (C) 2009-2012 Jens Ayton

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


#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"


@interface OOPolygonSprite: NSObject
{
@private
	GLfloat					*_solidData;
	size_t					_solidCount;
	GLfloat					*_outlineData;
	size_t					_outlineCount;
	
#if OO_USE_VBO
	GLuint					_solidVBO;
	GLuint					_outlineVBO;
#endif
	
#ifndef NDEBUG
	NSString				*_name;
#endif
}

/*	DataArray is either an array of pairs of numbers, or an array of such
	arrays (representing one or more contours).
	OutlineWidth is the width of the tesselated outline, in the same scale as
	the vertices.
	Name is used for debugging only.
*/
- (id) initWithDataArray:(NSArray *)dataArray outlineWidth:(GLfloat)outlineWidth name:(NSString *)name;

- (void) drawFilled;
- (void) drawOutline;

@end


#import "HeadUpDisplay.h"

@interface OOPolygonSprite (OOHUDBeaconIcon) <OOHUDBeaconIcon>
@end
