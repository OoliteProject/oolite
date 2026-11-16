/*

OOProbabilitySet.mm

C++20 since bead oo-489v (proposed ADR-0056, the OOColor house style). The class cluster is a C++
hierarchy; method bodies are the Objective-C ones with message sends turned into calls. Still
Objective-C++ until Phase 4: an Object node element is an Objective-C object.


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


IMPLEMENTATION NOTES
OOProbabilitySet is implemented as a class cluster with two abstract classes,
two special-case implementations for immutable sets with zero or one object,
and two general implementations (one mutable and one immutable). The general
implementations are the only non-trivial ones.

The general immutable implementation, OOConcreteProbabilitySet, consists of
two parallel arrays, one of objects and one of cumulative weights. The
"cumulative weight" for an entry is the sum of its weight and the cumulative
weight of the entry to the left (i.e., with a lower index), with the implicit
entry -1 having a cumulative weight of 0. Since weight cannot be negative,
this means that cumulative weights increase to the right (not strictly
increasing, though, since weights may be zero). We can thus find an object
with a given cumulative weight through a binary search.

OOConcreteMutableProbabilitySet is a naïve implementation using arrays. It
could be optimized, but isn't expected to be used much except for building
sets that will then be immutablized.

*/

#include "OOProbabilitySet.h"
#include "OOFunctionAttributes.h"
#include "OOObjCPList.h"
#include "legacy_random.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

namespace {

constexpr const char* kObjectsKey = "objects";
constexpr const char* kWeightsKey = "weights";

// The property list representation: the objects (the elements themselves, as oo::PListFrom
// converted the Objective-C objects they were) and their weights (single reals, as
// +numberWithFloat: made them).
oo::PList PropertyListRepresentation(const oo::PList* objects, const float* weights, NSUInteger count)
{
    oo::PList::Array objectList, weightList;
    for (NSUInteger i = 0; i < count; ++i) {
        objectList.push_back(objects[i]);
        weightList.push_back(oo::PList::singleReal(weights[i]));
    }
    oo::PList::Dict result;
    result.emplace(kObjectsKey, oo::PList(std::move(objectList)));
    result.emplace(kWeightsKey, oo::PList(std::move(weightList)));
    return oo::PList(std::move(result));
}

// -isEqual: of the objects the elements were: == of two values (a string is equal to the same
// string); an Object node is equal to the same node. (A node holding an Objective-C object, equal to
// one holding the same or an -isEqual: object, went with bead oo-4aq6a.5: no game object is one.)
bool SameElement(const oo::PList& element, const oo::PList& object)
{
    return element == object;
}

// -indexOfObject: of the old object array: the first object that is the same, or -isEqual:.
NSUInteger IndexOfObject(const std::vector<oo::PList>& objects, const oo::PList& object)
{
    for (std::size_t i = 0; i < objects.size(); ++i) {
        if (SameElement(objects[i], object))
            return i;
    }
    return NSNotFound;
}

} // namespace

namespace {

class OOEmptyProbabilitySet final : public OOProbabilitySet {
public:
    static OOEmptyProbabilitySet* singleton();

    oo::PList propertyListRepresentation() override;
    oo::PList randomObject() override;
    float weightForObject(const oo::PList& object) override;
    float sumOfWeights() override;
    NSUInteger count() override;
    std::vector<oo::PList> allElements() override;
    oo::Ref<OOMutableProbabilitySet> mutableCopy() override;
};

class OOSingleObjectProbabilitySet final : public OOProbabilitySet {
public:
    bool initWithObject(const oo::PList& object, float weight);

    oo::PList propertyListRepresentation() override;
    oo::PList randomObject() override;
    float weightForObject(const oo::PList& object) override;
    float sumOfWeights() override;
    NSUInteger count() override;
    std::vector<oo::PList> allElements() override;
    oo::Ref<OOMutableProbabilitySet> mutableCopy() override;

private:
    oo::PList _object = { };
    float _weight = { };
};

class OOConcreteProbabilitySet final : public OOProbabilitySet {
public:
    ~OOConcreteProbabilitySet() override;

