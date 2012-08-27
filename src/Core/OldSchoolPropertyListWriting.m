/*
	OldSchoolPropertyListWriting.m
	Copyright 2006-2012 Jens Ayton
	
	Permission is hereby granted, free of charge, to any person obtaining a copy of this software
	and associated documentation files (the "Software"), to deal in the Software without
	restriction, including without limitation the rights to use, copy, modify, merge, publish,
	distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in all copies or
	substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
	BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
	DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#include <assert.h>

#import "OldSchoolPropertyListWriting.h"
#import "NSNumberOOExtensions.h"


static void AppendNewLineAndIndent(NSMutableString *ioString, unsigned indentDepth);


@implementation NSString (OldSchoolPropertyListWriting)

- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription
{
	NSCharacterSet		*charSet;
	NSRange				foundRange, searchRange;
	NSString			*foundString;
	NSMutableString		*newString;
	NSUInteger			length;
	
	length = [self length];
	if (0 != length
		&& [self rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location == NSNotFound
		&& ![[NSCharacterSet decimalDigitCharacterSet] longCharacterIsMember:[self characterAtIndex:0]])
	{
		// This is an alphanumeric string whose first character is not a digit
		return [[self copy] autorelease];
	}
	else
	{
		charSet = [NSCharacterSet characterSetWithCharactersInString:@"\"\r\n\\"];
		foundRange = [self rangeOfCharacterFromSet:charSet options:NSLiteralSearch];
		if (NSNotFound == foundRange.location)
		{
			newString = (NSMutableString *)self;
		}
		else
		{
			// Escape quotes, backslashes and newlines
			newString = [[[self substringToIndex:foundRange.location] mutableCopy] autorelease];
			
			for (;;)
			{
				// Append escaped character
				foundString = [self substringWithRange:foundRange];
				if ([foundString isEqual:@"\""]) [newString appendString:@"\\\""];
				else if ([foundString isEqual:@"\n"]) [newString appendString:@"\\\n"];
				else if ([foundString isEqual:@"\r"]) [newString appendString:@"\\\r"];
				else if ([foundString isEqual:@"\\"]) [newString appendString:@"\\\\"];
				else
				{
					[NSException raise:NSInternalInconsistencyException format:@"%s: expected \" or newline, found %@", __PRETTY_FUNCTION__, foundString];
				}
				
				// Use rest of string…
				searchRange.location = foundRange.location + foundRange.length;
				searchRange.length = length - searchRange.location;
				
				// …to search for next char needing escaping
				foundRange = [self rangeOfCharacterFromSet:charSet options:NSLiteralSearch range:searchRange];
				if (NSNotFound == foundRange.location)
				{
					[newString appendString:[self substringWithRange:searchRange]];
					break;
				}
			}
		}
		
		return [NSString stringWithFormat:@"\"%@\"", newString];
	}
}

@end


@implementation NSNumber (OldSchoolPropertyListWriting)

- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription
{
	NSString			*result;
	double				dVal;
	
	if ([self oo_isBoolean])
	{
		if ([self boolValue])  result = @"true";
		else  result = @"false";
	}
	else if ([self oo_isFloatingPointNumber])
	{
		dVal = [self doubleValue];
		result = [NSString stringWithFormat:@"%.8g", dVal];
	}
	else result = [NSString stringWithFormat:@"%@", self];
	
	// Allow infinities, but remember that they’ll be read in as strings
#if 0
	if ([result isEqual:@"inf"] || [result isEqual:@"-inf"])
	{
		*outErrorDescription = @"infinities cannot be represented in old-school property lists";
		return nil;
	}
#endif
	
	return result;
}

@end


@implementation NSData (OldSchoolPropertyListWriting)

- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription
{
	const uint8_t			*srcBytes;
	uint8_t					*dstBytes, *curr;
	NSUInteger				i, j, srcLength, dstLength;
	const char				hexTable[] = "0123456789ABCDEF";
	NSString				*result;
	
	srcBytes = [self bytes];
	srcLength = [self length];
	
	dstLength = 2 * srcLength + srcLength/8 + 2 + (srcLength/64 * (1 + inIndentation));
	
	dstBytes = malloc(dstLength);
	if (dstBytes == NULL)
	{
		if (NULL != outErrorDescription)
		{
			*outErrorDescription = [NSString stringWithFormat:@"failed to allocate space (%lu bytes) for conversion of NSData to old-school property list representation", dstLength];
		}
		return nil;
	}
	
	curr = dstBytes;
	*curr++ = '<';
	for (i = 0; i != srcLength; ++i)
	{
		if (0 != i && 0 == (i & 3))
		{
			if (0 == (i & 31))
			{
				*curr++ = '\n';
				j = inIndentation;
				while (--j) *curr++ = '\t';
			}
			*curr++ = ' ';
		}
		*curr++ = hexTable[srcBytes[i] >> 4];
		*curr++ = hexTable[srcBytes[i] & 0xF];
	}
	*curr = '>';
	
	assert((size_t)(curr - dstBytes) <= dstLength);
	
	result = [[NSString alloc] initWithBytesNoCopy:dstBytes length:dstLength encoding:NSASCIIStringEncoding freeWhenDone:YES];
	return [result autorelease];
}

@end


@implementation NSArray (OldSchoolPropertyListWriting)

- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription
{
	NSMutableString			*result;
	NSUInteger				i, count;
	id						object;
	
	result = [NSMutableString string];
	
	[result appendString:@"("];
	
	count = [self count];
	AppendNewLineAndIndent(result, inIndentation + 1);
	
	for (i = 0; i != count; ++i)
	{
		if (0 != i)
		{
			[result appendString:@","];
			AppendNewLineAndIndent(result, inIndentation + 1);
		}
		
		object = [self objectAtIndex:i];
		if (![object conformsToProtocol:@protocol (OldSchoolPropertyListWriting)])
		{
			if (nil != object && NULL != outErrorDescription)
			{
				*outErrorDescription = [NSString stringWithFormat:@"non-plist object in dictionary"];
			}
			return nil;
		}
		
		object = [object oldSchoolPListFormatWithIndentation:inIndentation + 1 errorDescription:outErrorDescription];
		if (nil == object) return nil;
		[result appendString:object];
	}
	
	AppendNewLineAndIndent(result, inIndentation);
	[result appendString:@")"];
	return result;
}

@end


@implementation NSDictionary (OldSchoolPropertyListWriting)

- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription
{
	NSMutableString			*result;
	NSUInteger				i, count;
	NSArray					*allKeys;
	id						key, value;
	NSString				*valueDesc;
	
	result = [NSMutableString string];
	allKeys = [[self allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	count = [allKeys count];
	
	[result appendString:@"{"];
	
	AppendNewLineAndIndent(result, inIndentation + 1);
	
	for (i = 0; i != count; ++i)
	{
		if (0 != i)
		{
			AppendNewLineAndIndent(result, inIndentation + 1);
		}
		
		key = [allKeys objectAtIndex:i];
		if (![key isKindOfClass:[NSString class]])
		{
			if (NULL != outErrorDescription) *outErrorDescription = [NSString stringWithFormat:@"non-string key in dictionary"];
			return nil;
		}
		value = [self objectForKey:key];
		if (![value conformsToProtocol:@protocol(OldSchoolPropertyListWriting)])
		{
			if (nil != value && NULL != outErrorDescription)
			{
				*outErrorDescription = [NSString stringWithFormat:@"non-plist object in dictionary"];
			}
			return nil;
		}
		
		key = [key oldSchoolPListFormatWithIndentation:inIndentation + 1 errorDescription:outErrorDescription];
		if (nil == key) return nil;
		valueDesc = [value oldSchoolPListFormatWithIndentation:inIndentation + 1 errorDescription:outErrorDescription];
		if (nil == valueDesc) return nil;
		
		[result appendFormat:@"%@ =", key];
		if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]])
		{
			AppendNewLineAndIndent(result, inIndentation + 1);
		}
		else
		{
			[result appendString:@" "];
		}
		[result appendFormat:@"%@;", valueDesc];
	}
	
	AppendNewLineAndIndent(result, inIndentation);
	[result appendString:@"}"];
	
	return result;
}

@end


@interface NSObject (OldSchoolPropertyListWriting_Private)

- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription;

@end


@implementation NSObject (OldSchoolPropertyListWriting)

- (NSData *)oldSchoolPListFormatWithErrorDescription:(NSString **)outErrorDescription
{
	NSString				*string;
	
	string = [self oldSchoolPListFormatWithIndentation:0 errorDescription:outErrorDescription];
	return [[string stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
}


- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription
{
	if (NULL != outErrorDescription)
	{
		*outErrorDescription = [NSString stringWithFormat:@"Class %@ does not support OldSchoolPropertyListWriting", [self className]];
	}
	return nil;
}

@end


static void AppendNewLineAndIndent(NSMutableString *ioString, unsigned indentDepth)
{
	[ioString appendString:@"\n"];
	while (indentDepth--) [ioString appendString:@"\t"];
}
