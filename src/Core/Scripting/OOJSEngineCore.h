/*

OOJSEngineCore.h

The plain C++ part of the JavaScript engine API, split verbatim out of OOJavaScriptEngine.h (bead
oo-9ht.72): context acquisition, error reporters, argument helpers, the value/PList/string
converters, subclass and converter registration, GC root macros, the native wrappers and the
OOJS_* property flags and return macros. Nothing here declares an Objective-C class, so a
binding translation unit that is C++ (not Objective-C++) includes this header instead of
OOJavaScriptEngine.h, which includes it back. id, Class and BOOL are libobjc2's C types.
OOJS_RETURN returns true and OOJS_RETURN_WITH_HELPER keeps its result in a bool (they were YES
and BOOL; natives return bool).

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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

*/

#ifndef INCLUDED_OOJSENGINECORE_h
#define INCLUDED_OOJSENGINECORE_h

#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOFoundationTypes.h"
#include "oofnd/objc/OOAssert.h"
#include "OOFunctionAttributes.h"
#include "OOJSPropID.h"

#include <cstdarg>


#ifdef __cplusplus
#define OOJS_EXTERN_C extern "C"
#else
#define OOJS_EXTERN_C
#endif


// Get the main thread's JS context, and begin a request on it.
OOINLINE ooscript::Context OOJSAcquireContext(void)
{
	extern ooscript::Context gOOJSMainThreadContext;
	OOCAssert(gOOJSMainThreadContext != NULL, "Attempt to use JavaScript context before JavaScript engine is initialized.");
	ooscript::beginRequest(gOOJSMainThreadContext);
	return gOOJSMainThreadContext;
}


// End a request on the main thread's context.
OOINLINE void OOJSRelinquishContext(ooscript::Context context)
{
#ifndef NDEBUG
	extern ooscript::Context gOOJSMainThreadContext;
	OOCParameterAssert(context == gOOJSMainThreadContext && ooscript::isInRequest(context));
#endif
	ooscript::endRequest(context);
}


/*	Notifications sent when JavaScript engine is reset, on oo::NotificationCenter
	(oofnd/Notification.hpp, bead oo-3rb.9), posted with the engine as the object: will-reset
	before the context is destroyed, did-reset after it is recreated.
*/
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
extern const char * const kOOJavaScriptEngineDidResetNotificationName;


/*	Error and warning reporters.
	
	Note that after reporting an error in a JavaScript callback, the caller
	must return NO to signal an error.
	The cxx_ forms (proposed ADR-0043 item 17's pattern; bead oo-3rb.200) take printf formats
	(no %@: pass an object's text as %s with oo::DescriptionOf), formatted by oo::str::vformat.
	A nullopt function means no caller prefix; a nullopt scriptClass prefixes "function: ".
	Plain C++, not OOJS_EXTERN_C.
*/
void cxx_OOJSReportError(ooscript::Context context, const char *format, ...) OO_PRINTF_FORMAT(2, 3);
void cxx_OOJSReportErrorWithArguments(ooscript::Context context, const char *format, va_list args) OO_PRINTF_FORMAT(2, 0);
void cxx_OOJSReportErrorForCaller(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...) OO_PRINTF_FORMAT(4, 5);

void cxx_OOJSReportWarning(ooscript::Context context, const char *format, ...) OO_PRINTF_FORMAT(2, 3);
void cxx_OOJSReportWarningWithArguments(ooscript::Context context, const char *format, va_list args) OO_PRINTF_FORMAT(2, 0);
void cxx_OOJSReportWarningForCaller(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...) OO_PRINTF_FORMAT(4, 5);

OOJS_EXTERN_C void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object thisObj, ooscript::PropertyId propID, ooscript::PropertySpec *propertySpec);
OOJS_EXTERN_C void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object thisObj, ooscript::PropertyId propID, ooscript::PropertySpec *propertySpec, ooscript::Value value);
// A nullopt message is "Invalid arguments"; a nullopt expectedArgsDescription adds no " -- expected ..." suffix.
void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription);

/*	OOJSSetWarningOrErrorStackSkip()
	
	Indicate that the direct call site is not relevant for error handler.
	Currently, if non-zero, no call site information is provided.
	Ideally, we'd stack crawl instead.
*/
OOJS_EXTERN_C void OOJSSetWarningOrErrorStackSkip(unsigned skip);


