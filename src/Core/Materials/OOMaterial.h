/*

OOMaterial.h

A material which can be applied to an OpenGL object, or more accurately, to
the current OpenGL render state.

This is an abstract class; actual materials should be subclasses.

Currently, only shader materials are supported. Direct use of textures should
also be replaced with an OOMaterial subclass.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
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


@interface OOMaterial: NSObject

// Called once at startup (by -[Universe init]).
+ (void)setUp;


- (NSString *)name;

// Make this the current material.
- (void)apply;

/*	Make no material the current material, tearing down anything set up by the
	current material.
*/
+ (void)applyNone;

/*	Ensure material is ready to be used in a display list. This is not
	required before using a material directly.
*/
- (void)ensureFinishedLoading;

// Only used by shader material, but defined for all materials for convenience.
- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target;

- (void)reloadTextures;

@end


@interface OOMaterial (OOConvenienceCreators)

/*	Get a material based on configuration. The result will be an
	OOBasicMaterial, OOSingleTextureMaterial or OOShaderMaterial (the latter
	only if shaders are available).
*/
+ (id)materialWithName:(NSString *)name configuration:(NSDictionary *)configuration macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)object;

/*	Select an appropriate material description (based on availability of
	shaders and content of dictionaries, which may be nil) and call
	+materialWithDescription:.
*/
+ (id)materialWithName:(NSString *)name materialDictionary:(NSDictionary *)materialDict shadersDictionary:(NSDictionary *)shadersDict macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)object;

@end


@interface OOMaterial (OOSubclassInterface)

// Subclass responsibilities - don't call directly.
- (BOOL)doApply;	// Override instead of -apply
- (void)unapplyWithNext:(OOMaterial *)next;

// Call at top of dealloc
- (void)willDealloc;

@end
