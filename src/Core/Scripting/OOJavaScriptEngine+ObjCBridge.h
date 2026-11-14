/*

OOJavaScriptEngine+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, beads oo-10qz, oo-903c, oo-elta and oo-k4nu): the Objective-C OOJavaScriptEngine, a
facade over the C++ cxx::OOJavaScriptEngine (OOJavaScriptEngine.h), for the code that is not
converted yet: nearly every scripting file, the debug support, the player and the universe. Its
interface is the one OOJavaScriptEngine.h declared before the conversion, copied exactly (same
selectors, same types, same root); every method forwards to its C++ member in one line
(OOJavaScriptEngine+ObjCBridge.mm). The monitor protocol and the OOMonitorSupport category moved
here from OOJavaScriptEngine.h, and so did the root class's JS glue (the category OOObject
(OOJavaScript), whose default methods forward to free functions in OOJavaScriptEngine.mm) and
OONull and OOJSValue, the facades of cxx::OONull and cxx::OOJSValue. Below them are the one-line bridges through which
OOJavaScriptEngine.mm's free functions send to classes that are still Objective-C (amendment
oo-9ht.139 item 3). Imported as the last line of OOJavaScriptEngine.h; do not import it directly.

        a caller that is                       holds / passes                       crosses with
        -------------------------------------  -----------------------------------  ------------------------
        still Objective-C                      OOJavaScriptEngine * (this facade)   nothing: messages as before
        converted (C++)                        cxx::OOJavaScriptEngine * (the singleton)
          handing the engine to Objective-C                                         oo::ToObjC(engine)
          taking it from Objective-C                                                oo::ToCxx(objcEngine)

The engine is a singleton: +sharedEngine answers one facade for the life of the process
(proposed ADR-0056 amendment oo-r7m0, item 5), and that facade is the sender of the engine's
reset notifications, as the engine was. Never add to this file; converted code does not message
the facade. Deleted by its deletion bead once slices 2-4 are converted and no file outside
OOJavaScriptEngine.* names the Objective-C class.

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

#ifndef OOJAVASCRIPTENGINE_OBJCBRIDGE_H
#define OOJAVASCRIPTENGINE_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOJavaScriptEngine : OOObject {
@private
    oo::Ref<cxx::OOJavaScriptEngine> _cxxEngine;
}

+ (OOJavaScriptEngine*)sharedEngine;

- (JSContext*)context;
- (JSValueConst)globalObject;

- (void)runMissionCallback;

/*	Tear down context and global object and rebuild them from scratch. This
        invalidates -globalObject and all prototypes.
*/
- (BOOL)reset;

// Call a JS function. *outResult is owned by the caller. Exceptions are reported and cleared.
- (BOOL)callJSFunction:(JSValueConst)function
             forObject:(JSValueConst)jsThis
                  argc:(int)argc
                  argv:(JSValueConst*)argv
                result:(JSValue*)outResult;

- (void)garbageCollectionOpportunity:(BOOL)force;

- (BOOL)showErrorLocations;
- (void)setShowErrorLocations:(BOOL)value;

#ifdef OO_DEBUG_MONITOR_ENABLED
- (BOOL)dumpStackForErrors;
- (void)setDumpStackForErrors:(BOOL)value;

- (BOOL)dumpStackForWarnings;
- (void)setDumpStackForWarnings:(BOOL)value;

// Install handler for JS "debugger" statment. (Not supported by QuickJS; does nothing.)
- (void)enableDebuggerStatement;
#endif

/*	Destroy the context and runtime. All native objects holding JSValues must
        have released them first. Returns the number of JS objects still alive
        after a final garbage collection; if it is non-zero, they are logged
        and the runtime is abandoned rather than freed.
*/
- (NSUInteger)shutDown;

@end

/*	The root-class JS glue for classes rooted on OOObject (ADR-0029). An object on another root
        has none: OOJSValueFromNativeObject() gives undefined for it (oo-qps.72).

        -oo_jsValueInContext:

        Return the JavaScript value representation of an object, owned by the
        caller. The default implementation returns JS_UNDEFINED.
        If the receiver may be nil, use OOJSValueFromNativeObject() instead.

        -cxx_oo_jsDescription
        -cxx_oo_jsDescriptionWithClassName:
        -cxx_oo_jsClassName

        They wrap -cxx_descriptionComponents (OODescription.h) as [jsClassName components]. C++ string twins on OOObject.

        oo_clearJSSelf:
        This is called by OOJSObjectWrapperFinalize() when a JS object wrapper is
        collected. The default implementation does nothing.
*/
@interface OOObject (OOJavaScript)

- (JSValue)oo_jsValueInContext:(JSContext*)context;
- (std::optional<std::string>)cxx_oo_jsDescription;
- (std::optional<std::string>)cxx_oo_jsDescriptionWithClassName:(const std::optional<std::string>&)className;
- (std::optional<std::string>)cxx_oo_jsClassName;
- (void)oo_clearJSSelf:(JSValueConst)selfVal;

@end

/*	OONull: the placeholder for null inside native collections, which cannot
        hold nil (was Foundation's null singleton, ADR-0029 Decision 5). A JS array
        element that is null or undefined becomes [OONull null] in the native array, and
        [OONull null] becomes JS null, so JS null round-trips as before. Game code
        uses it where a collection slot is empty (MFD settings, target memory,
        script event arguments). It describes itself as "<null>", as its
        predecessor did, and -copy returns itself. The facade of cxx::OONull
        (OOJavaScriptEngine.h): there is one, made by +null, for the life of the process.
*/
@interface OONull : OOObject <OOCopying> {
@private
    oo::Ref<cxx::OONull> _cxxNull;
}

