/*

OOPListSchemaVerifier.h

Utility class to verify the structure of a property list based on a schema
(which is itself a property list).


Copyright (C) 2007-2013 Jens Ayton

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

#import "OOOXPVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#import <Foundation/Foundation.h>
#import "OOFunctionAttributes.h"


@interface OOPListSchemaVerifier: NSObject
{
@private
	NSDictionary				*_schema;
	NSDictionary				*_definitions;
	
	id							_delegate;
	uint32_t					_badDelegateWarning: 1;
}

+ (instancetype)verifierWithSchema:(NSDictionary *)schema;
- (id)initWithSchema:(NSDictionary *)schema;

- (void)setDelegate:(id)delegate;
- (id)delegate;

- (BOOL)verifyPropertyList:(id)plist named:(NSString *)name;

/*	Convert a key path (such as provided to the delegate method
	-verifier:withPropertyList:failedForProperty:atPath:expectedType:) to a
	human-readable string. Strings are separated by dots and numbers are give
	brackets. For instance, the key path ( "adder-player", "custom_views", 0,
	"view_description" ) is transfomed to
	"adder-player.custom_views[0].view_description".
*/
+ (NSString *)descriptionForKeyPath:(NSArray *)keyPath;

@end


@interface NSObject (OOPListSchemaVerifierDelegate)

// Handle "delegated types". Return YES for valid, NO for invalid.
- (BOOL)verifier:(OOPListSchemaVerifier *)verifier
withPropertyList:(id)rootPList
		   named:(NSString *)name
	testProperty:(id)subPList
		  atPath:(NSArray *)keyPath
	 againstType:(NSString *)typeKey
		   error:(NSError **)outError;

/*	Method notifying of verification failure.
	Return YES to continue verifying, NO to stop.
*/
- (BOOL)verifier:(OOPListSchemaVerifier *)verifier
withPropertyList:(id)rootPList
		   named:(NSString *)name
 failedForProperty:(id)subPList
	   withError:(NSError *)error
	expectedType:(NSDictionary *)localSchema;

@end


// NSError domain and codes used to report schema verifier errors.
extern NSString * const kOOPListSchemaVerifierErrorDomain;

extern NSString * const kPListKeyPathErrorKey;			// Array specifying key path in plist.
extern NSString * const kSchemaKeyPathErrorKey;			// Array specifying key path in schema.

extern NSString * const	kExpectedClassErrorKey;			// Expected class. Nil for vector and quaternion.
extern NSString * const	kExpectedClassNameErrorKey;		// String describing expected class. May be more specific (for instance, "boolean" or "positive integer" for NSNumber).
extern NSString * const kUnknownKeyErrorKey;			// Unallowed key found in dictionary.
extern NSString * const kMissingRequiredKeysErrorKey;	// Set of required keys not present in dictionary
extern NSString * const kMissingSubStringErrorKey;		// String or array of strings not found for kPListErrorStringPrefixMissing/kPListErrorStringSuffixMissing/kPListErrorStringSubstringMissing.
extern NSString * const kUnnownFilterErrorKey;			// Unrecognized filter specifier for kPListErrorSchemaUnknownFilter. Not specified if filter is not a string.
extern NSString * const kErrorsByOptionErrorKey;		// Dictionary of errors for oneOf types.

extern NSString * const kUnknownTypeErrorKey;			// Set for kPListErrorSchemaUnknownType.
extern NSString * const kUndefinedMacroErrorKey;		// Set for kPListErrorSchemaUndefiniedMacroReference.


// All plist verifier errors have a short error description in their -localizedFailureReason.

typedef enum
{
	kPListErrorNone,
	kPListErrorInternal,				// PList verifier did something dumb.
	
	// Verification errors -- property list doesn't match schema.
	kPListErrorTypeMismatch,			// Basic type mismatch -- array instead of number, for instance.
	
	kPListErrorMinimumConstraintNotMet,	// minimum/minCount/minLength constraint violated
	kPListErrorMaximumConstraintNotMet,	// maximum/maxCount/maxLength constraint violated
	kPListErrorNumberIsNegative,		// Negative number in positiveFloat.
	
	kPListErrorStringPrefixMissing,		// String does not match requiredPrefix rule. kMissingSubStringErrorKey is set.
	kPListErrorStringSuffixMissing,		// String does not match requiredSuffix rule. kMissingSubStringErrorKey is set.
	kPListErrorStringSubstringMissing,	// String does not match requiredSuffix rule. kMissingSubStringErrorKey is set.
	
	kPListErrorDictionaryUnknownKey,	// Unknown key for dictionary with allowOthers = NO.
	kPListErrorDictionaryMissingRequiredKeys,	// requiredKeys rule is not fulfilled. The missing keys are listed in kMissingRequiredKeysErrorKey.
	
	kPListErrorEnumerationBadValue,		// Enumeration type contains string that isn't in permitted set.
	
	kPListErrorOneOfNoMatch,			// No match for oneOf type. kErrorsByOptionErrorKey is set to a dictionary of type specifiers to errors. Note that the keys in this dictionary can be either strings or dictionaries.
	
	kPListDelegatedTypeError,			// Delegate's verification method failed. If it returned an error, this will be in NSUnderlyingErrorKey.
	
	// Schema errors -- schema is broken.
	kPListErrorStartOfSchemaErrors		= 100,
	
	kPListErrorSchemaBadTypeSpecifier,	// Bad type specifier - specifier is not a string or a dictionary, or is a dictionary with no type key. kUndefinedMacroErrorKey is set.
	kPListErrorSchemaUndefiniedMacroReference,	// Reference to $macro not found in $definitions.
	kPListErrorSchemaUnknownType,		// Unknown type specified in type specifier. kUnknownTypeErrorKey is set.
	kPListErrorSchemaNoOneOfOptions,	// OneOf clause has no options array.
	kPListErrorSchemaNoEnumerationValues,	// Enumeration clause has no values array.
	kPListErrorSchemaUnknownFilter,		// Bad value for string/enumeration filter specifier.
	kPListErrorSchemaBadComparator,		// String comparision requirement value (requiredPrefix etc.) is not a string.
	
	kPListErrorLastErrorCode
} OOPListSchemaVerifierErrorCode;


OOINLINE BOOL OOPlistErrorIsSchemaError(OOPListSchemaVerifierErrorCode error)
{
	return kPListErrorStartOfSchemaErrors < error && error < kPListErrorLastErrorCode;
}


@interface NSError (OOPListSchemaVerifierConveniences)

- (NSArray *)plistKeyPath;
- (NSString *)plistKeyPathDescription;	// Result of calling +[OOPListSchemaVerifier descriptionForKeyPath:] on kPListKeyPathErrorKey.

- (NSSet *)missingRequiredKeys;

- (Class)expectedClass;
- (NSString *)expectedClassName;

@end

#endif	// OO_OXP_VERIFIER_ENABLED
