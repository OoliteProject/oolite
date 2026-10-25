/*

OOPListSchemaVerifier.m


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED ìAS ISî, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOPListSchemaVerifier.h"
#include "OOObjCPList.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOLoggingExtended.h"
#include "oofnd/Log.hpp"
#include "OOMaths.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/String.hpp"
#include <limits.h>
#include "oofnd/objc/OOException.h"
#include "OOPListGameTypes.h"


#define PLIST_VERIFIER_DEBUG_DUMP_ENABLED		1


enum
{
	// Largest allowable number of characters for string included in error message.
	kMaximumLengthForStringInErrorMessage		= 100
};


// Internal error codes.
enum
{
	kStartOfPrivateErrorCodes = kPListErrorLastErrorCode,
	
	kPListErrorFailedAndErrorHasBeenReported
};


#if PLIST_VERIFIER_DEBUG_DUMP_ENABLED
static BOOL				sDebugDump = NO;

#define DebugDumpIndent()		do { if (sDebugDump) oo::log::indent(); } while (0)
#define DebugDumpOutdent()		do { if (sDebugDump) oo::log::outdent(); } while (0)
#define DebugDumpPushIndent()	do { if (sDebugDump) oo::log::pushIndent(); } while (0)
#define DebugDumpPopIndent()	do { if (sDebugDump) oo::log::popIndent(); } while (0)
#define DebugDump(...)			do { if (sDebugDump) OO_LOG("verifyOXP.verbose.plistDebugDump", __VA_ARGS__); } while (0)
#else
#define DebugDumpIndent()		do { } while (0)
#define DebugDumpOutdent()		do { } while (0)
#define DebugDumpPushIndent()	do { } while (0)
#define DebugDumpPopIndent()	do { } while (0)
#define DebugDump(...)			do { } while (0)
#endif


const char * const kOOPListSchemaVerifierErrorDomain = "org.aegidian.oolite.OOPListSchemaVerifier.ErrorDomain";

const char * const kPListKeyPathErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier plist key path";
const char * const kSchemaKeyPathErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier schema key path";

const char * const kExpectedClassErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier expected class";
const char * const kExpectedClassNameErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier expected class name";
const char * const kUnknownKeyErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier unknown key";
const char * const kMissingRequiredKeysErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier missing required keys";
const char * const kMissingSubStringErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier missing substring";
const char * const kUnnownFilterErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier unknown filter";
const char * const kErrorsByOptionErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier errors by option";
const char * const kUnderlyingErrorErrorKey = "NSUnderlyingError";

const char * const kUnknownTypeErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier unknown type";
const char * const kUndefinedMacroErrorKey = "org.aegidian.oolite.OOPListSchemaVerifier undefined macro";


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


/*	The key path the verification core hands down, one link per level (a dictionary key, an array
	index, or neither for the root). OOPListSchemaVerifier.h declares it for the core's members;
	it is defined here again since bead oo-9ht.119 (it was in the header from bead oo-pni4).
*/
struct BackLinkChain
{
	BackLinkChain			*link;
	const std::string		*key;		// a dictionary key (the caller keeps it alive), or
	NSUInteger				index;		// an array index when isIndex; neither for the root
	bool					isIndex;
};

namespace {

OOINLINE BackLinkChain BackLink(BackLinkChain *link, const std::string *key)
{
	BackLinkChain result = { link, key, 0, false };
	return result;
}

OOINLINE BackLinkChain BackLinkIndex(BackLinkChain *link, NSUInteger index)
{
	BackLinkChain result = { link, nullptr, index, true };
	return result;
}

OOINLINE BackLinkChain BackLinkRoot(void)
{
	BackLinkChain result = { NULL, nullptr, 0, false };
	return result;
}

} // namespace


namespace {

typedef bool (*StringTest)(const std::string &string, const std::string &test);

SchemaType StringToSchemaType(const std::string &string, std::optional<OOPListSchemaVerifierError> *outError);
std::string ApplyStringFilter(const std::string &string, const oo::PList &filterSpec, BackLinkChain keyPath, std::optional<OOPListSchemaVerifierError> *outError);
BOOL ApplyStringTest(const std::string &string, const oo::PList &test, StringTest stringTest, const char *testDescription, BackLinkChain keyPath, std::optional<OOPListSchemaVerifierError> *outError);

oo::PList KeyPathToArray(BackLinkChain keyPath);
std::string KeyPathToString(BackLinkChain keyPath);

} // namespace

namespace {

std::string StringForErrorReport(const std::string &string);
std::string ArrayForErrorReport(const oo::PList &array);
std::string SetForErrorReport(std::vector<std::string> strings);
std::string StringOrArrayForErrorReport(const oo::PList &value, const char *arrayPrefix);

} // namespace

namespace {

// The formats are printf formats (oo::str::vformat); an object's text is %s of oo::DescriptionOf(x).
OOPListSchemaVerifierError Error(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const char *format, ...);
OOPListSchemaVerifierError ErrorWithProperty(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const std::string &propKey, const oo::PList &propValue, const char *format, ...);
OOPListSchemaVerifierError ErrorWithDictionary(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const oo::PList &dict, const char *format, ...);
OOPListSchemaVerifierError ErrorWithDictionaryAndArguments(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const oo::PList &dict, const char *format, va_list arguments);

OOPListSchemaVerifierError ErrorTypeMismatch(const char *expectedClassName, const oo::PList &actual, BackLinkChain keyPath);
OOPListSchemaVerifierError ErrorFailureAlreadyReported(void);
BOOL IsFailureAlreadyReportedError(const OOPListSchemaVerifierError &error);

} // namespace


namespace {

// +descriptionForKeyPath: of an error's kPListKeyPathErrorKey (what the retired
// error category's key-path description returned; "root" when there is none).
std::optional<std::string> KeyPathDescriptionOfError(const OOPListSchemaVerifierError &error)
{
	const oo::PList *keyPath = error.userInfo.find(kPListKeyPathErrorKey);
	return OOPListSchemaVerifier::descriptionForKeyPath((keyPath != nullptr) ? *keyPath : oo::PList());
}


// A nested error (the delegate's underlying error, a oneOf option's error) as a userInfo value.
oo::PList PListFromError(const OOPListSchemaVerifierError &error)
{
	oo::PList::Dict result { { "domain", oo::PList(error.domain) }, { "code", oo::PList(error.code) }, { "userInfo", error.userInfo } };
	if (error.failureReason.has_value())  result["failureReason"] = oo::PList(*error.failureReason);
	return oo::PList(std::move(result));
}

} // namespace


