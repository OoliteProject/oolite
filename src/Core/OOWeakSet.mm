/*

OOWeakSet.m

Written by Jens Ayton in 2012 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OOWeakSet.h"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

namespace {

// The objects behind the live references, in insertion order.
std::vector<oo::ObjCRef<id>> LiveObjects(const std::vector<oo::ObjCRef<OOWeakReference*>>& references)
{
    std::vector<oo::ObjCRef<id>> result;
    result.reserve(references.size());
    for (const auto& weakRef : references) {
        id object = oo::ToCxx(weakRef.get())->weakRefUnderlyingObject();
        if (object != nil)
            result.emplace_back(object);
    }
    return result;
}

} // namespace

OOWeakSet::OOWeakSet(NSUInteger capacity)
{
    _objects.reserve(capacity);
}

oo::Ref<OOWeakSet> OOWeakSet::set()
{
    return oo::makeRef<OOWeakSet>();
}

oo::Ref<OOWeakSet> OOWeakSet::setWithCapacity(NSUInteger capacity)
{
    return oo::makeRef<OOWeakSet>(capacity);
}

OOWeakSet::~OOWeakSet()
{
    _objects.clear();
}

std::optional<std::string> OOWeakSet::description()
{
    // DescriptionOf([self class]) and the facade's address (amendments oo-3lj8 item 4, oo-bhb9 item 6).
    std::string result = oo::str::format("<%s %s>{", "OOWeakSet", oo::str::pointerDescription(this).c_str());
    bool first = true;
    for (const oo::ObjCRef<id>& object : LiveObjects(_objects)) {
        if (!first)
            result += ", ";
        else
            first = false;

        result += oo::ShortDescriptionOf(object.get()); // every object answered -shortDescription
    }

    result += "}";
    return result;
}

// MARK: Protocol conformance

oo::Ref<OOWeakSet> OOWeakSet::copyWithZone(OOZone* /*zone*/)
{
    compact();
    oo::Ref<OOWeakSet> result = oo::makeRef<OOWeakSet>();
    for (const oo::ObjCRef<id>& object : objectEnumerator())
        result->addObject(object.get()); // as -addObjectsByEnumerating: of the snapshot did
    return result;
}

bool OOWeakSet::isEqual(OOWeakSet* other)
{
    // (-isEqual:'s -isKindOfClass: test is the facade's; null is "not a weak set".)
    if (other == nullptr)
        return false;
    if (count() != other->count())
        return false;

    bool result = true;
    for (const oo::ObjCRef<id>& object : objectEnumerator()) {
        if (!other->containsObject(object.get())) {
            result = false;
            break;
        }
    }

    return result;
}

// MARK: Meat and potatoes

NSUInteger OOWeakSet::count()
{
    compact();
    return _objects.size();
}

bool OOWeakSet::containsObject(id object)
{
    compact();
    // (a live object has one weak reference, so membership is identity, as the set's was)
    ::OOWeakReference* weakObj = [object weakRetain];
    bool result = std::find_if(_objects.begin(), _objects.end(), [weakObj](const auto& ref) { return ref.get() == weakObj; }) != _objects.end();
    [weakObj release];
    return result;
}

std::vector<oo::ObjCRef<id>> OOWeakSet::objectEnumerator()
{
    return LiveObjects(_objects);
}

void OOWeakSet::addObject(id object)
{
    if (object == nil)
        return;

    OOCAssert([object conformsToProtocol:objc_getProtocol("OOWeakReferenceSupport")], "Attempt to add object to OOWeakSet which does not conform to OOWeakReferenceSupport.");
    ::OOWeakReference* weakObj = [object weakRetain];
    if (std::find_if(_objects.begin(), _objects.end(), [weakObj](const auto& ref) { return ref.get() == weakObj; }) == _objects.end()) {
        _objects.emplace_back(weakObj); // (a set holds each once)
    }
    [weakObj release];
}

void OOWeakSet::removeObject(id object)
{
    ::OOWeakReference* weakObj = [object weakRetain];
    std::erase_if(_objects, [weakObj](const auto& ref) { return ref.get() == weakObj; });
    [weakObj release];
}

void OOWeakSet::makeObjectsPerformSelector(SEL selector)
{
    // (over a copy of the references: a selector may change the set)
    const std::vector<oo::ObjCRef<::OOWeakReference*>> references = _objects;
    for (const auto& weakRef : references) {
        [oo::ToCxx(weakRef.get())->weakRefUnderlyingObject() performSelector:selector];
    }
}

void OOWeakSet::makeObjectsPerformSelector(SEL selector, id argument)
{
    const std::vector<oo::ObjCRef<::OOWeakReference*>> references = _objects;
    for (const auto& weakRef : references) {
        [oo::ToCxx(weakRef.get())->weakRefUnderlyingObject() performSelector:selector withObject:argument];
    }
}

std::vector<oo::ObjCRef<id>> OOWeakSet::allObjects()
{
    return LiveObjects(_objects);
}

void OOWeakSet::removeAllObjects()
{
    _objects.clear();
}

void OOWeakSet::compact()
{
    std::erase_if(_objects, [](const auto& weakRef) { return oo::ToCxx(weakRef.get())->weakRefUnderlyingObject() == nil; });
}
