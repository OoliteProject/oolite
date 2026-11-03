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
#import "OOLogging.h"
#import "OOPListView.h"

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

- (NSData*)performConversionForString:(NSString*)string;
#if PROFILE_ENCODING_CONVERTER
- (void)profileFire:(id)junk;
#endif

@end

@implementation OOEncodingConverter

- (id)initWithEncoding:(NSStringEncoding)encoding substitutions:(NSDictionary*)substitutions
{
    self = [super init];
    if (self != nil) {
        _cache = [[OOCache alloc] init];
        [_cache setPruneThreshold:kCachePruneThreshold];
        [_cache setName:@"Text encoding"];
        _substitutions = [substitutions copy];
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

- (id)initWithFontPList:(NSDictionary*)fontPList
{
    return [self initWithEncoding:EncodingFromString(oo::PListView(fontPList).get<NSString*>(@"encoding")) substitutions:oo::PListView(fontPList).get<NSDictionary*>(@"substitutions")];
}

- (void)dealloc
{
    [_cache release];
    [_substitutions release];

#if PROFILE_ENCODING_CONVERTER
    sProfiledConverter = nil;
    sCacheHits = 0;
    sCacheMisses = 0;
#endif

    [super dealloc];
}

- (NSString*)descriptionComponents
{
    return [NSString stringWithFormat:@"encoding: %u", _encoding];
}

- (NSData*)convertString:(NSString*)string
{
    NSData* data = nil;

#if USE_COMPATIBILITY_MAPPING
    // Convert to Unicode Normalization Form KC (that is, minimize the use of combining modifiers while avoiding precomposed ligatures)
    string = [string precomposedStringWithCompatibilityMapping];
#endif

    if (string == nil)
        return [NSData data];

    data = [_cache objectForKey:string];
    if (data == nil) {
        data = [self performConversionForString:string];
        if (data != nil)
            [_cache setObject:data forKey:string];

#if PROFILE_ENCODING_CONVERTER
        ++sCacheMisses;
    } else {
        ++sCacheHits;
#endif
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

- (NSStringEncoding)encoding
{
    return _encoding;
}

@end

@implementation OOEncodingConverter (Private)

- (NSData*)performConversionForString:(NSString*)string
{
    NSString* subst = nil;
    NSMutableString* mutableString = nil;

    mutableString = [[string mutableCopy] autorelease];
    if (mutableString == nil)
        return nil;

    foreachkey(subst, _substitutions)
    {
        [mutableString replaceOccurrencesOfString:subst
                                       withString:[_substitutions objectForKey:subst]
                                          options:0
                                            range:NSMakeRange(0, [mutableString length])];
    }

    return [mutableString dataUsingEncoding:_encoding allowLossyConversion:YES];
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
    OOLog(@"strings.encoding.profile", @"Cache hits: %u, misses: %u, ratio: %.2g", sCacheHits, sCacheMisses, ratio);
    sCacheHits = sCacheMisses = 0;
}
#endif

@end

#endif // OOENCODINGCONVERTER_EXCLUDE

/*
        There are a variety of overlapping naming schemes for text encoding.
        We ignore them and use a fixed list:
                "windows-latin-1"		NSWindowsCP1252StringEncoding
                "windows-latin-2"		NSWindowsCP1250StringEncoding
                "windows-cyrillic"		NSWindowsCP1251StringEncoding
                "windows-greek"			NSWindowsCP1253StringEncoding
                "windows-turkish"		NSWindowsCP1254StringEncoding
*/

#define kWindowsLatin1Str @"windows-latin-1"
#define kWindowsLatin2Str @"windows-latin-2"
#define kWindowsCyrillicStr @"windows-cyrillic"
#define kWindowsGreekStr @"windows-greek"
#define kWindowsTurkishStr @"windows-turkish"

NSString* StringFromEncoding(NSStringEncoding encoding)
{
    switch (encoding) {
    case NSWindowsCP1252StringEncoding:
        return kWindowsLatin1Str;

    case NSWindowsCP1250StringEncoding:
        return kWindowsLatin2Str;

    case NSWindowsCP1251StringEncoding:
        return kWindowsCyrillicStr;

    case NSWindowsCP1253StringEncoding:
        return kWindowsGreekStr;

    case NSWindowsCP1254StringEncoding:
        return kWindowsTurkishStr;

    default:
        return nil;
    }
}

NSStringEncoding EncodingFromString(NSString* name)
{
    if ([name isEqualToString:kWindowsLatin1Str])
        return NSWindowsCP1252StringEncoding;
    if ([name isEqualToString:kWindowsLatin2Str])
        return NSWindowsCP1250StringEncoding;
    if ([name isEqualToString:kWindowsCyrillicStr])
        return NSWindowsCP1251StringEncoding;
    if ([name isEqualToString:kWindowsGreekStr])
        return NSWindowsCP1253StringEncoding;
    if ([name isEqualToString:kWindowsTurkishStr])
        return NSWindowsCP1254StringEncoding;
    return (NSStringEncoding)NSNotFound;
}