// The verification core (the old OOPrivate category) is OOPListSchemaVerifier's internal
// members: the type verifiers below call them on the verifier they are handed.


// Each verifier takes the value, the resolved schema type and the name as C++ values.
#define VERIFY_PROTO(T) static std::optional<OOPListSchemaVerifierError> Verify_##T(OOPListSchemaVerifier *verifier, const oo::PList &value, const oo::PList &params, const oo::PList &rootPList, const std::string &name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
namespace {
VERIFY_PROTO(String);
VERIFY_PROTO(Array);
VERIFY_PROTO(Dictionary);
VERIFY_PROTO(Integer);
VERIFY_PROTO(PositiveInteger);
VERIFY_PROTO(Float);
VERIFY_PROTO(PositiveFloat);
VERIFY_PROTO(OneOf);
VERIFY_PROTO(Enumeration);
VERIFY_PROTO(Boolean);
VERIFY_PROTO(FuzzyBoolean);
VERIFY_PROTO(Vector);
VERIFY_PROTO(Quaternion);
VERIFY_PROTO(DelegatedType);
} // namespace


oo::Ref<OOPListSchemaVerifier> OOPListSchemaVerifier::verifierWithSchema(const oo::PList &schema)
{
	return initWithSchema(schema);
}


OOPListSchemaVerifier::OOPListSchemaVerifier(const oo::PList &schema)
{
	_schema = schema;
	const oo::PList *definitions = _schema.get<oo::PList::Dict>("$definitions");
	_definitions = (definitions != nullptr) ? *definitions : oo::PList();
	sDebugDump = oo::Defaults::standard().boolForKey("plist-schema-verifier-dump-structure") ? YES : NO;
	if (sDebugDump)  oo::log::logger().setDisplay("verifyOXP.verbose.plistDebugDump", YES);
}


oo::Ref<OOPListSchemaVerifier> OOPListSchemaVerifier::initWithSchema(const oo::PList &schema)
{
	oo::Ref<OOPListSchemaVerifier> verifier = oo::adopt(new OOPListSchemaVerifier(schema));
	if (!verifier->_schema)
	{
		return nullptr;
	}

	return verifier;
}


void OOPListSchemaVerifier::setDelegate(OOPListSchemaVerifierDelegate *delegate)
{
	if (_delegate != delegate)
	{
		_delegate = delegate;
		_badDelegateWarning = NO;
	}
}


OOPListSchemaVerifierDelegate *OOPListSchemaVerifier::delegate()
{
	return _delegate;
}


bool OOPListSchemaVerifier::verifyPropertyList(const oo::PList &plist, const std::string &name)
{
	BOOL						OK;
	BOOL						stop = NO;

	OK = verifyPList(plist,
					 name,
					 plist,
					 _schema,
					 BackLinkRoot(),
					 NO,
					 NULL,
					 &stop);

	return OK;
}


std::optional<std::string> OOPListSchemaVerifier::descriptionForKeyPath(const oo::PList &keyPath)
{
	std::string					result;
	BOOL						first = YES;

	if (const oo::PList::Array *components = keyPath.getIf<oo::PList::Array>())
	{
		for (const oo::PList &component : *components)
		{
			if (component.isNumber())
			{
				result += "[" + oo::plist_get::numberStringValue(component) + "]";	// as %@ printed the number
			}
			else if (const std::string *string = component.getIf<std::string>())
			{
				if (!first)  result += ".";
				result += *string;
			}
			else  return std::nullopt;
			first = NO;
		}
	}

	if (first)
	{
		// Empty path
		return std::string("root");
	}

	return result;
}


bool OOPListSchemaVerifier::delegateVerifierWithPropertyList(const oo::PList &rootPList,
															 const std::string &name,
															 const oo::PList &subPList,
															 BackLinkChain keyPath,
															 const oo::PList &typeKey,
															 std::optional<OOPListSchemaVerifierError> *outError)
{
	BOOL					result;
	std::optional<OOPListSchemaVerifierError> error;

	// A C++ delegate answers both members; no delegate is what a delegate that did not answer the
	// selector (or nil) was (bead oo-9ht.119).
	if (_delegate != nullptr)
	{
		try
		{
			result = _delegate->verifierTestProperty(this,
													 rootPList,
													 name,
													 subPList,
													 KeyPathToArray(keyPath),
													 typeKey,
													 &error);
		}
		catch (...)
		{
			const auto exception = oo::CurrentOOException();
			if (!exception)  throw;	// not an OOException: it goes on up, as before
			OO_LOG("plistVerifier.delegateException", "Property list schema verifier: delegate threw exception ({}) in -verifier:withPropertyList:named:testProperty:atPath:againstType: for type \"{}\" at {} in {} -- treating as failure.", exception->name(), oo::DescriptionOf(typeKey), KeyPathToString(keyPath), name);
			result = NO;
			error = std::nullopt;
		}

		if (outError != NULL)
		{
			if (!result || error.has_value())
			{
				// Note: Generates an error if delegate returned NO (meaning stop) or if delegate produced an error but did not request a stop.
				*outError = ErrorWithProperty(kPListDelegatedTypeError, &keyPath, kUnderlyingErrorErrorKey, error.has_value() ? PListFromError(*error) : oo::PList(), "Value at %s does not match delegated type \"%s\".", KeyPathToString(keyPath).c_str(), oo::DescriptionOf(typeKey).c_str());
			}
			else *outError = std::nullopt;
		}
	}
	else
	{
		if (!_badDelegateWarning)
		{
			OO_LOG("plistVerifier.badDelegate", "{}", "Property list schema verifier: delegate does not handle delegated types.");
			_badDelegateWarning = YES;
		}
		result = YES;
	}

	return result;
}


bool OOPListSchemaVerifier::delegateVerifierWithPropertyList(const oo::PList &rootPList,
															 const std::string &name,
															 const oo::PList &subPList,
															 const OOPListSchemaVerifierError &error,
															 const oo::PList &localSchema)
{
	BOOL					result;

	if (_delegate != nullptr)	// as above
	{
		try
		{
			result = _delegate->verifierFailedForProperty(this,
														  rootPList,
														  name,
														  subPList,
														  error,
														  localSchema);
		}
		catch (...)
		{
			const auto exception = oo::CurrentOOException();
			if (!exception)  throw;	// not an OOException: it goes on up, as before
			OO_LOG("plistVerifier.delegateException", "Property list schema verifier: delegate threw exception ({}) in -verifier:withPropertyList:named:failedForProperty:atPath:expectedType: at {} in {} -- stopping.", exception->name(), KeyPathDescriptionOfError(error).value_or("(null)"), name);
			result = NO;
		}
	}
	else
	{
		OO_LOG("plistVerifier.failed", "Verification of property list \"{}\" failed at {}: {}", name, KeyPathDescriptionOfError(error).value_or("(null)"), error.failureReason.value_or("(null)"));
		result = NO;
	}
	return result;
}


