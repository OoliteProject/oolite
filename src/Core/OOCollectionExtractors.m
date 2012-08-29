/*

OOCollectionExtractors.m

Copyright (C) 2007-2012 Jens Ayton and contributors

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

#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
#import "OOCocoa.h"
#import "OOStringParsing.h"
#endif

#import "OOCollectionExtractors.h"
#include <limits.h>
#import "OOMaths.h"


static NSSet *SetForObject(id object, NSSet *defaultValue);
static NSString *StringForObject(id object, NSString *defaultValue);


@implementation NSArray (OOExtractor)

- (char) oo_charAtIndex:(NSUInteger)index defaultValue:(char)value
{
	return OOCharFromObject([self oo_objectAtIndex:index], value);
}


- (short) oo_shortAtIndex:(NSUInteger)index defaultValue:(short)value
{
	return OOShortFromObject([self oo_objectAtIndex:index], value);
}


- (int) oo_intAtIndex:(NSUInteger)index defaultValue:(int)value
{
	return OOIntFromObject([self oo_objectAtIndex:index], value);
}


- (long) oo_longAtIndex:(NSUInteger)index defaultValue:(long)value
{
	return OOLongFromObject([self oo_objectAtIndex:index], value);
}


- (long long) oo_longLongAtIndex:(NSUInteger)index defaultValue:(long long)value
{
	return OOLongLongFromObject([self oo_objectAtIndex:index], value);
}


- (NSInteger) oo_integerAtIndex:(NSUInteger)index defaultValue:(NSInteger)value
{
	return OOIntegerFromObject([self oo_objectAtIndex:index], value);
}


- (unsigned char) oo_unsignedCharAtIndex:(NSUInteger)index defaultValue:(unsigned char)value
{
	return OOUnsignedCharFromObject([self oo_objectAtIndex:index], value);
}


- (unsigned short) oo_unsignedShortAtIndex:(NSUInteger)index defaultValue:(unsigned short)value
{
	return OOUnsignedShortFromObject([self oo_objectAtIndex:index], value);
}


- (unsigned int) oo_unsignedIntAtIndex:(NSUInteger)index defaultValue:(unsigned int)value
{
	return OOUnsignedIntFromObject([self oo_objectAtIndex:index], value);
}


- (unsigned long) oo_unsignedLongAtIndex:(NSUInteger)index defaultValue:(unsigned long)value
{
	return OOUnsignedLongFromObject([self oo_objectAtIndex:index], value);
}


- (unsigned long long) oo_unsignedLongLongAtIndex:(NSUInteger)index defaultValue:(unsigned long long)value
{
	return OOUnsignedLongLongFromObject([self oo_objectAtIndex:index], value);
}


- (NSUInteger) oo_unsignedIntegerAtIndex:(NSUInteger)index defaultValue:(NSUInteger)value
{
	return OOUIntegerFromObject([self oo_objectAtIndex:index], value);
}


- (BOOL) oo_boolAtIndex:(NSUInteger)index defaultValue:(BOOL)value
{
	return OOBooleanFromObject([self oo_objectAtIndex:index], value);
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanAtIndex:(NSUInteger)index defaultValue:(float)value
{
	return OOFuzzyBooleanFromObject([self oo_objectAtIndex:index], value);
}
#endif


- (float) oo_floatAtIndex:(NSUInteger)index defaultValue:(float)value
{
	return OOFloatFromObject([self oo_objectAtIndex:index], value);
}


- (double) oo_doubleAtIndex:(NSUInteger)index defaultValue:(double)value
{
	return OODoubleFromObject([self oo_objectAtIndex:index], value);
}


- (float) oo_nonNegativeFloatAtIndex:(NSUInteger)index defaultValue:(float)value
{
	return OONonNegativeFloatFromObject([self oo_objectAtIndex:index], value);
}


- (double) oo_nonNegativeDoubleAtIndex:(NSUInteger)index defaultValue:(double)value
{
	return OONonNegativeDoubleFromObject([self oo_objectAtIndex:index], value);
}


- (id) oo_objectAtIndex:(NSUInteger)index defaultValue:(id)value
{
	id					objVal = [self oo_objectAtIndex:index];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (id) oo_objectOfClass:(Class)class atIndex:(NSUInteger)index defaultValue:(id)value
{
	id					objVal = [self oo_objectAtIndex:index];
	NSString			*result;
	
	if ([objVal isKindOfClass:class])  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *) oo_stringAtIndex:(NSUInteger)index defaultValue:(NSString *)value
{
	return StringForObject([self oo_objectAtIndex:index], value);
}


- (NSArray *) oo_arrayAtIndex:(NSUInteger)index defaultValue:(NSArray *)value
{
	return [self oo_objectOfClass:[NSArray class] atIndex:index defaultValue:value];
}


- (NSSet *) oo_setAtIndex:(NSUInteger)index defaultValue:(NSSet *)value
{
	return SetForObject([self oo_objectAtIndex:index], value);
}


- (NSDictionary *) oo_dictionaryAtIndex:(NSUInteger)index defaultValue:(NSDictionary *)value
{
	return [self oo_objectOfClass:[NSDictionary class] atIndex:index defaultValue:value];
}


- (NSData *) oo_dataAtIndex:(NSUInteger)index defaultValue:(NSData *)value
{
	return [self oo_objectOfClass:[NSData class] atIndex:index defaultValue:value];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector) oo_vectorAtIndex:(NSUInteger)index defaultValue:(Vector)value
{
	return OOVectorFromObject([self oo_objectAtIndex:index], value);
}


- (Quaternion) oo_quaternionAtIndex:(NSUInteger)index defaultValue:(Quaternion)value
{
	return OOQuaternionFromObject([self oo_objectAtIndex:index], value);
}
#endif


- (char) oo_charAtIndex:(NSUInteger)index
{
	return [self oo_charAtIndex:index defaultValue:0];
}


- (short) oo_shortAtIndex:(NSUInteger)index
{
	return [self  oo_shortAtIndex:index defaultValue:0];
}


- (int) oo_intAtIndex:(NSUInteger)index
{
	return [self oo_intAtIndex:index defaultValue:0];
}


- (long) oo_longAtIndex:(NSUInteger)index
{
	return [self oo_longAtIndex:index defaultValue:0];
}


- (long long) oo_longLongAtIndex:(NSUInteger)index
{
	return [self oo_longLongAtIndex:index defaultValue:0];
}


- (NSInteger) oo_integerAtIndex:(NSUInteger)index
{
	return [self oo_integerAtIndex:index defaultValue:0];
}


- (unsigned char) oo_unsignedCharAtIndex:(NSUInteger)index
{
	return [self oo_unsignedCharAtIndex:index defaultValue:0];
}


- (unsigned short) oo_unsignedShortAtIndex:(NSUInteger)index
{
	return [self oo_unsignedShortAtIndex:index defaultValue:0];
}


- (unsigned int) oo_unsignedIntAtIndex:(NSUInteger)index
{
	return [self oo_unsignedIntAtIndex:index defaultValue:0];
}


- (unsigned long) oo_unsignedLongAtIndex:(NSUInteger)index
{
	return [self oo_unsignedLongAtIndex:index defaultValue:0];
}


- (unsigned long long) oo_unsignedLongLongAtIndex:(NSUInteger)index
{
	return [self oo_unsignedLongLongAtIndex:index defaultValue:0];
}


- (NSUInteger) oo_unsignedIntegerAtIndex:(NSUInteger)index
{
	return [self oo_unsignedIntegerAtIndex:index defaultValue:0];
}


- (BOOL) oo_boolAtIndex:(NSUInteger)index
{
	return [self oo_boolAtIndex:index defaultValue:NO];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanAtIndex:(NSUInteger)index
{
	return [self oo_fuzzyBooleanAtIndex:index defaultValue:0.0f];
}
#endif


- (float) oo_floatAtIndex:(NSUInteger)index
{
	return OOFloatFromObject([self oo_objectAtIndex:index], 0.0f);
}


- (double) oo_doubleAtIndex:(NSUInteger)index
{
	return OODoubleFromObject([self oo_objectAtIndex:index], 0.0);
}


- (float) oo_nonNegativeFloatAtIndex:(NSUInteger)index
{
	return OONonNegativeFloatFromObject([self oo_objectAtIndex:index], 0.0f);
}


- (double) oo_nonNegativeDoubleAtIndex:(NSUInteger)index
{
	return OONonNegativeDoubleFromObject([self oo_objectAtIndex:index], 0.0);
}


- (id) oo_objectAtIndex:(NSUInteger)index
{
	if (index < [self count])  return [self objectAtIndex:index];
	else  return nil;
}


- (id) oo_objectOfClass:(Class)class atIndex:(NSUInteger)index
{
	return [self oo_objectOfClass:class atIndex:index defaultValue:nil];
}


- (NSString *) oo_stringAtIndex:(NSUInteger)index
{
	return [self oo_stringAtIndex:index defaultValue:nil];
}


- (NSArray *) oo_arrayAtIndex:(NSUInteger)index
{
	return [self oo_arrayAtIndex:index defaultValue:nil];
}


- (NSSet *) oo_setAtIndex:(NSUInteger)index
{
	return [self oo_setAtIndex:index defaultValue:nil];
}


- (NSDictionary *) oo_dictionaryAtIndex:(NSUInteger)index
{
	return [self oo_dictionaryAtIndex:index defaultValue:nil];
}


- (NSData *) oo_dataAtIndex:(NSUInteger)index
{
	return [self oo_dataAtIndex:index defaultValue:nil];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector) oo_vectorAtIndex:(NSUInteger)index
{
	return [self oo_vectorAtIndex:index defaultValue:kZeroVector];
}


- (Quaternion) oo_quaternionAtIndex:(NSUInteger)index
{
	return [self oo_quaternionAtIndex:index defaultValue:kIdentityQuaternion];
}
#endif

@end


@implementation NSDictionary (OOExtractor)

- (char) oo_charForKey:(id)key defaultValue:(char)value
{
	return OOCharFromObject([self objectForKey:key], value);
}


- (short) oo_shortForKey:(id)key defaultValue:(short)value
{
	return OOShortFromObject([self objectForKey:key], value);
}


- (int) oo_intForKey:(id)key defaultValue:(int)value
{
	return OOIntFromObject([self objectForKey:key], value);
}


- (long) oo_longForKey:(id)key defaultValue:(long)value
{
	return OOLongFromObject([self objectForKey:key], value);
}


- (long long) oo_longLongForKey:(id)key defaultValue:(long long)value
{
	return OOLongLongFromObject([self objectForKey:key], value);
}


- (NSInteger) oo_integerForKey:(id)key defaultValue:(NSInteger)value
{
	return OOIntegerFromObject([self objectForKey:key], value);
}


- (unsigned char) oo_unsignedCharForKey:(id)key defaultValue:(unsigned char)value
{
	return OOUnsignedCharFromObject([self objectForKey:key], value);
}


- (unsigned short) oo_unsignedShortForKey:(id)key defaultValue:(unsigned short)value
{
	return OOUnsignedShortFromObject([self objectForKey:key], value);
}


- (unsigned int) oo_unsignedIntForKey:(id)key defaultValue:(unsigned int)value
{
	return OOUnsignedIntFromObject([self objectForKey:key], value);
}


- (unsigned long) oo_unsignedLongForKey:(id)key defaultValue:(unsigned long)value
{
	return OOUnsignedLongFromObject([self objectForKey:key], value);
}


- (unsigned long long) oo_unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value
{
	return OOUnsignedLongLongFromObject([self objectForKey:key], value);
}


- (NSUInteger) oo_unsignedIntegerForKey:(id)key defaultValue:(NSUInteger)value
{
	return OOUIntegerFromObject([self objectForKey:key], value);
}


- (BOOL) oo_boolForKey:(id)key defaultValue:(BOOL)value
{
	return OOBooleanFromObject([self objectForKey:key], value);
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key defaultValue:(float)value
{
	return OOFuzzyBooleanFromObject([self objectForKey:key], value);
}
#endif


- (float) oo_floatForKey:(id)key defaultValue:(float)value
{
	return OOFloatFromObject([self objectForKey:key], value);
}


- (double) oo_doubleForKey:(id)key defaultValue:(double)value
{
	return OODoubleFromObject([self objectForKey:key], value);
}


- (float) oo_nonNegativeFloatForKey:(id)key defaultValue:(float)value
{
	return OONonNegativeFloatFromObject([self objectForKey:key], value);
}


- (double) oo_nonNegativeDoubleForKey:(id)key defaultValue:(double)value
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], value);
}


- (id) oo_objectForKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (id) oo_objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if ([objVal isKindOfClass:class])  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *) oo_stringForKey:(id)key defaultValue:(NSString *)value
{
	return StringForObject([self objectForKey:key], value);
}


- (NSArray *) oo_arrayForKey:(id)key defaultValue:(NSArray *)value
{
	return [self oo_objectOfClass:[NSArray class] forKey:key defaultValue:value];
}


- (NSSet *) oo_setForKey:(id)key defaultValue:(NSSet *)value
{
	return SetForObject([self objectForKey:key], value);
}


- (NSDictionary *) oo_dictionaryForKey:(id)key defaultValue:(NSDictionary *)value
{
	return [self oo_objectOfClass:[NSDictionary class] forKey:key defaultValue:value];
}


- (NSData *) oo_dataForKey:(id)key defaultValue:(NSData *)value
{
	return [self oo_objectOfClass:[NSData class] forKey:key defaultValue:value];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector) oo_vectorForKey:(id)key defaultValue:(Vector)value
{
	return OOVectorFromObject([self objectForKey:key], value);
}


- (Quaternion) oo_quaternionForKey:(id)key defaultValue:(Quaternion)value
{
	return OOQuaternionFromObject([self objectForKey:key], value);
}
#endif


- (char) oo_charForKey:(id)key
{
	return [self oo_charForKey:key defaultValue:0];
}


- (short) oo_shortForKey:(id)key
{
	return [self oo_shortForKey:key defaultValue:0];
}


- (int) oo_intForKey:(id)key
{
	return [self oo_intForKey:key defaultValue:0];
}


- (long) oo_longForKey:(id)key
{
	return [self oo_longForKey:key defaultValue:0];
}


- (long long) oo_longLongForKey:(id)key
{
	return [self oo_longLongForKey:key defaultValue:0];
}


- (NSInteger) oo_integerForKey:(id)key
{
	return [self oo_integerForKey:key defaultValue:0];
}


- (unsigned char) oo_unsignedCharForKey:(id)key
{
	return [self  oo_unsignedCharForKey:key defaultValue:0];
}


- (unsigned short) oo_unsignedShortForKey:(id)key
{
	return [self oo_unsignedShortForKey:key defaultValue:0];
}


- (unsigned int) oo_unsignedIntForKey:(id)key
{
	return [self oo_unsignedIntForKey:key defaultValue:0];
}


- (unsigned long) oo_unsignedLongForKey:(id)key
{
	return [self  oo_unsignedLongForKey:key defaultValue:0];
}


- (NSUInteger) oo_unsignedIntegerForKey:(id)key
{
	return [self oo_unsignedIntegerForKey:key defaultValue:0];
}


- (unsigned long long) oo_unsignedLongLongForKey:(id)key
{
	return [self oo_unsignedLongLongForKey:key defaultValue:0];
}


- (BOOL) oo_boolForKey:(id)key
{
	return [self oo_boolForKey:key defaultValue:NO];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key
{
	return [self oo_fuzzyBooleanForKey:key defaultValue:0.0f];
}
#endif


- (float) oo_floatForKey:(id)key
{
	return OOFloatFromObject([self objectForKey:key], 0.0f);
}


- (double) oo_doubleForKey:(id)key
{
	return OODoubleFromObject([self objectForKey:key], 0.0);
}


- (float) oo_nonNegativeFloatForKey:(id)key
{
	return OONonNegativeFloatFromObject([self objectForKey:key], 0.0f);
}


- (double) oo_nonNegativeDoubleForKey:(id)key
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], 0.0);
}


- (id) oo_objectOfClass:(Class)class forKey:(id)key
{
	return [self oo_objectOfClass:class forKey:key defaultValue:nil];
}


- (NSString *) oo_stringForKey:(id)key
{
	return [self oo_stringForKey:key defaultValue:nil];
}


- (NSArray *) oo_arrayForKey:(id)key
{
	return [self oo_arrayForKey:key defaultValue:nil];
}


- (NSSet *) oo_setForKey:(id)key
{
	return [self oo_setForKey:key defaultValue:nil];
}


- (NSDictionary *) oo_dictionaryForKey:(id)key
{
	return [self oo_dictionaryForKey:key defaultValue:nil];
}


- (NSData *) oo_dataForKey:(id)key
{
	return [self oo_dataForKey:key defaultValue:nil];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (Vector) oo_vectorForKey:(id)key
{
	return [self oo_vectorForKey:key defaultValue:kZeroVector];
}


- (Quaternion) oo_quaternionForKey:(id)key
{
	return [self oo_quaternionForKey:key defaultValue:kIdentityQuaternion];
}
#endif

@end


@implementation NSUserDefaults (OOExtractor)

- (char) oo_charForKey:(id)key defaultValue:(char)value
{
	return OOCharFromObject([self objectForKey:key], value);
}


- (short) oo_shortForKey:(id)key defaultValue:(short)value
{
	return OOShortFromObject([self objectForKey:key], value);
}


- (int) oo_intForKey:(id)key defaultValue:(int)value
{
	return OOIntFromObject([self objectForKey:key], value);
}


- (long) oo_longForKey:(id)key defaultValue:(long)value
{
	return OOLongFromObject([self objectForKey:key], value);
}


- (long long) oo_longLongForKey:(id)key defaultValue:(long long)value
{
	return OOLongLongFromObject([self objectForKey:key], value);
}


- (NSInteger) oo_integerForKey:(id)key defaultValue:(NSInteger)value
{
	return OOIntegerFromObject([self objectForKey:key], value);
}


- (unsigned char) oo_unsignedCharForKey:(id)key defaultValue:(unsigned char)value
{
	return OOUnsignedCharFromObject([self objectForKey:key], value);
}


- (unsigned short) oo_unsignedShortForKey:(id)key defaultValue:(unsigned short)value
{
	return OOUnsignedShortFromObject([self objectForKey:key], value);
}


- (unsigned int) oo_unsignedIntForKey:(id)key defaultValue:(unsigned int)value
{
	return OOUnsignedIntFromObject([self objectForKey:key], value);
}


- (unsigned long) oo_unsignedLongForKey:(id)key defaultValue:(unsigned long)value
{
	return OOUnsignedLongFromObject([self objectForKey:key], value);
}


- (unsigned long long) oo_unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value
{
	return OOUnsignedLongLongFromObject([self objectForKey:key], value);
}


- (NSUInteger) oo_unsignedIntegerForKey:(id)key defaultValue:(NSUInteger)value
{
	return OOUIntegerFromObject([self objectForKey:key], value);
}


- (BOOL) oo_boolForKey:(id)key defaultValue:(BOOL)value
{
	return OOBooleanFromObject([self objectForKey:key], value);
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key defaultValue:(float)value
{
	return OOFuzzyBooleanFromObject([self objectForKey:key], value);
}
#endif


- (float) oo_floatForKey:(id)key defaultValue:(float)value
{
	return OOFloatFromObject([self objectForKey:key], value);
}


- (double) oo_doubleForKey:(id)key defaultValue:(double)value
{
	return OODoubleFromObject([self objectForKey:key], value);
}


- (float) oo_nonNegativeFloatForKey:(id)key defaultValue:(float)value
{
	return OONonNegativeFloatFromObject([self objectForKey:key], value);
}


- (double) oo_nonNegativeDoubleForKey:(id)key defaultValue:(double)value
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], value);
}


- (id) oo_objectForKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (id) oo_objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if ([objVal isKindOfClass:class])  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *) oo_stringForKey:(id)key defaultValue:(NSString *)value
{
	return StringForObject([self objectForKey:key], value);
}


- (NSArray *) oo_arrayForKey:(id)key defaultValue:(NSArray *)value
{
	return [self oo_objectOfClass:[NSArray class] forKey:key defaultValue:value];
}


- (NSSet *) oo_setForKey:(id)key defaultValue:(NSSet *)value
{
	return SetForObject([self objectForKey:key], value);
}


- (NSDictionary *) oo_dictionaryForKey:(id)key defaultValue:(NSDictionary *)value
{
	return [self oo_objectOfClass:[NSDictionary class] forKey:key defaultValue:value];
}


- (NSData *) oo_dataForKey:(id)key defaultValue:(NSData *)value
{
	return [self oo_objectOfClass:[NSData class] forKey:key defaultValue:value];
}


- (char) oo_charForKey:(id)key
{
	return [self oo_charForKey:key defaultValue:0];
}


- (short) oo_shortForKey:(id)key
{
	return [self oo_shortForKey:key defaultValue:0];
}


- (int) oo_intForKey:(id)key
{
	return [self oo_intForKey:key defaultValue:0];
}


- (long) oo_longForKey:(id)key
{
	return [self oo_longForKey:key defaultValue:0];
}


- (long long) oo_longLongForKey:(id)key
{
	return [self oo_longLongForKey:key defaultValue:0];
}


- (unsigned char) oo_unsignedCharForKey:(id)key
{
	return [self  oo_unsignedCharForKey:key defaultValue:0];
}


- (unsigned short) oo_unsignedShortForKey:(id)key
{
	return [self oo_unsignedShortForKey:key defaultValue:0];
}


- (unsigned int) oo_unsignedIntForKey:(id)key
{
	return [self oo_unsignedIntForKey:key defaultValue:0];
}


- (unsigned long) oo_unsignedLongForKey:(id)key
{
	return [self  oo_unsignedLongForKey:key defaultValue:0];
}


- (unsigned long long) oo_unsignedLongLongForKey:(id)key
{
	return [self oo_unsignedLongLongForKey:key defaultValue:0];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (BOOL) oo_fuzzyBooleanForKey:(id)key
{
	return [self oo_fuzzyBooleanForKey:key defaultValue:0.0f];
}
#endif


- (double) oo_doubleForKey:(NSString *)key
{
	return OODoubleFromObject([self objectForKey:key], 0.0);
}


- (float) oo_nonNegativeFloatForKey:(id)key
{
	return OONonNegativeFloatFromObject([self objectForKey:key], 0.0f);
}


- (double) oo_nonNegativeDoubleForKey:(id)key
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], 0.0);
}


- (id) oo_objectOfClass:(Class)class forKey:(id)key
{
	return [self oo_objectOfClass:class forKey:key defaultValue:nil];
}


- (NSSet *) oo_setForKey:(id)key
{
	return [self oo_setForKey:key defaultValue:nil];
}

@end


@implementation NSMutableArray (OOInserter)

- (void) oo_addInteger:(long)value
{
	[self addObject:[NSNumber numberWithLong:value]];
}


- (void) oo_addUnsignedInteger:(unsigned long)value
{
	[self addObject:[NSNumber numberWithUnsignedLong:value]];
}


- (void) oo_addFloat:(double)value
{
	[self addObject:[NSNumber numberWithDouble:value]];
}


- (void) oo_addBool:(BOOL)value
{
	[self addObject:[NSNumber numberWithBool:value]];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void) oo_addVector:(Vector)value
{
	[self addObject:OOPropertyListFromVector(value)];
}


- (void) oo_addQuaternion:(Quaternion)value
{
	[self addObject:OOPropertyListFromQuaternion(value)];
}
#endif


- (void) oo_insertInteger:(long)value atIndex:(NSUInteger)index
{
	[self insertObject:[NSNumber numberWithLong:value] atIndex:index];
}


- (void) oo_insertUnsignedInteger:(unsigned long)value atIndex:(NSUInteger)index
{
	[self insertObject:[NSNumber numberWithUnsignedLong:value] atIndex:index];
}


- (void) oo_insertFloat:(double)value atIndex:(NSUInteger)index
{
	[self insertObject:[NSNumber numberWithDouble:value] atIndex:index];
}


- (void) oo_insertBool:(BOOL)value atIndex:(NSUInteger)index
{
	[self insertObject:[NSNumber numberWithBool:value] atIndex:index];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void) oo_insertVector:(Vector)value atIndex:(NSUInteger)index
{
	[self insertObject:OOPropertyListFromVector(value) atIndex:index];
}


- (void) oo_insertQuaternion:(Quaternion)value atIndex:(NSUInteger)index
{
	[self insertObject:OOPropertyListFromQuaternion(value) atIndex:index];
}
#endif

@end


@implementation NSMutableDictionary (OOInserter)

- (void) oo_setInteger:(long)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithLong:value] forKey:key];
}


- (void) oo_setUnsignedInteger:(unsigned long)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithUnsignedLong:value] forKey:key];
}


- (void) oo_setLongLong:(long long)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithLongLong:value] forKey:key];
}


- (void) oo_setUnsignedLongLong:(unsigned long long)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithUnsignedLongLong:value] forKey:key];
}


- (void) oo_setFloat:(double)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithDouble:value] forKey:key];
}


- (void) oo_setBool:(BOOL)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithBool:value] forKey:key];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void) oo_setVector:(Vector)value forKey:(id)key
{
	[self setObject:OOPropertyListFromVector(value) forKey:key];
}


- (void) oo_setQuaternion:(Quaternion)value forKey:(id)key
{
	[self setObject:OOPropertyListFromQuaternion(value) forKey:key];
}
#endif

@end


@implementation NSMutableSet (OOInserter)

- (void) oo_addInteger:(long)value
{
	[self addObject:[NSNumber numberWithLong:value]];
}


- (void) oo_addUnsignedInteger:(unsigned long)value
{
	[self addObject:[NSNumber numberWithUnsignedLong:value]];
}


- (void) oo_addFloat:(double)value
{
	[self addObject:[NSNumber numberWithDouble:value]];
}


- (void) oo_addBool:(BOOL)value
{
	[self addObject:[NSNumber numberWithBool:value]];
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
- (void) oo_addVector:(Vector)value
{
	[self addObject:OOPropertyListFromVector(value)];
}


- (void) oo_addQuaternion:(Quaternion)value
{
	[self addObject:OOPropertyListFromQuaternion(value)];
}
#endif

@end


long long OOLongLongFromObject(id object, long long defaultValue)
{
	long long llValue;
	
	if ([object respondsToSelector:@selector(longLongValue)])  llValue = [object longLongValue];
	else if ([object respondsToSelector:@selector(longValue)])  llValue = [object longValue];
	else if ([object respondsToSelector:@selector(intValue)])  llValue = [object intValue];
	else llValue = defaultValue;
	
	return llValue;
}


unsigned long long OOUnsignedLongLongFromObject(id object, unsigned long long defaultValue)
{
	unsigned long long ullValue;
	
	if ([object respondsToSelector:@selector(unsignedLongLongValue)])  ullValue = [object unsignedLongLongValue];
	else if ([object respondsToSelector:@selector(unsignedLongValue)])  ullValue = [object unsignedLongValue];
	else if ([object respondsToSelector:@selector(unsignedIntValue)])  ullValue = [object unsignedIntValue];
	else if ([object respondsToSelector:@selector(intValue)])  ullValue = [object intValue];
	else ullValue = defaultValue;
	
	return ullValue;
}


static inline BOOL IsSpaceOrTab(int value)
{
	return value == ' ' || value == '\t';
}


static BOOL IsZeroString(NSString *string)
{
	/*	I don't particularly like regexps, but there are occasions...
	 To match NSString's behaviour for intValue etc. with non-zero numbers,
	 we need to skip any leading spaces or tabs (but not line breaks), get
	 an optional minus sign, then at least one 0. Any trailing junk is
	 ignored. It is assumed that this function is called for strings whose
	 numerical value has already been determined to be 0.
	 */
	
	unsigned long i = 0, count = [string length];