    bool initWithObjects(const oo::PList* objects, const float* weights, NSUInteger count);

    oo::PList propertyListRepresentation() override;
    NSUInteger count() override;
    oo::PList randomObject() override;
    float weightForObject(const oo::PList& object) override;
    float sumOfWeights() override;
    std::vector<oo::PList> allElements() override;
    oo::Ref<OOMutableProbabilitySet> mutableCopy() override;

private:
    oo::PList privObjectForWeight(float target);

    NSUInteger _count = { };
    oo::PList* _objects = { };
    float* _cumulativeWeights = { }; // Each cumulative weight is weight of object at this index + weight of all objects to left.
    float _sumOfWeights = { };
};

class OOConcreteMutableProbabilitySet final : public OOMutableProbabilitySet {
public:
    // (-initPriv, which leaves the object and weight arrays empty, is the constructor.)
    void initPrivWithObjectArray(const std::vector<oo::PList>& objects, const std::vector<float>& weights, float sumOfWeights); // For internal use by mutableCopy
    void initWithObjects(const oo::PList* objects, const float* weights, NSUInteger count);
    bool initWithPropertyListRepresentation(const oo::PList& plist);

    oo::PList propertyListRepresentation() override;
    NSUInteger count() override;
    oo::PList randomObject() override;
    float weightForObject(const oo::PList& object) override;
    float sumOfWeights() override;
    std::vector<oo::PList> allElements() override;
    void setWeight(float weight, const oo::PList& object) override;
    void removeObject(const oo::PList& object) override;
    oo::Ref<OOProbabilitySet> copy() override;
    oo::Ref<OOMutableProbabilitySet> mutableCopy() override;

private:
    std::vector<oo::PList> _objects = { };
    std::vector<float> _weights = { };
    float _sumOfWeights = { };
};

oo::Ref<OOMutableProbabilitySet> MakeConcreteMutable(const oo::PList* objects, const float* weights, NSUInteger count)
{
    oo::Ref<OOConcreteMutableProbabilitySet> result = oo::makeRef<OOConcreteMutableProbabilitySet>();
    result->initWithObjects(objects, weights, count);
    return result;
}

} // namespace

// Abstract class just tosses allocations over to concrete class.

oo::Ref<OOProbabilitySet> OOProbabilitySet::probabilitySet()
{
    return oo::Ref<OOProbabilitySet>(OOEmptyProbabilitySet::singleton());
}

oo::Ref<OOProbabilitySet> OOProbabilitySet::probabilitySetWithObjects(const oo::PList* objects, const float* weights, NSUInteger count)
{
    // Zero objects: return empty-set singleton.
    if (count == 0)
        return probabilitySet();

    // If count is not zero and one of the paramters is nil, we've got us a programming error.
    if (objects == NULL || weights == NULL) {
        OORaiseException(OOInvalidArgumentException, "Attempt to create %s with non-zero count but nil objects or weights.", "OOProbabilitySet");
        abort(); // unreachable: +raise:format: does not return (the analyser cannot see that through a message)
    }

    // Single object: simple one-object set. Expected to be quite common.
    if (count == 1) {
        oo::Ref<OOSingleObjectProbabilitySet> result = oo::makeRef<OOSingleObjectProbabilitySet>();
        if (!result->initWithObject(objects[0], weights[0]))
            return nullptr;
        return result;
    }

    // Otherwise, use general implementation.
    oo::Ref<OOConcreteProbabilitySet> result = oo::makeRef<OOConcreteProbabilitySet>();
    if (!result->initWithObjects(objects, weights, count))
        return nullptr;
    return result;
}