bool OOPListSchemaVerifier::verifyPList(const oo::PList &rootPList,
										const std::string &name,
										const oo::PList &subProperty,
										const oo::PList &subSchema,
										BackLinkChain keyPath,
										bool tentative,
										std::optional<OOPListSchemaVerifierError> *outError,
										BOOL *outStop)
{
	SchemaType				type = kTypeUnknown;
	std::optional<OOPListSchemaVerifierError> error;
	oo::PList				resolvedSpecifier;

	assert(outStop != NULL);


	DebugDumpPushIndent();

	try
	{
		DebugDumpIndent();

		resolvedSpecifier = resolveSchemaType(subSchema, keyPath, &error);
		if (resolvedSpecifier)  type = StringToSchemaType(resolvedSpecifier.get<std::string>("type"), &error);

		// The type verifiers (slice 2, bead oo-pgh9) take the verifier.
		#define VERIFY_CASE(T) case kType##T: error = Verify_##T(this, subProperty, resolvedSpecifier, rootPList, name, keyPath, tentative, outStop); break;

		switch (type)
		{
			VERIFY_CASE(String);
			VERIFY_CASE(Array);
			VERIFY_CASE(Dictionary);
			VERIFY_CASE(Integer);
			VERIFY_CASE(PositiveInteger);
			VERIFY_CASE(Float);
			VERIFY_CASE(PositiveFloat);
			VERIFY_CASE(OneOf);
			VERIFY_CASE(Enumeration);
			VERIFY_CASE(Boolean);
			VERIFY_CASE(FuzzyBoolean);
			VERIFY_CASE(Vector);
			VERIFY_CASE(Quaternion);
			VERIFY_CASE(DelegatedType);

			case kTypeUnknown:
				// resolveSchemaType() or StringToSchemaType() should have provided an error.
				*outStop = YES;
		}
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		error = Error(kPListErrorInternal, (BackLinkChain *)&keyPath, "Uncaught exception %s: %s in plist verifier for \"%s\" at %s.", exception->name(), exception->reason(), name.c_str(), KeyPathToString(keyPath).c_str());
	}

	DebugDumpPopIndent();

	if (error.has_value())
	{
		if (!tentative && !IsFailureAlreadyReportedError(*error))
		{
			*outStop = !delegateVerifierWithPropertyList(rootPList,
														 name,
														 subProperty,
														 *error,
														 subSchema);
		}
		else if (tentative)  *outStop = YES;
	}

	if (outError != NULL && error.has_value())  *outError = error;

	return !error.has_value();
}


oo::PList OOPListSchemaVerifier::resolveSchemaType(const oo::PList &specifier,
												   BackLinkChain keyPath,
												   std::optional<OOPListSchemaVerifierError> *outError)
{
	oo::PList				current = specifier;
	BOOL					haveTypeValue = NO;

	assert(outError != NULL);

	if (current.isString() || current.isDict())
	{
		for (;;)
		{
			if (current.isString())  current = oo::PList(oo::PList::Dict{ { "type", current } });
			const oo::PList *typeVal = current.find("type");
			haveTypeValue = (typeVal != nullptr);

			if (typeVal != nullptr && typeVal->isString())
			{
				const std::string typeString = *typeVal->getIf<std::string>();
				if (oo::str::hasPrefix(typeString, "$"))
				{
					// Macro reference; look it up in $definitions
					const oo::PList *definition = _definitions.find(typeString);
					if (definition == nullptr)
					{
						*outError = ErrorWithProperty(kPListErrorSchemaUndefiniedMacroReference, &keyPath, kUndefinedMacroErrorKey, oo::PList(typeString), "Bad schema: reference to undefined macro \"%s\".", StringForErrorReport(typeString).c_str());
						return oo::PList();
					}
					current = *definition;
				}
				else
				{
					// Non-macro string
					return current;
				}
			}
			else if (typeVal != nullptr && typeVal->isDict())
			{
				oo::PList next = *typeVal;
				current = std::move(next);
			}
			else
			{
				break;
			}
		}
	}

	// Error: bad type
	const char *complaint = haveTypeValue ? "not string or dictionary" : "no type specified";

	*outError = Error(kPListErrorSchemaBadTypeSpecifier, &keyPath, "Bad schema: invalid type specifier for path %s (%s).", KeyPathToString(keyPath).c_str(), complaint);
	return oo::PList();
}


