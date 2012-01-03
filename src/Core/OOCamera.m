/*

OOCamera.m


Copyright (C) 2008-2012 Jens Ayton

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

#import "OOCamera.h"
#import "OOMacroOpenGL.h"


@implementation OOCamera

- (id) init
{
	self = [super init];
	if (self != nil)
	{
		_orientation = kIdentityQuaternion;
	}
	return self;
}


- (void) dealloc
{
	[_reference autorelease];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString *refDesc = @"";
	if (_reference != nil)  refDesc = [NSString stringWithFormat:@"relative to ", [(id)_reference shortDescription]];
	
	return [NSString stringWithFormat:@"position: %@ orientation: %@%@", VectorDescription([self position]), QuaternionDescription([self orientation]), refDesc];
}


- (Vector) position
{
	return _position;
}


- (void) setPosition:(Vector)position
{
	_position = position;
}


- (Quaternion) orientation
{
	return _orientation;
}


- (void) setOrientation:(Quaternion)orientation
{
	_orientation = orientation;
}


- (id <OOSpatialReference>)reference
{
	return _reference;
}


- (void) setReference:(id <OOSpatialReference>)reference
{
	[_reference autorelease];
	_reference = [reference retain];
}


- (void) rotateToHeading:(Vector)heading upVector:(Vector)upVector
{
	
}


- (OOMatrix) transformationMatrix
{
	return OOMatrixForQuaternionRotation([self orientation]);
}


- (OOMatrix) rotationMatrix
{
	return OOMatrixTranslate([self rotationMatrix], [self position]);
}


- (void) glApply
{
	GLint			matrixMode;
	
	OO_ENTER_OPENGL();
	
	glGetIntegerv(GL_MATRIX_MODE, &matrixMode);
	glMatrixMode(GL_MODELVIEW);
	GLLoadOOMatrix([self rotationMatrix]);	// Absolute
	glMatrixMode(matrixMode);
}


- (void) glApplyRelative
{
	GLint			matrixMode;
	
	OO_ENTER_OPENGL();
	
	glGetIntegerv(GL_MATRIX_MODE, &matrixMode);
	glMatrixMode(GL_MODELVIEW);
	GLMultOOMatrix([self rotationMatrix]);	// Relative
	glMatrixMode(matrixMode);
}

@end
