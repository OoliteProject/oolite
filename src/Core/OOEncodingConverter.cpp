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

#include "OOEncodingConverter.h"
#include "OOCache.h"
#include "OOLogging.h"
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
static OOEncodingConverter* sProfiledConverter = nullptr;
static std::chrono::steady_clock::time_point sProfileDeadline;

static unsigned sCacheHits = 0;
static unsigned sCacheMisses = 0;
#endif

namespace {

// The substitutions -initWithFontPList: passed on (a null PList: none).
oo::PList FontSubstitutions(const oo::PList& fontPList)
{
    const oo::PList* substitutions = fontPList.get<oo::PList::Dict>("substitutions");
    return (substitutions != nullptr) ? *substitutions : oo::PList();
}

} // namespace

OOEncodingConverter::OOEncodingConverter(std::optional<oo::str::Encoding> encoding, const oo::PList& substitutions)
{
    _cache = OOCache::cacheWithPList(oo::PList());
    _cache->setPruneThreshold(kCachePruneThreshold);
    _cache->setName(std::string("Text encoding"));
    if (const oo::PList::Dict* substitutionDictionary = substitutions.getIf<oo::PList::Dict>()) {
        // In key order (bead oo-qps.51): the Foundation dictionary this was once
        // built into enumerated in its hash order. Two substitutions give different results in
        // different orders only when one's key occurs in another's key or replacement; the
        // stock oolite-font.plist's keys are distinct single characters that occur in no
        // replacement, so its result is unchanged. A value that is not a string was an
        // -length sent to a non-string; it substitutes "" here.
        for (const auto& [key, value] : *substitutionDictionary) {
            const std::string* replacement = value.getIf<std::string>();
            _substitutions.emplace_back(key, (replacement != nullptr) ? *replacement : std::string());
        }
    }
    _encoding = encoding;

#if PROFILE_ENCODING_CONVERTER
    if (sProfiledConverter == nullptr) {
        sProfiledConverter = this;
        sProfileDeadline = std::chrono::steady_clock::now() + kProfileInterval;
    }
#endif
}

OOEncodingConverter::OOEncodingConverter(const oo::PList& fontPList)
    : OOEncodingConverter(oo::str::encodingFromName(fontPList.get<std::string>("encoding")), FontSubstitutions(fontPList))
{
}

OOEncodingConverter::~OOEncodingConverter()
{
    _substitutions.clear();

#if PROFILE_ENCODING_CONVERTER
    sProfiledConverter = nullptr;
    sCacheHits = 0;
    sCacheMisses = 0;
#endif
}

// oo::DescriptionOf (OODescription.h) wraps this as "<OOEncodingConverter 0x...>{...}".
std::optional<std::string> OOEncodingConverter::descriptionComponents() const
{
    // (an unknown encoding printed as NSNotFound's low 32 bits, 4294967295)
    return oo::str::format("encoding: %u", _encoding.has_value() ? static_cast<unsigned>(*_encoding) : static_cast<unsigned>(NSNotFound));
}

oo::Data OOEncodingConverter::convertString(const std::string& string)
{
    oo::Data data;

#if USE_COMPATIBILITY_MAPPING
    // (Unicode Normalization Form KC has no oofnd equivalent; the mapping has always been off.)
#endif

    // The string is the cache key, the bytes its value (PList data).
    const oo::PList cached = _cache->pListForKey(string);
    if (cached.isNull()) {
        const std::optional<oo::Data> converted = performConversionForString(string);
        if (converted.has_value()) {
            data = *converted;
            _cache->setPList(oo::PList(data), string);
        }

#if PROFILE_ENCODING_CONVERTER
        ++sCacheMisses;
#endif
    } else {
#if PROFILE_ENCODING_CONVERTER
        ++sCacheHits;
#endif
        if (const oo::Data* cachedData = cached.getIf<oo::Data>())
            data = *cachedData;
    }

#if PROFILE_ENCODING_CONVERTER
    if (this == sProfiledConverter) {
        std::chrono::steady_clock::time_point now = std::chrono::steady_clock::now();
        if (now >= sProfileDeadline) {
            do
                sProfileDeadline += kProfileInterval;
            while (sProfileDeadline <= now);
            profileFire(nullptr);
        }
    }
#endif

    return data;
}

std::optional<oo::str::Encoding> OOEncodingConverter::encoding()
{
    return _encoding;
}

std::optional<oo::Data> OOEncodingConverter::performConversionForString(const std::string& string)
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
void OOEncodingConverter::profileFire(void* junk)
{
    float ratio = (float)sCacheHits / (float)(sCacheHits + sCacheMisses);
    OO_LOG("strings.encoding.profile", "Cache hits: {}, misses: {}, ratio: {:.2g}", sCacheHits, sCacheMisses, ratio);
    sCacheHits = sCacheMisses = 0;
}
#endif

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