namespace {

SchemaType StringToSchemaType(const std::string &string, std::optional<OOPListSchemaVerifierError> *outError)
{
	static const std::map<std::string, SchemaType, std::less<>> typeMap =
	{
		{ "string",				kTypeString },
		{ "array",				kTypeArray },
		{ "dictionary",			kTypeDictionary },
		{ "integer",			kTypeInteger },
		{ "positiveInteger",	kTypePositiveInteger },
		{ "float",				kTypeFloat },
		{ "positiveFloat",		kTypePositiveFloat },
		{ "oneOf",				kTypeOneOf },
		{ "enumeration",		kTypeEnumeration },
		{ "boolean",			kTypeBoolean },
		{ "fuzzyBoolean",		kTypeFuzzyBoolean },
		{ "vector",				kTypeVector },
		{ "quaternion",			kTypeQuaternion },
		{ "delegatedType",		kTypeDelegatedType },
	};
	SchemaType					result;

	const auto found = typeMap.find(string);
	result = (found != typeMap.end()) ? found->second : kTypeUnknown;
	if (result == kTypeUnknown && outError != NULL)
	{
		if (oo::str::hasPrefix(string, "$"))
		{
			*outError = ErrorWithProperty(kPListErrorSchemaUnknownType, NULL, kUnknownTypeErrorKey, oo::PList(string), "Bad schema: unresolved macro reference \"%s\".", string.c_str());
		}
		else
		{
			*outError = ErrorWithProperty(kPListErrorSchemaUnknownType, NULL, kUnknownTypeErrorKey, oo::PList(string), "Bad schema: unknown type \"%s\".", string.c_str());
		}
	}

	return result;
}


// -rangeOfString: (options 0) as GNUstep answers it: the first occurrence that ends on a composed-
// sequence boundary (the rule oo::str::replaceOccurrences follows); an empty string is found at 0
// (captured: {0, 0}). npos when there is none.
std::size_t FindSubString(std::u16string_view string, std::u16string_view sub)
{
	if (sub.empty())  return 0;
	for (std::size_t i = 0; i + sub.size() <= string.size(); ++i)
	{
		const std::size_t end = i + sub.size();
		if (string.substr(i, sub.size()) == sub && !(end < string.size() && oo::str::detail::extendsSequence(string[end])))  return i;
	}
	return std::u16string_view::npos;
}


bool HasSubString(const std::string &string, const std::string &sub)
{
	return FindSubString(oo::utf8ToUtf16(string), oo::utf8ToUtf16(sub)) != std::u16string_view::npos;
}


// -substringToIndex: over UTF-16 units. Past the end GNUstep raised OORangeException with this
// reason (captured, whatever the string's class); -verifyPList: reports it as before.
std::u16string SubstringToIndex(const std::u16string &units, unsigned long long index)
{
	if (index > units.size())
	{
		OORaiseException(OORangeException, "in substringWithRange:, range { 0, %llu } extends beyond size (%llu)", index, (unsigned long long)units.size());
	}
	return units.substr(0, index);
}


std::string ApplyStringFilter(const std::string &string, const oo::PList &filterSpec, BackLinkChain keyPath, std::optional<OOPListSchemaVerifierError> *outError)
{
	std::u16string			result = oo::utf8ToUtf16(string);
	oo::PList::Array		filters;

	assert(outError != NULL);

	if (!filterSpec)  return string;

	if (filterSpec.isString())
	{
		filters.push_back(filterSpec);
	}
	else if (const oo::PList::Array *array = filterSpec.getIf<oo::PList::Array>())
	{
		filters = *array;
	}
	else
	{
		*outError = Error(kPListErrorSchemaUnknownFilter, &keyPath, "Bad schema: \"filter\" must be a string or an array.");
		return string;
	}

	for (const oo::PList &filterValue : filters)
	{
		const std::string *filter = filterValue.getIf<std::string>();
		if (filter != nullptr)
		{
			const std::u16string filterUnits = oo::utf8ToUtf16(*filter);
			// The argument after a filter's prefix (ASCII, so byte and UTF-16 offsets agree).
			auto argument = [&](std::size_t prefixLength) { return filterUnits.substr(prefixLength); };

			if (*filter == "lowerCase")  result = oo::utf8ToUtf16(oo::str::lowercase(oo::utf16ToUtf8(result)));
			else if (*filter == "upperCase")  result = oo::utf8ToUtf16(oo::str::uppercase(oo::utf16ToUtf8(result)));
			else if (*filter == "capitalized")  result = oo::utf8ToUtf16(oo::str::capitalized(oo::utf16ToUtf8(result)));
			else if (oo::str::hasPrefix(*filter, "truncFront:"))
			{
				result = SubstringToIndex(result, (unsigned long long)(NSUInteger)oo::str::intValue(oo::utf16ToUtf8(argument(11))));
			}
			else if (oo::str::hasPrefix(*filter, "truncBack:"))
			{
				result = SubstringToIndex(result, (unsigned long long)(NSUInteger)oo::str::intValue(oo::utf16ToUtf8(argument(10))));
			}
			else if (oo::str::hasPrefix(*filter, "subStringTo:"))
			{
				const std::u16string sub = argument(12);
				const std::size_t location = FindSubString(result, sub);
				if (location != std::u16string::npos)
				{
					result = result.substr(0, location);
				}
			}
			else if (oo::str::hasPrefix(*filter, "subStringFrom:"))
			{
				const std::u16string sub = argument(14);
				const std::size_t location = FindSubString(result, sub);
				if (location != std::u16string::npos)
				{
					result = result.substr(location + sub.size());
				}
			}
			else if (oo::str::hasPrefix(*filter, "subStringToInclusive:"))
			{
				const std::u16string sub = argument(21);
				const std::size_t location = FindSubString(result, sub);
				if (location != std::u16string::npos)
				{
					result = result.substr(0, location + sub.size());
				}
			}
			else if (oo::str::hasPrefix(*filter, "subStringFromInclusive:"))
			{
				const std::u16string sub = argument(23);
				const std::size_t location = FindSubString(result, sub);
				if (location != std::u16string::npos)
				{
					result = result.substr(location);
				}
			}
			else
			{
				*outError = ErrorWithProperty(kPListErrorSchemaUnknownFilter, &keyPath, kUnnownFilterErrorKey, filterValue, "Bad schema: unknown string filter specifier \"%s\".", filter->c_str());
			}
		}
		else
		{
			*outError = Error(kPListErrorSchemaUnknownFilter, &keyPath, "Bad schema: filter specifier is not a string.");
		}
	}

	return oo::utf16ToUtf8(result);
}


BOOL ApplyStringTest(const std::string &string, const oo::PList &test, StringTest stringTest, const char *testDescription, BackLinkChain keyPath, std::optional<OOPListSchemaVerifierError> *outError)
{
	oo::PList::Array		tests;

	assert(outError != NULL);

	if (!test)  return YES;

	if (test.isString())
	{
		tests.push_back(test);
	}
	else if (const oo::PList::Array *array = test.getIf<oo::PList::Array>())
	{
		tests = *array;
	}
	else
	{
		*outError = Error(kPListErrorSchemaBadComparator, &keyPath, "Bad schema: %s requirement specification is not a string or array.", testDescription);
		return NO;
	}

	for (const oo::PList &subTest : tests)
	{
		if (const std::string *subString = subTest.getIf<std::string>())
		{
			if (stringTest(string, *subString))  return YES;
		}
		else
		{
			*outError = Error(kPListErrorSchemaBadComparator, &keyPath, "Bad schema: required %s is not a string.", testDescription);
			return NO;
		}
	}
	return NO;
}

} // namespace


namespace {

oo::PList KeyPathToArray(BackLinkChain keyPath)
{
	oo::PList::Array		result;
	BackLinkChain			*curr = NULL;

	for (curr = &keyPath; curr != NULL; curr = curr->link)
	{
		// Keys as strings, indices as signed integers (+numberWithInteger:).
		if (curr->key != nullptr)  result.insert(result.begin(), oo::PList(*curr->key));
		else if (curr->isIndex)  result.insert(result.begin(), oo::PList(static_cast<std::int64_t>(curr->index)));
	}

	return oo::PList(std::move(result));
}


std::string KeyPathToString(BackLinkChain keyPath)
{
	return OOPListSchemaVerifier::descriptionForKeyPath(KeyPathToArray(keyPath)).value_or("(null)");	// %@ of nil
}

} // namespace


