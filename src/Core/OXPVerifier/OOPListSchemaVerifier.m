/*
 
 OOPListSchemaVerifier.m
 
 
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

#import "OOPListSchemaVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOLogging.h"
#import "OOCollectionExtractors.h"
#import "OOFunctionAttributes.h"
#import "OOMaths.h"
#import <limits.h>


NSString * const kOOPListSchemaVerifierErrorDomain = @"org.aegidian.oolite.OOPListSchemaVerifier.ErrorDomain";

NSString * const kPListKeyPathErrorKey = @"org.aegidian.oolite.OOPListSchemaVerifier plist key path";
NSString * const kSchemaKeyPathErrorKey = @"org.aegidian.oolite.OOPListSchemaVerifier schema key path";

NSString * const kMissingRequiredKeysErrorKey = @"org.aegidian.oolite.OOPListSchemaVerifier missing required keys";
NSString * const kUnknownTypeErrorKey = @"org.aegidian.oolite.OOPListSchemaVerifier unknown type";


typedef enum
{
	kTypeUnknown,
	kTypeString,
	kTypeArray,
	kTypeDictionary,
	kTypeInteger,
	kTypePositiveInteger,
	kTypeFloat,
	kTypePositiveFloat,
	kTypeOneOf,
	kTypeEnumeration,
	kTypeBoolean,
	kTypeFuzzyBoolean,
	kTypeVector,
	kTypeQuaternion,
	kTypeDelegatedType
} SchemaType;


typedef struct BackLinkChain BackLinkChain;
struct BackLinkChain
{
	BackLinkChain			*link;
	id						element;
};

OOINLINE BackLinkChain BackLink(BackLinkChain *link, id element)
{
	BackLinkChain result = { link, element };
	return result;
}

OOINLINE BackLinkChain BackLinkIndex(BackLinkChain *link, unsigned index)
{
	BackLinkChain result = { link, [NSNumber numberWithInt:index] };
	return result;
}

OOINLINE BackLinkChain BackLinkRoot(void)
{
	BackLinkChain result = { NULL, NULL };
	return result;
}


static SchemaType StringToSchemaType(NSString *string);
static SchemaType ResolveSchemaType(NSDictionary **typeSpec, BackLinkChain keyPath);
static NSString *ApplyStringFilter(NSString *string, id filterSpec);
static BOOL ApplyStringTest(NSString *string, id test, SEL testSelector, NSString *testDescription);

static NSError *Error(OOPListSchemaVerifierErrorCode errorCode, NSString *format, ...);
static NSError *ErrorWithProperty(OOPListSchemaVerifierErrorCode errorCode, NSString *propKey, id propValue, NSString *format, ...);
static NSError *ErrorWithDictionary(OOPListSchemaVerifierErrorCode errorCode, NSDictionary *dict, NSString *format, ...);
static NSError *ErrorWithDictionaryAndArguments(OOPListSchemaVerifierErrorCode errorCode, NSDictionary *dict, NSString *format, va_list arguments);


@interface OOPListSchemaVerifier (OOPrivate)

// Call delegate methods.
- (BOOL)delegateVerifierWithPropertyList:(id)rootPList named:(NSString *)name testProperty:(id)subPList atPath:(NSArray *)keyPath againstType:(NSString *)typeKey;
- (BOOL)delegateVerifierWithPropertyList:(id)rootPList named:(NSString *)name failedForProperty:(id)subPList atPath:(NSArray *)keyPath expectedType:(NSDictionary *)localSchema;

+ (NSDictionary *)normalizedSchema:(id)schema;

+ (NSDictionary *)normalizedSubSchema:(NSDictionary *)subSchema
							   atPath:(BackLinkChain)keyPath
					  withDefinitions:(NSDictionary *)definitions
							  changed:(BOOL *)outChanged;

+ (NSDictionary *)normalizedSchemaType:(id)element
								atPath:(BackLinkChain)keyPath
					   withDefinitions:(NSDictionary *)definitions
							   changed:(BOOL *)outChanged;

+ (NSArray *)normalizedArrayOfSchemaTypes:(NSArray *)types
								   atPath:(BackLinkChain)keyPath
						  withDefinitions:(NSDictionary *)definitions
								  changed:(BOOL *)outChanged;

+ (NSArray *)keyPathToArray:(BackLinkChain)keyPath;
+ (NSString *)keyPathToString:(BackLinkChain)keyPath;

- (BOOL)validatePList:(id)rootPList
				named:(NSString *)name
		  subProperty:(id)subProperty
	againstSchemaType:(NSDictionary *)subSchema
			   atPath:(BackLinkChain)keyPath
			tentative:(BOOL)tentative
				 stop:(BOOL *)outStop;

@end


#define VALIDATE_PROTO(T) static BOOL Validate_##T(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
VALIDATE_PROTO(String);
VALIDATE_PROTO(Array);
VALIDATE_PROTO(Dictionary);
VALIDATE_PROTO(Integer);
VALIDATE_PROTO(PositiveInteger);
VALIDATE_PROTO(Float);
VALIDATE_PROTO(PositiveFloat);
VALIDATE_PROTO(OneOf);
VALIDATE_PROTO(Enumeration);
VALIDATE_PROTO(Boolean);
VALIDATE_PROTO(FuzzyBoolean);
VALIDATE_PROTO(Vector);
VALIDATE_PROTO(Quaternion);
VALIDATE_PROTO(DelegatedType);


@implementation OOPListSchemaVerifier

+ (id)verifierWithSchema:(id)schema
{
	return [[[self alloc] initWithSchema:schema] autorelease];
}


- (id)initWithSchema:(id)schema
{
	self = [super init];
	if (self != nil)
	{
		_schema = [[OOPListSchemaVerifier normalizedSchema:schema] retain];
		if (_schema == nil)
		{
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (void)dealloc
{
	[_schema release];
	
	[super dealloc];
}


- (void)setDelegate:(id)delegate
{
	if (_delegate != delegate)
	{
		_delegate = delegate;
		_badDelegateWarning = NO;
	}
}


- (id)delegate
{
	return _delegate;
}


- (BOOL)validatePropertyList:(id)plist named:(NSString *)name
{
	NSAutoreleasePool			*pool = nil;
	BOOL						OK;
	BOOL						stop = NO;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	OK = [self validatePList:plist
					   named:name
				 subProperty:plist
		   againstSchemaType:_schema
					  atPath:BackLinkRoot()
				   tentative:NO
						stop:&stop];
	
	[pool release];
	
	return OK;
}


+ (NSString *)descriptionForKeyPath:(NSArray *)keyPath
{
	NSMutableString				*result = nil;
	NSEnumerator				*componentEnum = nil;
	id							component = nil;
	BOOL						first = YES;
	
	result = [NSMutableString string];
	
	for (componentEnum = [keyPath objectEnumerator]; (component = [componentEnum nextObject]); )
	{
		if ([component isKindOfClass:[NSNumber class]])
		{
			[result appendFormat:@"[%@]", component];
		}
		else if ([component isKindOfClass:[NSString class]])
		{
			if (!first)  [result appendString:@"."];
			[result appendString:component];
		}
		else  return nil;
		first = NO;
	}
	
	if (first)
	{
		// Empty path
		result = @"root";
	}
	
	return result;
}

@end


@implementation OOPListSchemaVerifier (OOPrivate)

- (BOOL)delegateVerifierWithPropertyList:(id)rootPList named:(NSString *)name testProperty:(id)subPList atPath:(NSArray *)keyPath againstType:(NSString *)typeKey
{
	BOOL					result;
	
	if ([_delegate respondsToSelector:@selector(verifier:withPropertyList:named:testProperty:atPath:againstType:)])
	{
		NS_DURING
			result = [_delegate verifier:self
						withPropertyList:rootPList
								   named:name
							testProperty:subPList
								  atPath:keyPath
							 againstType:typeKey];
		NS_HANDLER
			OOLog(@"plistVerifier.delegateException", @"Property list schema verifier: delegate threw exception (%@) in -verifier:withPropertyList:named:testProperty:atPath:againstType: for type \"%@\" at %@ in %@ -- treating as failure.", [localException name], typeKey, [OOPListSchemaVerifier descriptionForKeyPath:keyPath], name);
			result = NO;
		NS_ENDHANDLER
	}
	else
	{
		if (!_badDelegateWarning)
		{
			OOLog(@"plistVerifier.badDelegate", @"Property list schema verifier: delegate does not handle delegated types.");
			_badDelegateWarning = YES;
		}
		result = NO;
	}
	return result;
}


- (BOOL)delegateVerifierWithPropertyList:(id)rootPList named:(NSString *)name failedForProperty:(id)subPList atPath:(NSArray *)keyPath expectedType:(NSDictionary *)localSchema
{
	BOOL					result;
	
	if ([_delegate respondsToSelector:@selector(verifier:withPropertyList:named:failedForProperty:atPath:expectedType:)])
	{
		NS_DURING
			result = [_delegate verifier:self
						withPropertyList:rootPList
								   named:name
					   failedForProperty:subPList
								  atPath:keyPath
							expectedType:localSchema];
		NS_HANDLER
			OOLog(@"plistVerifier.delegateException", @"Property list schema verifier: delegate threw exception (%@) in -verifier:withPropertyList:named:failedForProperty:atPath:expectedType: at %@ in %@ -- stopping.", [localException name], [OOPListSchemaVerifier descriptionForKeyPath:keyPath], name);
			result = NO;
		NS_ENDHANDLER
	}
	else
	{
		OOLog(@"plistVerifier.failed", @"Verification of property list \"%@\" failed: wrong type at %@.", name, [[self class] descriptionForKeyPath:keyPath]);
		result = NO;
	}
	return result;
}


+ (NSDictionary *)normalizedSchema:(id)schema
{
	enum { kRecursionLimit = 32 };
	NSDictionary			*definitions = nil;
	NSAutoreleasePool		*pool = nil;
	unsigned				i;
	BOOL					OK = NO, changed;
	
	if (schema == nil)  return nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	if ([schema isKindOfClass:[NSString class]])  schema = [NSDictionary dictionaryWithObject:schema forKey:@"type"];
	
	definitions = [schema dictionaryForKey:@"$definitions"];
	
	// Repeatedly normalize until all definition references are resolved.
	for (i = 0; i != kRecursionLimit; ++i)
	{
		changed = NO;
		schema = [self normalizedSchemaType:schema atPath:BackLinkRoot() withDefinitions:definitions changed:&changed];
		if (schema != nil && !changed)
		{
			OK = YES;
			break;
		}
		if (schema == nil)  break;
	}
	
	if (!OK)
	{
		if (schema != nil)
		{
			schema = nil;
			OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- hit definition resolution recursion limit %u.", i);
		}
	}
	else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"plist-schema-verifier-dump-schema"])
	{
		NSString *errorDesc = nil;
		NSData *data = [NSPropertyListSerialization dataFromPropertyList:schema format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorDesc];
		if (data != nil)  [data writeToFile:@"schema.plist" atomically:YES];
		else OOLog(@"plistVerifier.temp", @"Failed to convert schema to plist: %@", errorDesc);
	}
	
	[schema retain];
	[pool release];
	return [schema autorelease];
}



+ (NSDictionary *)normalizedSubSchema:(NSDictionary *)subSchema
							   atPath:(BackLinkChain)keyPath
					  withDefinitions:(NSDictionary *)definitions
							  changed:(BOOL *)outChanged
{
	NSMutableDictionary		*result = nil;
	BOOL					OK = YES, thisChanged, changed = NO;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						schemaType = nil;
	id						newType = nil;
	
	if (![subSchema isKindOfClass:[NSDictionary class]])
	{
		OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- expected dictionary, got %@ at path: %@.", [subSchema class], [self keyPathToString:keyPath]);
		return nil;
	}
	
	// Iterate over each key-type pair, normalizing types.
	result = [[NSMutableDictionary alloc] initWithCapacity:[subSchema count]];
	for (keyEnum = [subSchema keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		schemaType = [subSchema objectForKey:key];
		thisChanged = NO;
		newType = [self normalizedSchemaType:schemaType
									  atPath:BackLink(&keyPath, key)
							 withDefinitions:definitions
									 changed:&thisChanged];
		
		if (newType == nil)
		{
			OK = NO;
			break;
		}
		if (thisChanged)
		{
			changed = YES;
			[result setObject:newType forKey:key];
		}
		else
		{
			[result setObject:schemaType forKey:key];
		}
	}
	
	
	if (OK)
	{
		if (changed)
		{
			if (outChanged != NULL)  *outChanged = YES;
			return [result autorelease];
		}
		else
		{
			[result release];
			return subSchema;
		}
	}
	else
	{
		[result release];
		return nil;
	}
}


+ (NSDictionary *)normalizedSchemaType:(id)schemaType
								atPath:(BackLinkChain)keyPath
					   withDefinitions:(NSDictionary *)definitions
							   changed:(BOOL *)outChanged
{
	BOOL					OK = YES, changed = NO, subChanged = NO;
	id						type = nil;
	id						newType = nil;
	NSMutableDictionary		*dict = nil;
	id						sub = nil;
	static NSSet			*simpleTypes = nil;
	
	if ([schemaType isKindOfClass:[NSString class]])
	{
		// Short-circuit dictionary references here to avoid {type = {type = "foo"}}
		if ([schemaType hasPrefix:@"$"])
		{
			newType = [definitions objectForKey:schemaType];
			if (newType == nil)
			{
				OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- undefined reference %@ at path %@.", schemaType, [self keyPathToString:keyPath]);
			}
			if (outChanged != NULL)  *outChanged = YES;
			return newType;
		}
		dict = schemaType = [[NSMutableDictionary alloc] initWithObjectsAndKeys:schemaType, @"type", nil];
		changed = YES;
	}
	else if ([schemaType isKindOfClass:[NSDictionary class]])
	{
		dict = [schemaType mutableCopy];
		[dict removeObjectForKey:@"$definitions"];
	}
	else
	{
		OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- expected string or dictionary, got %@ at path: %@.", [schemaType class], [self keyPathToString:keyPath]);
		OK = NO;
	}
	
	// Normalize type
	if (OK)
	{
		type = [schemaType objectForKey:@"type"];
		if (type == nil)
		{
			OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- no type specified at path: %@.", [self keyPathToString:keyPath]);
			OK = NO;
		}
	}
	
	if (OK && [type isKindOfClass:[NSString class]] && [type hasPrefix:@"$"])
	{
		newType = [definitions objectForKey:type];
		if (newType == nil)
		{
			OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- undefined reference %@ at path %@.", type, [self keyPathToString:keyPath]);
			OK = NO;
		}
		type = newType;
		changed = YES;
	}
	
	if (OK && [type isKindOfClass:[NSDictionary class]])
	{
		type = [self normalizedSchemaType:type atPath:BackLink(&keyPath, @"type") withDefinitions:definitions changed:&changed];
		OK = type != nil;
	}
	
	if (OK && changed)
	{
		[dict setObject:type forKey:@"type"];
	}
	
	// Normalize settings for various types.
	if (OK && [type isKindOfClass:[NSString class]])
	{
		if ([type isEqualToString:@"delegatedType"])
		{
			sub = [dict objectForKey:@"baseType"];
			if (sub != nil)
			{
				sub = [self normalizedSchemaType:sub atPath:BackLink(&keyPath, @"baseType") withDefinitions:definitions changed:&subChanged];
				OK = sub != nil;
				if (subChanged)
				{
					changed = YES;
					[dict setObject:sub forKey:@"baseType"];
				}
			}
		}
		else if ([type isEqualToString:@"dictionary"])
		{
			sub = [dict objectForKey:@"schema"];
			if (sub != nil)
			{
				sub = [self normalizedSubSchema:sub atPath:BackLink(&keyPath, @"schema") withDefinitions:definitions changed:&subChanged];
				OK = sub != nil;
				if (subChanged)
				{
					changed = YES;
					[dict setObject:sub forKey:@"schema"];
				}
			}
			sub = [dict objectForKey:@"valueType"];
			if (sub != nil)
			{
				sub = [self normalizedSchemaType:sub atPath:BackLink(&keyPath, @"valueType") withDefinitions:definitions changed:&subChanged];
				OK = sub != nil;
				if (subChanged)
				{
					changed = YES;
					[dict setObject:sub forKey:@"valueType"];
				}
			}
		}
		else if ([type isEqualToString:@"array"])
		{
			sub = [dict objectForKey:@"valueType"];
			if (sub != nil)
			{
				sub = [self normalizedSchemaType:sub atPath:BackLink(&keyPath, @"valueType") withDefinitions:definitions changed:&subChanged];
				OK = sub != nil;
				if (subChanged)
				{
					changed = YES;
					[dict setObject:sub forKey:@"valueType"];
				}
			}
		}
		else if ([type isEqualToString:@"oneOf"])
		{
			sub = [dict objectForKey:@"options"];
			if (sub != nil)
			{
				sub = [self normalizedArrayOfSchemaTypes:sub atPath:BackLink(&keyPath, @"options") withDefinitions:definitions changed:&subChanged];
				OK = sub != nil;
				if (subChanged)
				{
					changed = YES;
					[dict setObject:sub forKey:@"options"];
				}
			}
		}
		else 
		{	
			if (simpleTypes == nil)
			{
				// Types which are known and for which no special verification is needed.
				simpleTypes = [[NSSet setWithObjects:@"string", @"integer", @"positiveInteger", @"float", @"positiveFloat", @"boolean", @"fuzzyBoolean", @"vector", @"quaternion", @"enumeration", nil] retain];
			}
			if ([simpleTypes member:type] == nil && ![type hasPrefix:@"$"])
			{
				OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- unknown type \"%@\" at path %@.", type, [self keyPathToString:keyPath]);
				OK = NO;
			}
		}
	}
	
	if (OK)
	{
		if (changed)
		{
			if (outChanged != NULL)  *outChanged = YES;
			return [dict autorelease];
		}
		else
		{
			[dict release];
			return schemaType;
		}
	}
	else
	{
		[dict release];
		return nil;
	}
}


+ (NSArray *)normalizedArrayOfSchemaTypes:(NSArray *)types
								   atPath:(BackLinkChain)keyPath
						  withDefinitions:(NSDictionary *)definitions
								  changed:(BOOL *)outChanged
{
	NSMutableArray			*result = nil;
	BOOL					OK = YES, thisChanged, changed = NO;
	NSEnumerator			*schemaTypeEnum = nil;
	id						schemaType = nil;
	id						newType = nil;
	unsigned				i = 0;
	
	if (![types isKindOfClass:[NSArray class]])
	{
		OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- expected array, got %@ at path: %@.", [types class], [self keyPathToString:keyPath]);
		return nil;
	}
	
	// Iterate over each type, normalizing.
	result = [[NSMutableArray alloc] initWithCapacity:[types count]];
	for (schemaTypeEnum = [types objectEnumerator]; (schemaType = [schemaTypeEnum nextObject]); )
	{
		thisChanged = NO;
		newType = [self normalizedSchemaType:schemaType
									  atPath:BackLinkIndex(&keyPath, i)
							 withDefinitions:definitions
									 changed:&thisChanged];
		
		if (newType == nil)
		{
			OK = NO;
			break;
		}
		if (thisChanged)
		{
			changed = YES;
			[result addObject:newType];
		}
		else
		{
			[result addObject:schemaType];
		}
	}
	
	if (OK)
	{
		if (changed)
		{
			if (outChanged != NULL)  *outChanged = YES;
			return [result autorelease];
		}
		else
		{
			[result release];
			return types;
		}
	}
	else
	{
		[result release];
		return nil;
	}
	
}


+ (NSArray *)keyPathToArray:(BackLinkChain)keyPath
{
	NSMutableArray			*result = nil;
	BackLinkChain			*curr = NULL;
	
	result = [NSMutableArray array];
	for (curr = &keyPath; curr != NULL; curr = curr->link)
	{
		if (curr->element != nil)  [result insertObject:curr->element atIndex:0];
	}
	
	return result;
}


+ (NSString *)keyPathToString:(BackLinkChain)keyPath
{
	return [self descriptionForKeyPath:[self keyPathToArray:keyPath]];
}


- (BOOL)validatePList:(id)rootPList
				named:(NSString *)name
		  subProperty:(id)subProperty
	againstSchemaType:(NSDictionary *)subSchema
			   atPath:(BackLinkChain)keyPath
			tentative:(BOOL)tentative
				 stop:(BOOL *)outStop
{
	SchemaType				type;
	BOOL					OK;
	
	assert(outStop != nil);
	
	type = ResolveSchemaType(&subSchema, keyPath);
	
	#define VALIDATE_CASE(T) case kType##T: OK = Validate_##T(self, subProperty, subSchema, rootPList, name, keyPath, tentative, outStop); break;
	
	switch (type)
	{
		VALIDATE_CASE(String);
		VALIDATE_CASE(Array);
		VALIDATE_CASE(Dictionary);
		VALIDATE_CASE(Integer);
		VALIDATE_CASE(PositiveInteger);
		VALIDATE_CASE(Float);
		VALIDATE_CASE(PositiveFloat);
		VALIDATE_CASE(OneOf);
		VALIDATE_CASE(Enumeration);
		VALIDATE_CASE(Boolean);
		VALIDATE_CASE(FuzzyBoolean);
		VALIDATE_CASE(Vector);
		VALIDATE_CASE(Quaternion);
		VALIDATE_CASE(DelegatedType);
		
		case kTypeUnknown:
			// ResolveSchemaType() should have provided an error.
			*outStop = YES;
			return NO;
	}
	
	if (!OK && !tentative && type != kTypeArray && type != kTypeDictionary)
	{
		[self delegateVerifierWithPropertyList:rootPList
										 named:name
							 failedForProperty:subProperty
										atPath:[OOPListSchemaVerifier keyPathToArray:keyPath]
								  expectedType:subSchema];
	}
	return OK;
}

@end


static SchemaType StringToSchemaType(NSString *string)
{
	static NSDictionary			*typeMap = nil;
	SchemaType					result;
	
	if (typeMap == nil)
	{
		typeMap =
			[[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithUnsignedInt:kTypeString],			@"string",
				[NSNumber numberWithUnsignedInt:kTypeArray],			@"array",
				[NSNumber numberWithUnsignedInt:kTypeDictionary],		@"dictionary",
				[NSNumber numberWithUnsignedInt:kTypeInteger],			@"integer",
				[NSNumber numberWithUnsignedInt:kTypePositiveInteger],	@"positiveInteger",
				[NSNumber numberWithUnsignedInt:kTypeFloat],			@"float",
				[NSNumber numberWithUnsignedInt:kTypePositiveFloat],	@"positiveFloat",
				[NSNumber numberWithUnsignedInt:kTypeOneOf],			@"oneOf",
				[NSNumber numberWithUnsignedInt:kTypeEnumeration],		@"enumeration",
				[NSNumber numberWithUnsignedInt:kTypeBoolean],			@"boolean",
				[NSNumber numberWithUnsignedInt:kTypeFuzzyBoolean],		@"fuzzyBoolean",
				[NSNumber numberWithUnsignedInt:kTypeVector],			@"vector",
				[NSNumber numberWithUnsignedInt:kTypeQuaternion],		@"quaternion",
				[NSNumber numberWithUnsignedInt:kTypeDelegatedType],	@"delegatedType",
				nil
			 ] retain];
	}
	
	result = [[typeMap objectForKey:string] unsignedIntValue];
	if (result == kTypeUnknown)
	{
		if ([string hasPrefix:@"$"])
		{
			OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- unresolved type definition reference \"%@\".", string);
		}
		else
		{
			OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- unknown type \"%@\".", string);
		}
	}
	
	return result;
}


static SchemaType ResolveSchemaType(NSDictionary **typeSpec, BackLinkChain keyPath)
{
	id						typeVal = nil;
	
	for (;;)
	{
		typeVal = [*typeSpec objectForKey:@"type"];
		if (![typeVal isKindOfClass:[NSDictionary class]])  break;
		*typeSpec = typeVal;
	}
	
	if ([typeVal isKindOfClass:[NSString class]])  return StringToSchemaType(typeVal);
	
	OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- no type for path %@.", [OOPListSchemaVerifier keyPathToString:keyPath]);
	return kTypeUnknown;
}


static NSString *ApplyStringFilter(NSString *string, id filterSpec)
{
	NSEnumerator			*filterEnum = nil;
	id						filter = nil;
	
	if (filterSpec == nil)  return string;
	
	if ([filterSpec isKindOfClass:[NSString class]])
	{
		filterSpec = [NSArray arrayWithObject:filterSpec];
	}
	if ([filterSpec isKindOfClass:[NSArray class]])
	{
		for (filterEnum = [filterSpec objectEnumerator]; (filter = [filterEnum nextObject]); )
		{
			if ([filter isKindOfClass:[NSString class]])
			{
				if ([filter isEqual:@"lowerCase"])  string = [string lowercaseString];
				if ([filter isEqual:@"upperCase"])  string = [string uppercaseString];
				if ([filter hasPrefix:@"truncFront:"])
				{
					string = [string substringToIndex:[[filter substringFromIndex:11] intValue]];
				}
				if ([filter hasPrefix:@"truncBack:"])
				{
					string = [string substringToIndex:[[filter substringFromIndex:10] intValue]];
				}
			}
			else
			{
				OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: unknown string filter \"%@\".", filter);
			}
		}
	}
	else
	{
		OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: unknown string filter \"%@\".", filterSpec);
	}
	
	return string;
}


static BOOL ApplyStringTest(NSString *string, id test, SEL testSelector, NSString *testDescription)
{
	BOOL					(*testIMP)(id, SEL, NSString *);
	NSEnumerator			*testEnum = nil;
	id						subTest = nil;	
	
	if (test == nil)  return YES;
	
	testIMP = (BOOL(*)(id, SEL, NSString *))[string methodForSelector:testSelector];
	if (testIMP == NULL)  return NO;
	
	if ([test isKindOfClass:[NSString class]])
	{
		test = [NSArray arrayWithObject:test];
	}
	
	if ([test isKindOfClass:[NSArray class]])
	{
		for (testEnum = [test objectEnumerator]; (subTest = [testEnum nextObject]); )
		{
			if ([subTest isKindOfClass:[NSString class]])
			{
				if (testIMP(string, testSelector, subTest))  return YES;
			}
			else
			{
				OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- %@ requirement \"%@\" is not a %@.", testDescription, subTest, @"string");
				return NO;
			}
		}
	}
	else
	{
		OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema -- %@ requirement \"%@\" is not a %@.", testDescription, test, @"string or array");
	}
	return NO;
}


static BOOL Validate_String(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	NSString			*filteredString = nil;
	id					testValue = nil;
	unsigned			length;
	unsigned			lengthConstraint;
	
	if (![value isKindOfClass:[NSString class]])  return NO;
	
	filteredString = ApplyStringFilter(value, [params objectForKey:@"filter"]);
	if (filteredString == nil)  return NO;
	
	testValue = [params objectForKey:@"requiredPrefix"];
	if (testValue != nil)
	{
		if (!ApplyStringTest(filteredString, testValue, @selector(hasPrefix:), @"prefix"))  return NO;
	}
	
	testValue = [params objectForKey:@"requiredSuffix"];
	if (testValue != nil)
	{
		if (!ApplyStringTest(filteredString, testValue, @selector(hasSuffix:), @"suffix"))  return NO;
	}
	
	testValue = [params objectForKey:@"requiredSubString"];
	if (testValue != nil)
	{
		if (!ApplyStringTest(filteredString, testValue, @selector(ooPListVerifierHasSubString:), @"substring")
		)  return NO;
	}
	
	length = [filteredString length];
	lengthConstraint = [params unsignedIntForKey:@"minLength"];
	if (length < lengthConstraint)  return NO;
	
	lengthConstraint = [params unsignedIntForKey:@"maxLength" defaultValue:UINT_MAX];
	if (lengthConstraint < length)  return NO;
	
	return YES;
}


static BOOL Validate_Array(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	NSDictionary			*valueType = nil;
	BOOL					OK = YES, stop = NO;
	unsigned				i, count;
	id						subProperty = nil;
	NSAutoreleasePool		*pool = nil;
	unsigned				constraint;
	
	if (![value isKindOfClass:[NSArray class]])  return NO;
	
	count = [value count];
	constraint = [params unsignedIntForKey:@"minCount" defaultValue:0];
	if (count < constraint)  return NO;
	constraint = [params unsignedIntForKey:@"maxCount" defaultValue:UINT_MAX];
	if (constraint < count)  return NO;
	
	valueType = [params objectForKey:@"valueType"];
	if (valueType != nil)
	{
		for (i = 0; i != count; ++i)
		{
			pool = [[NSAutoreleasePool alloc] init];
			
			subProperty = [value objectAtIndex:i];
			
			if (![verifier validatePList:rootPList
									  named:name
							 subProperty:subProperty
					   againstSchemaType:valueType
								  atPath:BackLinkIndex(&keyPath, i)
							   tentative:tentative stop:&stop])
			{
				OK = NO;
			}
			
			[pool release];
		}
	}
	
	*outStop = stop;
	return OK;
}


static BOOL Validate_Dictionary(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	NSDictionary			*schema = nil,
							*valueType = nil,
							*typeSpec = nil;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						subProperty = nil;
	BOOL					OK = YES, stop = NO;
	BOOL					allowOthers;
	NSAutoreleasePool		*pool = nil;
	NSMutableSet			*requiredKeys = nil;
	NSArray					*requiredKeyList = nil;
	unsigned				count, constraint;
	
	if (![value isKindOfClass:[NSDictionary class]])  return NO;
	
	count = [value count];
	constraint = [params unsignedIntForKey:@"minCount" defaultValue:0];
	if (count < constraint)  return NO;
	constraint = [params unsignedIntForKey:@"maxCount" defaultValue:UINT_MAX];
	if (constraint < count)  return NO;
	
	schema = [params objectForKey:@"schema"];
	valueType = [params objectForKey:@"valueType"];
	allowOthers = [params boolForKey:@"allowOthers" defaultValue:YES];
	requiredKeyList = [params arrayForKey:@"requiredKeys"];
	
	if (schema == nil && valueType == nil && requiredKeyList == nil && allowOthers)  return YES;
	
	if (requiredKeyList != nil)
	{
		requiredKeys = [NSMutableSet setWithArray:requiredKeyList];
	}
	
	for (keyEnum = [value keyEnumerator]; (key = [keyEnum nextObject]) && !stop; )
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		subProperty = [value objectForKey:key];
		typeSpec = [schema objectForKey:key];
		if (typeSpec == nil)  typeSpec = valueType;
		
		if (typeSpec != nil)
		{
			if (![verifier validatePList:rootPList
								   named:name
							 subProperty:subProperty
					   againstSchemaType:typeSpec
								  atPath:BackLink(&keyPath, key)
							   tentative:tentative stop:&stop])
			{
				OK = NO;
			}
		}
		else if (!allowOthers && ![requiredKeys member:key])  OK = NO;
		
		[requiredKeys removeObject:key];
		
		[pool release];
	}
	
	if ([requiredKeys count] != 0)
	{
		OK = NO;
	}
	
	*outStop = stop;
	return OK;
}


static BOOL Validate_Integer(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	long long				numericValue;
	long long				constraint;
	
	numericValue = OOLongLongFromObject(value, 0);
	
	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != OOLongLongFromObject(value, 1))  return NO;
	
	// Check constraints.
	constraint = [params longLongForKey:@"minimum" defaultValue:LLONG_MIN];
	if (numericValue < constraint)  return NO;
	
	constraint = [params longLongForKey:@"maximum" defaultValue:LLONG_MAX];
	if (constraint < numericValue)  return NO;
	
	return YES;
}


static BOOL Validate_PositiveInteger(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	unsigned long long		numericValue;
	unsigned long long		constraint;
	
	numericValue = OOUnsignedLongLongFromObject(value, 0);
	
	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != OOUnsignedLongLongFromObject(value, 1))  return NO;
	
	// Check constraints.
	constraint = [params unsignedLongLongForKey:@"minimum"];
	if (numericValue < constraint)  return NO;
	
	constraint = [params unsignedLongLongForKey:@"maximum" defaultValue:ULLONG_MAX];
	if (constraint < numericValue)  return NO;
	
	return YES;
}


static BOOL Validate_Float(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	double					numericValue;
	double					constraint;
	
	numericValue = OODoubleFromObject(value, 0);
	
	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != OODoubleFromObject(value, 1))  return NO;
	
	// Check constraints.
	constraint = [params doubleForKey:@"minimum" defaultValue:-INFINITY];
	if (numericValue < constraint)  return NO;
	
	constraint = [params doubleForKey:@"maximum" defaultValue:INFINITY];
	if (constraint < numericValue)  return NO;
	
	return YES;
}


static BOOL Validate_PositiveFloat(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	double					numericValue;
	double					constraint;
	
	numericValue = OODoubleFromObject(value, 0);
	
	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != OODoubleFromObject(value, 1))  return NO;
	
	if (numericValue < 0)  return NO;
	
	// Check constraints.
	constraint = [params doubleForKey:@"minimum" defaultValue:0];
	if (numericValue < constraint)  return NO;
	
	constraint = [params doubleForKey:@"maximum" defaultValue:INFINITY];
	if (constraint < numericValue)  return NO;
	
	return YES;
}


static BOOL Validate_OneOf(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	NSArray					*options = nil;
	BOOL					OK = NO, stop = NO;
	NSEnumerator			*optionEnum = nil;
	id						option = nil;
	NSAutoreleasePool		*pool = nil;
	
	options = [params arrayForKey:@"options"];
	if (options == nil)
	{
		OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema encountered while verifying %@ -- no options specified for oneOf clause at path %@.", name, [OOPListSchemaVerifier keyPathToString:keyPath]);
		*outStop = YES;
		return NO;
	}
	
	for (optionEnum = [options objectEnumerator]; (option = [optionEnum nextObject]) ;)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		if ([verifier validatePList:rootPList
							  named:name
						subProperty:value
				  againstSchemaType:option
							 atPath:keyPath
						  tentative:YES
							   stop:&stop])
		{
			OK = YES;
		}
		
		[pool release];
		if (OK)  break;
	}
	
	// Ignore stop in tentatives.
	return OK;
}


static BOOL Validate_Enumeration(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	NSArray					*values = nil;
	NSString				*filteredString = nil;
	
	values = [params arrayForKey:@"values"];
	if (values == nil)
	{
		OOLog(@"plistVerifier.badSchema", @"Property list schema verifier: bad schema encountered while verifying %@ -- no values specified for enumeration at path %@.", name, [OOPListSchemaVerifier keyPathToString:keyPath]);
		*outStop = YES;
		return NO;
	}
	
	filteredString = ApplyStringFilter(value, [params objectForKey:@"filter"]);
	if (filteredString == nil)  return NO;
	
	return [values containsObject:filteredString];
}


static BOOL Validate_Boolean(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	// Check basic parseability. If there's inequality here, the default value is being returned.
	return OOBooleanFromObject(value, 0) == OOBooleanFromObject(value, 1);
}


static BOOL Validate_FuzzyBoolean(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	// Check basic parseability. If there's inequality here, the default value is being returned.
	return OOFuzzyBooleanFromObject(value, 0) == OOFuzzyBooleanFromObject(value, 1);
}


static BOOL Validate_Vector(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	// Check basic parseability. If there's inequality here, the default value is being returned.
	return vector_equal(OOVectorFromObject(value, kZeroVector), OOVectorFromObject(value, kBasisXVector));
}


static BOOL Validate_Quaternion(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	// Check basic parseability. If there's inequality here, the default value is being returned.
	return quaternion_equal(OOQuaternionFromObject(value, kZeroQuaternion), OOQuaternionFromObject(value, kIdentityQuaternion));
}


static BOOL Validate_DelegatedType(OOPListSchemaVerifier *verifier, id value, NSDictionary *params, id rootPList, NSString *name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	NSDictionary			*baseType = nil;
	NSString				*key = nil;
	BOOL					stop = NO;
	
	baseType = [params objectForKey:@"baseType"];
	if (baseType != nil)
	{
		if (![verifier validatePList:rootPList
							   named:name
						 subProperty:value
				   againstSchemaType:baseType
							  atPath:keyPath
						   tentative:NO
								stop:&stop])
		{
			*outStop = stop;
			return NO;
		}
	}
	
	key = [params objectForKey:@"key"];
	return [verifier delegateVerifierWithPropertyList:rootPList
												named:name
										 testProperty:value
											   atPath:[OOPListSchemaVerifier keyPathToArray:keyPath]
										  againstType:key];
}


@implementation NSString (OOPListSchemaVerifierHelpers)

- (BOOL)ooPListVerifierHasSubString:(NSString *)string
{
	return [self rangeOfString:string].location != NSNotFound;
}

@end


static NSError *Error(OOPListSchemaVerifierErrorCode errorCode, NSString *format, ...)
{
	NSError				*result = nil;
	va_list				args;
	
	va_start(args, format);
	result = ErrorWithDictionaryAndArguments(errorCode, nil, format, args);
	va_end(args);
	
	return result;
}


static NSError *ErrorWithProperty(OOPListSchemaVerifierErrorCode errorCode, NSString *propKey, id propValue, NSString *format, ...)
{
	NSError				*result = nil;
	va_list				args;
	NSDictionary		*dict = nil;
	
	dict = [NSDictionary dictionaryWithObject:propValue forKey:propKey];
	va_start(args, format);
	ErrorWithDictionaryAndArguments(errorCode, dict, format, args);
	va_end(args);
	
	return result;
}


static NSError *ErrorWithDictionary(OOPListSchemaVerifierErrorCode errorCode, NSDictionary *dict, NSString *format, ...)
{
	NSError				*result = nil;
	va_list				args;
	
	va_start(args, format);
	ErrorWithDictionaryAndArguments(errorCode, dict, format, args);
	va_end(args);
	
	return result;
}


static NSError *ErrorWithDictionaryAndArguments(OOPListSchemaVerifierErrorCode errorCode, NSDictionary *dict, NSString *format, va_list arguments)
{
	NSString			*message = nil;
	id					userInfo = nil;
	
	message = [[NSString alloc] initWithFormat:format arguments:arguments];
	if (dict == nil)  userInfo = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
	else
	{
		userInfo = [dict mutableCopy];
		[userInfo setObject:userInfo forKey:NSLocalizedDescriptionKey];
		[userInfo autorelease];
	}
	[message release];
	
	return [NSError errorWithDomain:kOOPListSchemaVerifierErrorDomain code:errorCode userInfo:dict];
}

#endif	// OO_OXP_VERIFIER_ENABLED
