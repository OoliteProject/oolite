/*

OOProbabilitySet.m


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

#import "OOProbabilitySet.h"
#import "OOFoundationBridge.h"
#import "OOFunctionAttributes.h"
#import "legacy_random.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

namespace {

constexpr const char* kObjectsKey = "objects";
constexpr const char* kWeightsKey = "weights";

// The property list representation: the objects (each converted as oo::PListFrom converts it, as
// the Objective-C dictionary this was before was converted) and their weights (single reals, as
// +numberWithFloat: made them).
oo::PList PropertyListRepresentation(const id* objects, const float* weights, NSUInteger count)
{
    oo::PList::Array objectList, weightList;
    for (NSUInteger i = 0; i < count; ++i) {
        objectList.push_back(oo::PListFrom(objects[i]));
        weightList.push_back(oo::PList::singleReal(weights[i]));
    }
    oo::PList::Dict result;
    result.emplace(kObjectsKey, oo::PList(std::move(objectList)));
    result.emplace(kWeightsKey, oo::PList(std::move(weightList)));
    return oo::PList(std::move(result));
}

// -indexOfObject: of the old object array: the first object that is the same, or -isEqual:.
NSUInteger IndexOfObject(const std::vector<oo::ObjCRef<id>>& objects, id object)
{
    for (std::size_t i = 0; i < objects.size(); ++i) {
        id element = objects[i].get();
        if (element == object || [element isEqual:object])
            return i;
    }
    return NSNotFound;
}

} // namespace

@interface OOProbabilitySet (OOPrivate)

// Designated initializer. This must be used by subclasses, since init is overriden for public use.
- (id)initPriv;

@end

@interface OOEmptyProbabilitySet : OOProbabilitySet

+ (OOEmptyProbabilitySet*)singleton OO_RETURNS_RETAINED;

@end

@interface OOSingleObjectProbabilitySet : OOProbabilitySet {
@private
    id _object;
    float _weight;
}

- (id)initWithObject:(id)object weight:(float)weight;

@end

@interface OOConcreteProbabilitySet : OOProbabilitySet {
@private
    NSUInteger _count;
    id* _objects;
    float* _cumulativeWeights; // Each cumulative weight is weight of object at this index + weight of all objects to left.
    float _sumOfWeights;
}
@end

@interface OOConcreteMutableProbabilitySet : OOMutableProbabilitySet {
@private
    std::vector<oo::ObjCRef<id>> _objects;
    std::vector<float> _weights;
    float _sumOfWeights;
}

- (id)initPrivWithObjectArray:(const std::vector<oo::ObjCRef<id>>&)objects weightsArray:(const std::vector<float>&)weights sum:(float)sumOfWeights;

@end

static void ThrowAbstractionViolationException(id obj) GCC_ATTR((noreturn));

@implementation OOProbabilitySet

// Abstract class just tosses allocations over to concrete class, and throws exception if you try to use it directly.

+ (id)probabilitySet
{
    return [[OOEmptyProbabilitySet singleton] autorelease];
}

+ (id)probabilitySetWithObjects:(id*)objects weights:(float*)weights count:(NSUInteger)count
{
    return [[[self alloc] initWithObjects:objects weights:weights count:count] autorelease];
}

+ (id)probabilitySetWithPropertyListRepresentation:(const oo::PList&)plist
{
    return [[[self alloc] initWithPropertyListRepresentation:plist] autorelease];
}

- (id)init
{
    [self release];
    return [OOEmptyProbabilitySet singleton];
}

- (id)initWithObjects:(id*)objects weights:(float*)weights count:(NSUInteger)count
{
    OOZone* zone = [self zone];
    DESTROY(self);

    // Zero objects: return empty-set singleton.
    if (count == 0)
        return [OOEmptyProbabilitySet singleton];

    // If count is not zero and one of the paramters is nil, we've got us a programming error.
    if (objects == NULL || weights == NULL) {
        [OOException raise:OOInvalidArgumentException format:"Attempt to create %s with non-zero count but nil objects or weights.", "OOProbabilitySet"];
    }

    // Single object: simple one-object set. Expected to be quite common.
    if (count == 1)
        return [[OOSingleObjectProbabilitySet allocWithZone:zone] initWithObject:objects[0] weight:weights[0]];

    // Otherwise, use general implementation.
    return [[OOConcreteProbabilitySet allocWithZone:zone] initWithObjects:objects weights:weights count:count];
}

- (id)initWithPropertyListRepresentation:(const oo::PList&)plist
{
    const oo::PList& representation = plist;
    const oo::PList* objects = representation.find(kObjectsKey);
    const oo::PList* weights = representation.find(kWeightsKey);
    NSUInteger i = 0, count = 0;
    id* rawObjects = NULL;
    float* rawWeights = NULL;

    // Validate
    if (objects == nullptr || !objects->isArray() || weights == nullptr || !weights->isArray()) {
        [self release];
        return nil;
    }
    count = objects->count();
    if (count != weights->count()) {
        [self release];
        return nil;
    }

    // Extract contents.
    rawObjects = (id*)malloc(sizeof *rawObjects * count);
    rawWeights = (float*)malloc(sizeof *rawWeights * count);

    if (rawObjects != NULL || rawWeights != NULL) {
        // Extract objects.
        for (i = 0; i < count; ++i) {
            rawObjects[i] = oo::ObjectFromPList(*objects->at(i));
        }

        // Extract and convert weights.
        for (i = 0; i < count; ++i) {
            rawWeights[i] = fmax(weights->at<float>(i), 0.0f);
        }

        self = [self initWithObjects:rawObjects weights:rawWeights count:count];
    } else {
        [self release];
        self = nil;
    }

    // Clean up.
    free(rawObjects);
    free(rawWeights);

    return self;
}

- (id)initPriv
{
    return [super init];
}

- (id)descriptionComponents
{
    return oo::NSStringFrom(oo::str::format("count=%zu", [self count]));
}

- (oo::PList)propertyListRepresentation
{
    ThrowAbstractionViolationException(self);
}

- (id)randomObject
{
    ThrowAbstractionViolationException(self);
}

- (float)weightForObject:(id)object
{
    ThrowAbstractionViolationException(self);
}

- (float)sumOfWeights
{
    ThrowAbstractionViolationException(self);
}

- (NSUInteger)count
{
    ThrowAbstractionViolationException(self);
}

- (id)allObjects
{
    ThrowAbstractionViolationException(self);
}

- (id)copyWithZone:(OOZone*)zone
{
    if (zone == [self zone]) {
        return [self retain];
    } else {
        return [[OOProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:[self propertyListRepresentation]];
    }
}

- (id)mutableCopyWithZone:(OOZone*)zone
{
    return [[OOMutableProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:[self propertyListRepresentation]];
}

@end

@implementation OOProbabilitySet (OOExtendedProbabilitySet)

- (BOOL)containsObject:(id)object
{
    return [self weightForObject:object] >= 0.0f;
}

- (id)objectEnumerator
{
    return [[self allObjects] objectEnumerator];
}

- (float)probabilityForObject:(id)object
{
    float weight = [self weightForObject:object];
    if (weight > 0)
        weight /= [self sumOfWeights];

    return weight;
}

@end

static OOEmptyProbabilitySet* sOOEmptyProbabilitySetSingleton = nil;

@implementation OOEmptyProbabilitySet : OOProbabilitySet

+ (OOEmptyProbabilitySet*)singleton
{
    if (sOOEmptyProbabilitySetSingleton == nil) {
        sOOEmptyProbabilitySetSingleton = [[self alloc] init];
    }

    return sOOEmptyProbabilitySetSingleton;
}

- (oo::PList)propertyListRepresentation
{
    return PropertyListRepresentation(NULL, NULL, 0);
}

- (id)randomObject
{
    return nil;
}

- (float)weightForObject:(id)object
{
    return -1.0f;
}

- (float)sumOfWeights
{
    return 0.0f;
}

- (NSUInteger)count
{
    return 0;
}

- (id)allObjects
{
    return oo::NSArrayFromObjects(std::vector<id>());
}

- (id)mutableCopyWithZone:(OOZone*)zone
{
    // A mutable copy of an empty probability set is equivalent to a new empty mutable probability set.
    return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initPriv];
}

@end

@implementation OOEmptyProbabilitySet (Singleton)

/*	Canonical singleton boilerplate.
        See Cocoa Fundamentals Guide: Creating a Singleton Instance.
        See also +singleton above.

        NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(OOZone*)inZone
{
    if (sOOEmptyProbabilitySetSingleton == nil) {
        sOOEmptyProbabilitySetSingleton = [super allocWithZone:inZone];
        return sOOEmptyProbabilitySetSingleton;
    }
    return nil;
}

- (id)copyWithZone:(OOZone*)inZone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return UINT_MAX;
}

- (void)release
{
}

- (id)autorelease
{
    return self;
}

@end

@implementation OOSingleObjectProbabilitySet : OOProbabilitySet

- (id)initWithObject:(id)object weight:(float)weight
{
    if (object == nil) {
        [self release];
        return nil;
    }

    if ((self = [super initPriv])) {
        _object = [object retain];
        _weight = fmax(weight, 0.0f);
    }

    return self;
}

- (void)dealloc
{
    [_object release];

    [super dealloc];
}

- (oo::PList)propertyListRepresentation
{
    return PropertyListRepresentation(&_object, &_weight, 1);
}

- (id)randomObject
{
    return _object;
}

- (float)weightForObject:(id)object
{
    if ([_object isEqual:object])
        return _weight;
    else
        return -1.0f;
}

- (float)sumOfWeights
{
    return _weight;
}

- (NSUInteger)count
{
    return 1;
}

- (id)allObjects
{
    return oo::NSArrayFromObjects(std::vector<id> { _object });
}

- (id)mutableCopyWithZone:(OOZone*)zone
{
    return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initWithObjects:&_object weights:&_weight count:1];
}

@end

@implementation OOConcreteProbabilitySet

- (id)initWithObjects:(id*)objects weights:(float*)weights count:(NSUInteger)count
{
    NSUInteger i = 0;
    float cuWeight = 0.0f;

    assert(count > 1 && objects != NULL && weights != NULL);

    if ((self = [super initPriv])) {
        // Allocate arrays
        _objects = (id*)malloc(sizeof *objects * count);
        _cumulativeWeights = (float*)malloc(sizeof *_cumulativeWeights * count);
        if (_objects == NULL || _cumulativeWeights == NULL) {
            [self release];
            return nil;
        }

        // Fill in arrays, retain objects, add up weights.
        for (i = 0; i != count; ++i) {
            _objects[i] = [objects[i] retain];
            cuWeight += weights[i];
            _cumulativeWeights[i] = cuWeight;
        }
        _count = count;
        _sumOfWeights = cuWeight;
    }

    return self;
}

- (void)dealloc
{
    NSUInteger i = 0;

    if (_objects != NULL) {
        for (i = 0; i < _count; ++i) {
            [_objects[i] release];
        }
        free(_objects);
        _objects = NULL;
    }

    if (_cumulativeWeights != NULL) {
        free(_cumulativeWeights);
        _cumulativeWeights = NULL;
    }

    [super dealloc];
}

- (oo::PList)propertyListRepresentation
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

- (NSUInteger)count
{
    return _count;
}

- (id)privObjectForWeight:(float)target
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
    id result = _objects[idx];
    return result;
}

- (id)randomObject
{
    if (_sumOfWeights <= 0.0f)
        return nil;
    return [self privObjectForWeight:randf() * _sumOfWeights];
}

- (float)weightForObject:(id)object
{
    NSUInteger i;

    // Can't have nil in collection.
    if (object == nil)
        return -1.0f;

    // Perform linear search, then get weight by subtracting cumulative weight from cumulative weight to left.
    for (i = 0; i < _count; ++i) {
        if ([_objects[i] isEqual:object]) {
            float leftWeight = (i != 0) ? _cumulativeWeights[i - 1] : 0.0f;
            return _cumulativeWeights[i] - leftWeight;
        }
    }

    // If we got here, object not found.
    return -1.0f;
}

- (float)sumOfWeights
{
    return _sumOfWeights;
}

- (id)allObjects
{
    return oo::NSArrayFromObjects(std::vector<id>(_objects, _objects + _count));
}

- (id)objectEnumerator
{
    return [[self allObjects] objectEnumerator];
}

- (id)mutableCopyWithZone:(OOZone*)zone
{
    id result = nil;
    float* weights = NULL;
    NSUInteger i = 0;
    float weight = 0.0f, sum = 0.0f;

    // Convert cumulative weights to "plain" weights.
    weights = (float*)malloc(sizeof *weights * _count);
    if (weights == NULL)
        return nil;

    for (i = 0; i < _count; ++i) {
        weight = _cumulativeWeights[i];
        weights[i] = weight - sum;
        sum += weights[i];
    }

    result = [[OOConcreteMutableProbabilitySet allocWithZone:zone] initWithObjects:_objects weights:weights count:_count];
    free(weights);

    return result;
}

@end

@implementation OOMutableProbabilitySet

+ (id)probabilitySet
{
    return [[[OOConcreteMutableProbabilitySet alloc] initPriv] autorelease];
}

- (id)init
{
    OOZone* zone = [self zone];
    [self release];
    return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initPriv];
}

- (id)initWithObjects:(id*)objects weights:(float*)weights count:(NSUInteger)count
{
    OOZone* zone = [self zone];
    [self release];
    return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initWithObjects:objects weights:weights count:count];
}

- (id)initWithPropertyListRepresentation:(const oo::PList&)plist
{
    OOZone* zone = [self zone];
    [self release];
    return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:plist];
}

- (id)copyWithZone:(OOZone*)zone
{
    return [[OOProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:[self propertyListRepresentation]];
}

- (void)setWeight:(float)weight forObject:(id)object
{
    ThrowAbstractionViolationException(self);
}

- (void)removeObject:(id)object
{
    ThrowAbstractionViolationException(self);
}

@end

@implementation OOConcreteMutableProbabilitySet

- (id)initPriv
{
    self = [super initPriv]; // (the object and weight arrays start empty)

    return self;
}

// For internal use by mutableCopy
- (id)initPrivWithObjectArray:(const std::vector<oo::ObjCRef<id>>&)objects weightsArray:(const std::vector<float>&)weights sum:(float)sumOfWeights
{
    assert(objects.size() == weights.size() && sumOfWeights >= 0.0f);

    if ((self = [super initPriv])) {
        _objects = objects;
        _weights = weights;
        _sumOfWeights = sumOfWeights;
    }

    return self;
}

- (id)initWithObjects:(id*)objects weights:(float*)weights count:(NSUInteger)count
{
    NSUInteger i = 0;

    // Validate parameters.
    if (count != 0 && (objects == NULL || weights == NULL)) {
        [self release];
        [OOException raise:OOInvalidArgumentException format:"Attempt to create %s with non-zero count but nil objects or weights.", "OOMutableProbabilitySet"];
    }

    // Set up & go.
    if ((self = [self initPriv])) {
        for (i = 0; i != count; ++i) {
            [self setWeight:fmax(weights[i], 0.0f) forObject:objects[i]];
        }
    }

    return self;
}

- (id)initWithPropertyListRepresentation:(const oo::PList&)plist
{
    BOOL OK = YES;
    const oo::PList& representation = plist;
    const oo::PList* objects = nullptr;
    const oo::PList* weights = nullptr;
    NSUInteger i = 0, count = 0;

    if (!(self = [super initPriv]))
        OK = NO;

    if (OK) {
        objects = representation.find(kObjectsKey);
        weights = representation.find(kWeightsKey);

        // Validate
        if (objects == nullptr || !objects->isArray() || weights == nullptr || !weights->isArray())
            OK = NO;
        else {
            count = objects->count();
            if (count != weights->count())
                OK = NO;
        }
    }

    if (OK) {
        for (i = 0; i < count; ++i) {
            [self setWeight:weights->at<float>(i) forObject:oo::ObjectFromPList(*objects->at(i))];
        }
    }

    if (!OK) {
        [self release];
        self = nil;
    }

    return self;
}

- (void)dealloc
{
    _objects.clear();
    _weights.clear();

    [super dealloc];
}

- (oo::PList)propertyListRepresentation
{
    std::vector<id> objects;
    for (const oo::ObjCRef<id>& object : _objects)
        objects.push_back(object.get());
    return PropertyListRepresentation(objects.data(), _weights.data(), objects.size());
}

- (NSUInteger)count
{
    return _objects.size();
}

- (id)randomObject
{
    float target = 0.0f, sum = 0.0f, sumOfWeights;
    NSUInteger i = 0, count = 0;

    sumOfWeights = [self sumOfWeights];
    target = randf() * sumOfWeights;
    count = _objects.size();
    if (count == 0 || sumOfWeights <= 0.0f)
        return nil;

    for (i = 0; i < count; ++i) {
        sum += _weights[i];
        if (sum >= target)
            return _objects[i].get();
    }

    OO_LOG("probabilitySet.broken", "{} fell off end, returning first object. Nominal sum = {:f}, target = {:f}, actual sum = {:f}, count = {}. {}", __PRETTY_FUNCTION__, sumOfWeights, target, sum, count, "This is an internal error, please report it.");
    return _objects[0].get();
}

- (float)weightForObject:(id)object
{
    float result = -1.0f;

    if (object != nil) {
        NSUInteger index = IndexOfObject(_objects, object);
        if (index != NSNotFound) {
            result = _weights[index];
            if (index != 0)
                result -= _weights[index - 1];
        }
    }
    return result;
}

- (float)sumOfWeights
{
    if (_sumOfWeights < 0.0f) {
        NSUInteger i, count;
        count = [self count];

        _sumOfWeights = 0.0f;
        for (i = 0; i < count; ++i) {
            _sumOfWeights += _weights[i];
        }
    }
    return _sumOfWeights;
}

- (id)allObjects
{
    return oo::NSArrayFromObjects(_objects);
}

- (id)objectEnumerator
{
    return [[self allObjects] objectEnumerator];
}

- (void)setWeight:(float)weight forObject:(id)object
{
    if (object == nil)
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

- (void)removeObject:(id)object
{
    if (object == nil)
        return;

    NSUInteger index = IndexOfObject(_objects, object);
    if (index != NSNotFound) {
        _objects.erase(_objects.begin() + static_cast<std::ptrdiff_t>(index));
        _sumOfWeights = -1.0f; // Simply subtracting the relevant weight doesn't work if the weight is large, due to floating-point precision issues.
        _weights.erase(_weights.begin() + static_cast<std::ptrdiff_t>(index));
    }
}

- (id)copyWithZone:(OOZone*)zone
{
    id result = nil;
    id* objects = NULL;
    float* weights = NULL;
    NSUInteger i = 0, count = 0;

    count = _objects.size();
    if (EXPECT_NOT(count == 0))
        return [OOEmptyProbabilitySet singleton];

    objects = (id*)malloc(sizeof *objects * count);
    weights = (float*)malloc(sizeof *weights * count);
    if (objects != NULL && weights != NULL) {
        for (i = 0; i < count; ++i) {
            objects[i] = _objects[i].get();
        }

        for (i = 0; i < count; ++i) {
            weights[i] = _weights[i];
        }

        result = [[OOProbabilitySet probabilitySetWithObjects:objects weights:weights count:count] retain];
    }

    if (objects != NULL)
        free(objects);
    if (weights != NULL)
        free(weights);

    return result;
}

- (id)mutableCopyWithZone:(OOZone*)zone
{
    // (the arrays are copied; zones are unused)
    return [[OOConcreteMutableProbabilitySet alloc] initPrivWithObjectArray:_objects
                                                               weightsArray:_weights
                                                                        sum:_sumOfWeights];
}

@end

static void ThrowAbstractionViolationException(id obj)
{
    [OOException raise:OOGenericException format:"Attempt to use abstract class %s - this indicates an incorrect initialization.", class_getName(object_getClass(obj))];
    abort(); // unreachable
}