/*	cxx_OOJSArgumentListGetNumber()
	
	Get a single number from an argument list. The optional outConsumed
	argument can be used to find out how many parameters were used (currently,
	this will be 0 on failure, otherwise 1).
	
	On failure, it will return NO and raise an error. If the caller is a JS
	callback, it must return NO to signal an error.
*/
BOOL cxx_OOJSArgumentListGetNumber(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed);

/*	OOJSArgumentListGetNumberNoError()
	
	Like cxx_OOJSArgumentListGetNumber(), but does not report an error on failure.
*/
OOJS_EXTERN_C BOOL OOJSArgumentListGetNumberNoError(ooscript::Context context, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed);


// Typed as int rather than BOOL to work with more general expressions such as bitfield tests.
OOINLINE ooscript::Value OOJSValueFromBOOL(int b) INLINE_CONST_FUNC;
OOINLINE ooscript::Value OOJSValueFromBOOL(int b)
{
	return ooscript::booleanValue(b != NO);
}


/*	(OOJSValueFromNativeObject(), the JS value of an Objective-C object, and OOJSObjectFromNativeObject()
	went with bead oo-4aq6a.6.2: no game object is an Objective-C object. Plist data is
	OOJSValueFromPList()'s.)
*/


/*	OOJSValueFromPList()
	Return the JavaScript value representation of a property list, exactly as
	OOJSValueFromNativeObject(context, oo::ObjectFromPList(plist)) gave it
	(proposed ADR-0051): null for a null PList; a bool as the number 1 or 0; an
	integer as an int32 when it fits, else a double; a real as a double (a
	single-precision one as the double of its float); a string as a string;
	data and dates undefined; an array as an Array and a dictionary as an
	Object (null elements and values dropped, empty keys skipped, key order);
	a PList::Object node as its C++ object's JS glue (OOJSValueFromNativeObject() of its
	object until bead oo-4aq6a.6.2).
	
	Requires a request on context.
*/
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist);




/**** String utilities ****/

/*	OOJSSTR(const char * [literal])
	
	Create and cache a ooscript::Value referring to an interned string literal.
*/
#define OOJSSTR(str) ({ static ooscript::Value strCache; static BOOL inited; if (EXPECT_NOT(!inited)) OOJSStrLiteralCachePRIVATE("" str, &strCache, &inited); strCache; })
OOJS_EXTERN_C void OOJSStrLiteralCachePRIVATE(const char *string, ooscript::Value *strCache, BOOL *inited);


/*	The JS-to-string converters (proposed ADR-0043; bead oo-3rb.198). Each returns
	std::nullopt where the Foundation form it replaces returned nil. Plain C++ (not
	OOJS_EXTERN_C): a C-linkage function cannot return std::optional.
*/

// Convert a JSString to a UTF-8 string (nullopt for a NULL string or no characters).
std::optional<std::string> cxx_OOStringFromJSString(ooscript::Context context, ooscript::String string);

/*	Convert an arbitrary JS object to a string, calling ooscript::valueToString.
	cxx_OOStringFromJSValue() returns nullopt if value is null or undefined,
	cxx_OOStringFromJSValueEvenIfNull() returns "null" or "undefined".
*/
std::optional<std::string> cxx_OOStringFromJSValue(ooscript::Context context, ooscript::Value value);
std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(ooscript::Context context, ooscript::Value value);


/*	cxx_OOStringFromJSPropertyIDAndSpec(context, propID, propertySpec)
	
	Returns the name of a property given either a name or a tinyid. (Intended
	for error reporting inside JSPropertyOps.)
*/
std::optional<std::string> cxx_OOStringFromJSPropertyIDAndSpec(ooscript::Context context, ooscript::PropertyId propID, ooscript::PropertySpec *propertySpec);


/*	Describe a value for debugging or error reporting. Strings are quoted,
	escaped and limited in length. Functions are described as "function foo"
	(or just "function" if they're anonymous). Up to four elements of arrays
	are included, followed by total count of there are more than four.
	If abbreviateObjects, the description "[object Object]" is replaced with
	"{...}", which may or may not be clearer depending on context. Never empty of meaning:
	the last fallback is "?".
*/
std::string cxx_OOJSDescribeValue(ooscript::Context context, ooscript::Value value, BOOL abbreviateObjects);