+ (OONull*)null;

@end

/*	OOJSValue: an object whose purpose in life is to hold a JavaScript value.
        This is somewhat useful for putting JavaScript objects in ObjC collections,
        for instance to pass as properties to script loaders. The value is held
        (with its own reference) until the OOJSValue is deallocated or the engine
        is reset. The facade of cxx::OOJSValue (OOJSEngineCore.h).
*/
@interface OOJSValue : OOObject {
@private
    oo::Ref<cxx::OOJSValue> _cxxValue;
}

+ (id)valueWithJSValue:(JSValueConst)value inContext:(JSContext*)context;
- (id)initWithJSValue:(JSValueConst)value inContext:(JSContext*)context;

@end

#if OOJSENGINE_MONITOR_SUPPORT

/*	Protocol for debugging "monitor" object.
        The monitor is an object -- in Oolite, or via Distributed Objects -- which
        is provided with debugging information by the OOJavaScriptEngine.

        QuickJS has no JSErrorReport, so problems are described by severity
        ("exception" or "warning") and the innermost location on the stack, if
        any (file is nullopt otherwise).
*/
@protocol OOJavaScriptEngineMonitor <OOObject>

// Sent for JS errors or warnings.
- (void)jsEngine:(OOJavaScriptEngine*)engine
              context:(JSContext*)context
    problemOfSeverity:(const std::string&)severity
               inFile:(const std::optional<std::string>&)file
                 line:(unsigned)line
            stackSkip:(unsigned)stackSkip
      showingLocation:(BOOL)showLocation
          withMessage:(const std::string&)message;

// Sent for JS log messages. Note: messageClass is nullopt if Log() is used rather than LogWithClass().
- (void)jsEngine:(OOJavaScriptEngine*)engine
         context:(JSContext*)context
      logMessage:(const std::string&)message
         ofClass:(const std::optional<std::string>&)messageClass;

@end

@interface OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)monitor;

@end

#endif

namespace oo {

// The engine's Objective-C facade: the one +sharedEngine answers, the same object every time (it
// is the sender of the engine's reset notifications, as the engine was); nil for null.
OOJavaScriptEngine* ToObjC(cxx::OOJavaScriptEngine* engine);
// The C++ engine behind a facade, borrowed; null for nil.
cxx::OOJavaScriptEngine* ToCxx(OOJavaScriptEngine* engine);

// A held value's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOJSValue* ToObjC(cxx::OOJSValue* value);
// The C++ held value behind a facade, borrowed; null for nil.
cxx::OOJSValue* ToCxx(OOJSValue* value);

// The one null's facade, the same object every time (+[OONull null]); nil for null.
OONull* ToObjC(cxx::OONull* null);
// The C++ null behind the facade, borrowed; null for nil.
cxx::OONull* ToCxx(OONull* null);

} // namespace oo

/*	One-line bridges for OOJavaScriptEngine.mm's free functions (amendment oo-9ht.139 item 3): each
        is the one message it is named after, verbatim, to a class that is still Objective-C. Each goes
        with the conversion of the class it messages.
*/
// -weakRefUnderlyingObject (OOWeakReferenceSupport): the object itself for a non-weakref, nil for nil.
id OOJavaScriptEngineWeakRefUnderlyingObject(id object);
// The JS glue of any object (OOObject (OOJavaScript)), as the object's class answers it; the value
// is owned by the caller.
JSValue OOJavaScriptEngineJSValueInContext(id object, JSContext* context);
std::optional<std::string> OOJavaScriptEngineJSClassName(id object);
std::optional<std::string> OOJavaScriptEngineJSDescriptionWithClassName(id object, const std::optional<std::string>& className);
// -cxx_descriptionComponents (OODescription.h) and -class of any object.
std::optional<std::string> OOJavaScriptEngineDescriptionComponents(id object);
Class OOJavaScriptEngineClass(id object);
// [OOObject class]
Class OOJavaScriptEngineOOObjectClass();
// -cxx_oo_jsDescription and -oo_clearJSSelf: of any object (OOObject (OOJavaScript)).
std::optional<std::string> OOJavaScriptEngineJSDescription(id object);
void OOJavaScriptEngineClearJSSelf(id object, JSValueConst selfVal);
// -isKindOfClass: of any object; NO for nil.
bool OOJavaScriptEngineIsKindOfClass(id object, Class requiredClass);
#if !OOJS_POC_HARNESS
// What the entity predicates ask an entity (Entity and EntityOOJavaScriptExtensions.h), messaged as
// the Objective-C Entity while its subclasses are Objective-C (amendment oo-nge8 item 5).
bool OOJavaScriptEngineIsVisibleToScripts(Entity* entity);
bool OOJavaScriptEngineIsShip(Entity* entity);
bool OOJavaScriptEngineIsSubEntity(Entity* entity);
bool OOJavaScriptEngineIsPlanet(Entity* entity);
OOEntityStatus OOJavaScriptEngineStatus(Entity* entity);
#endif

#endif // OOJAVASCRIPTENGINE_OBJCBRIDGE_H
