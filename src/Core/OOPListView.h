/*

OOPListView.h

oo::PListView: the bridge that lets a file drop OOCollectionExtractors' `oo_*ForKey:` shape
while the game still holds Foundation collections (proposed ADR-0031, bead oo-u77). It is a
zero-copy view over an NSDictionary / NSUserDefaults / NSArray (anything answering
-objectForKey: or -objectAtIndex:) with oo::PList's accessor API (oofnd/PListGet.hpp):

        [dict oo_floatForKey:KEY defaultValue:1.0f]      ->  oo::PListView(dict).get<float>(KEY, 1.0f)
        [dict oo_stringForKey:KEY]                       ->  oo::PListView(dict).get<NSString *>(KEY)
        [array oo_intAtIndex:i defaultValue:-1]          ->  oo::PListView(array).at<int>(i, -1)

The receiver, key, index and fallback expressions move over unchanged. Behaviour is identical
by construction: each get<T> performs the lookup the category method performed and calls the
same OO<Type>FromObject conversion function (or, for NSString / NSSet, the same three lines the
category's static helper had), and a nil receiver returns the zero of T, as messaging nil did.
The full table of T for each `oo_<type>ForKey:` is in src/oofnd/README.md, "Migrating
oo_*ForKey"; an unsupported T does not compile.

When the collections become oo::PList (the Foundation sweep), `oo::PListView(x).get<T>(...)`
becomes `x.get<T>(...)` with T mapped to its C++ counterpart (NSString * -> std::string, ...),
and this header is deleted with gnustep-base.

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

#ifndef OOPLISTVIEW_H
#define OOPLISTVIEW_H

#import "OOCollectionExtractors.h"
#import "OOFoundation.h"
#import "OOMaths.h"

#include "oofnd/PListGet.hpp" // oo::NonNegative<F>, and the PList API this mirrors

namespace oo {

// oo_fuzzyBooleanForKey: reads a probability (fallback: a float) and returns YES with it.
struct FuzzyBoolean {
};

// One specialisation per requested type: Result, Fallback, the no-fallback form's default, and
// the conversion of the looked-up object (nil when absent).
template <class T>
struct PListViewGet;

#define OO_PLISTVIEW_SCALAR(T, CONVERT, DEFAULT)                                   \
    template <>                                                                    \
    struct PListViewGet<T> {                                                       \
        using Result = T;                                                          \
        using Fallback = T;                                                        \
        static T defaultFallback() { return DEFAULT; }                             \
        static T from(id object, T fallback) { return CONVERT(object, fallback); } \
    };

OO_PLISTVIEW_SCALAR(char, OOCharFromObject, 0)
OO_PLISTVIEW_SCALAR(short, OOShortFromObject, 0)
OO_PLISTVIEW_SCALAR(int, OOIntFromObject, 0)
OO_PLISTVIEW_SCALAR(long, OOLongFromObject, 0)
OO_PLISTVIEW_SCALAR(long long, OOLongLongFromObject, 0) // also NSInteger (Windows)
OO_PLISTVIEW_SCALAR(unsigned char, OOUnsignedCharFromObject, 0)
OO_PLISTVIEW_SCALAR(unsigned short, OOUnsignedShortFromObject, 0)
OO_PLISTVIEW_SCALAR(unsigned int, OOUnsignedIntFromObject, 0)
OO_PLISTVIEW_SCALAR(unsigned long, OOUnsignedLongFromObject, 0)
OO_PLISTVIEW_SCALAR(unsigned long long, OOUnsignedLongLongFromObject, 0) // also NSUInteger (Windows)
OO_PLISTVIEW_SCALAR(float, OOFloatFromObject, 0.0f)
OO_PLISTVIEW_SCALAR(double, OODoubleFromObject, 0.0)
OO_PLISTVIEW_SCALAR(Vector, OOVectorFromObject, kZeroVector)
OO_PLISTVIEW_SCALAR(HPVector, OOHPVectorFromObject, kZeroHPVector)
OO_PLISTVIEW_SCALAR(Quaternion, OOQuaternionFromObject, kIdentityQuaternion)

#undef OO_PLISTVIEW_SCALAR

// Booleans are read as bool. There is no BOOL row: BOOL is unsigned char in the GNUstep runtime
// on Linux, where it would redefine the unsigned char one.
template <>
struct PListViewGet<bool> {
    using Result = bool;
    using Fallback = bool;
    static bool defaultFallback() { return false; }
    static bool from(id object, bool fallback) { return OOBooleanFromObject(object, fallback); }
};

template <>
struct PListViewGet<NonNegative<float>> {
    using Result = float;
    using Fallback = float;
    static float defaultFallback() { return 0.0f; }
    static float from(id object, float fallback) { return OONonNegativeFloatFromObject(object, fallback); }
};

template <>
struct PListViewGet<NonNegative<double>> {
    using Result = double;
    using Fallback = double;
    static double defaultFallback() { return 0.0; }
    static double from(id object, double fallback) { return OONonNegativeDoubleFromObject(object, fallback); }
};

template <>
struct PListViewGet<FuzzyBoolean> {
    using Result = BOOL;
    using Fallback = float;
    static float defaultFallback() { return 0.0f; }
    static BOOL from(id object, float fallback) { return OOFuzzyBooleanFromObject(object, fallback); }
};

// oo_textureSpecifierForKey:defaultName: (OOTexture.h): the fallback is the default NAME.
struct TextureSpecifier {
};

} // namespace oo

NSDictionary* OOTextureSpecFromObject(id object, NSString* defaultName); // OOTexture.h

namespace oo {

template <>
struct PListViewGet<TextureSpecifier> {
    using Result = NSDictionary*;
    using Fallback = NSString*;
    static NSString* defaultFallback() { return nil; }
    static NSDictionary* from(id object, NSString* defaultName) { return OOTextureSpecFromObject(object, defaultName); }
};

// oo_objectForKey: any object.
template <>
struct PListViewGet<id> {
    using Result = id;
    using Fallback = id;
    static id defaultFallback() { return nil; }
    static id from(id object, id fallback) { return (object != nil) ? object : fallback; }
};

// oo_stringForKey: OOCollectionExtractors.mm's StringForObject.
template <>
struct PListViewGet<NSString*> {
    using Result = NSString*;
    using Fallback = NSString*;
    static NSString* defaultFallback() { return nil; }
    static NSString* from(id object, NSString* fallback)
    {
        if ([object isKindOfClass:[NSString class]])
            return object;
        else if ([object respondsToSelector:@selector(stringValue)])
            return [object stringValue];

        return fallback;
    }
};

// oo_setForKey: OOCollectionExtractors.mm's SetForObject.
template <>
struct PListViewGet<NSSet*> {
    using Result = NSSet*;
    using Fallback = NSSet*;
    static NSSet* defaultFallback() { return nil; }
    static NSSet* from(id object, NSSet* fallback)
    {
        if ([object isKindOfClass:[NSArray class]])
            return [NSSet setWithArray:object];
        else if ([object isKindOfClass:[NSSet class]])
            return [[object copy] autorelease];

        return fallback;
    }
};

// oo_arrayForKey, oo_dictionaryForKey, oo_mutableDictionaryForKey, oo_dataForKey, and
// oo_objectOfClass:[C class] forKey: - the object if it -isKindOfClass: C.
template <class C>
struct PListViewGet<C*> {
    using Result = C*;
    using Fallback = C*;
    static C* defaultFallback() { return nil; }
    static C* from(id object, C* fallback) { return [object isKindOfClass:[C class]] ? (C*)object : fallback; }
};

class PListView {
public:
    explicit PListView(id collection)
        : _collection(collection)
    {
    }

    // -oo_<type>ForKey:defaultValue: / -oo_<type>ForKey:
    template <class T>
    typename PListViewGet<T>::Result get(id key, typename PListViewGet<T>::Fallback fallback) const
    {
        if (_collection == nil)
            return typename PListViewGet<T>::Result { }; // messaging nil
        return PListViewGet<T>::from([_collection objectForKey:key], fallback);
    }
    template <class T>
    typename PListViewGet<T>::Result get(id key) const
    {
        return get<T>(key, PListViewGet<T>::defaultFallback());
    }

    // -oo_<type>AtIndex:defaultValue: / -oo_<type>AtIndex: (nil past the end, as -oo_objectAtIndex:)
    template <class T>
    typename PListViewGet<T>::Result at(NSUInteger index, typename PListViewGet<T>::Fallback fallback) const
    {
        if (_collection == nil)
            return typename PListViewGet<T>::Result { }; // messaging nil
        id object = (index < [_collection count]) ? [_collection objectAtIndex:index] : nil;
        return PListViewGet<T>::from(object, fallback);
    }
    template <class T>
    typename PListViewGet<T>::Result at(NSUInteger index) const
    {
        return at<T>(index, PListViewGet<T>::defaultFallback());
    }

private:
    id _collection;
};

} // namespace oo

#endif // OOPLISTVIEW_H