// Convert a ooscript::PropertyId to a UTF-8 string (nullopt if it has no string value).
std::optional<std::string> cxx_OOStringFromJSID(ooscript::PropertyId propID);

// Convert a UTF-8 string to a ooscript::PropertyId.
ooscript::PropertyId cxx_OOJSIDFromString(const std::string &string);


/*	The string helpers of the retired string category (OOJavaScriptExtensions) (bead oo-3rb.199).
	Each std::optional result is nullopt where the category method returned nil.
*/

// For diagnostic messages; produces things like "(42, true, "a string", an object description)".
// nullopt if params is NULL and count is not zero.
std::optional<std::string> cxx_OOJSStringWithJavaScriptParameters(ooscript::Value *params, unsigned count, ooscript::Context context);

// Concatenate sequence of arbitrary JS objects into string (nullopt if count < 1 or values is NULL).
std::optional<std::string> cxx_OOJSConcatenationOfStringsFromJavaScriptValues(ooscript::Value *values, size_t count, const std::string &separator, ooscript::Context context);

// Add escape codes for string so that it's a valid JavaScript literal (if you put "" or '' around it).
std::string cxx_OOJSEscapedForJavaScriptLiteral(std::string_view string);


/*	cxx_OOJSPListFromJSValue(context, value) / cxx_OOJSPListFromJSObject(context, object)
	The oo::PList form of the native-object family: exactly what oo::PListFrom()
	made of OOJSNativeObjectFromJSValue()'s result (proposed ADR-0051): null for
	null, undefined or an unconvertible value; int32 -> signed integer, double
	-> real, boolean -> bool, string -> string; a JS Array -> array (a null or
	undefined element -> a PList::Object holding [OONull null]); a plain Object
	-> dictionary (see cxx_OOJSDictionaryFromJSObject()); an object of a class
	with a registered converter -> oo::PListFrom() of what the converter
	returns (a private object -> a PList::Object node holding it). The id
	functions that returned the Objective-C object of such a node
	(OOJSNativeObjectFromJSValue/FromJSObject and their OfClass forms) are
	deleted (bead oo-4aq6a.6): no slot holds an Objective-C object.
	
	These require a request on context.
*/
oo::PList cxx_OOJSPListFromJSValue(ooscript::Context context, ooscript::Value value);
oo::PList cxx_OOJSPListFromJSObject(ooscript::Context context, ooscript::Object object);


OOINLINE ooscript::ClassDef *OOJSGetClass(ooscript::Context cx, ooscript::Object obj)  ALWAYS_INLINE_FUNC;
OOINLINE ooscript::ClassDef *OOJSGetClass(ooscript::Context cx, ooscript::Object obj)
{
	return const_cast<ooscript::ClassDef *>(ooscript::getObjectClass(cx, obj));
}


/*	OOJSValueIsFunction(context, value)
	
	Test whether a ooscript::Value is a function object. The main tripping point here
	is that ooscript::isObjectOrNull() is true for ooscript::nullValue(), but ooscript::objectIsFunction()
	crashes if passed null.
*/
OOINLINE BOOL OOJSValueIsFunction(ooscript::Context context, ooscript::Value value)
{
	return ooscript::isObjectOrNull(value) && !ooscript::isNull(value) && ooscript::objectIsFunction(context, ooscript::toObject(value));
}


/*	OOJSValueIsArray(context, value)
	
	Test whether a ooscript::Value is an array object. The main tripping point here
	is that ooscript::isObjectOrNull() is true for ooscript::nullValue(), but ooscript::isArrayObject()
	crashes if passed null.
	
*/
OOINLINE BOOL OOJSValueIsArray(ooscript::Context context, ooscript::Value value)
{
	return ooscript::isObjectOrNull(value) && !ooscript::isNull(value) && ooscript::isArrayObject(context, ooscript::toObject(value));
}


/*	OOJSDictionaryFromJSValue(context, value)
	cxx_OOJSDictionaryFromJSObject(context, object)

	Converts a JavaScript value to a dictionary by calling
	cxx_OOJSPListFromJSValue() on each of its values (a live object such as
	an entity or OONull stays a PList::Object node); a value that converts to
	null is left out.

	Only enumerable own (i.e., not inherited) properties are included; an
	integer-like property is keyed by its decimal text, as JS itself names it
	(proposed ADR-0051). A value that is not an object or cannot be enumerated
	gives a null PList. This is also how the native-object family converts a
	plain JS Object.

	Requires a request on context.
*/
oo::PList OOJSDictionaryFromJSValue(ooscript::Context context, ooscript::Value value);
oo::PList cxx_OOJSDictionaryFromJSObject(ooscript::Context context, ooscript::Object object);


