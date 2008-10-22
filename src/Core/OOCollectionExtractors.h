/*

OOCollectionExtractors.h

Convenience extensions to Foundation collections to extract optional values.
In addition to being convenient, these perform type checking. Which is,
y'know, good to have.

Note on types: ideally, stdint.h types would be used for integers. However,
NSNumber doesn't do this, so doing so portably would add new complications.

Starting with Oolite 1.69.1, the various integer methods will always clamp
values to the range of the return type, rather than truncating like NSNumber.
Before that, they weren't entirely inconsistent.

The "non-negative float"/"non-negative double" will clamp read values to zero
if negative, but will return a negative defaultValue unchanged.


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

Copyright (C) 2007 Jens Ayton

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


#import <Foundation/Foundation.h>
#import "OOFunctionAttributes.h"
#include <limits.h>

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
#import "OOMaths.h"
#endif



@interface NSArray (OOExtractor)

- (char)charAtIndex:(OOUInteger)index defaultValue:(char)value;
- (short)shortAtIndex:(OOUInteger)index defaultValue:(short)value;
- (int)intAtIndex:(OOUInteger)index defaultValue:(int)value;
- (long)longAtIndex:(OOUInteger)index defaultValue:(long)value;
- (long long)longLongAtIndex:(OOUInteger)index defaultValue:(long long)value;
- (OOInteger)integerAtIndex:(OOUInteger)index defaultValue:(OOInteger)value;

- (unsigned char)unsignedCharAtIndex:(OOUInteger)index defaultValue:(unsigned char)value;
- (unsigned short)unsignedShortAtIndex:(OOUInteger)index defaultValue:(unsigned short)value;
- (unsigned int)unsignedIntAtIndex:(OOUInteger)index defaultValue:(unsigned int)value;
- (unsigned long)unsignedLongAtIndex:(OOUInteger)index defaultValue:(unsigned long)value;
- (unsigned long long)unsignedLongLongAtIndex:(OOUInteger)index defaultValue:(unsigned long long)value;
- (OOUInteger)unsignedIntegerAtIndex:(OOUInteger)index defaultValue:(OOUInteger)value;

- (BOOL)boolAtIndex:(OOUInteger)index defaultValue:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL)fuzzyBooleanAtIndex:(OOUInteger)index defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

- (float)floatAtIndex:(OOUInteger)index defaultValue:(float)value;
- (double)doubleAtIndex:(OOUInteger)index defaultValue:(double)value;
- (float)nonNegativeFloatAtIndex:(OOUInteger)index defaultValue:(float)value;
- (double)nonNegativeDoubleAtIndex:(OOUInteger)index defaultValue:(double)value;

- (id)objectAtIndex:(OOUInteger)index defaultValue:(id)value;
- (id)objectOfClass:(Class)class atIndex:(OOUInteger)index defaultValue:(id)value;
- (NSString *)stringAtIndex:(OOUInteger)index defaultValue:(NSString *)value;
- (NSArray *)arrayAtIndex:(OOUInteger)index defaultValue:(NSArray *)value;
- (NSSet *)setAtIndex:(OOUInteger)index defaultValue:(NSSet *)value;
- (NSDictionary *)dictionaryAtIndex:(OOUInteger)index defaultValue:(NSDictionary *)value;
- (NSData *)dataAtIndex:(OOUInteger)index defaultValue:(NSData *)value;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector)vectorAtIndex:(OOUInteger)index defaultValue:(Vector)value;
- (Quaternion)quaternionAtIndex:(OOUInteger)index defaultValue:(Quaternion)value;
#endif


// Default: 0
- (char)charAtIndex:(OOUInteger)index;
- (short)shortAtIndex:(OOUInteger)index;
- (int)intAtIndex:(OOUInteger)index;
- (long)longAtIndex:(OOUInteger)index;
- (long long)longLongAtIndex:(OOUInteger)index;
- (OOInteger)integerAtIndex:(OOUInteger)index;

- (unsigned char)unsignedCharAtIndex:(OOUInteger)index;
- (unsigned short)unsignedShortAtIndex:(OOUInteger)index;
- (unsigned int)unsignedIntAtIndex:(OOUInteger)index;
- (unsigned long)unsignedLongAtIndex:(OOUInteger)index;
- (unsigned long long)unsignedLongLongAtIndex:(OOUInteger)index;
- (OOUInteger)unsignedIntegerAtIndex:(OOUInteger)index;

// Default: NO
- (BOOL)boolAtIndex:(OOUInteger)index;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL)fuzzyBooleanAtIndex:(OOUInteger)index;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

// Default: 0.0
- (float)floatAtIndex:(OOUInteger)index;
- (double)doubleAtIndex:(OOUInteger)index;
- (float)nonNegativeFloatAtIndex:(OOUInteger)index;
- (double)nonNegativeDoubleAtIndex:(OOUInteger)index;

// Default: nil
// - (id)objectAtIndex:(OOUInteger)index;	// Already defined
- (id)objectOfClass:(Class)class atIndex:(OOUInteger)index;
- (NSString *)stringAtIndex:(OOUInteger)index;
- (NSArray *)arrayAtIndex:(OOUInteger)index;
- (NSSet *)setAtIndex:(OOUInteger)index;
- (NSDictionary *)dictionaryAtIndex:(OOUInteger)index;
- (NSData *)dataAtIndex:(OOUInteger)index;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
// Default: kZeroVector
- (Vector)vectorAtIndex:(OOUInteger)index;
// Default: kIdentityQuaternion
- (Quaternion)quaternionAtIndex:(OOUInteger)index;
#endif

@end


@interface NSDictionary (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value;
- (short)shortForKey:(id)key defaultValue:(short)value;
- (int)intForKey:(id)key defaultValue:(int)value;
- (long)longForKey:(id)key defaultValue:(long)value;
- (long long)longLongForKey:(id)key defaultValue:(long long)value;
- (OOInteger)integerForKey:(id)key defaultValue:(OOInteger)value;

- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value;
- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value;
- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value;
- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value;
- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value;
- (OOUInteger)unsignedIntegerForKey:(id)key defaultValue:(OOUInteger)value;

- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

- (float)floatForKey:(id)key defaultValue:(float)value;
- (double)doubleForKey:(id)key defaultValue:(double)value;
- (float)nonNegativeFloatForKey:(id)key defaultValue:(float)value;
- (double)nonNegativeDoubleForKey:(id)key defaultValue:(double)value;

- (id)objectForKey:(id)key defaultValue:(id)value;
- (id)objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value;
- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value;
- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value;
- (NSSet *)setForKey:(id)key defaultValue:(NSSet *)value;
- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value;
- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector)vectorForKey:(id)key defaultValue:(Vector)value;
- (Quaternion)quaternionForKey:(id)key defaultValue:(Quaternion)value;
#endif


// Default: 0
- (char)charForKey:(id)key;
- (short)shortForKey:(id)key;
- (int)intForKey:(id)key;
- (long)longForKey:(id)key;
- (long long)longLongForKey:(id)key;
- (OOInteger)integerForKey:(id)key;

- (unsigned char)unsignedCharForKey:(id)key;
- (unsigned short)unsignedShortForKey:(id)key;
- (unsigned int)unsignedIntForKey:(id)key;
- (unsigned long)unsignedLongForKey:(id)key;
- (unsigned long long)unsignedLongLongForKey:(id)key;
- (OOUInteger)unsignedIntegerForKey:(id)key;

// Default: NO
- (BOOL)boolForKey:(id)key;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL)fuzzyBooleanForKey:(id)key;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

// Default: 0.0
- (float)floatForKey:(id)key;
- (double)doubleForKey:(id)key;
- (float)nonNegativeFloatForKey:(id)key;
- (double)nonNegativeDoubleForKey:(id)key;

// Default: nil
// - (id)objectForKey:(id)key;	// Already defined
- (id)objectOfClass:(Class)class forKey:(id)key;
- (NSString *)stringForKey:(id)key;
- (NSArray *)arrayForKey:(id)key;
- (NSSet *)setForKey:(id)key;
- (NSDictionary *)dictionaryForKey:(id)key;
- (NSData *)dataForKey:(id)key;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
// Default: kZeroVector
- (Vector)vectorForKey:(id)key;
// Default: kIdentityQuaternion
- (Quaternion)quaternionForKey:(id)key;
#endif

@end


@interface NSUserDefaults (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value;
- (short)shortForKey:(id)key defaultValue:(short)value;
- (int)intForKey:(id)key defaultValue:(int)value;
- (long)longForKey:(id)key defaultValue:(long)value;
- (long long)longLongForKey:(id)key defaultValue:(long long)value;

- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value;
- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value;
- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value;
- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value;
- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value;

- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

- (float)floatForKey:(id)key defaultValue:(float)value;
- (double)doubleForKey:(id)key defaultValue:(double)value;
- (float)nonNegativeFloatForKey:(id)key defaultValue:(float)value;
- (double)nonNegativeDoubleForKey:(id)key defaultValue:(double)value;

- (id)objectForKey:(id)key defaultValue:(id)value;
- (id)objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value;
- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value;
- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value;
- (NSSet *)setForKey:(id)key defaultValue:(NSSet *)value;
- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value;
- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value;


// Default: 0
- (char)charForKey:(id)key;
- (short)shortForKey:(id)key;
- (int)intForKey:(id)key;
- (long)longForKey:(id)key;
- (long long)longLongForKey:(id)key;

- (unsigned char)unsignedCharForKey:(id)key;
- (unsigned short)unsignedShortForKey:(id)key;
- (unsigned int)unsignedIntForKey:(id)key;
- (unsigned long)unsignedLongForKey:(id)key;
- (unsigned long long)unsignedLongLongForKey:(id)key;

// Default: NO
// - (BOOL)boolForKey:(id)key;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL)fuzzyBooleanForKey:(id)key;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

// Default: 0.0
// - (float)floatForKey:(id)key;
- (double)doubleForKey:(NSString *)key;
- (float)nonNegativeFloatForKey:(id)key;
- (double)nonNegativeDoubleForKey:(id)key;

// Default: nil
// - (id)objectForKey:(id)key;	// Already defined
- (id)objectOfClass:(Class)class forKey:(id)key;
// - (NSString *)stringForKey:(id)key;
// - (NSArray *)arrayForKey:(id)key;
- (NSSet *)setForKey:(id)key;
// - (NSDictionary *)dictionaryForKey:(id)key;
// - (NSData *)dataForKey:(id)key;

@end


@interface NSMutableArray (OOInserter)

- (void)addInteger:(long)value;
- (void)addUnsignedInteger:(unsigned long)value;
- (void)addFloat:(double)value;
- (void)addBool:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void)addVector:(Vector)value;
- (void)addQuaternion:(Quaternion)value;
#endif

- (void)insertInteger:(long)value atIndex:(OOUInteger)index;
- (void)insertUnsignedInteger:(unsigned long)value atIndex:(OOUInteger)index;
- (void)insertFloat:(double)value atIndex:(OOUInteger)index;
- (void)insertBool:(BOOL)value atIndex:(OOUInteger)index;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void)insertVector:(Vector)value atIndex:(OOUInteger)index;
- (void)insertQuaternion:(Quaternion)value atIndex:(OOUInteger)index;
#endif

@end


@interface NSMutableDictionary (OOInserter)

- (void)setInteger:(long)value forKey:(id)key;
- (void)setUnsignedInteger:(unsigned long)value forKey:(id)key;
- (void)setLongLong:(long long)value forKey:(id)key;
- (void)setUnsignedLongLong:(unsigned long long)value forKey:(id)key;
- (void)setFloat:(double)value forKey:(id)key;
- (void)setBool:(BOOL)value forKey:(id)key;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void)setVector:(Vector)value forKey:(id)key;
- (void)setQuaternion:(Quaternion)value forKey:(id)key;
#endif

@end


@interface NSMutableSet (OOInserter)

- (void)addInteger:(long)value;
- (void)addUnsignedInteger:(unsigned long)value;
- (void)addFloat:(double)value;
- (void)addBool:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void)addVector:(Vector)value;
- (void)addQuaternion:(Quaternion)value;
#endif

@end


// *** Value extraction utilities ***

/*	Utility function to interpret a boolean. May be an NSNumber or any of the
	following strings (case-insensitive):
		yes
		true
		on
		
		no
		false
		off
*/
BOOL OOBooleanFromObject(id object, BOOL defaultValue);


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
/*	Utility function to interpret a fuzzy boolean. May be any of the strings
	accepted by OOBooleanFromObject(), or a number indicating probability of
	a yes (between 0 and 1).
*/
BOOL OOFuzzyBooleanFromObject(id object, float defaultValue);
#endif


