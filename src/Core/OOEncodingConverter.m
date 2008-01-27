/*

OOEncodingConverter.h

Convert a 


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2008 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOEncodingConverter.h"
#import "OOCache.h"
#import "OOCollectionExtractors.h"


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
		_substitutions = [substitutions copy];
		_encoding = encoding;
	}
	
	return self;
}


- (id) initWithFontPList:(NSDictionary *)fontPList
{
	return [self initWithEncoding:[fontPList unsignedIntForKey:@"encoding"] substitutions:[fontPList dictionaryForKey:@"substitutions"]];
}


- (void) dealloc
{
	[_cache release];
	[_substitutions release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"encoding: %u", _encoding];
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
	}
	
	return data;
}

@end


@implementation OOEncodingConverter (Private)

- (NSData *) performConversionForString:(NSString *)string
{
	NSString			*subst = nil;
	NSEnumerator		*substEnum = nil;
	NSMutableString		*mutable = nil;
	
	mutable = [string mutableCopy];
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

@end
