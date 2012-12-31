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


Copyright (C) 2007-2013 Jens Ayton and contributors

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

- (char) oo_charAtIndex:(NSUInteger)index defaultValue:(char)value;
- (short) oo_shortAtIndex:(NSUInteger)index defaultValue:(short)value;
- (int) oo_intAtIndex:(NSUInteger)index defaultValue:(int)value;
- (long) oo_longAtIndex:(NSUInteger)index defaultValue:(long)value;
- (long long) oo_longLongAtIndex:(NSUInteger)index defaultValue:(long long)value;
- (NSInteger) oo_integerAtIndex:(NSUInteger)index defaultValue:(NSInteger)value;

- (unsigned char) oo_unsignedCharAtIndex:(NSUInteger)index defaultValue:(unsigned char)value;
- (unsigned short) oo_unsignedShortAtIndex:(NSUInteger)index defaultValue:(unsigned short)value;
- (unsigned int) oo_unsignedIntAtIndex:(NSUInteger)index defaultValue:(unsigned int)value;
- (unsigned long) oo_unsignedLongAtIndex:(NSUInteger)index defaultValue:(unsigned long)value;
- (unsigned long long) oo_unsignedLongLongAtIndex:(NSUInteger)index defaultValue:(unsigned long long)value;
- (NSUInteger) oo_unsignedIntegerAtIndex:(NSUInteger)index defaultValue:(NSUInteger)value;

- (BOOL) oo_boolAtIndex:(NSUInteger)index defaultValue:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanAtIndex:(NSUInteger)index defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

- (float) oo_floatAtIndex:(NSUInteger)index defaultValue:(float)value;
- (double) oo_doubleAtIndex:(NSUInteger)index defaultValue:(double)value;
- (float) oo_nonNegativeFloatAtIndex:(NSUInteger)index defaultValue:(float)value;
- (double) oo_nonNegativeDoubleAtIndex:(NSUInteger)index defaultValue:(double)value;

- (id) oo_objectAtIndex:(NSUInteger)index defaultValue:(id)value;
- (id) oo_objectOfClass:(Class)class atIndex:(NSUInteger)index defaultValue:(id)value;
- (NSString *) oo_stringAtIndex:(NSUInteger)index defaultValue:(NSString *)value;
- (NSArray *) oo_arrayAtIndex:(NSUInteger)index defaultValue:(NSArray *)value;
- (NSSet *) oo_setAtIndex:(NSUInteger)index defaultValue:(NSSet *)value;
- (NSDictionary *) oo_dictionaryAtIndex:(NSUInteger)index defaultValue:(NSDictionary *)value;
- (NSData *) oo_dataAtIndex:(NSUInteger)index defaultValue:(NSData *)value;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector) oo_vectorAtIndex:(NSUInteger)index defaultValue:(Vector)value;
- (Quaternion) oo_quaternionAtIndex:(NSUInteger)index defaultValue:(Quaternion)value;
#endif


// Default: 0
- (char) oo_charAtIndex:(NSUInteger)index;
- (short) oo_shortAtIndex:(NSUInteger)index;
- (int) oo_intAtIndex:(NSUInteger)index;
- (long) oo_longAtIndex:(NSUInteger)index;
- (long long) oo_longLongAtIndex:(NSUInteger)index;
- (NSInteger) oo_integerAtIndex:(NSUInteger)index;

- (unsigned char) oo_unsignedCharAtIndex:(NSUInteger)index;
- (unsigned short) oo_unsignedShortAtIndex:(NSUInteger)index;
- (unsigned int) oo_unsignedIntAtIndex:(NSUInteger)index;
- (unsigned long) oo_unsignedLongAtIndex:(NSUInteger)index;
- (unsigned long long) oo_unsignedLongLongAtIndex:(NSUInteger)index;
- (NSUInteger) oo_unsignedIntegerAtIndex:(NSUInteger)index;

