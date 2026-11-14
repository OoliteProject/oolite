/*

OOPriorityQueue.h

A prority queue is a collection into which objects may be inserted in any
order, but (primarily) extracted in sorted order. The order is defined by the
comparison selector specified at creation time, which is assumed to have the
same signature as a compare method used for array sorting:
- (OOComparisonResult)compare:(id)other
and must define a partial order on the objects in the priority queue. The
behaviour when provided with an inconsistent comparison method is undefined.

The implementation is the standard one, a binary heap. It is described in
detail in most algorithm textbooks.

This collection is *not* thread-safe.


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

#ifndef OOPRIORITYQUEUE_H
#define OOPRIORITYQUEUE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#ifndef OO_PQ_STRONG
#if __has_feature(objc_arc)
#define OO_PQ_STRONG __strong
#else
#define OO_PQ_STRONG
#endif
#endif

/*	C++20 since bead oo-3lj8 (proposed ADR-0056, the OOColor house style). Its one caller,
        OOScriptTimer, was adapted in the same bead, so there is no Objective-C facade and the class is
        global. The elements are still Objective-C objects, ordered by a comparator selector that
        each of them implements (OOScriptTimer's -compareByNextFireTime:).
*/
class OOPriorityQueue : public oo::RefCounted {
public:
    // The Objective-C initialiser's factory: null where -initWithComparator: returned nil (a NULL
    // comparator). (-init, which gave the comparator compare:, had no sender.)
    static oo::Ref<OOPriorityQueue> queueWithComparator(SEL comparator);

    ~OOPriorityQueue() override;

    void addObject(id object); // May throw OOInvalidArgumentException or OOMallocException.
    void removeObject(id object); // Uses comparator (looking for NSOrderedEqual) to find object. Note: relatively expensive.
    void removeExactObject(id object); // Uses pointer comparison to find object. Note: still relatively expensive.

    NSUInteger count();

    id nextObject();
    id peekAtNextObject(); // Returns next object without removing it.
    void removeNextObject();

    std::vector<oo::ObjCRef<id>> sortedObjects(); // Returns the objects in -nextObject order and empties the heap. To get the objects without emptying the heap, copy the priority queue first.
    std::vector<oo::ObjCRef<id>> objectEnumerator(); // sortedObjects(): C++ iteration in nextObject() order (empties the heap)

    // -isEqual:, -hash and -copyWithZone: (a copy's capacity is its count).
    bool isEqual(OOPriorityQueue* object);
    NSUInteger hash();
    oo::Ref<OOPriorityQueue> copy();

    // The whole of what "%@" printed: <OOPriorityQueue 0x...>{count=n, capacity=n}.
    std::optional<std::string> description();

#if OO_DEBUG
    std::string debugDescription(); // (was -debugDescription, an Objective-C string)
#endif

#if DEBUG_GRAPHVIZ
    std::string generateGraphViz();
    void writeGraphVizToPath(const std::string& path);
#endif

private:
    bool initWithComparator(SEL comparator);

    void makeObjectsPerformSelector(SEL selector);

    void bubbleUpFrom(NSUInteger i);
    void bubbleDownFrom(NSUInteger i);

    void growBuffer();
    void shrinkBuffer();

    void removeObjectAtIndex(NSUInteger i);

#if OO_DEBUG
    void appendDebugDataToString(std::string& string, NSUInteger i, NSUInteger depth);
#endif

    SEL _comparator = { };
    OO_PQ_STRONG id* _heap = { };
    NSUInteger _count = { },
               _capacity = { };
};

#endif // OOPRIORITYQUEUE_H