/*	OOJSDictionaryFromStringTable(context, value)
	
	Treat an arbitrary JavaScript object as a dictionary mapping strings to
	strings, and convert to a corresponding dictionary. The values are
	converted to strings using ooscript::valueToString(). A null PList if the
	value is null or not an object, or cannot be enumerated.

	Only enumerable own (i.e., not inherited) properties with string keys are
	included.
	
	Requires a request on context.
*/
oo::PList OOJSDictionaryFromStringTable(ooscript::Context context, ooscript::Value value);


/*
	Subclass relationships.
	
	JSAPI doesn't have a concept of subclassing, as JavaScript doesn't have a
	concept of classes, but Oolite reflects part of its class hierarchy as
	related JSClasses whose prototypes inherit each other. For instance,
	JS Entity methods work on JS Ships. In order for this to work,
	OOJSEntityGetEntity() must be able to know that Ship is a subclass of
	Entity. This is done using OOJSIsSubclass().
	
	void OOJSRegisterSubclass(ooscript::ClassDef *subclass, ooscript::ClassDef *superclass)
	Register subclass as a subclass of superclass. Subclass must not previously
	have been registered as a subclass of any class (i.e., single inheritance
	is required).
 
	BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
	Test whether putativeSubclass is a equal to superclass or a registered
	subclass of superclass, recursively.
*/
OOJS_EXTERN_C void OOJSRegisterSubclass(ooscript::ClassDef *subclass, ooscript::ClassDef *superclass);
OOJS_EXTERN_C BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass);
OOINLINE BOOL OOJSIsMemberOfSubclass(ooscript::Context context, ooscript::Object object, ooscript::ClassDef *superclass)
{
	return OOJSIsSubclass(OOJSGetClass(context, object), superclass);
}


/*	Support for OOJSNativeObjectFromJSValue() family
	
	OOJSClassConverterCallback specifies the prototype for a callback function
	which converts a JavaScript object to its property-list form: plist data,
	or a PList::Object node holding a native object (proposed ADR-0055 item 4).
	
	OOJSBasicPrivateObjectConverter() is a OOJSClassConverterCallback which
	returns the JS object's private storage value as an Object node (a null
	PList for none). The slot holds a C++ object (bead oo-4aq6a.6): a node
	is made of it when it is a PList::Object's foreign object, else none.
	
	OOJSRegisterObjectConverter() registers a callback for a specific JS class.
	It is not automatically propagated to subclasses.
*/
typedef oo::PList (*OOJSClassConverterCallback)(ooscript::Context context, ooscript::Object object);
oo::PList OOJSBasicPrivateObjectConverter(ooscript::Context context, ooscript::Object object);

OOJS_EXTERN_C void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, OOJSClassConverterCallback converter);


/*	JS root handling
	
	The name parameter to the façade's addNamed*Root is assigned with no overhead, not
	copied, but the strings serve no purpose in a release build so we may as
	well strip them out.
	
	In debug builds, this will deliberately cause an error if name is not a
	string literal.
*/
#ifdef NDEBUG
#define OOJSAddGCValueRoot(context, root, name)		ooscript::addNamedValueRoot((context), (root), nullptr)
#define OOJSAddGCStringRoot(context, root, name)	ooscript::addNamedStringRoot((context), (root), nullptr)
#define OOJSAddGCObjectRoot(context, root, name)	ooscript::addNamedObjectRoot((context), (root), nullptr)
#else
#define OOJSAddGCValueRoot(context, root, name)		ooscript::addNamedValueRoot((context), (root), "" name)
#define OOJSAddGCStringRoot(context, root, name)	ooscript::addNamedStringRoot((context), (root), "" name)
#define OOJSAddGCObjectRoot(context, root, name)	ooscript::addNamedObjectRoot((context), (root), "" name)
#endif


