/*

OODrawable.m


Copyright (C) 2007-2013 Jens Ayton

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

#import "OODrawable.h"
#import "NSObjectOOExtensions.h"


@implementation OODrawable

- (void)renderOpaqueParts
{
	
}


- (void)renderTranslucentParts
{

}


- (BOOL)hasOpaqueParts
{
	return NO;
}


- (BOOL)hasTranslucentParts
{
	return NO;
}


- (GLfloat)collisionRadius
{
	return 0.0f;
}


- (GLfloat)maxDrawDistance
{
	return 0.0f;
}


- (BoundingBox)boundingBox
{
	return kZeroBoundingBox;
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	
}


- (void)dumpSelfState
{
	
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	return nil;
}


- (size_t) totalSize
{
	return [self oo_objectSize];
}
#endif

@end
