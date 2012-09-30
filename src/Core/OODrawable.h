/*

OODrawable.h

Abstract base class for objects which can draw themselves.


Copyright (C) 2007-2012 Jens Ayton

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
#import "OOMaths.h"
#import "OOWeakReference.h"


@interface OODrawable: NSObject

- (void)renderOpaqueParts;
- (void)renderTranslucentParts;
- (BOOL)hasOpaqueParts;
- (BOOL)hasTranslucentParts;

- (GLfloat)collisionRadius;
- (GLfloat)maxDrawDistance;

- (BoundingBox)boundingBox;

// Passed to all materials.
- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target;

- (void)dumpSelfState;

#ifndef NDEBUG
- (NSSet *) allTextures;
- (size_t) totalSize;	// Size including dynamic data, not counting textures.
#endif

@end
