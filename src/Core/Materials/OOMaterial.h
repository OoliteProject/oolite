/*

OOMaterial.h

A material which can be applied to an OpenGL object, or more accurately, to
the current OpenGL render state.

This is an abstract class; actual materials should be subclasses.

Currently, only shader materials are supported. Direct use of textures should
also be replaced with an OOMaterial subclass.

 
Copyright (C) 2007-2012 Jens Ayton and contributors

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

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"
#import "OOWeakReference.h"
#import "OOOpenGLExtensionManager.h"


@interface OOMaterial: NSObject

// Called once at startup (by -[Universe init]).
+ (void) setUp;


- (NSString *) name;

// Make this the current material.
- (void) apply;

/*	Make no material the current material, tearing down anything set up by the
	current material.
*/
+ (void) applyNone;

/*	Get current material.
*/
+ (OOMaterial *) current;

/*	Ensure material is ready to be used in a display list. This is not
	required before using a material directly.
*/
- (void) ensureFinishedLoading;
- (BOOL) isFinishedLoading;

// Only used by shader material, but defined for all materials for convenience.
- (void) setBindingTarget:(id<OOWeakReferenceSupport>)target;

// True if material wants three-component cube map texture coordinates.
- (BOOL) wantsNormalsAsTextureCoordinates;

#if OO_MULTITEXTURE
// Nasty hack: number of texture units for which the drawable should set its basic texture coordinates.
- (NSUInteger) countOfTextureUnitsWithBaseCoordinates;
#endif

#ifndef NDEBUG
- (NSSet *) allTextures;
#endif

@end


@interface OOMaterial (OOSubclassInterface)

// Subclass responsibilities - don't call directly.
- (BOOL) doApply;	// Override instead of -apply
- (void) unapplyWithNext:(OOMaterial *)next;

// Call at top of dealloc
- (void) willDealloc;

@end