// Default: NO
- (BOOL) oo_boolAtIndex:(NSUInteger)index;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanAtIndex:(NSUInteger)index;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

// Default: 0.0
- (float) oo_floatAtIndex:(NSUInteger)index;
- (double) oo_doubleAtIndex:(NSUInteger)index;
- (float) oo_nonNegativeFloatAtIndex:(NSUInteger)index;
- (double) oo_nonNegativeDoubleAtIndex:(NSUInteger)index;

// Default: nil
- (id) oo_objectAtIndex:(NSUInteger)index;	// Differs from objectAtIndex: in that it returns nil rather than throwing NSRangeException.
- (id) oo_objectOfClass:(Class)class atIndex:(NSUInteger)index;
- (NSString *) oo_stringAtIndex:(NSUInteger)index;
- (NSArray *) oo_arrayAtIndex:(NSUInteger)index;
- (NSSet *) oo_setAtIndex:(NSUInteger)index;
- (NSDictionary *) oo_dictionaryAtIndex:(NSUInteger)index;
- (NSData *) oo_dataAtIndex:(NSUInteger)index;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
// Default: kZeroVector
- (Vector) oo_vectorAtIndex:(NSUInteger)index;
// Default: kIdentityQuaternion
- (Quaternion) oo_quaternionAtIndex:(NSUInteger)index;
#endif

@end


@interface NSDictionary (OOExtractor)

- (char) oo_charForKey:(id)key defaultValue:(char)value;
- (short) oo_shortForKey:(id)key defaultValue:(short)value;
- (int) oo_intForKey:(id)key defaultValue:(int)value;
- (long) oo_longForKey:(id)key defaultValue:(long)value;
- (long long) oo_longLongForKey:(id)key defaultValue:(long long)value;
- (NSInteger) oo_integerForKey:(id)key defaultValue:(NSInteger)value;

- (unsigned char) oo_unsignedCharForKey:(id)key defaultValue:(unsigned char)value;
- (unsigned short) oo_unsignedShortForKey:(id)key defaultValue:(unsigned short)value;
- (unsigned int) oo_unsignedIntForKey:(id)key defaultValue:(unsigned int)value;
- (unsigned long) oo_unsignedLongForKey:(id)key defaultValue:(unsigned long)value;
- (unsigned long long) oo_unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value;
- (NSUInteger) oo_unsignedIntegerForKey:(id)key defaultValue:(NSUInteger)value;

- (BOOL) oo_boolForKey:(id)key defaultValue:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

- (float) oo_floatForKey:(id)key defaultValue:(float)value;
- (double) oo_doubleForKey:(id)key defaultValue:(double)value;
- (float) oo_nonNegativeFloatForKey:(id)key defaultValue:(float)value;
- (double) oo_nonNegativeDoubleForKey:(id)key defaultValue:(double)value;

- (id) oo_objectForKey:(id)key defaultValue:(id)value;
- (id) oo_objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value;
- (NSString *) oo_stringForKey:(id)key defaultValue:(NSString *)value;
- (NSArray *) oo_arrayForKey:(id)key defaultValue:(NSArray *)value;
- (NSSet *) oo_setForKey:(id)key defaultValue:(NSSet *)value;
- (NSDictionary *) oo_dictionaryForKey:(id)key defaultValue:(NSDictionary *)value;
- (NSData *) oo_dataForKey:(id)key defaultValue:(NSData *)value;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector) oo_vectorForKey:(id)key defaultValue:(Vector)value;
- (Quaternion) oo_quaternionForKey:(id)key defaultValue:(Quaternion)value;
#endif


// Default: 0
- (char) oo_charForKey:(id)key;
- (short) oo_shortForKey:(id)key;
- (int) oo_intForKey:(id)key;
- (long) oo_longForKey:(id)key;
- (long long) oo_longLongForKey:(id)key;
- (NSInteger) oo_integerForKey:(id)key;