float OOFloatFromObject(id object, float defaultValue);
double OODoubleFromObject(id object, double defaultValue);
float OONonNegativeFloatFromObject(id object, float defaultValue);
double OONonNegativeDoubleFromObject(id object, double defaultValue);

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
//	These take strings, dictionaries or arrays.
Vector OOVectorFromObject(id object, Vector defaultValue);
Quaternion OOQuaternionFromObject(id object, Quaternion defaultValue);

NSDictionary *OOPropertyListFromVector(Vector value);
NSDictionary *OOPropertyListFromQuaternion(Quaternion value);
#endif


OOINLINE long long OOClampInteger(long long value, long long minValue, long long maxValue) ALWAYS_INLINE_FUNC;
long long OOLongLongFromObject(id object, long long defaultValue);
unsigned long long OOUnsignedLongLongFromObject(id object, unsigned long long defaultValue);


OOINLINE long long OOClampInteger(long long value, long long minValue, long long maxValue)
{
	return (minValue < value) ? ((value < maxValue) ? value : maxValue) : minValue;
}


/*	Define an inline function to clamp a give type and its unsigned
	counterpart. Example:
	
		OO_DEFINE_CLAMP_PAIR(char, Char, CHAR)
	
	expands to
	
		OOINLINE char OOCharFromObject(id object, char defaultValue)
		{
			return OOClampInteger(OOLongLongFromObject(object, defaultValue), CHAR_MIN, CHAR_MAX);
		}
		OOINLINE unsigned char OOUnsignedCharFromObject(id object, unsigned char defaultValue)
		{
			return OOClampInteger(OOLongLongFromObject(object, defaultValue), 0, UCHAR_MAX);
		}
*/
#define OO_DEFINE_CLAMP(type, typeName, min, max) \
	OOINLINE type OO ## typeName ## FromObject(id object, type defaultValue) \
	{ \
		return OOClampInteger(OOLongLongFromObject(object, defaultValue), min, max); \
	}

