/*

OOProbabilitySet.h

A collection for selecting objects randomly, with probability weighting.
Probability weights can be 0 - an object may be in the set but not selectable.
Comes in mutable and immutable variants.

Performance characteristics:
  *	randomObject(), the primary method, is O(log n) for immutable
        OOProbabilitySets and O(n) for mutable ones.
  *	containsObject() and probabilityForObject() are O(n). This could be
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

#ifndef OOPROBABILITYSET_H
#define OOPROBABILITYSET_H

#include "OOFoundation.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

/*	C++20 since bead oo-489v (proposed ADR-0056, the OOColor house style). The class cluster is a
        C++ hierarchy: the two abstract classes here, and the four concrete ones private to
        OOProbabilitySet.mm. Its callers (OOShipRegistry, Universe) were adapted in the same bead, so
        there is no Objective-C facade and the classes are global.
*/
class OOMutableProbabilitySet;

class OOProbabilitySet : public oo::RefCounted {
public:
    // The elements are oo::PList values (proposed ADR-0055 item 2): ship keys are strings; an
    // Object node (oo::PListObject) carries an Objective-C object. Two elements are the same if they
    // are == or are Object nodes holding the same object or -isEqual: objects.
    // The factories are the class cluster's +alloc/-init...: an immutable set, null where the
    // initialiser returned nil.
    static oo::Ref<OOProbabilitySet> probabilitySet(); // the empty set: one shared object
    static oo::Ref<OOProbabilitySet> probabilitySetWithObjects(const oo::PList* objects, const float* weights, NSUInteger count);
    static oo::Ref<OOProbabilitySet> probabilitySetWithPropertyListRepresentation(const oo::PList& plist);

    // propertyListRepresentation is only valid if objects are property list objects.
    virtual oo::PList propertyListRepresentation() = 0;

    virtual NSUInteger count() = 0;
    virtual oo::PList randomObject() = 0; // A null PList for none (an empty set, or every weight zero).

    virtual float weightForObject(const oo::PList& object) = 0; // Returns -1 for unknown objects.
    virtual float sumOfWeights() = 0;
    virtual std::vector<oo::PList> allElements() = 0; // the elements, in the same order (-cxx_allObjects is OOWeakSet's family)

    // (OOExtendedProbabilitySet)
    bool containsObject(const oo::PList& object);
    float probabilityForObject(const oo::PList& object); // Returns -1 for unknown objects, or a value from 0 to 1 inclusive for known objects.

    // -copy (an immutable set) and -mutableCopy.
    virtual oo::Ref<OOProbabilitySet> copy();
    virtual oo::Ref<OOMutableProbabilitySet> mutableCopy();

    // What "%@" printed between the braces of <Class 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;
};

class OOMutableProbabilitySet : public OOProbabilitySet {
public:
    // The same factories, for a mutable set (+probabilitySet: a new empty one).
    static oo::Ref<OOMutableProbabilitySet> probabilitySet();
    static oo::Ref<OOMutableProbabilitySet> probabilitySetWithObjects(const oo::PList* objects, const float* weights, NSUInteger count);
    static oo::Ref<OOMutableProbabilitySet> probabilitySetWithPropertyListRepresentation(const oo::PList& plist);

    virtual void setWeight(float weight, const oo::PList& object) = 0; // Adds object if needed; a null object is ignored.
    virtual void removeObject(const oo::PList& object) = 0;

    oo::Ref<OOProbabilitySet> copy() override;
};

#endif // OOPROBABILITYSET_H