#define PEEK() ((i >= count) ? -1 : [string characterAtIndex:i])
	
	while (IsSpaceOrTab(PEEK()))  ++i;	// Skip spaces and tabs
	if (PEEK() == ' ')  ++i;			// Skip optional hyphen-minus
	return PEEK() == '0';				// If this is a 0, it's a numerical string.
	
#undef PEEK
}


static BOOL BooleanFromString(NSString *string, BOOL defaultValue)
{
	if (NSOrderedSame == [string caseInsensitiveCompare:@"yes"] ||
		NSOrderedSame == [string caseInsensitiveCompare:@"true"] ||
		NSOrderedSame == [string caseInsensitiveCompare:@"on"] ||
		[string doubleValue] != 0.0)	// Floating point is used so values like @"0.1" are treated as nonzero.
	{
		return YES;
	}
	else if (NSOrderedSame == [string caseInsensitiveCompare:@"no"] ||
			 NSOrderedSame == [string caseInsensitiveCompare:@"false"] ||
			 NSOrderedSame == [string caseInsensitiveCompare:@"off"] ||
			 IsZeroString(string))
	{
		return NO;
	}
	return defaultValue;
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
static float FuzzyBooleanProbabilityFromString(NSString *string, float defaultValue)
{
	if (NSOrderedSame == [string caseInsensitiveCompare:@"yes"] ||
		NSOrderedSame == [string caseInsensitiveCompare:@"true"] ||
		NSOrderedSame == [string caseInsensitiveCompare:@"on"] ||
		[string doubleValue] != 0.0)	// Floating point is used so values like @"0.1" are treated as nonzero.
	{
		return 1.0f;
	}
	else if (NSOrderedSame == [string caseInsensitiveCompare:@"no"] ||
			 NSOrderedSame == [string caseInsensitiveCompare:@"false"] ||
			 NSOrderedSame == [string caseInsensitiveCompare:@"off"] ||
			 IsZeroString(string))
	{
		return 0.0f;
	}
	return defaultValue;
}
#endif


BOOL OOBooleanFromObject(id object, BOOL defaultValue)
{
	BOOL result;
	
	if ([object isKindOfClass:[NSString class]])
	{
		result = BooleanFromString(object, defaultValue);
	}
	else
	{
		if ([object respondsToSelector:@selector(boolValue)])  result = [object boolValue];
		else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue] != 0;
		else result = defaultValue;
	}
	
	return result;
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
BOOL OOFuzzyBooleanFromObject(id object, float defaultValue)
{
	float probability;
	
	if ([object isKindOfClass:[NSString class]])
	{
		probability = [object floatValue];
		
		// If our string represents zero, it might be erroneous input or simply yes/no,
		// true/false or on/off valid boolean strings. Act on it.
		if (probability == 0.0f && !IsZeroString(object))
		{
			probability = FuzzyBooleanProbabilityFromString(object, defaultValue);
		}
	}
	else
	{
		probability = OOFloatFromObject(object, defaultValue);
	}
	
	/*	This will always be NO for negative values and YES for values
		greater than 1, as expected. randf() is always less than 1, so
		< is the correct operator here.
	*/
	return randf() < probability;
}
#endif


float OOFloatFromObject(id object, float defaultValue)
{
	float result;
	
	if ([object respondsToSelector:@selector(floatValue)])
	{
		result = [object floatValue];
		if (result == 0.0f && [object isKindOfClass:[NSString class]] && !IsZeroString(object))  result = defaultValue;
	}
	else if ([object respondsToSelector:@selector(doubleValue)])  result = [object doubleValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else result = defaultValue;
	
	return result;
}


double OODoubleFromObject(id object, double defaultValue)
{
	double result;
	
	if ([object respondsToSelector:@selector(doubleValue)])
	{
		result = [object doubleValue];
		if (result == 0.0 && [object isKindOfClass:[NSString class]] && !IsZeroString(object))  result = defaultValue;
	}
	else if ([object respondsToSelector:@selector(floatValue)])  result = [object floatValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else result = defaultValue;
	
	return result;
}


float OONonNegativeFloatFromObject(id object, float defaultValue)
{
	float result;
	
	if ([object respondsToSelector:@selector(floatValue)])  result = [object floatValue];
	else if ([object respondsToSelector:@selector(doubleValue)])  result = [object doubleValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else return defaultValue;	// Don't clamp default
	
	return fmax(result, 0.0f);
}


double OONonNegativeDoubleFromObject(id object, double defaultValue)
{
	double result;
	
	if ([object respondsToSelector:@selector(doubleValue)])  result = [object doubleValue];
	else if ([object respondsToSelector:@selector(floatValue)])  result = [object floatValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else return defaultValue;	// Don't clamp default
	
	return fmax(result, 0.0);
}


#ifndef OOCOLLECTIONEXTRACTORS_SIMPLE
Vector OOVectorFromObject(id object, Vector defaultValue)
{
	Vector				result = defaultValue;
	NSDictionary		*dict = nil;
	
	if ([object isKindOfClass:[NSString class]])
	{
		// This will only write result if a valid vector is found, and will write an error message otherwise.
		ScanVectorFromString(object, &result);
	}
	else if ([object isKindOfClass:[NSArray class]] && [object count] == 3)
	{
		result.x = [object oo_floatAtIndex:0];
		result.y = [object oo_floatAtIndex:1];
		result.z = [object oo_floatAtIndex:2];
	}
	else if ([object isKindOfClass:[NSDictionary class]])
	{
		dict = object;
		// Require at least one of the keys x, y, or z
		if ([dict objectForKey:@"x"] != nil ||
			[dict objectForKey:@"y"] != nil ||
			[dict objectForKey:@"z"] != nil)
		{
			// Note: uses 0 for unknown components rather than components of defaultValue.
			result.x = [dict oo_floatForKey:@"x" defaultValue:0.0f];
			result.y = [dict oo_floatForKey:@"y" defaultValue:0.0f];
			result.z = [dict oo_floatForKey:@"z" defaultValue:0.0f];
		}
	}
	
	return result;
}


Quaternion OOQuaternionFromObject(id object, Quaternion defaultValue)
{
	Quaternion			result = defaultValue;
	NSDictionary		*dict = nil;
	
	if ([object isKindOfClass:[NSString class]])
	{
		// This will only write result if a valid quaternion is found, and will write an error message otherwise.
		ScanQuaternionFromString(object, &result);
	}
	else if ([object isKindOfClass:[NSArray class]] && [object count] == 4)
	{
		result.w = [object oo_floatAtIndex:0];
		result.x = [object oo_floatAtIndex:1];
		result.y = [object oo_floatAtIndex:2];
		result.z = [object oo_floatAtIndex:3];
	}
	else if ([object isKindOfClass:[NSDictionary class]])
	{
		dict = object;
		// Require at least one of the keys w, x, y, or z
		if ([dict objectForKey:@"w"] != nil ||
			[dict objectForKey:@"x"] != nil ||
			[dict objectForKey:@"y"] != nil ||
			[dict objectForKey:@"z"] != nil)
		{
			// Note: uses 0 for unknown components rather than components of defaultValue.
			result.w = [dict oo_floatForKey:@"w" defaultValue:0.0f];
			result.x = [dict oo_floatForKey:@"x" defaultValue:0.0f];
			result.y = [dict oo_floatForKey:@"y" defaultValue:0.0f];
			result.z = [dict oo_floatForKey:@"z" defaultValue:0.0f];
		}
	}
	
	return result;
}


NSDictionary *OOPropertyListFromVector(Vector value)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithFloat:value.x], @"x",
			[NSNumber numberWithFloat:value.y], @"y",
			[NSNumber numberWithFloat:value.z], @"z",
			nil];
}


NSDictionary *OOPropertyListFromQuaternion(Quaternion value)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithFloat:value.w], @"w",
			[NSNumber numberWithFloat:value.x], @"x",
			[NSNumber numberWithFloat:value.y], @"y",
			[NSNumber numberWithFloat:value.z], @"z",
			nil];
}
#endif


static NSSet *SetForObject(id object, NSSet *defaultValue)
{
	if ([object isKindOfClass:[NSArray class]])  return [NSSet setWithArray:object];
	else if ([object isKindOfClass:[NSSet class]])  return [[object copy] autorelease];
	
	return defaultValue;
}


static NSString *StringForObject(id object, NSString *defaultValue)
{
	if ([object isKindOfClass:[NSString class]])  return object;
	else if ([object respondsToSelector:@selector(stringValue)])  return [object stringValue];
	
	return defaultValue;
}
