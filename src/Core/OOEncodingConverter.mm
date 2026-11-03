/*

OOEncodingConverter.m

Copyright (C) 2008-2013 Jens Ayton and contributors

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

#ifndef OOENCODINGCONVERTER_EXCLUDE

#import "OOEncodingConverter.h"
#import "OOCache.h"
#import "OOFoundationBridge.h"
#import "OOLogging.h"
#include "oofnd/Encoding.hpp"
#include "oofnd/String.hpp"

/*	Using compatibility mapping - converting strings to Unicode form KC - would
        reduce potential complications in localizing Oolite. However, the method to
        perform the transformation is not available in GNUstep. I'm currently not
        using it under OS X either, for cross-platform consistency.
        -- Ahruman 2008-01-27
*/
#if OOLITE_MAC_OS_X
#define USE_COMPATIBILITY_MAPPING 0
#else
#define USE_COMPATIBILITY_MAPPING 0
#endif

#define PROFILE_ENCODING_CONVERTER 0

static const NSUInteger kCachePruneThreshold = 200;

#if PROFILE_ENCODING_CONVERTER
#include <chrono>

// The 5-second profile report was a repeating run-loop timer; it is now a deadline checked on each conversion (proposed ADR-0033).
static const std::chrono::seconds kProfileInterval { 5 };
static OOEncodingConverter* sProfiledConverter = nil;
static std::chrono::steady_clock::time_point sProfileDeadline;

static unsigned sCacheHits = 0;
static unsigned sCacheMisses = 0;
#endif

@interface OOEncodingConverter (Private)

- (std::optional<oo::Data>)performConversionForString:(const std::string&)string;
#if PROFILE_ENCODING_CONVERTER
- (void)profileFire:(id)junk;
#endif

@end

@implementation OOEncodingConverter

- (id)initWithEncoding:(std::optional<oo::str::Encoding>)encoding substitutions:(const oo::PList&)substitutions
{
    self = [super init];
    if (self != nil) {
        _cache = [[OOCache alloc] init];
        [_cache setPruneThreshold:kCachePruneThreshold];
        [_cache setName:@"Text encoding"];
        if (substitutions.isDict()) {
            // In the order the Foundation dictionary enumerated them (two that overlap give
            // different results in different orders), which is the order this one enumerates in.
            id substitutionDictionary = oo::ObjectFromPList(substitutions);
            for (id key in substitutionDictionary) {
                _substitutions.emplace_back(oo::StdString(key), oo::StdString([substitutionDictionary objectForKey:key]));
            }
        }
        _encoding = encoding;

#if PROFILE_ENCODING_CONVERTER
        if (sProfiledConverter == nil) {
            sProfiledConverter = self;
            sProfileDeadline = std::chrono::steady_clock::now() + kProfileInterval;
        }
#endif
    }

    return self;
}

- (id)initWithFontPList:(const oo::PList&)fontPList
{
    const oo::PList* substitutions = fontPList.get<oo::PList::Dict>("substitutions");
    return [self initWithEncoding:oo::str::encodingFromName(fontPList.get<std::string>("encoding")) substitutions:(substitutions != nullptr) ? *substitutions : oo::PList()];
}

- (void)dealloc
{
    [_cache release];
    _substitutions.clear();

#if PROFILE_ENCODING_CONVERTER
    sProfiledConverter = nil;
    sCacheHits = 0;
    sCacheMisses = 0;
#endif

    [super dealloc];
}

- (id)descriptionComponents
{
    // (an unknown encoding printed as NSNotFound's low 32 bits, 4294967295)
    return oo::NSStringFrom(oo::str::format("encoding: %u", _encoding.has_value() ? static_cast<unsigned>(*_encoding) : static_cast<unsigned>(NSNotFound)));
}

- (oo::Data)convertString:(const std::string&)string
{
    oo::Data data;

#if USE_COMPATIBILITY_MAPPING
    // (Unicode Normalization Form KC has no oofnd equivalent; the mapping has always been off.)
#endif

    // OOCache holds Objective-C objects: the string is its key, the bytes its value.
    id key = oo::NSStringFrom(string);
    id cached = [_cache objectForKey:key];
    if (cached == nil) {
        const std::optional<oo::Data> converted = [self performConversionForString:string];
        if (converted.has_value()) {
            data = *converted;
            [_cache setObject:oo::ObjectFromPList(oo::PList(data)) forKey:key];
        }

#if PROFILE_ENCODING_CONVERTER
        ++sCacheMisses;
#endif
    } else {
#if PROFILE_ENCODING_CONVERTER
        ++sCacheHits;
#endif
        if (const oo::Data* cachedData = oo::PListFrom(cached).getIf<oo::Data>())
            data = *cachedData;
    }

#if PROFILE_ENCODING_CONVERTER
    if (self == sProfiledConverter) {
        std::chrono::steady_clock::time_point now = std::chrono::steady_clock::now();
        if (now >= sProfileDeadline) {
            do
                sProfileDeadline += kProfileInterval;
            while (sProfileDeadline <= now);
            [self profileFire:nil];
        }
    }
#endif

    return data;
}

- (std::optional<oo::str::Encoding>)encoding
{
    return _encoding;
}

@end

@implementation OOEncodingConverter (Private)

- (std::optional<oo::Data>)performConversionForString:(const std::string&)string
{
    // (an unknown encoding, NSNotFound: the conversion gave nil)
    if (!_encoding.has_value())
        return std::nullopt;

    return oo::str::convertForFont(string, *_encoding, _substitutions);
}

#if PROFILE_ENCODING_CONVERTER
/*
        Profiling observations:
        * The clock generates one new string per second.
        * The trade screens each use over 100 strings, so cache sizes below 150
      are undesireable.
        * Cache hit ratio is extremely near 100% at most times.
*/
- (void)profileFire:(id)junk
{
    float ratio = (float)sCacheHits / (float)(sCacheHits + sCacheMisses);
    OO_LOG("strings.encoding.profile", "Cache hits: {}, misses: {}, ratio: {:.2g}", sCacheHits, sCacheMisses, ratio);
    sCacheHits = sCacheMisses = 0;
}
#endif

@end

#endif // OOENCODINGCONVERTER_EXCLUDE

#include "oofnd/Encoding.hpp"

/*
        There are a variety of overlapping naming schemes for text encoding.
        We ignore them and use a fixed list (oo::str::Encoding in oofnd/Encoding.hpp):
                "windows-latin-1"		windowsCP1252 (code page 1252)
                "windows-latin-2"		windowsCP1250 (code page 1250)
                "windows-cyrillic"		windowsCP1251 (code page 1251)
                "windows-greek"			windowsCP1253 (code page 1253)
                "windows-turkish"		windowsCP1254 (code page 1254)
*/

const char* StringFromEncoding(unsigned encoding)
{
    return oo::str::encodingName(static_cast<oo::str::Encoding>(encoding));
}
