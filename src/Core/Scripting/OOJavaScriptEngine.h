/*

OOJavaScriptEngine.h

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


#pragma once

#include "OOCocoa.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "oofnd/objc/OOObject.h"
#define OOJSENGINE_MONITOR_SUPPORT OOLITE_DEBUG


#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "OOJSPropID.h"

#include "oofnd/objc/OOAssert.h"
#include "oofnd/Ref.hpp"

/*	The plain C++ part of the engine API (bead oo-9ht.72): reporters, converters, argument and
	return macros, the native wrappers. A binding with no Objective-C includes only that header.
*/
#include "OOJSEngineCore.h"



#if OOJSENGINE_MONITOR_SUPPORT
#include "OOJavaScriptEngineMonitor.h"	// a C++ interface since bead oo-9ht.74.1
#endif


/*	The engine (proposed ADR-0056; docs/phases/3-slices/OOJavaScriptEngine.md): the singleton
	that owns the JS runtime and the main thread context. A global class since bead oo-wdqw1
	deleted its Objective-C facade; it is the sender of its reset notifications.
*/
class OOJavaScriptEngine : public oo::RefCounted
{
public:
	// The shared engine, made on first use; borrowed, never released (proposed ADR-0056
	// amendment oo-r7m0).
	static OOJavaScriptEngine *sharedEngine();

	~OOJavaScriptEngine();

	void runMissionCallback();

	/*	Tear down context and global object and rebuild them from scratch. This
		invalidates -globalObject and the main thread context.
	*/
	bool reset();

	ooscript::Object globalObject();

	// Call a JS function, setting up new contexts as necessary. Caller is responsible for ensuring the ooscript::Value passed really is a function.
	bool callJSFunction(ooscript::Value function, ooscript::Object jsThis, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult);

	void removeGCObjectRoot(ooscript::Object *rootPtr);
	void removeGCValueRoot(ooscript::Value *rootPtr);

	void garbageCollectionOpportunity(bool force);

	bool showErrorLocations();
	void setShowErrorLocations(bool value);

	ooscript::ClassDef *objectClass();
	ooscript::ClassDef *stringClass();
	ooscript::ClassDef *arrayClass();
	ooscript::ClassDef *numberClass();
	ooscript::ClassDef *booleanClass();

#ifndef NDEBUG
	bool dumpStackForErrors();
	void setDumpStackForErrors(bool value);

	bool dumpStackForWarnings();
	void setDumpStackForWarnings(bool value);

	// Install handler for JS "debugger" statment.
	void enableDebuggerStatement();
#endif

#if OOJSENGINE_MONITOR_SUPPORT
	// (OOMonitorSupport)
	void setMonitor(OOJavaScriptEngineMonitor *monitor);	// borrowed (bead oo-9ht.74.1)

	// (OOMonitorSupportInternal)
	void sendMonitorError(ooscript::ErrorReport *errorReport, const std::string &message, ooscript::Context context);
	// nullopt is meaningful to the monitor (Log() with a null message; no class for Log()).
	void sendMonitorLogMessage(const std::optional<std::string> &message, const std::optional<std::string> &messageClass, ooscript::Context context);
#endif

private:
	void init();	// -init's body after [super init]: run by sharedEngine() on the new object

	bool lookUpStandardClassPointers();
	void registerStandardObjectConverters();

	void createMainThreadContext();
	void destroyMainThreadContext();

	ooscript::Runtime				_runtime = {};
	ooscript::Object				_globalObject = {};
	bool							_showErrorLocations = {};

	ooscript::ClassDef				*_objectClass = {};
	ooscript::ClassDef				*_stringClass = {};
	ooscript::ClassDef				*_arrayClass = {};
	ooscript::ClassDef				*_numberClass = {};
	ooscript::ClassDef				*_booleanClass = {};

#ifndef NDEBUG
	bool							_dumpStackForErrors = {};
	bool							_dumpStackForWarnings = {};
#endif
#if OOJSENGINE_MONITOR_SUPPORT
	OOJavaScriptEngineMonitor		*_monitor = nullptr;	// borrowed: the debug monitor lives as long as the process
#endif
};