oo::Ref<OOProbabilitySet> OOProbabilitySet::probabilitySetWithPropertyListRepresentation(const oo::PList& plist)
{
    const oo::PList& representation = plist;
    const oo::PList* objects = representation.find(kObjectsKey);
    const oo::PList* weights = representation.find(kWeightsKey);
    NSUInteger i = 0, count = 0;
    std::vector<oo::PList> rawObjects;
    std::vector<float> rawWeights;

    // Validate
    if (objects == nullptr || !objects->isArray() || weights == nullptr || !weights->isArray()) {
        return nullptr;
    }
    count = objects->count();
    if (count != weights->count()) {
        return nullptr;
    }

    // Extract contents.
    rawObjects.reserve(count);
    rawWeights.reserve(count);

    // Extract objects.
    for (i = 0; i < count; ++i) {
        rawObjects.push_back(*objects->at(i));
    }

    // Extract and convert weights.
    for (i = 0; i < count; ++i) {
        rawWeights.push_back(fmax(weights->at<float>(i), 0.0f));
    }

    return probabilitySetWithObjects(rawObjects.data(), rawWeights.data(), count);
}

// oo::DescriptionOf (OODescription.h) wraps this as "<Class 0x...>{count=N}", as the legacy
// -descriptionComponents did.
std::optional<std::string> OOProbabilitySet::descriptionComponents() const
{
    // (count() is not const; the fixed const signature, ADR-0055 item 1, reaches it through a cast)
    return oo::str::format("count=%zu", const_cast<OOProbabilitySet*>(this)->count());
}

oo::Ref<OOProbabilitySet> OOProbabilitySet::copy()
{
    // Immutable: a copy is the set itself. (-copyWithZone: made a new set through the property
    // list only for a different zone, which C++ does not have.)
    return oo::Ref<OOProbabilitySet>(this);
}

oo::Ref<OOMutableProbabilitySet> OOProbabilitySet::mutableCopy()
{
    return OOMutableProbabilitySet::probabilitySetWithPropertyListRepresentation(propertyListRepresentation());
}

// (OOExtendedProbabilitySet)

bool OOProbabilitySet::containsObject(const oo::PList& object)
{
    return weightForObject(object) >= 0.0f;
}

float OOProbabilitySet::probabilityForObject(const oo::PList& object)
{
    float weight = weightForObject(object);
    if (weight > 0)
        weight /= sumOfWeights();

    return weight;
}

