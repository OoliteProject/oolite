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
#import "OOCollectionExtractors.h"
#import "OOLogging.h"


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


#if PROFILE_ENCODING_CONVERTER
static OOEncodingConverter	*sProfiledConverter = nil;
static NSTimer				*sProfileTimer = nil;

static unsigned				sCacheHits = 0;
static unsigned				sCacheMisses = 0;
#endif


@interface OOEncodingConverter (Private)

- (NSData *) performConversionForString:(NSString *)string;

@end


@implementation OOEncodingConverter

- (id) initWithEncoding:(NSStringEncoding)encoding substitutions:(NSDictionary *)substitutions
{
	self = [super init];
	if (self != nil)
	{
		_cache = [[OOCache alloc] init];
		[_cache setPruneThreshold:100];
		[_cache setName:@"Text encoding"];
		_substitutions = [substitutions copy];
		_encoding = encoding;
		
#if PROFILE_ENCODING_CONVERTER
		if (sProfiledConverter == nil)
		{
			sProfiledConverter = self;
			sProfileTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(profileFire:) userInfo:nil repeats:YES];
		}
#endif
	}
	
	return self;
}


- (id) initWithFontPList:(NSDictionary *)fontPList
{
	return [self initWithEncoding:EncodingFromString([fontPList oo_stringForKey:@"encoding"]) substitutions:[fontPList oo_dictionaryForKey:@"substitutions"]];
}


- (void) dealloc
{
	[_cache release];
	[_substitutions release];
	
#if PROFILE_ENCODING_CONVERTER
	sProfiledConverter = nil;
	[sProfileTimer invalidate];
	sProfileTimer = nil;
	sCacheHits = 0;
	sCacheMisses = 0;
#endif
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"encoding: %lu", _encoding];
}


- (NSData *) convertString:(NSString *)string
{
	NSData				*data = nil;
	
#if USE_COMPATIBILITY_MAPPING
	// Convert to Unicode Normalization Form KC (that is, minimize the use of combining modifiers while avoiding precomposed ligatures)
	string = [string precomposedStringWithCompatibilityMapping];
#endif
	
	if (string == nil)  return [NSData data];
	
	data = [_cache objectForKey:string];
	if (data == nil)
	{
		data = [self performConversionForString:string];
		if (data != nil)  [_cache setObject:data forKey:string];
		
#if PROFILE_ENCODING_CONVERTER
		++sCacheMisses;
	}
	else
	{
		++sCacheHits;
#endif
	}
	
	return data;
}


- (NSStringEncoding) encoding
{
	return _encoding;
}

@end


@implementation OOEncodingConverter (Private)

- (NSData *) performConversionForString:(NSString *)string
{
	NSString			*subst = nil;
	NSEnumerator		*substEnum = nil;
	NSMutableString		*mutable = nil;
	
	mutable = [[string mutableCopy] autorelease];
	if (mutable == nil)  return nil;
	
	for (substEnum = [_substitutions keyEnumerator]; (subst = [substEnum nextObject]); )
	{
		[mutable replaceOccurrencesOfString:subst
								 withString:[_substitutions objectForKey:subst]
									options:0
									  range:NSMakeRange(0, [mutable length])];
	}
	
	return [mutable dataUsingEncoding:_encoding allowLossyConversion:YES];
}


#if PROFILE_ENCODING_CONVERTER
/*
	Profiling observations:
	* The clock generates one new string per second.
	* The trade screens each use over 60 strings, so cache sizes below 70 are
	  undesireable.
	* Cache hit ratio is extremely near 100% at most times.
*/
- (void) profileFire:(id)junk
{
	float ratio = (float)sCacheHits / (float)(sCacheHits + sCacheMisses);
	OOLog(@"strings.encoding.profile", @"Cache hits: %u, misses: %u, ratio: %.2g", sCacheHits, sCacheMisses, ratio);
	sCacheHits = sCacheMisses = 0;
}
#endif

@end

#endif //OOENCODINGCONVERTER_EXCLUDE


/*
	There are a variety of overlapping naming schemes for text encoding.
	We ignore them and use a fixed list:
		"windows-latin-1"		NSWindowsCP1252StringEncoding
		"windows-latin-2"		NSWindowsCP1250StringEncoding
		"windows-cyrillic"		NSWindowsCP1251StringEncoding
		"windows-greek"			NSWindowsCP1253StringEncoding
		"windows-turkish"		NSWindowsCP1254StringEncoding
*/

#define kWindowsLatin1Str		@"windows-latin-1"
#define kWindowsLatin2Str		@"windows-latin-2"
#define kWindowsCyrillicStr		@"windows-cyrillic"
#define kWindowsGreekStr		@"windows-greek"
#define kWindowsTurkishStr		@"windows-turkish"


NSString *StringFromEncoding(NSStringEncoding encoding)
{
	switch (encoding)
	{
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


NSStringEncoding EncodingFromString(NSString *name)
{
	if ([name isEqualToString:kWindowsLatin1Str])  return NSWindowsCP1252StringEncoding;
	if ([name isEqualToString:kWindowsLatin2Str])  return NSWindowsCP1250StringEncoding;
	if ([name isEqualToString:kWindowsCyrillicStr])  return NSWindowsCP1251StringEncoding;
	if ([name isEqualToString:kWindowsGreekStr])  return NSWindowsCP1253StringEncoding;
	if ([name isEqualToString:kWindowsTurkishStr])  return NSWindowsCP1254StringEncoding;
	return (NSStringEncoding)NSNotFound;
}
