/*

OODrawable.m

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

#import "OODrawable.h"


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


- (void)reloadTextures
{
	
}

- (GLfloat)collisionRadius
{
	return 0.0f;
}


- (GLfloat)maxDrawDistance
{
	return 0.0f;
}


- (Geometry *)geometry
{
	return nil;
}


- (BoundingBox)boundingBox
{
	return kZeroBoundingBox;
}


- (BoundingBox)findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	return kZeroBoundingBox;
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	
}


- (void)dumpSelfState
{
	
}

@end
