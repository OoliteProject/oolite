/*

OOProbabilitySet.h

A collection for selecting objects randomly, with probability weighting.
Probability weights can be 0 - an object may be in the set but not selectable.
Comes in mutable and immutable variants.

Performance characteristics:
  *	-randomObject, the primary method, is O(log n) for immutable
	OOProbabilitySets and O(n) for mutable ones.
  *	-containsObject: and -probabilityForObject: are O(n). This could be
	optimized, but there's currently no need.


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

Copyright (C) 2008 Jens Ayton

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

#import "OOCocoa.h"


@interface OOProbabilitySet: NSObject <NSCopying, NSMutableCopying>

+ (id) probabilitySet;
+ (id) probabilitySetWithObjects:(id *)objects weights:(float *)weights count:(unsigned long)count;
+ (id) probabilitySetWithPropertyListRepresentation:(NSDictionary *)plist;

- (id) init;
- (id) initWithObjects:(id *)objects weights:(float *)weights count:(unsigned)count;
- (id) initWithPropertyListRepresentation:(NSDictionary *)plist;

// propertyListRepresentation is only valid if objects are property list objects.
- (NSDictionary *) propertyListRepresentation;

- (unsigned long) count;
- (id) randomObject;

- (float) weightForObject:(id)object;	// Returns -1 for unknown objects.
- (float) sumOfWeights;
- (NSArray *) allObjects;

@end


@interface OOProbabilitySet (OOExtendedProbabilitySet)

- (BOOL) containsObject:(id)object;
- (NSEnumerator *) objectEnumerator;
- (float) probabilityForObject:(id)object;	// Returns -1 for unknown objects, or a value from 0 to 1 inclusive for known objects.

@end


@interface OOMutableProbabilitySet: OOProbabilitySet

- (void) setWeight:(float)weight forObject:(id)object;	// Adds object if needed.
- (void) removeObject:(id)object;

@end
