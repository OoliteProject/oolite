/*

OOFoundationBridge.h

The boundary between a file the Foundation sweep has migrated to oofnd types and the code around
it that still holds Foundation objects (proposed ADR-0043; recipe in src/oofnd/README.md,
"Migrating Foundation usage"). Objective-C++ only; deleted with gnustep-base (oo-qps), when no
Foundation object is left to bridge. Strings are OOStringBridge.h's (imported here).

A migrated file includes this header and never spells a Foundation class itself. It uses these
functions only at its boundary: a shared selector that keeps an Objective-C object type (declared
`id`), a call into a callee that has not been migrated yet, or a direct caller adapted in the same
commit. Everything else in the file is std / oofnd.

        Foundation, in a migrated file                  here
        ----------------------------------------------  ---------------------------------------------
        nil-able NSString * <- std::optional<string>    oo::NSStringOrNil(opt)            (nullopt -> nil)
        std::optional<string> <- NSString *             oo::OptionalString(s)             (nil -> nullopt)
        [x isKindOfClass:[NSString class]] (& co.)      oo::IsNSString(x), IsNSArray, IsNSDictionary,
                                                        IsNSSet, IsNSNumber, IsNSData
        NSArray / NSSet of NSString -> strings          oo::StringsFrom(collection)       (enumeration order)
        strings -> NSArray / NSSet of NSString          oo::NSArrayFromStrings(r) / NSSetFromStrings(r)
        NSArray / NSSet of objects -> refs              oo::ObjCRefsFrom<OOFoo *>(collection)
        refs (or raw pointers) -> NSArray / NSSet       oo::NSArrayFromObjects(r) / NSSetFromObjects(r)
        property-list object graph -> oo::PList         oo::PListFrom(object)
        oo::PList -> property-list object graph         oo::ObjectFromPList(plist)
        the object inside a PList::Object node          oo::ObjectIn(plist)                 (nil for any other node)
        an object as a PList::Object node               oo::PListObject(object)
        what "%@" printed for an object                 oo::DescriptionOf(object)         (nil -> "(null)")

Exactness. Strings are unit for unit (OOStringBridge.h). PListFrom follows the table in
oofnd/PList.hpp: an NSNumber is a bool when it is the constant true/false object (kCFBoolean*
or GNUstep's cached +numberWithBool: identities — the test the game's plist writer uses),
a real when its -objCType is float or double, an unsigned integer for an unsigned
C type, else a signed integer; a float (its class is NSSmallFloat / NSFloatNumber: gnustep-base
reports -objCType 'd' for both) is a PList::singleReal, so it comes
back as +numberWithFloat: and prints as a float. (GNUstep caches small integers as int, so a non-negative <integer>
GNUstep parsed is a SIGNED PList::Integer here, where oo::parsePropertyList marks it unsigned:
same value, same writer output, but PList == is type-strict.) A dictionary with a key that is
not a string becomes a null PList. Any other object (a colour, a texture, NSNull, a placeholder)
becomes a PList::Object node that holds it (retained): the typed carrier for configuration
dictionaries that mix plist data with live objects (proposed ADR-0043 Amendment 2), so
ObjectFromPList(PListFrom(x)) gives back the same objects and the same NSNumber types.
ObjectFromPList builds immutable containers and drops null elements. Checked against gnustep-base 1.31.1 with a throwaway harness
(numbers of each kind, an old-style plist of every type round-tripping to an -isEqual: graph and
an == PList, a lone surrogate, the collection helpers) when this header was written.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#ifndef OOFOUNDATIONBRIDGE_H
#define OOFOUNDATIONBRIDGE_H

#import "OOFoundation.h"
#import "OOStringBridge.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h" // <optional> comes with PList.hpp

namespace oo {

// --- nil-able strings -------------------------------------------------------------------------

inline NSString* NSStringOrNil(const std::optional<std::string>& string)
{
    return string.has_value() ? NSStringFrom(*string) : nil;
}

inline std::optional<std::string> OptionalString(NSString* string)
{
    if (string == nil)
        return std::nullopt;
    return StdString(string);
}

// --- kinds ------------------------------------------------------------------------------------

inline bool IsNSString(id object) { return [object isKindOfClass:[NSString class]]; }
inline bool IsNSArray(id object) { return [object isKindOfClass:[NSArray class]]; }
inline bool IsNSDictionary(id object) { return [object isKindOfClass:[NSDictionary class]]; }
inline bool IsNSSet(id object) { return [object isKindOfClass:[NSSet class]]; }
inline bool IsNSNumber(id object) { return [object isKindOfClass:[NSNumber class]]; }
inline bool IsNSData(id object) { return [object isKindOfClass:[NSData class]]; }

// --- collections of strings -------------------------------------------------------------------

// The NSString elements of an NSArray / NSSet (or anything fast-enumerable), in its enumeration
// order; other elements are skipped. nil -> empty.
inline std::vector<std::string> StringsFrom(id collection)
{
    std::vector<std::string> result;
    for (id element in collection) {
        if (IsNSString(element))
            result.push_back(StdString(element));
    }
    return result;
}

template <class Range>
NSArray* NSArrayFromStrings(const Range& strings)
{
    NSMutableArray* result = [NSMutableArray array];
    for (const auto& string : strings)
        [result addObject:NSStringFrom(string)];
    return [[result copy] autorelease];
}

template <class Range>
NSSet* NSSetFromStrings(const Range& strings)
{
    NSMutableSet* result = [NSMutableSet set];
    for (const auto& string : strings)
        [result addObject:NSStringFrom(string)];
    return [[result copy] autorelease];
}

// --- collections of objects -------------------------------------------------------------------

// Every element of an NSArray / NSSet, retained, in its enumeration order. The caller names the
// element type it knows the collection holds (as a cast would); nothing is checked. nil -> empty.
template <class T>
std::vector<ObjCRef<T>> ObjCRefsFrom(id collection)
{
    std::vector<ObjCRef<T>> result;
    for (id element in collection)
        result.emplace_back(static_cast<T>(element));
    return result;
}

namespace bridge_detail {

    template <class T>
    id objectOf(const ObjCRef<T>& ref) { return ref.get(); }
    inline id objectOf(id object) { return object; }

} // namespace bridge_detail

// A range of oo::ObjCRef<T> (or of object pointers) as an immutable NSArray / NSSet. nil elements
// are skipped (a Foundation collection cannot hold nil).
template <class Range>
NSArray* NSArrayFromObjects(const Range& objects)
{
    NSMutableArray* result = [NSMutableArray array];
    for (const auto& object : objects) {
        id element = bridge_detail::objectOf(object);
        if (element != nil)
            [result addObject:element];
    }
    return [[result copy] autorelease];
}

template <class Range>
NSSet* NSSetFromObjects(const Range& objects)
{
    NSMutableSet* result = [NSMutableSet set];
    for (const auto& object : objects) {
        id element = bridge_detail::objectOf(object);
        if (element != nil)
            [result addObject:element];
    }
    return [[result copy] autorelease];
}

// --- property lists ---------------------------------------------------------------------------

// A PList::Object node's payload: an Objective-C object, retained (Amendment 2 carrier).
class ObjCPListForeign final : public PListForeign {
public:
    explicit ObjCPListForeign(id object)
        : object_(object)
    {
    }
    id object() const noexcept { return object_.get(); }
    std::string className() const override { return class_getName(object_getClass(object_.get())); }
    std::string description() const override { return StdString([object_.get() description]); }

private:
    ObjCRef<id> object_;
};

inline PList PListObject(id object)
{
    if (object == nil)
        return PList();
    return PList(PList::Object(makeRef<ObjCPListForeign>(object)));
}

// The object a PList::Object node holds; nil for any other node.
inline id ObjectIn(const PList& plist)
{
    if (const PList::Object* node = plist.getIf<PList::Object>()) {
        if (const auto* foreign = dynamic_cast<const ObjCPListForeign*>(node->get()))
            return foreign->object();
    }
    return nil;
}

inline PList PListFrom(id object)
{
    if (object == nil)
        return PList();
    if (IsNSString(object))
        return PList(StdString(object));
    if (IsNSNumber(object)) {
        NSNumber* number = object;
        // Former NSNumber (OOExtensions) boolean identity test: constant true/false objects only.
#if __COREFOUNDATION_CFNUMBER__
        if (number == (NSNumber*)kCFBooleanTrue || number == (NSNumber*)kCFBooleanFalse)
            return PList(static_cast<bool>([number boolValue]));
#else
        {
            static NSNumber *sTrue = nil, *sFalse = nil;
            if (sTrue == nil) {
                sTrue = [[NSNumber numberWithBool:YES] retain];
                sFalse = [[NSNumber numberWithBool:NO] retain];
            }
            if (number == sTrue || number == sFalse)
                return PList(static_cast<bool>([number boolValue]));
        }
#endif
        // gnustep-base reports 'd' for a float too; its class tells (NSSmallFloat, NSFloatNumber: probed).
        if (std::string_view(class_getName(object_getClass(number))).find("Float") != std::string_view::npos)
            return PList::singleReal([number floatValue]);
        switch (*[number objCType]) {
        case 'f':
        case 'd':
            return PList([number doubleValue]);
        case 'C':
        case 'S':
        case 'I':
        case 'L':
        case 'Q':
            return PList::unsignedInteger([number unsignedLongLongValue]);
        default:
            return PList::signedInteger([number longLongValue]);
        }
    }
    if (IsNSData(object)) {
        NSData* data = object;
        return PList(Data([data bytes], [data length]));
    }
    if ([object isKindOfClass:[NSDate class]]) {
        return PList(PList::Date { [(NSDate*)object timeIntervalSinceReferenceDate] });
    }
    if (IsNSArray(object)) {
        PList::Array array;
        array.reserve([(NSArray*)object count]);
        for (id element in (NSArray*)object)
            array.push_back(PListFrom(element));
        return PList(std::move(array));
    }
    if (IsNSDictionary(object)) {
        NSDictionary* dictionary = object;
        PList::Dict dict;
        for (id key in dictionary) {
            if (!IsNSString(key))
                return PList();
            dict.emplace(StdString(key), PListFrom([dictionary objectForKey:key]));
        }
        return PList(std::move(dict));
    }
    return PListObject(object);
}

inline id ObjectFromPList(const PList& plist)
{
    switch (plist.type()) {
    case PList::Type::Null:
        return nil;
    case PList::Type::Bool:
        return [NSNumber numberWithBool:*plist.getIf<bool>() ? YES : NO];
    case PList::Type::Integer: {
        const PList::Integer& integer = *plist.getIf<PList::Integer>();
        if (integer.isUnsigned)
            return [NSNumber numberWithUnsignedLongLong:integer.unsignedValue()];
        return [NSNumber numberWithLongLong:integer.value];
    }
    case PList::Type::Real:
        if (plist.isSinglePrecision())
            return [NSNumber numberWithFloat:static_cast<float>(*plist.getIf<double>())];
        return [NSNumber numberWithDouble:*plist.getIf<double>()];
    case PList::Type::String:
        return NSStringFrom(*plist.getIf<std::string>());
    case PList::Type::Data: {
        const Data& data = *plist.getIf<PList::Data>();
        return [NSData dataWithBytes:data.bytes() length:data.length()];
    }
    case PList::Type::Date:
        return [NSDate dateWithTimeIntervalSinceReferenceDate:plist.getIf<PList::Date>()->sinceReferenceDate];
    case PList::Type::Array: {
        const PList::Array& array = *plist.getIf<PList::Array>();
        NSMutableArray* result = [NSMutableArray arrayWithCapacity:array.size()];
        for (const PList& element : array) {
            id object = ObjectFromPList(element);
            if (object != nil)
                [result addObject:object];
        }
        return [[result copy] autorelease];
    }
    case PList::Type::Dict: {
        const PList::Dict& dict = *plist.getIf<PList::Dict>();
        NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:dict.size()];
        for (const auto& [key, value] : dict) {
            id object = ObjectFromPList(value);
            if (object != nil)
                [result setObject:object forKey:NSStringFrom(key)];
        }
        return [[result copy] autorelease];
    }
    case PList::Type::Object:
        return ObjectIn(plist);
    }
    return nil;
}

// --- descriptions -----------------------------------------------------------------------------

// The text "%@" put in a formatted string for <object>: its -description, or "(null)" for nil.
inline std::string DescriptionOf(id object)
{
    if (object == nil)
        return "(null)";
    return StdString([object description]);
}

} // namespace oo

#endif // OOFOUNDATIONBRIDGE_H
