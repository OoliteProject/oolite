/*

OOCollectionExtractors.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

Copyright (C) 2007 Jens Ayton

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

#import "OOCollectionExtractors.h"
#import <limits.h>
#import "OOMaths.h"


BOOL EvaluateAsBoolean(id object, BOOL defaultValue)
{
	BOOL result = defaultValue;
	
	if ([object isKindOfClass:[NSString class]])
	{
		if (NSOrderedSame == [object caseInsensitiveCompare:@"yes"] ||
			NSOrderedSame == [object caseInsensitiveCompare:@"true"] ||
			NSOrderedSame == [object caseInsensitiveCompare:@"on"] ||
			[object intValue] != 0)
		{
			result = YES;
		}
		else if (NSOrderedSame == [object caseInsensitiveCompare:@"no"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"false"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"off"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"0"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"-0"])
		{
			result = NO;
		}
	}
	else if ([object respondsToSelector:@selector(boolValue)])  result = [object boolValue];
	else if ([object respondsToSelector:@selector(intValue)])
	{
		result = [object intValue] != 0;
	}
	
	return result;
}


@implementation NSArray (OOExtractor)

- (char)charAtIndex:(unsigned)index defaultValue:(char)value
{
	id					objVal = [self objectAtIndex:index];
	int					intVal;
	char				result;
	
	if ([objVal respondsToSelector:@selector(charValue)])  result = [objVal charValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < CHAR_MIN) intVal = CHAR_MIN;
		else if (CHAR_MAX < intVal) intVal = CHAR_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (short)shortAtIndex:(unsigned)index defaultValue:(short)value
{
	id					objVal = [self objectAtIndex:index];
	int					intVal;
	short				result;
	
	if ([objVal respondsToSelector:@selector(shortValue)])  result = [objVal shortValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < SHRT_MIN) intVal = SHRT_MIN;
		else if (SHRT_MAX < intVal) intVal = SHRT_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (int)intAtIndex:(unsigned)index defaultValue:(int)value
{
	id					objVal = [self objectAtIndex:index];
	int					result;
	
	if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (long)longAtIndex:(unsigned)index defaultValue:(long)value
{
	id					objVal = [self objectAtIndex:index];
	long				result;
	
	if ([objVal respondsToSelector:@selector(longValue)])  result = [objVal longValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (long long)longLongAtIndex:(unsigned)index defaultValue:(long long)value
{
	id					objVal = [self objectAtIndex:index];
	long long			result;
	
	if ([objVal respondsToSelector:@selector(longLongValue)])  result = [objVal longLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (unsigned char)unsignedCharAtIndex:(unsigned)index defaultValue:(unsigned char)value
{
	id					objVal = [self objectAtIndex:index];
	int					intVal;
	unsigned char		result;
	
	if ([objVal respondsToSelector:@selector(unsignedCharValue)])  result = [objVal unsignedCharValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		else if (UCHAR_MAX < intVal) intVal = UCHAR_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned short)unsignedShortAtIndex:(unsigned)index defaultValue:(unsigned short)value
{
	id					objVal = [self objectAtIndex:index];
	int					intVal;
	unsigned short		result;
	
	if ([objVal respondsToSelector:@selector(unsignedShortValue)])  result = [objVal unsignedShortValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		else if (USHRT_MAX < intVal) intVal = USHRT_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned int)unsignedIntAtIndex:(unsigned)index defaultValue:(unsigned int)value
{
	id					objVal = [self objectAtIndex:index];
	int					intVal;
	unsigned int		result;
	
	if ([objVal respondsToSelector:@selector(unsignedIntValue)])  result = [objVal unsignedIntValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned long)unsignedLongAtIndex:(unsigned)index defaultValue:(unsigned long)value
{
	id					objVal = [self objectAtIndex:index];
	int					intVal;
	unsigned long		result;
	
	if ([objVal respondsToSelector:@selector(unsignedLongValue)])  result = [objVal unsignedLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned long long)unsignedLongLongAtIndex:(unsigned)index defaultValue:(unsigned long long)value
{
	id					objVal = [self objectAtIndex:index];
	int					intVal;
	unsigned long long	result;
	
	if ([objVal respondsToSelector:@selector(unsignedLongLongValue)])  result = [objVal unsignedLongLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (BOOL)boolAtIndex:(unsigned)index defaultValue:(BOOL)value
{
	id					objVal = [self objectAtIndex:index];
	BOOL				result;
	
	result = EvaluateAsBoolean(objVal, value);

	return result;
}


- (BOOL)fuzzyBooleanAtIndex:(unsigned)index defaultValue:(float)value
{
	float				chance;
	
	chance = [self floatAtIndex:index defaultValue:value];
	return randf() < chance;
}


- (float)floatAtIndex:(unsigned)index defaultValue:(float)value
{
	id					objVal = [self objectAtIndex:index];
	float				result;
	
	if ([objVal respondsToSelector:@selector(floatValue)])  result = [objVal floatValue];
	else if ([objVal respondsToSelector:@selector(doubleValue)])  result = [objVal doubleValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (double)doubleAtIndex:(unsigned)index defaultValue:(double)value
{
	id					objVal = [self objectAtIndex:index];
	double				result;
	
	if ([objVal respondsToSelector:@selector(doubleValue)])  result = [objVal doubleValue];
	else if ([objVal respondsToSelector:@selector(floatValue)])  result = [objVal floatValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (id)objectAtIndex:(unsigned)index defaultValue:(id)value
{
	id					objVal = [self objectAtIndex:index];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *)stringAtIndex:(unsigned)index defaultValue:(NSString *)value
{
	id					objVal = [self objectAtIndex:index];
	NSString			*result;
	
	if ([objVal isKindOfClass:[NSString class]])  result = objVal;
	else  result = value;
	
	return result;
}


- (NSArray *)arrayAtIndex:(unsigned)index defaultValue:(NSArray *)value
{
	id					objVal = [self objectAtIndex:index];
	NSArray				*result;
	
	if ([objVal isKindOfClass:[NSArray class]])  result = objVal;
	else  result = value;
	
	return result;	
}


- (NSDictionary *)dictionaryAtIndex:(unsigned)index defaultValue:(NSDictionary *)value
{
	id					objVal = [self objectAtIndex:index];
	NSDictionary		*result;
	
	if ([objVal isKindOfClass:[NSDictionary class]])  result = objVal;
	else  result = value;
	
	return result;	
}


- (NSData *)dataAtIndex:(unsigned)index defaultValue:(NSData *)value
{
	id					objVal = [self objectAtIndex:index];
	NSData				*result;
	
	if ([objVal isKindOfClass:[NSData class]])  result = objVal;
	else  result = value;
	
	return result;	
}


- (char)charAtIndex:(unsigned)index
{
	return [self charAtIndex:index defaultValue:0];
}


- (short)shortAtIndex:(unsigned)index
{
	return [self shortAtIndex:index defaultValue:0];
}


- (int)intAtIndex:(unsigned)index
{
	return [self intAtIndex:index defaultValue:0];
}


- (long)longAtIndex:(unsigned)index
{
	return [self longAtIndex:index defaultValue:0];
}


- (long long)longLongAtIndex:(unsigned)index
{
	return [self longLongAtIndex:index defaultValue:0];
}


- (unsigned char)unsignedCharAtIndex:(unsigned)index
{
	return [self unsignedCharAtIndex:index defaultValue:0];
}


- (unsigned short)unsignedShortAtIndex:(unsigned)index
{
	return [self unsignedShortAtIndex:index defaultValue:0];
}


- (unsigned int)unsignedIntAtIndex:(unsigned)index
{
	return [self unsignedIntAtIndex:index defaultValue:0];
}


- (unsigned long)unsignedLongAtIndex:(unsigned)index
{
	return [self unsignedLongAtIndex:index defaultValue:0];
}


- (unsigned long long)unsignedLongLongAtIndex:(unsigned)index
{
	return [self unsignedLongLongAtIndex:index defaultValue:0];
}


- (BOOL)boolAtIndex:(unsigned)index
{
	return [self boolAtIndex:index defaultValue:NO];
}


- (BOOL)fuzzyBooleanAtIndex:(unsigned)index
{
	return [self fuzzyBooleanAtIndex:index defaultValue:0.0f];
}


- (float)floatAtIndex:(unsigned)index
{
	return [self floatAtIndex:index defaultValue:0.0f];
}


- (double)doubleAtIndex:(unsigned)index
{
	return [self doubleAtIndex:index defaultValue:0.0];
}


- (NSString *)stringAtIndex:(unsigned)index
{
	return [self stringAtIndex:index defaultValue:nil];
}


- (NSArray *)arrayAtIndex:(unsigned)index
{
	return [self arrayAtIndex:index defaultValue:nil];
}


- (NSDictionary *)dictionaryAtIndex:(unsigned)index
{
	return [self dictionaryAtIndex:index defaultValue:nil];
}


- (NSData *)dataAtIndex:(unsigned)index
{
	return [self dataAtIndex:index defaultValue:nil];
}

@end


@implementation NSDictionary (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	char				result;
	
	if ([objVal respondsToSelector:@selector(charValue)])  result = [objVal charValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < CHAR_MIN) intVal = CHAR_MIN;
		else if (CHAR_MAX < intVal) intVal = CHAR_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (short)shortForKey:(id)key defaultValue:(short)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	short				result;
	
	if ([objVal respondsToSelector:@selector(shortValue)])  result = [objVal shortValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < SHRT_MIN) intVal = SHRT_MIN;
		else if (SHRT_MAX < intVal) intVal = SHRT_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (int)intForKey:(id)key defaultValue:(int)value
{
	id					objVal = [self objectForKey:key];
	int					result;
	
	if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (long)longForKey:(id)key defaultValue:(long)value
{
	id					objVal = [self objectForKey:key];
	long				result;
	
	if ([objVal respondsToSelector:@selector(longValue)])  result = [objVal longValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (long long)longLongForKey:(id)key defaultValue:(long long)value
{
	id					objVal = [self objectForKey:key];
	long long			result;
	
	if ([objVal respondsToSelector:@selector(longLongValue)])  result = [objVal longLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned char		result;
	
	if ([objVal respondsToSelector:@selector(unsignedCharValue)])  result = [objVal unsignedCharValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		else if (UCHAR_MAX < intVal) intVal = UCHAR_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned short		result;
	
	if ([objVal respondsToSelector:@selector(unsignedShortValue)])  result = [objVal unsignedShortValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		else if (USHRT_MAX < intVal) intVal = USHRT_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned int		result;
	
	if ([objVal respondsToSelector:@selector(unsignedIntValue)])  result = [objVal unsignedIntValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned long		result;
	
	if ([objVal respondsToSelector:@selector(unsignedLongValue)])  result = [objVal unsignedLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned long long	result;
	
	if ([objVal respondsToSelector:@selector(unsignedLongLongValue)])  result = [objVal unsignedLongLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value
{
	id					objVal = [self objectForKey:key];
	BOOL				result;
	
	result = EvaluateAsBoolean(objVal, value);

	return result;
}


- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value
{
	float				chance;
	
	chance = [self floatForKey:key defaultValue:value];
	return randf() < chance;
}


- (float)floatForKey:(id)key defaultValue:(float)value
{
	id					objVal = [self objectForKey:key];
	float				result;
	
	if ([objVal respondsToSelector:@selector(floatValue)])  result = [objVal floatValue];
	else if ([objVal respondsToSelector:@selector(doubleValue)])  result = [objVal doubleValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (double)doubleForKey:(id)key defaultValue:(double)value
{
	id					objVal = [self objectForKey:key];
	double				result;
	
	if ([objVal respondsToSelector:@selector(doubleValue)])  result = [objVal doubleValue];
	else if ([objVal respondsToSelector:@selector(floatValue)])  result = [objVal floatValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (id)objectForKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value
{
	id					objVal = [self objectForKey:key];
	NSString			*result;
	
	if ([objVal isKindOfClass:[NSString class]])  result = objVal;
	else result = value;
	
	return result;
}


- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if ([objVal isKindOfClass:[NSArray class]])  result = objVal;
	else result = value;
	
	return result;
}


- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value
{
	id					objVal = [self objectForKey:key];
	NSDictionary		*result;
	
	if ([objVal isKindOfClass:[NSDictionary class]])  result = objVal;
	else result = value;
	
	return result;
}


- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value
{
	id					objVal = [self objectForKey:key];
	NSData				*result;
	
	if ([objVal isKindOfClass:[NSData class]])  result = objVal;
	else result = value;
	
	return result;
}


- (char)charForKey:(id)key
{
	return [self charForKey:key defaultValue:0];
}


- (short)shortForKey:(id)key
{
	return [self shortForKey:key defaultValue:0];
}


- (int)intForKey:(id)key
{
	return [self intForKey:key defaultValue:0];
}


- (long)longForKey:(id)key
{
	return [self longForKey:key defaultValue:0];
}


- (long long)longLongForKey:(id)key
{
	return [self longLongForKey:key defaultValue:0];
}


- (unsigned char)unsignedCharForKey:(id)key
{
	return [self unsignedCharForKey:key defaultValue:0];
}


- (unsigned short)unsignedShortForKey:(id)key
{
	return [self unsignedShortForKey:key defaultValue:0];
}


- (unsigned int)unsignedIntForKey:(id)key
{
	return [self unsignedIntForKey:key defaultValue:0];
}


- (unsigned long)unsignedLongForKey:(id)key
{
	return [self unsignedLongForKey:key defaultValue:0];
}


- (unsigned long long)unsignedLongLongForKey:(id)key
{
	return [self unsignedLongLongForKey:key defaultValue:0];
}


- (BOOL)boolForKey:(id)key
{
	return [self boolForKey:key defaultValue:NO];
}


- (BOOL)fuzzyBooleanForKey:(id)key
{
	return [self fuzzyBooleanForKey:key defaultValue:0.0f];
}


- (float)floatForKey:(id)key
{
	return [self floatForKey:key defaultValue:0.0f];
}


- (double)doubleForKey:(id)key
{
	return [self doubleForKey:key defaultValue:0.0];
}


- (NSString *)stringForKey:(id)key
{
	return [self stringForKey:key defaultValue:nil];
}


- (NSArray *)arrayForKey:(id)key
{
	return [self arrayForKey:key defaultValue:nil];
}


- (NSDictionary *)dictionaryForKey:(id)key
{
	return [self dictionaryForKey:key defaultValue:nil];
}


- (NSData *)dataForKey:(id)key
{
	return [self dataForKey:key defaultValue:nil];
}

@end


@implementation NSUserDefaults (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	char				result;
	
	if ([objVal respondsToSelector:@selector(charValue)])  result = [objVal charValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < CHAR_MIN) intVal = CHAR_MIN;
		else if (CHAR_MAX < intVal) intVal = CHAR_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (short)shortForKey:(id)key defaultValue:(short)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	short				result;
	
	if ([objVal respondsToSelector:@selector(shortValue)])  result = [objVal shortValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < SHRT_MIN) intVal = SHRT_MIN;
		else if (SHRT_MAX < intVal) intVal = SHRT_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (int)intForKey:(id)key defaultValue:(int)value
{
	id					objVal = [self objectForKey:key];
	int					result;
	
	if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (long)longForKey:(id)key defaultValue:(long)value
{
	id					objVal = [self objectForKey:key];
	long				result;
	
	if ([objVal respondsToSelector:@selector(longValue)])  result = [objVal longValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (long long)longLongForKey:(id)key defaultValue:(long long)value
{
	id					objVal = [self objectForKey:key];
	long long			result;
	
	if ([objVal respondsToSelector:@selector(longLongValue)])  result = [objVal longLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned char		result;
	
	if ([objVal respondsToSelector:@selector(unsignedCharValue)])  result = [objVal unsignedCharValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		else if (UCHAR_MAX < intVal) intVal = UCHAR_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned short		result;
	
	if ([objVal respondsToSelector:@selector(unsignedShortValue)])  result = [objVal unsignedShortValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		else if (USHRT_MAX < intVal) intVal = USHRT_MAX;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned int		result;
	
	if ([objVal respondsToSelector:@selector(unsignedIntValue)])  result = [objVal unsignedIntValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned long		result;
	
	if ([objVal respondsToSelector:@selector(unsignedLongValue)])  result = [objVal unsignedLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value
{
	id					objVal = [self objectForKey:key];
	int					intVal;
	unsigned long long	result;
	
	if ([objVal respondsToSelector:@selector(unsignedLongLongValue)])  result = [objVal unsignedLongLongValue];
	else if ([objVal respondsToSelector:@selector(intValue)])
	{
		intVal = [objVal intValue];
		if (intVal < 0) intVal = 0;
		result = intVal;
	}
	else result = value;

	return result;
}


- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value
{
	id					objVal = [self objectForKey:key];
	BOOL				result;
	
	result = EvaluateAsBoolean(objVal, value);

	return result;
}


- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value
{
	float				chance;
	
	chance = [self floatForKey:key defaultValue:value];
	return randf() < chance;
}


- (float)floatForKey:(id)key defaultValue:(float)value
{
	id					objVal = [self objectForKey:key];
	float				result;
	
	if ([objVal respondsToSelector:@selector(floatValue)])  result = [objVal floatValue];
	else if ([objVal respondsToSelector:@selector(doubleValue)])  result = [objVal doubleValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (double)doubleForKey:(id)key defaultValue:(double)value
{
	id					objVal = [self objectForKey:key];
	double				result;
	
	if ([objVal respondsToSelector:@selector(doubleValue)])  result = [objVal doubleValue];
	else if ([objVal respondsToSelector:@selector(floatValue)])  result = [objVal floatValue];
	else if ([objVal respondsToSelector:@selector(intValue)])  result = [objVal intValue];
	else result = value;

	return result;
}


- (id)objectForKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value
{
	id					objVal = [self objectForKey:key];
	NSString			*result;
	
	if ([objVal isKindOfClass:[NSString class]])  result = objVal;
	else result = value;
	
	return result;
}


- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if ([objVal isKindOfClass:[NSArray class]])  result = objVal;
	else result = value;
	
	return result;
}


- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value
{
	id					objVal = [self objectForKey:key];
	NSDictionary		*result;
	
	if ([objVal isKindOfClass:[NSDictionary class]])  result = objVal;
	else result = value;
	
	return result;
}


- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value
{
	id					objVal = [self objectForKey:key];
	NSData				*result;
	
	if ([objVal isKindOfClass:[NSData class]])  result = objVal;
	else result = value;
	
	return result;
}


- (char)charForKey:(id)key
{
	return [self charForKey:key defaultValue:0];
}


- (short)shortForKey:(id)key
{
	return [self shortForKey:key defaultValue:0];
}


- (int)intForKey:(id)key
{
	return [self intForKey:key defaultValue:0];
}


- (long)longForKey:(id)key
{
	return [self longForKey:key defaultValue:0];
}


- (long long)longLongForKey:(id)key
{
	return [self longLongForKey:key defaultValue:0];
}


- (unsigned char)unsignedCharForKey:(id)key
{
	return [self unsignedCharForKey:key defaultValue:0];
}


- (unsigned short)unsignedShortForKey:(id)key
{
	return [self unsignedShortForKey:key defaultValue:0];
}


- (unsigned int)unsignedIntForKey:(id)key
{
	return [self unsignedIntForKey:key defaultValue:0];
}


- (unsigned long)unsignedLongForKey:(id)key
{
	return [self unsignedLongForKey:key defaultValue:0];
}


- (unsigned long long)unsignedLongLongForKey:(id)key
{
	return [self unsignedLongLongForKey:key defaultValue:0];
}


- (BOOL)fuzzyBooleanForKey:(id)key
{
	return [self fuzzyBooleanForKey:key defaultValue:0.0f];
}


- (double)doubleForKey:(id)key
{
	return [self doubleForKey:key defaultValue:0.0];
}

@end
