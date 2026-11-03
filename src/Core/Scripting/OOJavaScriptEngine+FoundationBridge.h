/*

OOJavaScriptEngine+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"). OOJavaScriptEngine's Foundation-typed
API as it was before its sweep, with the same names and types, forwarding to the cxx_ API in
OOJavaScriptEngine.h. It exists so that the engine's callers compile unchanged; each caller moves
to the cxx_ API in its own sweep. When `git grep` finds no caller of anything declared here, this
file, OOJavaScriptEngine+FoundationBridge.mm, its line in Core/Scripting/meson.build and the
#import at the end of OOJavaScriptEngine.h are deleted. Never call it from migrated code. The
removal of gnustep-base cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2013 David Taylor and Jens Ayton (OOJavaScriptEngine.h)

*/

// Imported only from the end of OOJavaScriptEngine.h (which declares everything used here); never
// import it directly, and never import OOJavaScriptEngine.h from it (a cycle).
#ifndef OOJAVASCRIPTENGINE_FOUNDATIONBRIDGE_H
#define OOJAVASCRIPTENGINE_FOUNDATIONBRIDGE_H

/*	Convert an arbitrary JS value to an NSString, calling its toString method
        if needed. OOStringFromJSValue() returns nil if value is null or
        undefined, OOStringFromJSValueEvenIfNull() returns "null" or "undefined".
*/
NSString* OOStringFromJSValue(JSContext* context, JSValueConst value); // -> cxx_OOStringFromJSValue
NSString* OOStringFromJSValueEvenIfNull(JSContext* context, JSValueConst value); // -> cxx_OOStringFromJSValueEvenIfNull

// Name of the property with the given magic (tinyid) in a property table, for error messages.
NSString* OOStringFromJSPropertyMagic(int magic, const JSCFunctionListEntry* list, size_t count); // -> cxx_OOStringFromJSPropertyMagic

// Convert a property ID to an NSString.
NSString* OOStringFromJSID(JSAtom propID); // -> cxx_OOStringFromJSID

// Convert an NSString to a property ID (interned for the life of the process; JS_ATOM_NULL for nil).
JSAtom OOJSIDFromString(NSString* string); // -> cxx_OOJSIDFromString

NSString* OOJSDescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects); // -> cxx_OOJSDescribeValue

// Error and warning reporters with NSString formats -> the cxx_ reporters, which take printf
// formats; the bridge formats %@ with GNUstep and hands over the finished text.
void OOJSReportError(JSContext* context, NSString* format, ...);
void OOJSReportErrorWithArguments(JSContext* context, NSString* format, va_list args);
void OOJSReportErrorForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...);

void OOJSReportWarning(JSContext* context, NSString* format, ...);
void OOJSReportWarningWithArguments(JSContext* context, NSString* format, va_list args);
void OOJSReportWarningForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...);

void OOJSReportBadArguments(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, NSString* message, NSString* expectedArgsDescription);

BOOL OOJSArgumentListGetNumber(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed);

// Retiring category on a Foundation class (ADR-0043 Amendment 1 item 7). The three helpers
// forward to cxx_OOJSStringWithJavaScriptParameters,
// cxx_OOJSConcatenationOfStringsFromJavaScriptValues and cxx_OOJSEscapedForJavaScriptLiteral.
@interface NSString (OOJavaScriptExtensions)

// For diagnostic messages; produces things like @"(42, true, "a string", an object description)".
+ (NSString*)stringWithJavaScriptParameters:(JSValueConst*)params count:(int)count inContext:(JSContext*)context;

// Concatenate sequence of arbitrary JS objects into string.
+ (NSString*)concatenationOfStringsFromJavaScriptValues:(JSValueConst*)values count:(size_t)count separator:(NSString*)separator inContext:(JSContext*)context;

// Add escape codes for string so that it's a valid JavaScript literal (if you put "" or '' around it).
- (NSString*)escapedForJavaScriptLiteral;

@end

// The JS glue on the Foundation root class (retiring with gnustep-base, ADR-0043 Amendment 1
// item 7). OOObject (OOJavaScript) in OOJavaScriptEngine.h documents the methods.
@interface NSObject (OOJavaScript)

/*	-oo_jsValueInContext:

        Return the JavaScript value representation of an object, owned by the
        caller. The default implementation returns JS_UNDEFINED.
        If the receiver may be nil, use OOJSValueFromNativeObject() instead.
*/
- (JSValue)oo_jsValueInContext:(JSContext*)context;

/*	-oo_jsDescription
        -oo_jsDescriptionWithClassName:
        -oo_jsClassName

        See comments for -descriptionComponents in OOFoundation.h.
*/
- (NSString*)oo_jsDescription;
- (NSString*)oo_jsDescriptionWithClassName:(NSString*)className;
- (NSString*)oo_jsClassName;

/*	oo_clearJSSelf:
        This is called by OOJSObjectWrapperFinalize() when a JS object wrapper is
        collected. The default implementation does nothing.
*/
- (void)oo_clearJSSelf:(JSValueConst)selfVal;

@end

// The converter for plain JS Objects (bead oo-3rb.202: moved verbatim, orchestrator decision on
// the chunk's STOP). It builds the NSDictionary that OOJSNativeObjectFromJSValue() hands to code
// that still expects Foundation objects, keeping an integer-like property id as an NSNumber key.
// cxx_OOJSDictionaryFromJSObject in OOJavaScriptEngine.h is the oo::PList form; the C++ converter
// and the integer-key question are bead oo-vp0y's.
NSDictionary* OOJSDictionaryFromJSObject(JSContext* context, JSValueConst object);

// Notifications sent when JavaScript engine is reset, for NSNotificationCenter observers (bead
// oo-3rb.203). kOOJavaScriptEngineWillResetNotificationName / ...DidResetNotificationName in
// OOJavaScriptEngine.h are the oo::NotificationCenter names.
extern NSString* const kOOJavaScriptEngineWillResetNotification;
extern NSString* const kOOJavaScriptEngineDidResetNotification;

#endif // OOJAVASCRIPTENGINE_FOUNDATIONBRIDGE_H