namespace {

OOEmptyProbabilitySet* sOOEmptyProbabilitySetSingleton = nullptr; // never released (it was an immortal singleton)

OOEmptyProbabilitySet* OOEmptyProbabilitySet::singleton()
{
    if (sOOEmptyProbabilitySetSingleton == nullptr) {
        sOOEmptyProbabilitySetSingleton = new OOEmptyProbabilitySet();
    }

    return sOOEmptyProbabilitySetSingleton;
}

oo::PList OOEmptyProbabilitySet::propertyListRepresentation()
{
    return PropertyListRepresentation(NULL, NULL, 0);
}

oo::PList OOEmptyProbabilitySet::randomObject()
{
    return oo::PList();
}

float OOEmptyProbabilitySet::weightForObject(const oo::PList& /*object*/)
{
    return -1.0f;
}

float OOEmptyProbabilitySet::sumOfWeights()
{
    return 0.0f;
}

NSUInteger OOEmptyProbabilitySet::count()
{
    return 0;
}

std::vector<oo::PList> OOEmptyProbabilitySet::allElements()
{
    return std::vector<oo::PList>();
}

oo::Ref<OOMutableProbabilitySet> OOEmptyProbabilitySet::mutableCopy()
{
    // A mutable copy of an empty probability set is equivalent to a new empty mutable probability set.
    return oo::makeRef<OOConcreteMutableProbabilitySet>();
}

bool OOSingleObjectProbabilitySet::initWithObject(const oo::PList& object, float weight)
{
    if (object.isNull()) {
        return false;
    }

    _object = object;
    _weight = fmax(weight, 0.0f);

    return true;
}

oo::PList OOSingleObjectProbabilitySet::propertyListRepresentation()
{
    return PropertyListRepresentation(&_object, &_weight, 1);
}

oo::PList OOSingleObjectProbabilitySet::randomObject()
{
    return _object;
}

float OOSingleObjectProbabilitySet::weightForObject(const oo::PList& object)
{
    if (SameElement(_object, object))
        return _weight;
    else
        return -1.0f;
}

float OOSingleObjectProbabilitySet::sumOfWeights()
{
    return _weight;
}

NSUInteger OOSingleObjectProbabilitySet::count()
{
    return 1;
}

std::vector<oo::PList> OOSingleObjectProbabilitySet::allElements()
{
    return std::vector<oo::PList> { _object };
}

oo::Ref<OOMutableProbabilitySet> OOSingleObjectProbabilitySet::mutableCopy()
{
    return MakeConcreteMutable(&_object, &_weight, 1);
}

bool OOConcreteProbabilitySet::initWithObjects(const oo::PList* objects, const float* weights, NSUInteger count)
{
    NSUInteger i = 0;
    float cuWeight = 0.0f;

    assert(count > 1 && objects != NULL && weights != NULL);
    if (objects == NULL || weights == NULL) {
        // Unreachable (probabilitySetWithObjects() raises first); copying an element
        // forms a reference, where the old -retain of an id element was a message to nil.
        return false;
    }

    // Allocate arrays
    _objects = new oo::PList[count];
    _cumulativeWeights = (float*)malloc(sizeof *_cumulativeWeights * count);
    if (_cumulativeWeights == NULL) {
        return false;
    }

    // Fill in arrays, copy objects, add up weights.
    for (i = 0; i != count; ++i) {
        _objects[i] = objects[i];
        cuWeight += weights[i];
        _cumulativeWeights[i] = cuWeight;
    }
    _count = count;
    _sumOfWeights = cuWeight;

    return true;
}

OOConcreteProbabilitySet::~OOConcreteProbabilitySet()
{
    delete[] _objects;
    _objects = NULL;

    if (_cumulativeWeights != NULL) {
        free(_cumulativeWeights);
        _cumulativeWeights = NULL;
    }
}

oo::PList OOConcreteProbabilitySet::propertyListRepresentation()
{
    std::vector<float> weights;
    float cuWeight = 0.0f, sum = 0.0f;
    NSUInteger i = 0;

    weights.reserve(_count);
    for (i = 0; i < _count; ++i) {
        cuWeight = _cumulativeWeights[i];
        weights.push_back(cuWeight - sum);
        sum = cuWeight;
    }

    return PropertyListRepresentation(_objects, weights.data(), _count);
}

NSUInteger OOConcreteProbabilitySet::count()
{
    return _count;
}

oo::PList OOConcreteProbabilitySet::privObjectForWeight(float target)
{
    /*	Select an object at random. This is a binary search in the cumulative
            weights array. Since weights of zero are allowed, there may be several
            objects with the same cumulative weight, in which case we select the
            leftmost, i.e. the one where the delta is non-zero.
    */

    NSUInteger low = 0, high = _count - 1, idx = 0;
    float weight = 0.0f;

    while (low < high) {
        idx = (low + high) / 2;
        weight = _cumulativeWeights[idx];
        if (weight > target) {
            if (EXPECT_NOT(idx == 0))
                break;
            high = idx - 1;
        } else if (weight < target)
            low = idx + 1;
        else
            break;
    }

    if (weight > target) {
        while (idx > 0 && _cumulativeWeights[idx - 1] >= target)
            --idx;
    } else {
        while (idx < (_count - 1) && _cumulativeWeights[idx] < target)
            ++idx;
    }

    assert(idx < _count);
    return _objects[idx];
}

oo::PList OOConcreteProbabilitySet::randomObject()
{
    if (_sumOfWeights <= 0.0f)
        return oo::PList();
    return privObjectForWeight(randf() * _sumOfWeights);
}

float OOConcreteProbabilitySet::weightForObject(const oo::PList& object)
{
    NSUInteger i;

    // Can't have a null object in collection.
    if (object.isNull())
        return -1.0f;

    // Perform linear search, then get weight by subtracting cumulative weight from cumulative weight to left.
    for (i = 0; i < _count; ++i) {
        if (SameElement(_objects[i], object)) {
            float leftWeight = (i != 0) ? _cumulativeWeights[i - 1] : 0.0f;
            return _cumulativeWeights[i] - leftWeight;
        }
    }

    // If we got here, object not found.
    return -1.0f;
}

float OOConcreteProbabilitySet::sumOfWeights()
{
    return _sumOfWeights;
}

std::vector<oo::PList> OOConcreteProbabilitySet::allElements()
{
    return std::vector<oo::PList>(_objects, _objects + _count);
}

oo::Ref<OOMutableProbabilitySet> OOConcreteProbabilitySet::mutableCopy()
{
    oo::Ref<OOMutableProbabilitySet> result;
    float* weights = NULL;
    NSUInteger i = 0;
    float weight = 0.0f, sum = 0.0f;

    // Convert cumulative weights to "plain" weights.
    weights = (float*)malloc(sizeof *weights * _count);
    if (weights == NULL)
        return nullptr;

    for (i = 0; i < _count; ++i) {
        weight = _cumulativeWeights[i];
        weights[i] = weight - sum;
        sum += weights[i];
    }

    result = MakeConcreteMutable(_objects, weights, _count);
    free(weights);

    return result;
}

} // namespace