namespace {

std::string StringForErrorReport(const std::string &string)
{
	std::u16string			units = oo::utf8ToUtf16(string);

	if (kMaximumLengthForStringInErrorMessage < units.size())
	{
		units.resize(kMaximumLengthForStringInErrorMessage);
	}

	/*	Each replacement searched only the first [string length] units of the result, as the
		mutable string's -replaceOccurrencesOfString:...range:NSMakeRange(0, [string length]) did
		after the tabs had lengthened it; the rest passes through unchanged.
	*/
	const std::size_t limit = units.size();
	std::u16string result = units;
	auto replaceWithinLimit = [&](const char *target, const char *replacement)
	{
		const std::size_t head = std::min(limit, result.size());
		const std::string replaced = oo::str::replaceOccurrences(oo::utf16ToUtf8(result.substr(0, head)), target, replacement);
		result = oo::utf8ToUtf16(replaced) + result.substr(head);
	};
	replaceWithinLimit("\t", "    ");
	replaceWithinLimit("\r\n", " \\ ");
	replaceWithinLimit("\n", " \\ ");
	replaceWithinLimit("\r", " \\ ");

	if (kMaximumLengthForStringInErrorMessage < result.size())
	{
		result.resize(kMaximumLengthForStringInErrorMessage - 3);
		result += u"...";
	}

	return oo::utf16ToUtf8(result);
}


// What %@ printed for an element of an array: a string as itself, a number as -stringValue,
// anything else as its description.
std::string ElementDescription(const oo::PList &element)
{
	if (const std::string *string = element.getIf<std::string>())  return *string;
	if (element.isNumber())  return oo::plist_get::numberStringValue(element);
	return oo::DescriptionOf(element);
}


std::string ArrayForErrorReport(const oo::PList &array)
{
	const oo::PList::Array	*elements = array.getIf<oo::PList::Array>();
	std::string				result;
	std::string				string;
	NSUInteger				i, count;

	count = (elements != nullptr) ? elements->size() : 0;
	if (count == 0)  return "( )";

	result = "(" + ElementDescription((*elements)[0]);

	for (i = 1; i != count; ++i)
	{
		string = result + ", " + ElementDescription((*elements)[i]);
		if (kMaximumLengthForStringInErrorMessage < oo::str::length(string))
		{
			result += ", ...";
			break;
		}
		result = string;
	}

	result += ")";

	return result;
}


std::string SetForErrorReport(std::vector<std::string> strings)
{
	std::stable_sort(strings.begin(), strings.end(), [](const std::string &a, const std::string &b) { return oo::str::caseInsensitiveCompare(a, b) < 0; });
	oo::PList::Array array;
	for (std::string &string : strings)  array.emplace_back(std::move(string));
	return ArrayForErrorReport(oo::PList(std::move(array)));
}

} // namespace


namespace {

std::string StringOrArrayForErrorReport(const oo::PList &value, const char *arrayPrefix)
{
	if (const std::string *string = value.getIf<std::string>())
	{
		return "\"" + StringForErrorReport(*string) + "\"";
	}

	const std::string prefix = (arrayPrefix != NULL) ? arrayPrefix : "";
	if (value.isArray())
	{
		return prefix + ArrayForErrorReport(value);
	}
	if (!value)  return "(null)";
	return "<?>";
}

} // namespace


// Specific type verifiers

// The leaves' type test, on the PList kind (isString & co.).
#define REQUIRE_PLIST_TYPE(KINDTEST, NAMESTRING)	 do { \
		if (!value.KINDTEST()) \
		{ \
			return ErrorTypeMismatch(NAMESTRING, value, keyPath); \
		} \
	} while (0)

