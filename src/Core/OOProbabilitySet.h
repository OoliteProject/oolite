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


Copyright (C) 2008-2013 Jens Ayton

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

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@interface OOProbabilitySet : OOObject <OOCopying, OOMutableCopying>

// The elements are oo::PList values (proposed ADR-0055 item 2): ship keys are strings; an
// Object node (oo::PListObject) carries an Objective-C object. Two elements are the same if they
// are == or are Object nodes holding the same object or -isEqual: objects.
+ (id)probabilitySet;
+ (id)probabilitySetWithObjects:(const oo::PList*)objects weights:(const float*)weights count:(NSUInteger)count;
+ (id)probabilitySetWithPropertyListRepresentation:(const oo::PList&)plist;

- (id)init;
- (id)initWithObjects:(const oo::PList*)objects weights:(const float*)weights count:(NSUInteger)count;
- (id)initWithPropertyListRepresentation:(const oo::PList&)plist;

// propertyListRepresentation is only valid if objects are property list objects.
- (oo::PList)propertyListRepresentation;

- (NSUInteger)count;
- (oo::PList)randomObject; // A null PList for none (an empty set, or every weight zero).

- (float)weightForObject:(const oo::PList&)object; // Returns -1 for unknown objects.
- (float)sumOfWeights;
- (id)allObjects; // shared selector: an Objective-C array (strings as NSStrings, Object nodes as their objects)
- (std::vector<oo::PList>)cxx_allElements; // the elements, in the same order (-cxx_allObjects is OOWeakSet's family)

@end

@interface OOProbabilitySet (OOExtendedProbabilitySet)

- (BOOL)cxx_containsObject:(const oo::PList&)object;
- (id)objectEnumerator; // shared selector: an enumerator over -allObjects
- (float)probabilityForObject:(const oo::PList&)object; // Returns -1 for unknown objects, or a value from 0 to 1 inclusive for known objects.

@end

@interface OOMutableProbabilitySet : OOProbabilitySet

- (void)setWeight:(float)weight forObject:(const oo::PList&)object; // Adds object if needed; a null object is ignored.
- (void)cxx_removeObject:(const oo::PList&)object;

@end