/*	OOJSValue: an object whose purpose in life is to hold a JavaScript value.
	This is somewhat useful for putting JavaScript objects in property lists,
	for instance to pass as properties to script loaders. The value is
	GC rooted for the lifetime of the OOJSValue.

	All methods take a context parameter, which must either be nil or a context
	in a request. A property list holds it as an Object node: it is its own node's foreign
	object (OOJSValueObjectNode(); bead oo-wdqw1, whose deletion of the Objective-C facade made it
	a global class).
*/
class OOJSValue : public oo::PListForeign
{
public:
	static oo::Ref<OOJSValue> valueWithJSValue(ooscript::Value value, ooscript::Context context);
	static oo::Ref<OOJSValue> valueWithJSObject(ooscript::Object object, ooscript::Context context);

	~OOJSValue();

	ooscript::Value jsValueInContext(ooscript::Context context);	// the held value

	// oo::PListForeign: what the facade answered (its class, and "%@" as <OOJSValue 0x...>).
	std::string className() const override;
	std::string description() const override;

private:
	// The initialisers after [super init], which could not fail: run by the factories.
	void initWithJSValue(ooscript::Value value, ooscript::Context context);
	void initWithJSObject(ooscript::Object object, ooscript::Context context);

	void deleteJSValue();

	ooscript::Value					_val = {};
	const void						*_resetSender = {};	// the engine, the sender of its reset notifications, while _val is rooted
};


// A held value as a PList::Object node (what oo::PListObject() did for the facade); null -> null PList.
inline oo::PList OOJSValueObjectNode(OOJSValue *value)
{
	if (value == nullptr)  return oo::PList();
	return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(value)));
}

#include "OOJSEngineNativeWrappers.h"

/*	See comments on time limiter in OOJSEngineTimeManagement.h.
*/
OOJS_EXTERN_C void OOJSPauseTimeLimiter(void);
OOJS_EXTERN_C void OOJSResumeTimeLimiter(void);


/*	OOJSDumpStack()
	Write JavaScript stack to log.
	
	OOJSDescribeLocation()
	Get script and line number for a stack frame.
	
	OOJSMarkConsoleEvalLocation()
	Specify that a given stack frame identifies eval()ed code from the debug
	console, so that matching locations can be described specially by
	OOJSDescribeLocation().
*/
#ifndef NDEBUG
OOJS_EXTERN_C void OOJSDumpStack(ooscript::Context context);

std::optional<std::string> OOJSDescribeLocation(ooscript::Context context, ooscript::StackFrame stackFrame);	// nullopt: no location
OOJS_EXTERN_C void OOJSMarkConsoleEvalLocation(ooscript::Context context, ooscript::StackFrame stackFrame);
#else
#define OOJSDumpStack(cx)						do {} while (0)
#define OOJSDescribeLocation(cx, frame)			do {} while (0)
#define OOJSMarkConsoleEvalLocation(cx, frame)  do {} while (0)
#endif




/***** Reusable JS callbacks ****/

/*	OOJSUnconstructableConstruct
	
	Constructor callback for pseudo-classes which can't be constructed.
*/
OOJS_EXTERN_C bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &oojsArgs);


/*	OOJSObjectWrapperFinalize
	
	Finalizer for JS classes whose private storage is a retained object
	reference: OOJSCxxObjectWrapperFinalize() (OOJSPrivateObject.h), since the
	slot holds only a C++ object (bead oo-4aq6a.6).
*/
OOJS_EXTERN_C void OOJSObjectWrapperFinalize(ooscript::Context context, ooscript::Object thisObj);


/*	OOJSObjectWrapperToString
	
	Implementation of toString() for JS classes whose private storage is an
	object reference: "[object <JS class name>]" ("[object]" for no class).
	Only an Objective-C object found through the class's converter described
	itself; no slot holds one since bead oo-4aq6a.6.
*/
OOJS_EXTERN_C bool OOJSObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &oojsArgs);



/***** Appropriate flags for host-defined read/write and read-only properties *****/

// Slot-based (defined with ooscript::defineProperty/defineObject/defineFunction and no callbacks)
#define OOJS_PROP_READWRITE				(ooscript::PropertyFlag::Permanent | ooscript::PropertyFlag::Enumerate)
#define OOJS_PROP_READONLY				(ooscript::PropertyFlag::Permanent | ooscript::PropertyFlag::Enumerate | ooscript::PropertyFlag::ReadOnly)

// Non-enumerable properties
#define OOJS_PROP_HIDDEN_READWRITE		(ooscript::PropertyFlag::Permanent)
#define OOJS_PROP_HIDDEN_READONLY		(ooscript::PropertyFlag::Permanent | ooscript::PropertyFlag::ReadOnly)