oo::Ref<OOMutableProbabilitySet> OOMutableProbabilitySet::probabilitySet()
{
    return oo::makeRef<OOConcreteMutableProbabilitySet>();
}

oo::Ref<OOMutableProbabilitySet> OOMutableProbabilitySet::probabilitySetWithObjects(const oo::PList* objects, const float* weights, NSUInteger count)
{
    return MakeConcreteMutable(objects, weights, count);
}

oo::Ref<OOMutableProbabilitySet> OOMutableProbabilitySet::probabilitySetWithPropertyListRepresentation(const oo::PList& plist)
{
    oo::Ref<OOConcreteMutableProbabilitySet> result = oo::makeRef<OOConcreteMutableProbabilitySet>();
    if (!result->initWithPropertyListRepresentation(plist))
        return nullptr;
    return result;
}

oo::Ref<OOProbabilitySet> OOMutableProbabilitySet::copy()
{
    return OOProbabilitySet::probabilitySetWithPropertyListRepresentation(propertyListRepresentation());
}

namespace {

// For internal use by mutableCopy
void OOConcreteMutableProbabilitySet::initPrivWithObjectArray(const std::vector<oo::PList>& objects, const std::vector<float>& weights, float sumOfWeights)
{
    assert(objects.size() == weights.size() && sumOfWeights >= 0.0f);

    _objects = objects;
    _weights = weights;
    _sumOfWeights = sumOfWeights;
}

void OOConcreteMutableProbabilitySet::initWithObjects(const oo::PList* objects, const float* weights, NSUInteger count)
{
    NSUInteger i = 0;

    // Validate parameters.
    if (count != 0 && (objects == NULL || weights == NULL)) {
        OORaiseException(OOInvalidArgumentException, "Attempt to create %s with non-zero count but nil objects or weights.", "OOMutableProbabilitySet");
        abort(); // unreachable: +raise:format: does not return (the analyser cannot see that through a message)
    }

    // Set up & go.
    for (i = 0; i != count; ++i) {
        setWeight(fmax(weights[i], 0.0f), objects[i]);
    }
}

bool OOConcreteMutableProbabilitySet::initWithPropertyListRepresentation(const oo::PList& plist)
{
    bool OK = true;
    const oo::PList& representation = plist;
    const oo::PList* objects = nullptr;
    const oo::PList* weights = nullptr;
    NSUInteger i = 0, count = 0;

    if (OK) {
        objects = representation.find(kObjectsKey);
        weights = representation.find(kWeightsKey);

        // Validate
        if (objects == nullptr || !objects->isArray() || weights == nullptr || !weights->isArray())
            OK = false;
        else {
            count = objects->count();
            if (count != weights->count())
                OK = false;
        }
    }

    if (OK) {
        for (i = 0; i < count; ++i) {
            setWeight(weights->at<float>(i), *objects->at(i));
        }
    }

    return OK;
}

oo::PList OOConcreteMutableProbabilitySet::propertyListRepresentation()
{
    return PropertyListRepresentation(_objects.data(), _weights.data(), _objects.size());
}

NSUInteger OOConcreteMutableProbabilitySet::count()
{
    return _objects.size();
}

oo::PList OOConcreteMutableProbabilitySet::randomObject()
{
    float target = 0.0f, sum = 0.0f, sumOfWeights;
    NSUInteger i = 0, count = 0;

    sumOfWeights = this->sumOfWeights();
    target = randf() * sumOfWeights;
    count = _objects.size();
    if (count == 0 || sumOfWeights <= 0.0f)
        return oo::PList();

    for (i = 0; i < count; ++i) {
        sum += _weights[i];
        if (sum >= target)
            return _objects[i];
    }

    OO_LOG("probabilitySet.broken", "{} fell off end, returning first object. Nominal sum = {:f}, target = {:f}, actual sum = {:f}, count = {}. {}", __PRETTY_FUNCTION__, sumOfWeights, target, sum, count, "This is an internal error, please report it.");
    return _objects[0];
}

float OOConcreteMutableProbabilitySet::weightForObject(const oo::PList& object)
{
    float result = -1.0f;

    if (!object.isNull()) {
        NSUInteger index = IndexOfObject(_objects, object);
        if (index != NSNotFound) {
            result = _weights[index];
            if (index != 0)
                result -= _weights[index - 1];
        }
    }
    return result;
}

float OOConcreteMutableProbabilitySet::sumOfWeights()
{
    if (_sumOfWeights < 0.0f) {
        NSUInteger i, count;
        count = this->count();

        _sumOfWeights = 0.0f;
        for (i = 0; i < count; ++i) {
            _sumOfWeights += _weights[i];
        }
    }
    return _sumOfWeights;
}

std::vector<oo::PList> OOConcreteMutableProbabilitySet::allElements()
{
    return _objects;
}

void OOConcreteMutableProbabilitySet::setWeight(float weight, const oo::PList& object)
{
    if (object.isNull())
        return;

    weight = fmax(weight, 0.0f);
    NSUInteger index = IndexOfObject(_objects, object);
    if (index == NSNotFound) {
        _objects.emplace_back(object);
        _weights.push_back(weight);
        if (_sumOfWeights >= 0) {
            _sumOfWeights += weight;
        }
        // Else, _sumOfWeights is invalid and will need to be recalculated on demand.
    } else {
        _sumOfWeights = -1.0f; // Simply subtracting the relevant weight doesn't work if the weight is large, due to floating-point precision issues.
        _weights[index] = weight;
    }
}

void OOConcreteMutableProbabilitySet::removeObject(const oo::PList& object)
{
    if (object.isNull())
        return;

    NSUInteger index = IndexOfObject(_objects, object);
    if (index != NSNotFound) {
        _objects.erase(_objects.begin() + static_cast<std::ptrdiff_t>(index));
        _sumOfWeights = -1.0f; // Simply subtracting the relevant weight doesn't work if the weight is large, due to floating-point precision issues.
        _weights.erase(_weights.begin() + static_cast<std::ptrdiff_t>(index));
    }
}

oo::Ref<OOProbabilitySet> OOConcreteMutableProbabilitySet::copy()
{
    NSUInteger count = 0;

    count = _objects.size();
    if (EXPECT_NOT(count == 0))
        return OOProbabilitySet::probabilitySet();

    return OOProbabilitySet::probabilitySetWithObjects(_objects.data(), _weights.data(), count);
}

oo::Ref<OOMutableProbabilitySet> OOConcreteMutableProbabilitySet::mutableCopy()
{
    // (the arrays are copied)
    oo::Ref<OOConcreteMutableProbabilitySet> result = oo::makeRef<OOConcreteMutableProbabilitySet>();
    result->initPrivWithObjectArray(_objects, _weights, _sumOfWeights);
    return result;
}

} // namespace
