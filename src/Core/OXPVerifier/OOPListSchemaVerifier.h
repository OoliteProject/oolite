/*
 
 OOPListSchemaVerifier.h
 
 Utility class to verify the structure of a property list based on a schema
 (which is itself a property list).
 
 
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

#import "OOOxpVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#import <Foundation/Foundation.h>


@interface OOPListSchemaVerifier: NSObject
{
	NSDictionary				*_schema;
	id							_delegate;
	uint32_t					_badDelegateWarning: 1;
}

+ (id)verifierWithSchema:(id)schema;
- (id)initWithSchema:(id)schema;

- (void)setDelegate:(id)delegate;
- (id)delegate;

- (BOOL)validatePropertyList:(id)plist named:(NSString *)name;

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
- (BOOL)verifier:(OOPListSchemaVerifier *)verifier withPropertyList:(id)rootPList named:(NSString *)name testProperty:(id)subPList atPath:(NSArray *)keyPath againstType:(NSString *)typeKey;

/*	Method notifying of validation failure.
	Return YES to continue validating, NO to stop.
*/
- (BOOL)verifier:(OOPListSchemaVerifier *)verifier withPropertyList:(id)rootPList named:(NSString *)name failedForProperty:(id)subPList atPath:(NSArray *)keyPath expectedType:(NSDictionary *)localSchema;

@end


// NSError domain and codes used to report schema verifier errors.
extern NSString * const kOOPListSchemaVerifierErrorDomain;

extern NSString * const kPListKeyPathErrorKey;
extern NSString * const kSchemaKeyPathErrorKey;

extern NSString * const kMissingRequiredKeysErrorKey;
extern NSString * const kUnknownTypeErrorKey;


// All plist verifier errors have a short error description in their -localizedDescription. Generally this is something that would be more suitable to -localizedFailureReason, but we need Mac OS X 10.3 compatibility.

typedef enum
{
	kPListErrorNone,
	
	// Validation errors -- property list doesn't match schema.
	kPListErrorTypeMismatch,			// Basic type mismatch -- array instead of number, for instance.
	
	kPListErrorMinimumConstraintNotMet,	// minimum/minCount/minLength constraint violated
	kPListErrorNumberIsNegative,		// Negative number in positiveInteger/positiveFloat
	
	kPListErrorStringPrefixMissing,		// String does not match requiredPrefix rule.
	kPListErrorStringSuffixMissing,		// String does not match requiredSuffix rule.
	kPListErrorStringSubstringMissing,	// String does not match requiredSuffix rule.
	
	kPListErrorDictionaryUnknownKey,	// Unknown key for dictionary with allowOthers = NO.
	kPListErrorDictionaryMissingRequiredKeys,	// requiredKeys rule is not fulfilled. The missing keys are listed in kMissingRequiredKeysErrorKey.
	
	kPListErrorEnumerationBadValue,		// Enumeration type contains string that isn't in permitted set.
	
	kPListDelegatedTypeError,			// Delegate's verification method failed. If it returned an error, this will be in NSUnderlyingErrorKey.
	
	// Schema errors -- schema is broken.
	kPListErrorSchemaMacroRecursion,	// Macro reference recursion limit hit (currently, recursion limit is 32). This can only happen on init.
	
	kPListErrorSchemaTypeMismatch,		// Bad type in schema.
	kPListErrorSchemaUndefinedMacro,	// Reference to undefined macro.
	kPListErrorSchemaNoType,			// No type specified in type specifier.
	kPListErrorSchemaUnkownType,		// Unknown type specified in type specifier. kUnknownTypeErrorKey is set.
	kPListErrorSchemaNoOneOfOptions,	// OneOf clause has no options array.
	kPListErrorSchemaNoEnumerationValues	// Enumeration clause has no values array.
} OOPListSchemaVerifierErrorCode;

#endif	// OO_OXP_VERIFIER_ENABLED