- (unsigned char) oo_unsignedCharForKey:(id)key;
- (unsigned short) oo_unsignedShortForKey:(id)key;
- (unsigned int) oo_unsignedIntForKey:(id)key;
- (unsigned long) oo_unsignedLongForKey:(id)key;
- (unsigned long long) oo_unsignedLongLongForKey:(id)key;
- (NSUInteger) oo_unsignedIntegerForKey:(id)key;

// Default: NO
- (BOOL) oo_boolForKey:(id)key;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

// Default: 0.0
- (float) oo_floatForKey:(id)key;
- (double) oo_doubleForKey:(id)key;
- (float) oo_nonNegativeFloatForKey:(id)key;
- (double) oo_nonNegativeDoubleForKey:(id)key;

// Default: nil
// - (id)objectForKey:(id)key;	// Already defined
- (id) oo_objectOfClass:(Class)class forKey:(id)key;
- (NSString *) oo_stringForKey:(id)key;
- (NSArray *) oo_arrayForKey:(id)key;
- (NSSet *) oo_setForKey:(id)key;
- (NSDictionary *) oo_dictionaryForKey:(id)key;
- (NSData *) oo_dataForKey:(id)key;

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
// Default: kZeroVector
- (Vector) oo_vectorForKey:(id)key;
// Default: kIdentityQuaternion
- (Quaternion) oo_quaternionForKey:(id)key;
#endif

@end


@interface NSUserDefaults (OOExtractor)

- (char) oo_charForKey:(id)key defaultValue:(char)value;
- (short) oo_shortForKey:(id)key defaultValue:(short)value;
- (int) oo_intForKey:(id)key defaultValue:(int)value;
- (long) oo_longForKey:(id)key defaultValue:(long)value;
- (long long) oo_longLongForKey:(id)key defaultValue:(long long)value;
- (NSInteger) oo_integerForKey:(id)key defaultValue:(NSInteger)value;

- (unsigned char) oo_unsignedCharForKey:(id)key defaultValue:(unsigned char)value;
- (unsigned short) oo_unsignedShortForKey:(id)key defaultValue:(unsigned short)value;
- (unsigned int) oo_unsignedIntForKey:(id)key defaultValue:(unsigned int)value;
- (unsigned long) oo_unsignedLongForKey:(id)key defaultValue:(unsigned long)value;
- (unsigned long long) oo_unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value;
- (NSUInteger) oo_unsignedIntegerForKey:(id)key defaultValue:(NSUInteger)value;

- (BOOL) oo_boolForKey:(id)key defaultValue:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

- (float) oo_floatForKey:(id)key defaultValue:(float)value;
- (double) oo_doubleForKey:(id)key defaultValue:(double)value;
- (float) oo_nonNegativeFloatForKey:(id)key defaultValue:(float)value;
- (double) oo_nonNegativeDoubleForKey:(id)key defaultValue:(double)value;

- (id) oo_objectForKey:(id)key defaultValue:(id)value;
- (id) oo_objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value;
- (NSString *) oo_stringForKey:(id)key defaultValue:(NSString *)value;
- (NSArray *) oo_arrayForKey:(id)key defaultValue:(NSArray *)value;
- (NSSet *) oo_setForKey:(id)key defaultValue:(NSSet *)value;
- (NSDictionary *) oo_dictionaryForKey:(id)key defaultValue:(NSDictionary *)value;
- (NSData *) oo_dataForKey:(id)key defaultValue:(NSData *)value;


// Default: 0
- (char) oo_charForKey:(id)key;
- (short) oo_shortForKey:(id)key;
- (int) oo_intForKey:(id)key;
- (long) oo_longForKey:(id)key;
- (long long) oo_longLongForKey:(id)key;

- (unsigned char) oo_unsignedCharForKey:(id)key;
- (unsigned short) oo_unsignedShortForKey:(id)key;
- (unsigned int) oo_unsignedIntForKey:(id)key;
- (unsigned long) oo_unsignedLongForKey:(id)key;
- (unsigned long long) oo_unsignedLongLongForKey:(id)key;

