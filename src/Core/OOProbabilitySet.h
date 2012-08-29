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

#import "OOCocoa.h"


@interface OOProbabilitySet: NSObject <NSCopying, NSMutableCopying>

+ (id) probabilitySet;
+ (id) probabilitySetWithObjects:(id *)objects weights:(float *)weights count:(NSUInteger)count;
+ (id) probabilitySetWithPropertyListRepresentation:(NSDictionary *)plist;

- (id) init;
- (id) initWithObjects:(id *)objects weights:(float *)weights count:(NSUInteger)count;
- (id) initWithPropertyListRepresentation:(NSDictionary *)plist;

// propertyListRepresentation is only valid if objects are property list objects.
- (NSDictionary *) propertyListRepresentation;

- (NSUInteger) count;
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