// Methods should be non-enumerable
#define OOJS_METHOD_READONLY			OOJS_PROP_HIDDEN_READONLY

// Callback-based (includes all properties specified in JSPropertySpecs)
#define OOJS_PROP_READWRITE_CB			(OOJS_PROP_READWRITE | ooscript::PropertyFlag::Shared)
#define OOJS_PROP_READONLY_CB			(OOJS_PROP_READONLY | ooscript::PropertyFlag::Shared)

#define OOJS_PROP_HIDDEN_READWRITE_CB	(OOJS_PROP_HIDDEN_READWRITE | ooscript::PropertyFlag::Shared)
#define OOJS_PROP_HIDDEN_READONLY_CB	(OOJS_PROP_HIDDEN_READONLY | ooscript::PropertyFlag::Shared)




/***** Helpers for native callbacks. *****/
// Every native is `bool Name(ooscript::Context context, ooscript::CallArgs &oojsArgs)`.
#define OOJS_THIS						(oojsArgs.thisObject())
#define OOJS_ARGV						(oojsArgs.argv())
#define OOJS_RVAL						(oojsArgs.rval())
#define OOJS_SET_RVAL(v)				oojsArgs.setRval(v)

#define OOJS_RETURN(v)					do { OOJS_SET_RVAL(v); return true; } while (0)
#define OOJS_RETURN_JSOBJECT(o)			OOJS_RETURN(ooscript::objectValue(o))
#define OOJS_RETURN_VOID				OOJS_RETURN(ooscript::undefinedValue())
#define OOJS_RETURN_NULL				OOJS_RETURN(ooscript::nullValue())
#define OOJS_RETURN_BOOL(v)				OOJS_RETURN(OOJSValueFromBOOL(v))
#define OOJS_RETURN_INT(v)				OOJS_RETURN(ooscript::int32Value(v))

/*	PList return slots (proposed ADR-0055 item 4). A native returns C++ values as
	oo::PList, converted by OOJSValueFromPList() (the same JS value
	OOJSValueFromNativeObject() gave for the Foundation object it replaces):
	
	OOJS_RETURN_PLIST(plist)            the value of <plist> (null for a null PList)
	OOJS_RETURN_STRING_OR_NULL(opt)     a std::optional<std::string>: the string,
	                                    or null for nullopt (what nil gave)
	
	The recipe the chunks followed (OOJS_RETURN_OBJECT, OOJSValueFromNativeObject(), oo::PListFromObjects()
	and the Foundation bridges are deleted; bead oo-4aq6a.6.2):

	OOJS_RETURN_OBJECT(oo::NSStringFrom(s))           OOJS_RETURN_PLIST(oo::PList(s))
	OOJS_RETURN_OBJECT(oo::NSStringOrNil(o))          OOJS_RETURN_STRING_OR_NULL(o)
	OOJS_RETURN_OBJECT(oo::ObjectFromPList(p))        OOJS_RETURN_PLIST(p)
		
	Exemplar: OOJSObjectWrapperToString() in OOJavaScriptEngine.mm.
*/
#define OOJS_RETURN_PLIST(plist)		OOJS_RETURN(OOJSValueFromPList(context, (plist)))
#define OOJS_RETURN_STRING_OR_NULL(opt) do { 	const std::optional<std::string> &oojsOptionalString_ = (opt); 	OOJS_RETURN_PLIST(oojsOptionalString_.has_value() ? oo::PList(*oojsOptionalString_) : oo::PList()); } while (0)

#define OOJS_RETURN_WITH_HELPER(helper, value) \
do { \
	ooscript::Value jsresult; \
	bool OK = helper(context, value, &jsresult); \
	oojsArgs.setRval(jsresult); return OK; \
} while (0)

#define OOJS_RETURN_VECTOR(value)		OOJS_RETURN_WITH_HELPER(VectorToJSValue, value)
#define OOJS_RETURN_HPVECTOR(value)		OOJS_RETURN_WITH_HELPER(HPVectorToJSValue, value)
#define OOJS_RETURN_QUATERNION(value)	OOJS_RETURN_WITH_HELPER(QuaternionToJSValue, value)
#define OOJS_RETURN_DOUBLE(value)		OOJS_RETURN_WITH_HELPER(ooscript::newNumberValue, value)


#endif	// INCLUDED_OOJSENGINECORE_h