namespace {

static std::optional<OOPListSchemaVerifierError> Verify_String(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &params, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	std::string			filteredString;
	const oo::PList		*testValue = nullptr;
	NSUInteger			length;
	NSUInteger			lengthConstraint;
	std::optional<OOPListSchemaVerifierError> error;

	REQUIRE_PLIST_TYPE(isString, "string");
	const std::string	&stringValue = *value.getIf<std::string>();

	DebugDump("* string: \"{}\"", StringForErrorReport(stringValue));

	// Apply filters
	const oo::PList *filter = params.find("filter");
	filteredString = ApplyStringFilter(stringValue, (filter != nullptr) ? *filter : oo::PList(), keyPath, &error);

	// Apply substring requirements
	testValue = params.find("requiredPrefix");
	if (testValue != nullptr)
	{
		if (!ApplyStringTest(filteredString, *testValue, [](const std::string &s, const std::string &t) { return oo::str::hasPrefix(s, t); }, "prefix", keyPath, &error))
		{
			if (!error.has_value())  error = ErrorWithProperty(kPListErrorStringPrefixMissing, &keyPath, kMissingSubStringErrorKey, *testValue, "String \"%s\" does not have required %s %s.", StringForErrorReport(stringValue).c_str(), "prefix", StringOrArrayForErrorReport(*testValue, "in ").c_str());
			return error;
		}
	}

	testValue = params.find("requiredSuffix");
	if (testValue != nullptr)
	{
		if (!ApplyStringTest(filteredString, *testValue, [](const std::string &s, const std::string &t) { return oo::str::hasSuffix(s, t); }, "suffix", keyPath, &error))
		{
			if (!error.has_value())  error = ErrorWithProperty(kPListErrorStringSuffixMissing, &keyPath, kMissingSubStringErrorKey, *testValue, "String \"%s\" does not have required %s %s.", StringForErrorReport(stringValue).c_str(), "suffix", StringOrArrayForErrorReport(*testValue, "in ").c_str());
			return error;
		}
	}

	testValue = params.find("requiredSubString");
	if (testValue != nullptr)
	{
		if (!ApplyStringTest(filteredString, *testValue, HasSubString, "substring", keyPath, &error))
		{
			if (!error.has_value())  error = ErrorWithProperty(kPListErrorStringSubstringMissing, &keyPath, kMissingSubStringErrorKey, *testValue, "String \"%s\" does not have required %s %s.", StringForErrorReport(stringValue).c_str(), "substring", StringOrArrayForErrorReport(*testValue, "in ").c_str());
			return error;
		}
	}

	// Apply length bounds (UTF-16 units, as -length counted them).
	length = oo::str::length(filteredString);
	lengthConstraint = params.get<NSUInteger>("minLength");
	if (length < lengthConstraint)
	{
		return  Error(kPListErrorMinimumConstraintNotMet, &keyPath, "String \"%s\" is too short (%u bytes, minimum is %u).", StringForErrorReport(filteredString).c_str(), length, lengthConstraint);
	}

	lengthConstraint = params.get<NSUInteger>("maxLength", NSUIntegerMax);
	if (lengthConstraint < length)
	{
		return  Error(kPListErrorMaximumConstraintNotMet, &keyPath, "String \"%s\" is too long (%u bytes, maximum is %u).", StringForErrorReport(filteredString).c_str(), length, lengthConstraint);
	}

	// All tests passed.
	return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Array(OOPListSchemaVerifier *verifier, const oo::PList &value, const oo::PList &params, const oo::PList &rootPList, const std::string &name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	const oo::PList			*valueType = nullptr;
	BOOL					OK = YES, stop = NO;
	NSUInteger				i, count;
	NSUInteger				constraint;

	REQUIRE_PLIST_TYPE(isArray, "array");
	const oo::PList::Array	&elements = *value.getIf<oo::PList::Array>();

	DebugDump("{}", "* array");

	// Apply count bounds.
	count = elements.size();
	constraint = params.get<NSUInteger>("minCount", 0);
	if (count < constraint)
	{
		return  Error(kPListErrorMinimumConstraintNotMet, &keyPath, "Array has too few members (%u, minimum is %u).", count, constraint);
	}

	constraint = params.get<NSUInteger>("maxCount", NSUIntegerMax);
	if (constraint < count)
	{
		return  Error(kPListErrorMaximumConstraintNotMet, &keyPath, "Array has too many members (%u, maximum is %u).", count, constraint);
	}

	// Test member objects.
	valueType = params.find("valueType");
	if (valueType != nullptr)
	{
		for (i = 0; i != count; ++i)
		{
			if (!verifier->verifyPList(rootPList, name, elements[i], *valueType, BackLinkIndex(&keyPath, i), tentative, nullptr, &stop))
			{
				OK = NO;
			}

			if ((stop && !tentative) || (tentative && !OK))  break;
		}
	}

	*outStop = stop && !tentative;

	if (!OK)  return ErrorFailureAlreadyReported();
	else  return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Dictionary(OOPListSchemaVerifier *verifier, const oo::PList &value, const oo::PList &params, const oo::PList &rootPList, const std::string &name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	const oo::PList			*schema = nullptr;
	const oo::PList			*valueType = nullptr,
							*typeSpec = nullptr;
	BOOL					OK = YES, stop = NO, prematureExit = NO;
	BOOL					allowOthers;
	std::set<std::string>	requiredKeys;
	const oo::PList			*requiredKeyList = nullptr;
	NSUInteger				count, constraint;

	REQUIRE_PLIST_TYPE(isDict, "dictionary");
	const oo::PList::Dict	&members = *value.getIf<oo::PList::Dict>();

	DebugDump("{}", "* dictionary");

	// Apply count bounds.
	count = members.size();
	constraint = params.get<NSUInteger>("minCount", 0);
	if (count < constraint)
	{
		return  Error(kPListErrorMinimumConstraintNotMet, &keyPath, "Dictionary has too few pairs (%u, minimum is %u).", count, constraint);
	}
	constraint = params.get<NSUInteger>("maxCount", NSUIntegerMax);
	if (constraint < count)
	{
		return  Error(kPListErrorMaximumConstraintNotMet, &keyPath, "Dictionary has too manu pairs (%u, maximum is %u).", count, constraint);
	}

	// Get schema.
	schema = params.get<oo::PList::Dict>("schema");
	valueType = params.find("valueType");
	allowOthers = params.get<BOOL>("allowOthers", YES);
	requiredKeyList = params.get<oo::PList::Array>("requiredKeys");

	// If these conditions are met, all members must pass:
	if (schema == nullptr && valueType == nullptr && requiredKeyList == nullptr && allowOthers)  return std::nullopt;

	if (requiredKeyList != nullptr)
	{
		for (const oo::PList &requiredKey : *requiredKeyList->getIf<oo::PList::Array>())
		{
			if (const std::string *keyString = requiredKey.getIf<std::string>())  requiredKeys.insert(*keyString);
		}
	}

	DebugDumpIndent();

	// Test member objects, in byte order of the key (the dictionary enumerated in hash order).
	for (const auto &[key, subProperty] : members)
	{
		if (stop)  break;
		typeSpec = (schema != nullptr) ? schema->find(key) : nullptr;
		if (typeSpec == nullptr)  typeSpec = valueType;

		DebugDump("- \"{}\"", key);
		DebugDumpIndent();

		if (typeSpec != nullptr)
		{
			if (!verifier->verifyPList(rootPList, name, subProperty, *typeSpec, BackLink(&keyPath, &key), tentative, nullptr, &stop))
			{
				OK = NO;
			}
		}
		else if (!allowOthers && requiredKeys.count(key) == 0 && (schema == nullptr || schema->find(key) == nullptr))
		{
			// Report error now rather than returning it, since there may be several unknown keys.
			if (!tentative)
			{
				const OOPListSchemaVerifierError error = ErrorWithProperty(kPListErrorDictionaryUnknownKey, &keyPath, kUnknownKeyErrorKey, oo::PList(key), "Unpermitted key \"%s\" in dictionary.", StringForErrorReport(key).c_str());
				stop = !verifier->delegateVerifierWithPropertyList(rootPList, name, value, error, params);
			}
			OK = NO;
		}

		DebugDumpOutdent();

		requiredKeys.erase(key);

		if ((stop && !tentative) || (tentative && !OK))
		{
			prematureExit = YES;
			break;
		}
	}

	DebugDumpOutdent();

	// Check that all required keys were present.
	if (!prematureExit && !requiredKeys.empty())
	{
		const std::vector<std::string> missing(requiredKeys.begin(), requiredKeys.end());
		return ErrorWithProperty(kPListErrorDictionaryMissingRequiredKeys, &keyPath, kMissingRequiredKeysErrorKey, oo::PList(oo::PList::Array(missing.begin(), missing.end())), "Required keys %s missing from dictionary.", SetForErrorReport(missing).c_str());
	}

	*outStop = stop && !tentative;

	if (!OK)  return ErrorFailureAlreadyReported();
	else  return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Integer(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &params, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	long long				numericValue;
	long long				constraint;

	// OOLongLongFromObject(value, d): d for nil and for what cannot be read.
	numericValue = oo::plist_get::longLongFrom(&value, 0);

	DebugDump("* integer: {}", numericValue);

	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != oo::plist_get::longLongFrom(&value, 1))
	{
		return ErrorTypeMismatch("integer", value, keyPath);
	}

	// Check constraints.
	constraint = params.get<long long>("minimum", LLONG_MIN);
	if (numericValue < constraint)
	{
		return  Error(kPListErrorMinimumConstraintNotMet, &keyPath, "Number is too small (%lli, minimum is %lli).", numericValue, constraint);
	}

	constraint = params.get<long long>("maximum", LLONG_MAX);
	if (constraint < numericValue)
	{
		return  Error(kPListErrorMaximumConstraintNotMet, &keyPath, "Number is too large (%lli, maximum is %lli).", numericValue, constraint);
	}

	return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_PositiveInteger(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &params, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	unsigned long long		numericValue;
	unsigned long long		constraint;

	numericValue = oo::plist_get::unsignedLongLongFrom(&value, 0);

	DebugDump("* positive integer: {}", numericValue);

	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != oo::plist_get::unsignedLongLongFrom(&value, 1))
	{
		return ErrorTypeMismatch("positive integer", value, keyPath);
	}

	// Check constraints.
	constraint = params.get<unsigned long long>("minimum", 0);
	if (numericValue < constraint)
	{
		return  Error(kPListErrorMinimumConstraintNotMet, &keyPath, "Number is too small (%zu, minimum is %zu).", numericValue, constraint);
	}

	constraint = params.get<unsigned long long>("maximum", ULLONG_MAX);
	if (constraint < numericValue)
	{
		return  Error(kPListErrorMaximumConstraintNotMet, &keyPath, "Number is too large (%zu, maximum is %zu).", numericValue, constraint);
	}

	return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Float(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &params, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	double					numericValue;
	double					constraint;

	// OODoubleFromObject(value, d).
	numericValue = oo::plist_get::realFrom<double>(&value, 0);

	DebugDump("* float: {:g}", numericValue);

	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != oo::plist_get::realFrom<double>(&value, 1))
	{
		return ErrorTypeMismatch("number", value, keyPath);
	}

	// Check constraints.
	constraint = params.get<double>("minimum", -INFINITY);
	if (numericValue < constraint)
	{
		return  Error(kPListErrorMinimumConstraintNotMet, &keyPath, "Number is too small (%g, minimum is %g).", numericValue, constraint);
	}

	constraint = params.get<double>("maximum", INFINITY);
	if (constraint < numericValue)
	{
		return  Error(kPListErrorMaximumConstraintNotMet, &keyPath, "Number is too large (%g, maximum is %g).", numericValue, constraint);
	}

	return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_PositiveFloat(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &params, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	double					numericValue;
	double					constraint;

	// OODoubleFromObject(value, d).
	numericValue = oo::plist_get::realFrom<double>(&value, 0);

	DebugDump("* positive float: {:g}", numericValue);

	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (numericValue != oo::plist_get::realFrom<double>(&value, 1))
	{
		return ErrorTypeMismatch("positive number", value, keyPath);
	}

	if (numericValue < 0)
	{
		return Error(kPListErrorNumberIsNegative, &keyPath, "Expected non-negative number, found %g.", numericValue);
	}

	// Check constraints.
	constraint = params.get<double>("minimum", 0);
	if (numericValue < constraint)
	{
		return  Error(kPListErrorMinimumConstraintNotMet, &keyPath, "Number is too small (%g, minimum is %g).", numericValue, constraint);
	}

	constraint = params.get<double>("maximum", INFINITY);
	if (constraint < numericValue)
	{
		return  Error(kPListErrorMaximumConstraintNotMet, &keyPath, "Number is too large (%g, maximum is %g).", numericValue, constraint);
	}

	return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_OneOf(OOPListSchemaVerifier *verifier, const oo::PList &value, const oo::PList &params, const oo::PList &rootPList, const std::string &name, BackLinkChain keyPath, BOOL /*tentative*/, BOOL *outStop)
{
	const oo::PList			*options = nullptr;
	BOOL					OK = NO, stop = NO;
	std::optional<OOPListSchemaVerifierError> error;
	oo::PList::Dict			errors;

	DebugDump("{}", "* oneOf");

	options = params.get<oo::PList::Array>("options");
	if (options == nullptr)
	{
		*outStop = YES;
		return Error(kPListErrorSchemaNoOneOfOptions, &keyPath, "Bad schema: no options specified for oneOf type.");
	}

	for (const oo::PList &option : *options->getIf<oo::PList::Array>())
	{
		if (verifier->verifyPList(rootPList, name, value, option, keyPath, YES, &error, &stop))
		{
			DebugDump("{}", "> Match.");
			OK = YES;
			break;
		}
		// Keyed by the option's %@ text (the option itself, a string or a dictionary, was the key).
		errors[oo::DescriptionOf(option)] = error.has_value() ? PListFromError(*error) : oo::PList();
	}

	if (!OK)
	{
		DebugDump("{}", "! No match.");
		return ErrorWithProperty(kPListErrorOneOfNoMatch, &keyPath, kErrorsByOptionErrorKey, oo::PList(std::move(errors)), "No matching type rule could be found.");
	}

	// Ignore stop in tentatives.
	return std::nullopt;
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Enumeration(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &params, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL *outStop)
{
	const oo::PList			*values = nullptr;
	std::string				filteredString;
	std::optional<OOPListSchemaVerifierError> error;

	DebugDump("{}", "* enumeration");

	REQUIRE_PLIST_TYPE(isString, "string");
	const std::string		&stringValue = *value.getIf<std::string>();

	values = params.get<oo::PList::Array>("values");
	DebugDump("  - \"{}\" in {}", StringForErrorReport(stringValue), ArrayForErrorReport((values != nullptr) ? *values : oo::PList()));

	if (values == nullptr)
	{
		*outStop = YES;
		return Error(kPListErrorSchemaNoEnumerationValues, &keyPath, "Bad schema: no options specified for oneOf type.");
	}

	const oo::PList *filter = params.find("filter");
	filteredString = ApplyStringFilter(stringValue, (filter != nullptr) ? *filter : oo::PList(), keyPath, &error);

	// -containsObject: (-isEqual: of a string is a unit-for-unit comparison).
	for (const oo::PList &permitted : *values->getIf<oo::PList::Array>())
	{
		if (const std::string *permittedString = permitted.getIf<std::string>(); permittedString != nullptr && *permittedString == filteredString)  return std::nullopt;
	}

	return Error(kPListErrorEnumerationBadValue, &keyPath, "Value \"%s\" not recognized, should be one of %s.", StringForErrorReport(stringValue).c_str(), ArrayForErrorReport(*values).c_str());
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Boolean(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &/*params*/, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	DebugDump("* boolean: {}", oo::DescriptionOf(value));

	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (oo::plist_get::boolFrom(&value, false) == oo::plist_get::boolFrom(&value, true))  return std::nullopt;
	else  return ErrorTypeMismatch("boolean", value, keyPath);
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_FuzzyBoolean(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &/*params*/, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	DebugDump("* fuzzy boolean: {}", oo::DescriptionOf(value));

	// Check basic parseability. If there's inequality here, the default value is being returned.
	if (oo::plist_get::realFrom<double>(&value, 0) == oo::plist_get::realFrom<double>(&value, 1) ||
		oo::plist_get::boolFrom(&value, false) == oo::plist_get::boolFrom(&value, true))  return std::nullopt;
	else  return ErrorTypeMismatch("fuzzy boolean", value, keyPath);
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Vector(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &/*params*/, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	DebugDump("* vector: {}", oo::DescriptionOf(value));

	// Check basic parseability. If there's inequality here, the default value is being returned.
	// OOVectorFromObject is not migrated: it reads the same object.
	if (vector_equal(OOVectorFromPList(&value, kZeroVector), OOVectorFromPList(&value, kBasisXVector)))  return std::nullopt;
	else  return ErrorTypeMismatch("vector", value, keyPath);
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_Quaternion(OOPListSchemaVerifier * /*verifier*/, const oo::PList &value, const oo::PList &/*params*/, const oo::PList & /*rootPList*/, const std::string & /*name*/, BackLinkChain keyPath, BOOL /*tentative*/, BOOL */*outStop*/)
{
	DebugDump("* quaternion: {}", oo::DescriptionOf(value));

	// Check basic parseability. If there's inequality here, the default value is being returned.
	// OOQuaternionFromObject is not migrated: it reads the same object.
	if (quaternion_equal(OOQuaternionFromPList(&value, kZeroQuaternion), OOQuaternionFromPList(&value, kIdentityQuaternion)))  return std::nullopt;
	else  return ErrorTypeMismatch("quaternion", value, keyPath);
}

} // namespace


namespace {

static std::optional<OOPListSchemaVerifierError> Verify_DelegatedType(OOPListSchemaVerifier *verifier, const oo::PList &value, const oo::PList &params, const oo::PList &rootPList, const std::string &name, BackLinkChain keyPath, BOOL tentative, BOOL *outStop)
{
	const oo::PList			*baseType = nullptr;
	BOOL					stop = NO;
	std::optional<OOPListSchemaVerifierError> error;

	const oo::PList			*keyValue = params.find("key");
	const oo::PList			key = (keyValue != nullptr) ? *keyValue : oo::PList();

	DebugDump("* delegated type: {}", oo::DescriptionOf(key));

	baseType = params.find("baseType");
	if (baseType != nullptr)
	{
		if (!verifier->verifyPList(rootPList, name, value, *baseType, keyPath, tentative, nullptr, &stop))
		{
			*outStop = stop;
			return std::nullopt;
		}
	}

	*outStop = !verifier->delegateVerifierWithPropertyList(rootPList, name, value, keyPath, key, &error);
	return error;
}

} // namespace


namespace {

OOPListSchemaVerifierError Error(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const char *format, ...)
{
	OOPListSchemaVerifierError	result;
	va_list				args;

	va_start(args, format);
	result = ErrorWithDictionaryAndArguments(errorCode, keyPath, oo::PList(), format, args);
	va_end(args);

	return result;
}


OOPListSchemaVerifierError ErrorWithProperty(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const std::string &propKey, const oo::PList &propValue, const char *format, ...)
{
	OOPListSchemaVerifierError	result;
	va_list				args;
	oo::PList			dict;

	if (propValue)
	{
		dict = oo::PList(oo::PList::Dict{ { propKey, propValue } });
	}
	va_start(args, format);
	result = ErrorWithDictionaryAndArguments(errorCode, keyPath, dict, format, args);
	va_end(args);

	return result;
}


OOPListSchemaVerifierError ErrorWithDictionary(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const oo::PList &dict, const char *format, ...)
{
	OOPListSchemaVerifierError	result;
	va_list				args;

	va_start(args, format);
	result = ErrorWithDictionaryAndArguments(errorCode, keyPath, dict, format, args);
	va_end(args);

	return result;
}


OOPListSchemaVerifierError ErrorWithDictionaryAndArguments(OOPListSchemaVerifierErrorCode errorCode, BackLinkChain *keyPath, const oo::PList &dict, const char *format, va_list arguments)
{
	oo::PList::Dict		userInfo;

	if (const oo::PList::Dict *entries = dict.getIf<oo::PList::Dict>())  userInfo = *entries;
	if (keyPath != NULL)
	{
		userInfo[kPListKeyPathErrorKey] = KeyPathToArray(*keyPath);
	}

	return OOPListSchemaVerifierError{ kOOPListSchemaVerifierErrorDomain, errorCode, oo::str::vformat(format, arguments), oo::PList(std::move(userInfo)) };
}


OOPListSchemaVerifierError ErrorTypeMismatch(const char *expectedClassName, const oo::PList &actual, BackLinkChain keyPath)
{
	oo::PList::Dict		dict;
	std::string			className;

	// The expected kind's name only: the expected class (kExpectedClassErrorKey) is no longer
	// recorded (nothing outside this file read it; the retiring -expectedClass did).
	dict[kExpectedClassNameErrorKey] = oo::PList(expectedClassName);

	switch (actual.type())
	{
		case oo::PList::Type::Null:		className = "nothing";  break;
		case oo::PList::Type::String:	className = "string";  break;
		case oo::PList::Type::Bool:
		case oo::PList::Type::Integer:
		case oo::PList::Type::Real:		className = "number";  break;
		case oo::PList::Type::Array:	className = "array";  break;
		case oo::PList::Type::Dict:		className = "dictionary";  break;
		case oo::PList::Type::Data:		className = "data";  break;
		case oo::PList::Type::Date:		className = "date";  break;
		case oo::PList::Type::Object:	className = "(null)";  break;	// any other object: its class's name, nil's for a node with no Objective-C object (none is made since bead oo-4aq6a.5)
	}

	return ErrorWithDictionary(kPListErrorTypeMismatch, &keyPath, oo::PList(std::move(dict)), "Expected %s, found %s.", expectedClassName, className.c_str());
}


OOPListSchemaVerifierError ErrorFailureAlreadyReported(void)
{
	return OOPListSchemaVerifierError{ kOOPListSchemaVerifierErrorDomain, kPListErrorFailedAndErrorHasBeenReported, std::nullopt, oo::PList() };
}


BOOL IsFailureAlreadyReportedError(const OOPListSchemaVerifierError &error)
{
	return error.domain == kOOPListSchemaVerifierErrorDomain && error.code == kPListErrorFailedAndErrorHasBeenReported;
}

} // namespace

#endif	// OO_OXP_VERIFIER_ENABLED