// Default: NO
// - (BOOL) boolForKey:(id)key;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key;	// Reads a float in the range [0, 1], and returns YES with that probability.
#endif

// Default: 0.0
// - (float) floatForKey:(id)key;
- (double) oo_doubleForKey:(NSString *)key;
- (float) oo_nonNegativeFloatForKey:(id)key;
- (double) oo_nonNegativeDoubleForKey:(id)key;

// Default: nil
// - (id) objectForKey:(id)key;	// Already defined
- (id) oo_objectOfClass:(Class)class forKey:(id)key;
// - (NSString *) stringForKey:(id)key;
// - (NSArray *) arrayForKey:(id)key;
- (NSSet *) oo_setForKey:(id)key;
// - (NSDictionary *) dictionaryForKey:(id)key;
// - (NSData *) dataForKey:(id)key;

@end


@interface NSMutableArray (OOInserter)

- (void) oo_addInteger:(long)value;
- (void) oo_addUnsignedInteger:(unsigned long)value;
- (void) oo_addFloat:(double)value;
- (void) oo_addBool:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void) oo_addVector:(Vector)value;
- (void) oo_addQuaternion:(Quaternion)value;
#endif

- (void) oo_insertInteger:(long)value atIndex:(NSUInteger)index;
- (void) oo_insertUnsignedInteger:(unsigned long)value atIndex:(NSUInteger)index;
- (void) oo_insertFloat:(double)value atIndex:(NSUInteger)index;
- (void) oo_insertBool:(BOOL)value atIndex:(NSUInteger)index;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void) oo_insertVector:(Vector)value atIndex:(NSUInteger)index;
- (void) oo_insertQuaternion:(Quaternion)value atIndex:(NSUInteger)index;
#endif

@end


@interface NSMutableDictionary (OOInserter)

- (void) oo_setInteger:(long)value forKey:(id)key;
- (void) oo_setUnsignedInteger:(unsigned long)value forKey:(id)key;
- (void) oo_setLongLong:(long long)value forKey:(id)key;
- (void) oo_setUnsignedLongLong:(unsigned long long)value forKey:(id)key;
- (void) oo_setFloat:(double)value forKey:(id)key;
- (void) oo_setBool:(BOOL)value forKey:(id)key;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void) oo_setVector:(Vector)value forKey:(id)key;
- (void) oo_setQuaternion:(Quaternion)value forKey:(id)key;
#endif

@end


@interface NSMutableSet (OOInserter)

- (void)oo_addInteger:(long)value;
- (void)oo_addUnsignedInteger:(unsigned long)value;
- (void)oo_addFloat:(double)value;
- (void)oo_addBool:(BOOL)value;
#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void)oo_addVector:(Vector)value;
- (void)oo_addQuaternion:(Quaternion)value;
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
		return (type)OOClampInteger(OOLongLongFromObject(object, defaultValue), min, max); \
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
OOINLINE NSInteger OOIntegerFromObject(id object, NSInteger defaultValue)
{
	return OOLongLongFromObject(object, defaultValue);
}

OOINLINE NSInteger OOUIntegerFromObject(id object, NSUInteger defaultValue)
{
	return OOUnsignedLongLongFromObject(object, defaultValue);
}
#else
OOINLINE NSInteger OOIntegerFromObject(id object, NSInteger defaultValue)
{
	return OOLongFromObject(object, defaultValue);
}

OOINLINE NSInteger OOUIntegerFromObject(id object, NSUInteger defaultValue)
{
	return OOUnsignedLongFromObject(object, defaultValue);
}
#endif


#undef OO_DEFINE_CLAMP
#undef OO_DEFINE_CLAMP_PAIR
#undef OO_ALIAS_CLAMP_LONG_LONG
#undef OO_ALIAS_CLAMP_PAIR_LONG_LONG