#define OO_DEFINE_CLAMP_PAIR(type, typeName, minMaxSymb) \
	OO_DEFINE_CLAMP(type, typeName, minMaxSymb ## _MIN, minMaxSymb ## _MAX) \
	OO_DEFINE_CLAMP(unsigned type, Unsigned ## typeName, 0, U ## minMaxSymb ## _MAX)

OO_DEFINE_CLAMP_PAIR(char, Char, CHAR)
OO_DEFINE_CLAMP_PAIR(short, Short, SHRT)

/*	When ints or longs are as large as long longs, we can't do any clamping
	because the clamping code will overflow (unless we add pointless complexity).
	Instead, we alias the long long versions which don't clamp. Inlines are
	used instead of macros so that the functions always have the precise type
	they should; this is necessary for stuff that uses @encode, notably the
	SenTestingKit framework.
*/
#define OO_ALIAS_CLAMP_LONG_LONG(type, typeName) \
static inline type OO##typeName##FromObject(id object, type defaultValue) \
{ \
	return OOLongLongFromObject(object, defaultValue); \
}
#define OO_ALIAS_CLAMP_PAIR_LONG_LONG(type, typeName) \
OO_ALIAS_CLAMP_LONG_LONG(type, typeName) \
OO_ALIAS_CLAMP_LONG_LONG(unsigned type, Unsigned##typeName)

#if INT_MAX == LLONG_MAX
//	Should never get here under Mac OS X, but may under GNUstep.
OO_ALIAS_CLAMP_PAIR_LONG_LONG(int, Int)
#else
OO_DEFINE_CLAMP_PAIR(int, Int, INT)
#endif

#if LONG_MAX == LLONG_MAX
OO_ALIAS_CLAMP_PAIR_LONG_LONG(long, Long)
#else
OO_DEFINE_CLAMP_PAIR(long, Long, LONG)
#endif


#if OOLITE_64_BIT
OOINLINE OOInteger OOIntegerFromObject(id object, OOInteger defaultValue)
{
	return OOLongLongFromObject(object, defaultValue);
}

OOINLINE OOInteger OOUIntegerFromObject(id object, OOUInteger defaultValue)
{
	return OOUnsignedLongLongFromObject(object, defaultValue);
}
#else
OOINLINE OOInteger OOIntegerFromObject(id object, OOInteger defaultValue)
{
	return OOLongLongFromObject(object, defaultValue);
}

OOINLINE OOInteger OOUIntegerFromObject(id object, OOUInteger defaultValue)
{
	return OOUnsignedLongLongFromObject(object, defaultValue);
}
#endif


#undef OO_DEFINE_CLAMP
#undef OO_DEFINE_CLAMP_PAIR
#undef OO_ALIAS_CLAMP_LONG_LONG
#undef OO_ALIAS_CLAMP_PAIR_LONG_LONG
