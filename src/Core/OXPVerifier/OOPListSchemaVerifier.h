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

#import "OOFunctionAttributes.h"
#import "oofnd/objc/OOObject.h"
#import <Foundation/Foundation.h>

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

@interface OOPListSchemaVerifier : OOObject {
@private
    oo::PList _schema;
    oo::PList _definitions; // the schema's $definitions (null if none)

    id _delegate;
    uint32_t _badDelegateWarning : 1;
}

+ (instancetype)verifierWithSchema:(const oo::PList&)schema; // nil for a null schema
- (id)initWithSchema:(const oo::PList&)schema;

- (void)setDelegate:(id)delegate;
- (id)delegate;

- (BOOL)verifyPropertyList:(const oo::PList&)plist named:(const std::string&)name;

/*	Convert a key path (such as provided to the delegate method
        -verifier:withPropertyList:failedForProperty:atPath:expectedType:) to a
        human-readable string. Strings are separated by dots and numbers are give
        brackets. For instance, the key path ( "adder-player", "custom_views", 0,
        "view_description" ) is transfomed to
        "adder-player.custom_views[0].view_description".
*/
+ (std::optional<std::string>)descriptionForKeyPath:(const oo::PList&)keyPath; // a null or empty path is "root"; nullopt for a component that is neither string nor number

@end

@interface NSObject (OOPListSchemaVerifierDelegate)

// Handle "delegated types". Return YES for valid, NO for invalid.
// name: a string; keyPath: an array of strings and numbers; typeKey: a string.
- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
    withPropertyList:(id)rootPList
               named:(id)name
        testProperty:(id)subPList
              atPath:(id)keyPath
         againstType:(id)typeKey
               error:(NSError**)outError; // shared selector (proposed ADR-0043)

/*	Method notifying of verification failure.
        Return YES to continue verifying, NO to stop.
*/
// name: a string; localSchema: the schema type specifier (a string or a dictionary).
- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
     withPropertyList:(id)rootPList
                named:(id)name
    failedForProperty:(id)subPList
            withError:(NSError*)error
         expectedType:(id)localSchema; // shared selector (proposed ADR-0043)

@end

// NSError domain and codes used to report schema verifier errors (UTF-8; the NSError's domain and
// userInfo keys are these texts).
extern const char* const kOOPListSchemaVerifierErrorDomain;

extern const char* const kPListKeyPathErrorKey; // Array specifying key path in plist.
extern const char* const kSchemaKeyPathErrorKey; // Array specifying key path in schema.

extern const char* const kExpectedClassErrorKey; // Expected class. Nil for vector and quaternion.
extern const char* const kExpectedClassNameErrorKey; // String describing expected class. May be more specific (for instance, "boolean" or "positive integer" for a number).
extern const char* const kUnknownKeyErrorKey; // Unallowed key found in dictionary.
extern const char* const kMissingRequiredKeysErrorKey; // Set of required keys not present in dictionary
extern const char* const kMissingSubStringErrorKey; // String or array of strings not found for kPListErrorStringPrefixMissing/kPListErrorStringSuffixMissing/kPListErrorStringSubstringMissing.
extern const char* const kUnnownFilterErrorKey; // Unrecognized filter specifier for kPListErrorSchemaUnknownFilter. Not specified if filter is not a string.
extern const char* const kErrorsByOptionErrorKey; // Dictionary of errors for oneOf types.

extern const char* const kUnknownTypeErrorKey; // Set for kPListErrorSchemaUnknownType.
extern const char* const kUndefinedMacroErrorKey; // Set for kPListErrorSchemaUndefiniedMacroReference.

// All plist verifier errors have a short error description in their -localizedFailureReason.

typedef enum {
    kPListErrorNone,
    kPListErrorInternal, // PList verifier did something dumb.

    // Verification errors -- property list doesn't match schema.
    kPListErrorTypeMismatch, // Basic type mismatch -- array instead of number, for instance.

    kPListErrorMinimumConstraintNotMet, // minimum/minCount/minLength constraint violated
    kPListErrorMaximumConstraintNotMet, // maximum/maxCount/maxLength constraint violated
    kPListErrorNumberIsNegative, // Negative number in positiveFloat.

    kPListErrorStringPrefixMissing, // String does not match requiredPrefix rule. kMissingSubStringErrorKey is set.
    kPListErrorStringSuffixMissing, // String does not match requiredSuffix rule. kMissingSubStringErrorKey is set.
    kPListErrorStringSubstringMissing, // String does not match requiredSuffix rule. kMissingSubStringErrorKey is set.

    kPListErrorDictionaryUnknownKey, // Unknown key for dictionary with allowOthers = NO.
    kPListErrorDictionaryMissingRequiredKeys, // requiredKeys rule is not fulfilled. The missing keys are listed in kMissingRequiredKeysErrorKey.

    kPListErrorEnumerationBadValue, // Enumeration type contains string that isn't in permitted set.

    kPListErrorOneOfNoMatch, // No match for oneOf type. kErrorsByOptionErrorKey is set to a dictionary of type specifiers to errors. Note that the keys in this dictionary can be either strings or dictionaries.

    kPListDelegatedTypeError, // Delegate's verification method failed. If it returned an error, this will be in NSUnderlyingErrorKey.

    // Schema errors -- schema is broken.
    kPListErrorStartOfSchemaErrors = 100,

    kPListErrorSchemaBadTypeSpecifier, // Bad type specifier - specifier is not a string or a dictionary, or is a dictionary with no type key. kUndefinedMacroErrorKey is set.
    kPListErrorSchemaUndefiniedMacroReference, // Reference to $macro not found in $definitions.
    kPListErrorSchemaUnknownType, // Unknown type specified in type specifier. kUnknownTypeErrorKey is set.
    kPListErrorSchemaNoOneOfOptions, // OneOf clause has no options array.
    kPListErrorSchemaNoEnumerationValues, // Enumeration clause has no values array.
    kPListErrorSchemaUnknownFilter, // Bad value for string/enumeration filter specifier.
    kPListErrorSchemaBadComparator, // String comparision requirement value (requiredPrefix etc.) is not a string.

    kPListErrorLastErrorCode
} OOPListSchemaVerifierErrorCode;

OOINLINE BOOL OOPlistErrorIsSchemaError(OOPListSchemaVerifierErrorCode error)
{
    return kPListErrorStartOfSchemaErrors < error && error < kPListErrorLastErrorCode;
}

#endif // OO_OXP_VERIFIER_ENABLED
