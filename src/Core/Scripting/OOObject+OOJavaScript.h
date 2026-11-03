/*

OOObject+OOJavaScript.h

TRANSITIONAL: the root class's JS glue, the category OOObject (OOJavaScript), and the one-line
bridges through which OOJavaScriptEngine.mm's free functions send to objects that are still
Objective-C. Both were in the engine's facade file (OOJavaScriptEngine+ObjCBridge.h), which was
deleted with the engine's, OONull's and OOJSValue's facades; they are not the engine's facade but
the root's glue, and go with the root class (Phase 4). Imported as the last line of
OOJavaScriptEngine.h; do not import it directly. Never add to this file.

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

#ifndef OOOBJECT_OOJAVASCRIPT_H
#define OOOBJECT_OOJAVASCRIPT_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

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

/*	One-line bridges for OOJavaScriptEngine.mm's free functions (amendment oo-9ht.139 item 3): each
        is the one message it is named after, verbatim, to a class that is still Objective-C (the root
        class and weak references). Each goes with the conversion of the class it messages.
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
// What the entity predicates ask an entity (Entity and EntityOOJavaScriptExtensions.h). They take
// the C++ entity and ask what the root facade's selectors forwarded to.
class Entity;
bool OOJavaScriptEngineIsVisibleToScripts(Entity* entity);
bool OOJavaScriptEngineIsShip(Entity* entity);
bool OOJavaScriptEngineIsSubEntity(Entity* entity);
bool OOJavaScriptEngineIsPlanet(Entity* entity);
OOEntityStatus OOJavaScriptEngineStatus(Entity* entity);
#endif

#endif // OOOBJECT_OOJAVASCRIPT_H