/*	(The root-class JS glue for classes rooted on OOObject, the defaults OOObject+OOJavaScript.h's
	bridges called, went with those bridges in bead oo-4aq6a.6.2: no game object is an Objective-C
	object.)
*/

// A vector box's JS value (OOJSValueFromPList, for an Object node that holds one).
class OONativeVector;
ooscript::Value OONativeVectorJSValueInContext(OONativeVector *vector, ooscript::Context context);


/*	OONull: the placeholder for null inside native collections, which cannot
	hold nil (was Foundation's null singleton, ADR-0029 Decision 5). A JS array
	element that is null or undefined becomes [OONull null] in the native array, and
	[OONull null] becomes JS null, so JS null round-trips as before. Game code
	uses it where a collection slot is empty (MFD settings, target memory,
	script event arguments). It describes itself as "<null>", as its
	predecessor did, and -copy returns itself. A property list holds it as an
	Object node whose foreign object it is (OONullObjectNode(); bead oo-wdqw1 deleted its
	Objective-C facade, which was what the collections held).
*/
class OONull : public oo::PListForeign
{
public:
	// The one null, made on first use; borrowed, never released (amendment oo-r7m0).
	static OONull *null();

	ooscript::Value jsValueInContext(ooscript::Context context);	// JS null

	// oo::PListForeign: what the facade answered (its class, and "%@" as "<null>").
	std::string className() const override;
	std::string description() const override;	// "<null>"
};


// The one null as a PList::Object node ([OONull null] through oo::PListObject()), and whether a
// node is that null (oo::ObjectIn(node) == [OONull null]).
inline oo::PList OONullObjectNode()
{
	return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(OONull::null())));
}

inline bool OOIsNullObjectNode(const oo::PList &plist)
{
	const oo::PList::Object *node = plist.getIf<oo::PList::Object>();
	return node != nullptr && node->get() == OONull::null();
}


// OOJSValue is declared in OOJSEngineCore.h (a plain C++ header, so C++-only bindings can use it).



// OOEntityFilterPredicate wrapping a JavaScript function.
typedef struct
{
	ooscript::Context context;
	ooscript::Value					function;	// Caller is responsible for ensuring this is a function object (using OOJSValueIsFunction()).
	ooscript::Object jsThis;
	BOOL					errorFlag;	// Set if a JS exception occurs. The
										// exception will have been reported.
										// This also supresses further filtering.
} JSFunctionPredicateParameter;
OOJS_EXTERN_C BOOL JSFunctionPredicate(Entity *entity, void *parameter);

// YES for ships and (normal) planets. Parameter: ignored.
OOJS_EXTERN_C BOOL JSEntityIsJavaScriptVisiblePredicate(Entity *entity, void *parameter);

// YES for ships other than sub-entities and menu-display ships, and planets other than atmospheres and menu miniatures. Parameter: ignored.
OOJS_EXTERN_C BOOL JSEntityIsJavaScriptSearchablePredicate(Entity *entity, void *parameter);

// YES for menu-display ships. Parameter: ignored
OOJS_EXTERN_C BOOL JSEntityIsDemoShipPredicate(Entity *entity, void *parameter);



/*	DEFINE_JS_OBJECT_GETTER() and OOJSObjectGetterImplPRIVATE(), which read an Objective-C object
	from a JS object's private slot with an Objective-C class check, are deleted (bead
	oo-4aq6a.6): every slot holds a C++ object, read by OOJSGetCxxPrivate() (OOJSPrivateObject.h).
*/



// (The root class's JS glue and the engine's one-line sends to Objective-C objects,
// OOObject+OOJavaScript.h, went with bead oo-4aq6a.6.2.)
#include "OOCocoa.h"


