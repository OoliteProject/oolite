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

*/

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"


@interface OOMaterial: NSObject

// Make this the current material.
- (void)apply;

// Make no material the current material, tearing down anything set up by the current material.
+ (void)applyNone;

@end


@interface OOMaterial (OOSubclassInterface)

// Subclass responsibilities - don't call directly.
- (BOOL)doApply;	// Override instead of -apply
- (void)unapplyWithNext:(OOMaterial *)next;

// Call at top of dealloc
- (void)willDealloc;

@end
