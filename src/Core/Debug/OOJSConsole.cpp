/*

OOJSConsole.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#ifndef NDEBUG

#include "OOJSConsole.h"
#include "OODebugMonitor.h"
#include <stdint.h>

#include "OOJSEngineTimeManagement.h"
#include "OOJSScript.h"
#include "OOJSVector.h"
#include "OOJSEntity.h"
#include "OOJSCall.h"
#include "OOLoggingExtended.h"
#include "OOConstToString.h"
#include "OOOpenGLExtensionManager.h"
#include "OODebugFlags.h"
#include "OODebugMonitor.h"
#include "OOProfilingStopwatch.h"
#include "ResourceManager.h"
#include "OOObjCPList.h"
#include "OOLogHeader.h"	// OOPlatformDescription()
#include "Entity.h"	// an entity's -inspect
#include "EntityOOJavaScriptExtensions.h"	// callObjC()'s class name of an entity (bead oo-9ht.39.5.1)
#if OO_DEBUG
#include "OOShaderUniformMethodType.h"	// callObjC()'s scalar results on the console (bead oo-9ht.74)
#include "OOTypeEncodings.h"	// the monitor rows' measured encodings (bead oo-dbz.3)
#endif

#include "oofnd/String.hpp"




// The Mac debug OXP's inspector added -inspect to entities (a category on Entity); inspectEntity()
// sent it to an entity that answered it. Since the root facade's deletion (bead oo-dpyk8) it calls
// the entity's virtual inspect() (oo::InspectEntity()), which does nothing unless a subclass overrides it.


static ooscript::Object sConsolePrototype = NULL;
static ooscript::Object sConsoleSettingsPrototype = NULL;

namespace {
oo::PList ConsoleConverter(ooscript::Context context, ooscript::Object object);
OODebugMonitor *MonitorFromJSObject(ooscript::Context context, ooscript::Object object);
}	// namespace


static bool ConsoleGetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value);
static bool ConsoleSetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, bool strict, ooscript::Value *value);
static void ConsoleFinalize(ooscript::Context context, ooscript::Object thisObject);

// Methods
static bool ConsoleConsoleMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleClearConsole(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleScriptStack(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleInspectEntity(ooscript::Context context, ooscript::CallArgs &oojsArgs);
#if OO_DEBUG
static bool ConsoleCallObjCMethod(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleSetUpCallObjC(ooscript::Context context, ooscript::CallArgs &oojsArgs);
#endif
static bool ConsoleIsExecutableJavaScript(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleDisplayMessagesInClass(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleSetDisplayMessagesInClass(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleWriteLogMarker(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleWriteMemoryStats(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleWriteJSMemoryStats(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleGarbageCollect(ooscript::Context context, ooscript::CallArgs &oojsArgs);
#if DEBUG
static bool ConsoleDumpNamedRoots(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleDumpHeap(ooscript::Context context, ooscript::CallArgs &oojsArgs);
#endif
#if OOJS_PROFILE
static bool ConsoleProfile(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleGetProfile(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ConsoleTrace(ooscript::Context context, ooscript::CallArgs &oojsArgs);
#endif

static bool ConsoleSettingsDeleteProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value);
static bool ConsoleSettingsGetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value);
static bool ConsoleSettingsSetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, bool strict, ooscript::Value *value);

#if OOJS_PROFILE
namespace {
bool PerformProfiling(ooscript::Context context, const char *nominalFunction, unsigned argc, ooscript::Value *argv, ooscript::Value *rval, bool trace, oo::Ref<OOTimeProfile> *profile);
}	// namespace
#endif


static ooscript::ClassDef sConsoleClass =
{
	"Console",
	ooscript::ClassFlag::HasPrivate,
	
	nullptr,				// addProperty
	nullptr,				// delProperty
	ConsoleGetProperty,				// getProperty
	ConsoleSetProperty,				// setProperty
	nullptr,				// enumerate
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,					// resolve
	nullptr,					// convert
	ConsoleFinalize,				// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};


enum
{
	// Property IDs
	kConsole_debugFlags,						// debug flags, integer, read/write
	kConsole_detailLevel,						// graphics detail level, symbolic string, read/write
	kConsole_maximumDetailLevel,				// maximum graphics detail level, symbolic string, read-only
	kConsole_displayFPS,						// display FPS (and related info), boolean, read/write
	kConsole_platformDescription,				// Information about system we're running on in unspecified format, string, read-only
	kConsole_ignoreDroppedPackets,				// boolean (default false), read/write
	kConsole_pedanticMode,						// JS pedantic mode (the engine's strict option, not the same as "use strict"), boolean (default true), read/write
	kConsole_showErrorLocations,				// Show error/warning source locations, boolean (default true), read/write
	kConsole_dumpStackForErrors,				// Write stack dump when reporting error/exception, boolean (default false), read/write
	kConsole_dumpStackForWarnings,				// Write stack dump when reporting warning, boolean (default false), read/write
	
	kConsole_glVendorString,					// OpenGL GL_VENDOR string, string, read-only
	kConsole_glRendererString,					// OpenGL GL_RENDERER string, string, read-only
	kConsole_glFixedFunctionTextureUnitCount,	// GL_MAX_TEXTURE_UNITS_ARB, integer, read-only
	kConsole_glFragmentShaderTextureUnitCount,	// GL_MAX_TEXTURE_IMAGE_UNITS_ARB, integer, read-only
	
	// Symbolic constants for debug flags:
	kConsole_DEBUG_LINKED_LISTS,
	kConsole_DEBUG_COLLISIONS,
	kConsole_DEBUG_DOCKING,
	kConsole_DEBUG_OCTREE_LOGGING,
	kConsole_DEBUG_BOUNDING_BOXES,
	kConsole_DEBUG_OCTREE_DRAW,
	kConsole_DEBUG_DRAW_NORMALS,
	kConsole_DEBUG_NO_DUST,
	kConsole_DEBUG_NO_SHADER_FALLBACK,
	kConsole_DEBUG_SHADER_VALIDATION,
	
	kConsole_DEBUG_MISC
};


static ooscript::PropertySpec sConsoleProperties[] =
{
	// JS name								ID											flags
	{ "debugFlags",							kConsole_debugFlags,						OOJS_PROP_READWRITE_CB },
	{ "detailLevel",						kConsole_detailLevel,						OOJS_PROP_READWRITE_CB },
	{ "maximumDetailLevel",					kConsole_maximumDetailLevel,				OOJS_PROP_READONLY_CB },
	{ "displayFPS",							kConsole_displayFPS,						OOJS_PROP_READWRITE_CB },
	{ "platformDescription",				kConsole_platformDescription,				OOJS_PROP_READONLY_CB },
	{ "pedanticMode",						kConsole_pedanticMode,						OOJS_PROP_READWRITE_CB },
	{ "ignoreDroppedPackets",				kConsole_ignoreDroppedPackets,				OOJS_PROP_READWRITE_CB },
	{ "__showErrorLocations",				kConsole_showErrorLocations,				OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "__dumpStackForErrors",				kConsole_dumpStackForErrors,				OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "__dumpStackForWarnings",				kConsole_dumpStackForWarnings,				OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "glVendorString",						kConsole_glVendorString,					OOJS_PROP_READONLY_CB },
	{ "glRendererString",					kConsole_glRendererString,					OOJS_PROP_READONLY_CB },
	{ "glFixedFunctionTextureUnitCount",	kConsole_glFixedFunctionTextureUnitCount,	OOJS_PROP_READONLY_CB },
	{ "glFragmentShaderTextureUnitCount",	kConsole_glFragmentShaderTextureUnitCount,	OOJS_PROP_READONLY_CB },
	
#define DEBUG_FLAG_DECL(x) { #x, kConsole_##x, OOJS_PROP_READONLY_CB }
	DEBUG_FLAG_DECL(DEBUG_LINKED_LISTS),
	DEBUG_FLAG_DECL(DEBUG_COLLISIONS),
	DEBUG_FLAG_DECL(DEBUG_DOCKING),
	DEBUG_FLAG_DECL(DEBUG_OCTREE_LOGGING),
	DEBUG_FLAG_DECL(DEBUG_BOUNDING_BOXES),
	DEBUG_FLAG_DECL(DEBUG_OCTREE_DRAW),
	DEBUG_FLAG_DECL(DEBUG_DRAW_NORMALS),
	DEBUG_FLAG_DECL(DEBUG_NO_DUST),
	DEBUG_FLAG_DECL(DEBUG_NO_SHADER_FALLBACK),
	DEBUG_FLAG_DECL(DEBUG_SHADER_VALIDATION),
	
	DEBUG_FLAG_DECL(DEBUG_MISC),
#undef DEBUG_FLAG_DECL
	
	{ 0 }
};


static ooscript::FunctionSpec sConsoleMethods[] =
{
	// JS name							Function							min args
	{ "consoleMessage",					ConsoleConsoleMessage,				2 },
	{ "clearConsole",					ConsoleClearConsole,				0 },
	{ "scriptStack",					ConsoleScriptStack,					0 },
	{ "inspectEntity",					ConsoleInspectEntity,				1 },
#if OO_DEBUG
	{ "__setUpCallObjC",				ConsoleSetUpCallObjC,				1 },
#endif
	{ "isExecutableJavaScript",			ConsoleIsExecutableJavaScript,		2 },
	{ "displayMessagesInClass",			ConsoleDisplayMessagesInClass,		1 },
	{ "setDisplayMessagesInClass",		ConsoleSetDisplayMessagesInClass,	2 },
	{ "writeLogMarker",					ConsoleWriteLogMarker,				0 },
	{ "writeMemoryStats",				ConsoleWriteMemoryStats,			0 },
	{ "writeJSMemoryStats",				ConsoleWriteJSMemoryStats,			0 },
	{ "garbageCollect",					ConsoleGarbageCollect,				0 },
#if DEBUG
	{ "dumpNamedRoots",					ConsoleDumpNamedRoots,				0 },
	{ "dumpHeap",						ConsoleDumpHeap,					0 },
#endif
#if OOJS_PROFILE
	{ "profile",						ConsoleProfile,						1 },
	{ "getProfile",						ConsoleGetProfile,					1 },
	{ "trace",							ConsoleTrace,						1 },
#endif
	{ 0 }
};


static ooscript::ClassDef sConsoleSettingsClass =
{
	"ConsoleSettings",
	ooscript::ClassFlag::HasPrivate,
	
	nullptr,				// addProperty
	ConsoleSettingsDeleteProperty,	// delProperty
	ConsoleSettingsGetProperty,		// getProperty
	ConsoleSettingsSetProperty,		// setProperty
	nullptr,				// enumerate. FIXME: this should work.
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,					// resolve
	nullptr,					// convert
	ConsoleFinalize,				// finalize (same as Console)
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};


static void InitOOJSConsole(ooscript::Context context, ooscript::Object global)
{
	sConsolePrototype = ooscript::initClass(context, global, NULL, &sConsoleClass, OOJSUnconstructableConstruct, 0, sConsoleProperties, sConsoleMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sConsoleClass, ConsoleConverter);
	
	sConsoleSettingsPrototype = ooscript::initClass(context, global, NULL, &sConsoleSettingsClass, OOJSUnconstructableConstruct, 0, NULL, NULL, NULL, NULL);
	OOJSRegisterObjectConverter(&sConsoleSettingsClass, ConsoleConverter);
}


void OOJSConsoleDestroy(void)
{
	sConsolePrototype = NULL;
}


/*	The console objects' private slot holds the C++ monitor with one retain, released by
	ConsoleFinalize (bead oo-9ht.74; it held the facade's weak reference). The monitor is never
	released, as the facade never was, so the slot keeps nothing alive that would otherwise die.
*/
namespace {

bool SetMonitorPrivate(ooscript::Context context, ooscript::Object object, OODebugMonitor *monitor)
{
	if (monitor != nullptr)  monitor->retain();
	if (ooscript::setPrivate(context, object, static_cast<oo::RefCounted *>(monitor)))  return true;
	if (monitor != nullptr)  monitor->release();
	return false;
}


// The monitor of a Console or ConsoleSettings object; null for any other object (or a prototype).
OODebugMonitor *MonitorFromJSObject(ooscript::Context context, ooscript::Object object)
{
	if (object == NULL)  return nullptr;
	const ooscript::ClassDef *jsClass = ooscript::getClass(context, object);
	if (jsClass != &sConsoleClass && jsClass != &sConsoleSettingsClass)  return nullptr;
	return static_cast<OODebugMonitor *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
}


/*	The natives' internal error for a `this` that is not a console object: the class of the object
	the engine converts it to, as the facade's check described what it got (nil for a plain object).
*/
void ReportNotTheMonitor(ooscript::Context context, ooscript::Object object, const char *function)
{
	const oo::PList node = (object != NULL) ? cxx_OOJSPListFromJSObject(context, object) : oo::PList();
	// An entity's node: the class of its object, the root facade's (bead oo-dpyk8). Any other node holds
	// no Objective-C object (bead oo-4aq6a.5 deleted that node): nil's class, described "(null)".
	const std::string className = (oo::EntityIn(node) != nullptr) ? std::string("Entity") : std::string("(null)");
	cxx_OOJSReportError(context, "Expected OODebugMonitor, got %s in %s. %s", className.c_str(), function, "This is an internal error, please report it.");
}


// The console objects' converter: the monitor as an Object node (oo::PListForeign), whose JS value
// is the console object, as the facade's node's was (OOJSBasicPrivateObjectConverter); null for none.
oo::PList ConsoleConverter(ooscript::Context context, ooscript::Object object)
{
	OODebugMonitor *monitor = static_cast<OODebugMonitor *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	if (monitor == nullptr)  return oo::PList();
	return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(monitor)));
}

}	// namespace


ooscript::Object DebugMonitorToJSConsole(ooscript::Context context, OODebugMonitor *monitor)
{
	OOJS_PROFILE_ENTER
	
	OOJavaScriptEngine		*engine = nullptr;
	ooscript::Object object = NULL;
	ooscript::Object settingsObject = NULL;
	ooscript::Value					value;
	
	engine = OOJavaScriptEngine::sharedEngine();
	
	if (sConsolePrototype == NULL)
	{
		InitOOJSConsole(context, engine->globalObject());
	}
	
	// Create Console object
	object = ooscript::newObject(context, &sConsoleClass, sConsolePrototype, NULL);
	if (object != NULL)
	{
		if (!SetMonitorPrivate(context, object, monitor))  object = NULL;
	}
	
	if (object != NULL)
	{
		// Create ConsoleSettings object
		settingsObject = ooscript::newObject(context, &sConsoleSettingsClass, sConsoleSettingsPrototype, NULL);
		if (settingsObject != NULL)
		{
			if (!SetMonitorPrivate(context, settingsObject, monitor))  settingsObject = NULL;
		}
		if (settingsObject != NULL)
		{
			value = ooscript::objectValue(settingsObject);
			if (!ooscript::setProperty(context, object, "settings", &value))
			{
				settingsObject = NULL;
			}
		}

		if (settingsObject == NULL)  object = NULL;
	}
	
	
	return object;
	// Analyzer: object leaked. (x2) [Expected, objects are retained by JS object.]
	
	OOJS_PROFILE_EXIT
}


static bool ConsoleGetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	OOJS_NATIVE_ENTER(context)
	
	switch (ooscript::idToInt32(propID))
	{
#ifndef NDEBUG
		case kConsole_debugFlags:
			*value = ooscript::int32Value((uint32_t)gDebugFlags);
			break;
#endif		
			
		case kConsole_detailLevel:
			*value = OOJSValueFromPList(context, oo::PList(cxx_OOStringFromGraphicsDetail((UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}))));
			break;
			
		case kConsole_maximumDetailLevel:
			*value = OOJSValueFromPList(context, oo::PList(cxx_OOStringFromGraphicsDetail(OOOpenGLExtensionManager::sharedManager()->maximumDetailLevel())));
			break;
			
		case kConsole_displayFPS:
			*value = OOJSValueFromBOOL((UNIVERSE != nullptr ? UNIVERSE->getDisplayFPS() : false));
			break;
			
		case kConsole_platformDescription:
			*value = OOJSValueFromPList(context, oo::PList(OOPlatformDescription()));
			break;
			
		case kConsole_pedanticMode:
			{
				uint32_t options = static_cast<uint32_t>(ooscript::getOptions(context));
				*value = OOJSValueFromBOOL(options & static_cast<uint32_t>(ooscript::ContextOption::Strict));
			}
			break;
			
		case kConsole_ignoreDroppedPackets:
			*value = OOJSValueFromBOOL(OODebugMonitor::sharedDebugMonitor()->TCPIgnoresDroppedPackets());
			break;
			
		case kConsole_showErrorLocations:
			*value = OOJSValueFromBOOL(OOJavaScriptEngine::sharedEngine()->showErrorLocations());
			break;
			
		case kConsole_dumpStackForErrors:
			*value = OOJSValueFromBOOL(OOJavaScriptEngine::sharedEngine()->dumpStackForErrors());
			break;
			
		case kConsole_dumpStackForWarnings:
			*value = OOJSValueFromBOOL(OOJavaScriptEngine::sharedEngine()->dumpStackForWarnings());
			break;
			
		case kConsole_glVendorString:
			{ const std::optional<std::string> vendor = OOOpenGLExtensionManager::sharedManager()->vendorString(); *value = OOJSValueFromPList(context, vendor.has_value() ? oo::PList(*vendor) : oo::PList()); }
			break;
			
		case kConsole_glRendererString:
			{ const std::optional<std::string> renderer = OOOpenGLExtensionManager::sharedManager()->rendererString(); *value = OOJSValueFromPList(context, renderer.has_value() ? oo::PList(*renderer) : oo::PList()); }
			break;
			
		case kConsole_glFixedFunctionTextureUnitCount:
			*value = ooscript::int32Value(OOOpenGLExtensionManager::sharedManager()->textureUnitCount());
			break;
			
		case kConsole_glFragmentShaderTextureUnitCount:
			*value = ooscript::int32Value(OOOpenGLExtensionManager::sharedManager()->textureImageUnitCount());
			break;
			
#define DEBUG_FLAG_CASE(x) case kConsole_##x: *value = ooscript::int32Value(x); break;
		DEBUG_FLAG_CASE(DEBUG_LINKED_LISTS);
		DEBUG_FLAG_CASE(DEBUG_COLLISIONS);
		DEBUG_FLAG_CASE(DEBUG_DOCKING);
		DEBUG_FLAG_CASE(DEBUG_OCTREE_LOGGING);
		DEBUG_FLAG_CASE(DEBUG_BOUNDING_BOXES);
		DEBUG_FLAG_CASE(DEBUG_OCTREE_DRAW);
		DEBUG_FLAG_CASE(DEBUG_DRAW_NORMALS);
		DEBUG_FLAG_CASE(DEBUG_NO_DUST);
		DEBUG_FLAG_CASE(DEBUG_NO_SHADER_FALLBACK);
		DEBUG_FLAG_CASE(DEBUG_SHADER_VALIDATION);
		
		DEBUG_FLAG_CASE(DEBUG_MISC);
#undef DEBUG_FLAG_CASE
			
		default:
			OOJSReportBadPropertySelector(context, thisObject, propID, sConsoleProperties);
			return false;
	}
	
	return true;
	
	OOJS_NATIVE_EXIT
}


bool ConsoleSetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, bool /*strict*/, ooscript::Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	OOJS_NATIVE_ENTER(context)
	
	int32_t						iValue;
	bool						bValue = false;
	std::optional<std::string>	sValue;
	
	switch (ooscript::idToInt32(propID))
	{
#ifndef NDEBUG
		case kConsole_debugFlags:
			if (ooscript::valueToInt32(context, *value, &iValue))
			{
				gDebugFlags = iValue;
			}
			break;
#endif		
		case kConsole_detailLevel:
			sValue = cxx_OOStringFromJSValue(context, *value);
			OOJS_BEGIN_FULL_NATIVE(context)
			if (UNIVERSE != nullptr)  UNIVERSE->setDetailLevel(cxx_OOGraphicsDetailFromString(sValue.value_or("")));
			OOJS_END_FULL_NATIVE
			break;
			
		case kConsole_displayFPS:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				if (UNIVERSE != nullptr)  UNIVERSE->setDisplayFPS(bValue);
			}
			break;
			
		case kConsole_pedanticMode:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				uint32_t options = static_cast<uint32_t>(ooscript::getOptions(context));
				if (bValue)  options |= static_cast<uint32_t>(ooscript::ContextOption::Strict);
				else  options &= ~static_cast<uint32_t>(ooscript::ContextOption::Strict);
				
				ooscript::setOptions(context, static_cast<ooscript::ContextOption>(options));
			}
			break;
			
		case kConsole_ignoreDroppedPackets:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				OODebugMonitor::sharedDebugMonitor()->setTCPIgnoresDroppedPackets(bValue);
			}
			break;
			
		case kConsole_showErrorLocations:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				OOJavaScriptEngine::sharedEngine()->setShowErrorLocations(bValue);
			}
			break;
			
		case kConsole_dumpStackForErrors:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				OOJavaScriptEngine::sharedEngine()->setDumpStackForErrors(bValue);
			}
			break;
			
		case kConsole_dumpStackForWarnings:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				OOJavaScriptEngine::sharedEngine()->setDumpStackForWarnings(bValue);
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, thisObject, propID, sConsoleProperties);
			return false;
	}
	
	return true;
	
	OOJS_NATIVE_EXIT
}


namespace {

bool DoWeDefineAllDebugFlags(enum OODebugFlags flags)  GCC_ATTR((unused));
bool DoWeDefineAllDebugFlags(enum OODebugFlags flags)
{
	/*	This function doesn't do anything, but will generate a warning
		(Enumeration value 'DEBUG_FOO' not handled in switch) if a debug flag
		is added without updating it. The point is that if you get such a
		warning, you should first add a JS symbolic constant for the flag,
		then add it to the switch to suppress the warning.
		NOTE: don't add a default: to this switch, or I will have to hurt you.
		-- Ahruman 2010-04-11
	*/
	switch (flags)
	{
		case DEBUG_LINKED_LISTS:
		case DEBUG_COLLISIONS:
		case DEBUG_DOCKING:
		case DEBUG_OCTREE_LOGGING:
		case DEBUG_BOUNDING_BOXES:
		case DEBUG_OCTREE_DRAW:
		case DEBUG_DRAW_NORMALS:
		case DEBUG_NO_DUST:
		case DEBUG_NO_SHADER_FALLBACK:
		case DEBUG_SHADER_VALIDATION:
		case DEBUG_MISC:
			return true;
	}
	
	return false;
}

}	// namespace


static void ConsoleFinalize(ooscript::Context context, ooscript::Object thisObject)
{
	OOJS_PROFILE_ENTER
	
	// The slot's retain of the monitor (OOJSCxxObjectWrapperFinalize, whose clearJSSelf() the
	// monitor answers by doing nothing, as OOObject's -oo_clearJSSelf: did for the facade).
	oo::RefCounted *held = static_cast<oo::RefCounted *>(ooscript::getPrivate(context, thisObject));
	if (held != nullptr)  held->release();
	ooscript::setPrivate(context, thisObject, nullptr);
	
	OOJS_PROFILE_EXIT_VOID
}


static bool ConsoleSettingsDeleteProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value)
{
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	key;
	OODebugMonitor		*monitor = nullptr;	// the monitor the private slot holds

	if (!ooscript::isStringId(propID))  return false;
	key = cxx_OOStringFromJSString(context, ooscript::idToString(propID));
	
	monitor = MonitorFromJSObject(context, thisObject);
	if (monitor == nullptr)
	{
		ReportNotTheMonitor(context, thisObject, __PRETTY_FUNCTION__);
		return false;
	}
	
	if (key.has_value())  monitor->setConfigurationValue(oo::PList(), *key);
	*value = ooscript::trueValue();
	return true;
	
	OOJS_NATIVE_EXIT
}


static bool ConsoleSettingsGetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value)
{
	if (!ooscript::isStringId(propID))  return true;
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	key;
	OODebugMonitor		*monitor = nullptr;	// the monitor the private slot holds

	key = cxx_OOStringFromJSString(context, ooscript::idToString(propID));

	monitor = MonitorFromJSObject(context, thisObject);
	if (monitor == nullptr)
	{
		ReportNotTheMonitor(context, thisObject, __PRETTY_FUNCTION__);
		return false;
	}

	const oo::PList setting = key.has_value() ? monitor->configurationValueForKey(*key) : oo::PList();
	if (!setting.isNull())  *value = OOJSValueFromPList(context, setting);
	else  *value = ooscript::undefinedValue();
	
	return true;
	
	OOJS_NATIVE_EXIT
}


bool ConsoleSettingsSetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, bool /*strict*/, ooscript::Value *value)
{
	if (!ooscript::isStringId(propID))  return true;
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	key;
	OODebugMonitor		*monitor = nullptr;	// the monitor the private slot holds

	key = cxx_OOStringFromJSString(context, ooscript::idToString(propID));

	monitor = MonitorFromJSObject(context, thisObject);
	if (monitor == nullptr)
	{
		ReportNotTheMonitor(context, thisObject, __PRETTY_FUNCTION__);
		return false;
	}

	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	if (ooscript::isNull(*value) || ooscript::isUndefined(*value))
	{
		if (key.has_value())  monitor->setConfigurationValue(oo::PList(), *key);
	}
	else
	{
		const oo::PList settingValue = cxx_OOJSPListFromJSValue(context, *value);
		if (!settingValue.isNull() && key.has_value())
		{
			monitor->setConfigurationValue(settingValue, *key);
		}
		else
		{
			cxx_OOJSReportWarning(context, "debugConsole.settings: could not convert %s to native object.", cxx_OOStringFromJSValue(context, *value).value_or("(null)").c_str());
		}
	}
	OOJSResumeTimeLimiter();
	
	return true;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// function consoleMessage(colorCode : String, message : String [, emphasisStart : Number, emphasisLength : Number]) : void
static bool ConsoleConsoleMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	NSRange				emphasisRange = {0, 0};
	
	OOJS_NATIVE_ENTER(context)
	
	OODebugMonitor		*monitor = nullptr;	// the monitor the private slot holds
	std::optional<std::string>	colorKey,
								message;
	double			location, length;
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	monitor = MonitorFromJSObject(context, OOJS_THIS);
	if (monitor == nullptr)
	{
		// The facade's class check left nil, so this described nil whatever `this` was.
		cxx_OOJSReportError(context, "Expected OODebugMonitor, got %s in %s. %s", "(null)", __PRETTY_FUNCTION__, "This is an internal error, please report it.");
		OOJSResumeTimeLimiter();
		return false;
	}
	
	if (oojsArgs.count() > 0) colorKey = cxx_OOStringFromJSValue(context,OOJS_ARGV[0]);
	if (oojsArgs.count() > 1) message = cxx_OOStringFromJSValue(context,OOJS_ARGV[1]);
	
	if (oojsArgs.count() > 3)
	{
		// Attempt to get two numbers, specifying an emphasis range.
		if (ooscript::valueToNumber(context, OOJS_ARGV[2], &location) &&
			ooscript::valueToNumber(context, OOJS_ARGV[3], &length))
		{
			emphasisRange = (NSRange){(NSUInteger)location, (NSUInteger)length};
		}
	}
	
	if (!message.has_value())
	{
		if (!colorKey.has_value())
		{
			cxx_OOJSReportWarning(context, "Console.consoleMessage() called with no parameters.");
		}
		else
		{
			message = colorKey;
			colorKey = "command-result";
		}
	}
	
	if (message.has_value())
	{
		monitor->appendJSConsoleLine(*message,
												colorKey,
												emphasisRange);
	}
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function clearConsole() : void
static bool ConsoleClearConsole(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	OODebugMonitor		*monitor = nullptr;	// the monitor the private slot holds
	
	monitor = MonitorFromJSObject(context, OOJS_THIS);
	if (monitor == nullptr)
	{
		ReportNotTheMonitor(context, OOJS_THIS, __PRETTY_FUNCTION__);
		return false;
	}
	
	monitor->clearJSConsole();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function scriptStack() : Array
static bool ConsoleScriptStack(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	// The scripts' nodes (a script that has gone, which a timer or definition pushed weakly, is null).
	oo::PList::Array stack;
	for (const oo::Ref<OOJSScript> &script : OOJSScript::scriptStack())  stack.push_back(OOScriptObjectNode(script.get()));
	OOJS_RETURN_PLIST(oo::PList(std::move(stack)));
	
	OOJS_NATIVE_EXIT
}


// function inspectEntity(entity : Entity) : void
static bool ConsoleInspectEntity(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	Entity			*cxxEntity = nullptr;	// the C++ entity since bead oo-9ht.39.3
	
	if (JSValueToEntity(context, OOJS_ARGV[0], &cxxEntity))
	{
		OOJS_BEGIN_FULL_NATIVE(context)
		oo::InspectEntity(cxxEntity);	// -inspect, if the entity has it (nothing for nil)
		OOJS_END_FULL_NATIVE
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


#if OO_DEBUG
namespace {

/*	callObjC()'s names on the console objects (proposed ADR-0056 amendment oo-9ht.74): the debug
	monitor's facade, which they held, answered any selector whose signature callObjC() matched.
	Its deletion leaves this table: exactly the facade's own selectors without arguments, and the
	two that take the joined string argument. Each row calls the C++ member the selector forwarded
	to, with the result the selector's signature gave; a scalar row keeps the @encode() of the
	facade's return type, so its result (or the "cannot be called" error) is the one the selector
	path read from the same encoding, and a row whose signature matched nothing (NotCallable)
	answers that error. Every other name answers "does not respond": the root classes' selectors
	(the weak-reference root and OOObject: lifetime, weak reference, description), the scalar selectors with
	arguments, which callObjC() called with the arguments missing, and the facade's other
	selectors with arguments, whose signatures matched nothing ("cannot be called" until then).
*/
enum class MonitorMethodForm { VoidVoid, VoidString, PListString, Scalar, NotCallable };

struct MonitorMethod
{
	const char			*name;
	MonitorMethodForm	form;
	void				(*voidVoid)(OODebugMonitor *);
	void				(*voidString)(OODebugMonitor *, const std::string &);
	oo::PList			(*pListString)(OODebugMonitor *, const std::string &);
	long long			(*scalar)(OODebugMonitor *);
	const char			*encoding;		// a Scalar row: @encode() of the facade's return type
};

const MonitorMethod kMonitorMethods[] =
{
	{ "performJSConsoleCommand:",	MonitorMethodForm::VoidString,	nullptr, [](OODebugMonitor *m, const std::string &s) { m->performJSConsoleCommand(s); }, nullptr, nullptr, nullptr },
	{ "configurationValueForKey:",	MonitorMethodForm::PListString,	nullptr, nullptr, [](OODebugMonitor *m, const std::string &s) { return m->configurationValueForKey(s); }, nullptr, nullptr },
	{ "clearJSConsole",				MonitorMethodForm::VoidVoid,	[](OODebugMonitor *m) { m->clearJSConsole(); }, nullptr, nullptr, nullptr, nullptr },
	{ "showJSConsole",				MonitorMethodForm::VoidVoid,	[](OODebugMonitor *m) { m->showJSConsole(); }, nullptr, nullptr, nullptr, nullptr },
	{ "dumpMemoryStatistics",		MonitorMethodForm::VoidVoid,	[](OODebugMonitor *m) { m->dumpMemoryStatistics(); }, nullptr, nullptr, nullptr, nullptr },
#if OOLITE_GNUSTEP
	{ "applicationWillTerminate",	MonitorMethodForm::VoidVoid,	[](OODebugMonitor *m) { m->applicationWillTerminate(); }, nullptr, nullptr, nullptr, nullptr },
#endif
	{ "debuggerConnected",			MonitorMethodForm::Scalar,		nullptr, nullptr, nullptr, [](OODebugMonitor *m) -> long long { return m->debuggerConnected(); }, kOOTypeEncoding<BOOL> },
	{ "TCPIgnoresDroppedPackets",	MonitorMethodForm::Scalar,		nullptr, nullptr, nullptr, [](OODebugMonitor *m) -> long long { return m->TCPIgnoresDroppedPackets(); }, kOOTypeEncoding<BOOL> },
	{ "usingPlugInController",		MonitorMethodForm::Scalar,		nullptr, nullptr, nullptr, [](OODebugMonitor *m) -> long long { return m->usingPlugInController(); }, kOOTypeEncoding<BOOL> },
	{ "configurationKeys",			MonitorMethodForm::NotCallable,	nullptr, nullptr, nullptr, nullptr, nullptr },	// a std::vector result
	{ "dumpJSMemoryStatistics",		MonitorMethodForm::Scalar,		nullptr, nullptr, nullptr, [](OODebugMonitor *m) -> long long { return static_cast<long long>(m->dumpJSMemoryStatistics()); }, kOOTypeEncoding<size_t> },
};


// OOJSCallObjCObjectMethod()'s steps for the facade's selectors, on the table above.
bool CallMonitorMethod(ooscript::Context context, OODebugMonitor *monitor, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult)
{
	const std::string className;	// the facade's -cxx_oo_jsClassName (OOObject's: none)
	if (argc == 0)
	{
		cxx_OOJSReportError(context, "%s.callObjC(): no selector specified.", className.c_str());
		return false;
	}

	const std::optional<std::string> name = cxx_OOStringFromJSValue(context, argv[0]);
	std::optional<std::string> parameter;
	if (1 < argc && name.has_value() && oo::str::hasSuffix(*name, ":"))
	{
		std::string joined;
		for (unsigned i = 1; i < argc; i++)
		{
			if (i > 1)  joined += " ";
			joined += cxx_OOStringFromJSValueEvenIfNull(context, argv[i]).value_or(std::string());
		}
		parameter = joined;
	}

	const MonitorMethod *method = nullptr;
	if (name.has_value())
	{
		for (const MonitorMethod &row : kMonitorMethods)
		{
			if (*name == row.name)  method = &row;
		}
	}
	const char *nameString = name.has_value() ? name->c_str() : "(null)";
	if (method == nullptr)
	{
		cxx_OOJSReportError(context, "%s.callObjC(): %s does not respond to method %s.", className.c_str(), monitor->description().c_str(), nameString);
		return false;
	}

	oo::PList result;
	switch (method->form)
	{
		case MonitorMethodForm::VoidString:
		case MonitorMethodForm::PListString:
			if (!parameter.has_value())
			{
				cxx_OOJSReportError(context, "%s.callObjC(): method %s requires a parameter.", className.c_str(), nameString);
				return false;
			}
			if (method->form == MonitorMethodForm::VoidString)  method->voidString(monitor, *parameter);
			else  result = method->pListString(monitor, *parameter);
			break;

		case MonitorMethodForm::VoidVoid:
			method->voidVoid(monitor);
			break;

		case MonitorMethodForm::Scalar:
			switch (OOShaderUniformTypeFromEncoding(method->encoding))
			{
				case kOOShaderUniformTypeChar:
				case kOOShaderUniformTypeUnsignedChar:
				case kOOShaderUniformTypeShort:
				case kOOShaderUniformTypeUnsignedShort:
				case kOOShaderUniformTypeInt:
				case kOOShaderUniformTypeUnsignedInt:
				case kOOShaderUniformTypeLong:
					result = oo::PList::signedInteger(method->scalar(monitor));
					break;

				case kOOShaderUniformTypeUnsignedLong:
					result = oo::PList::unsignedInteger(static_cast<unsigned long long>(method->scalar(monitor)));
					break;

				default:
					// size_t on Windows (unsigned long long) matched no template.
					cxx_OOJSReportError(context, "%s.callObjC(): method %s cannot be called from JavaScript.", className.c_str(), nameString);
					return false;
			}
			break;

		case MonitorMethodForm::NotCallable:
			cxx_OOJSReportError(context, "%s.callObjC(): method %s cannot be called from JavaScript.", className.c_str(), nameString);
			return false;
	}

	if (!result.isNull())  *outResult = OOJSValueFromPList(context, result);
	return true;
}

}	// namespace


// function callObjC(selector : String [, ...]) : Object
static bool ConsoleCallObjCMethod(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ooscript::Value					result;
	bool					OK;
	
	// The console objects hold the C++ monitor (bead oo-9ht.74): its table, not a selector.
	if (OODebugMonitor *monitor = MonitorFromJSObject(context, OOJS_THIS))
	{
		OOJSPauseTimeLimiter();
		result = ooscript::undefinedValue();
		OK = CallMonitorMethod(context, monitor, oojsArgs.count(), OOJS_ARGV, &result);
		OOJSResumeTimeLimiter();
		OOJS_SET_RVAL(result);
		return OK;
	}
	
	// An entity's `this` converts to its entity node, whose C++ entity this takes (bead
	// oo-9ht.39.5.3) and calls by its name table (bead oo-9ht.44).
	// Any other `this` held no Objective-C object since none is made (bead oo-4aq6a.5 deleted the
	// object path and its node): the error below, as for a plain JS object.
	const oo::PList thisNode = cxx_OOJSPListFromJSObject(context, OOJS_THIS);
	Entity *entity = oo::EntityIn(thisNode);
	if (entity == nullptr)
	{
		cxx_OOJSReportError(context, "Attempt to call __callObjCMethod() for non-Objective-C object %s.", cxx_OOStringFromJSValueEvenIfNull(context, ooscript::objectValue(OOJS_THIS)).value_or("(null)").c_str());
		return false;
	}
	
	OOJSPauseTimeLimiter();
	result = ooscript::undefinedValue();
	// The class name of the error texts: an entity's is its C++ part's (bead oo-9ht.39.5.1), the
	// answer its object's -cxx_oo_jsClassName forwarded to.
	std::optional<std::string> className = OOJSEntityJSClassName(entity);
	OK = OOJSCallEntityMethod(context, entity, className.value_or(std::string()), oojsArgs.count(), OOJS_ARGV, &result);
	OOJSResumeTimeLimiter();
	
	OOJS_SET_RVAL(result);
	return OK;
	
	OOJS_NATIVE_EXIT
}


// function __setUpCallObjC(object) -- object is expected to be Object.prototye.
static bool ConsoleSetUpCallObjC(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!ooscript::isObjectOrNull(OOJS_ARGV[0])))
	{
		cxx_OOJSReportBadArguments(context, "Console", "__setUpCallObjC", oojsArgs.count(), OOJS_ARGV, std::nullopt, "Object.prototype");
		return false;
	}
	
	ooscript::Object obj = ooscript::toObject(OOJS_ARGV[0]);
	ooscript::defineFunction(context, obj, "callObjC", ConsoleCallObjCMethod, 1, OOJS_METHOD_READONLY);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
#endif


// function isExecutableJavaScript(this : Object, string : String) : Boolean
static bool ConsoleIsExecutableJavaScript(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	bool					result = false;
	ooscript::Object target = NULL;
	
	if (oojsArgs.count() < 2 || !ooscript::valueToObject(context, OOJS_ARGV[0], &target) || !ooscript::isString(OOJS_ARGV[1]))
	{
		OOJS_RETURN_BOOL(false);	// Fail silently
	}
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	
	// FIXME: this must be possible using just JSAPI functions.
	const std::string string = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]).value_or(std::string());	// its UTF-8 bytes
	result = ooscript::bufferIsCompilableUnit(context, target, string.data(), string.size());
	
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


// function displayMessagesInClass(class : String) : Boolean
static bool ConsoleDisplayMessagesInClass(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	messageClass;

	messageClass = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	OOJS_RETURN_BOOL(messageClass.has_value() && oo::log::willDisplay(*messageClass));
	
	OOJS_NATIVE_EXIT
}


// function setDisplayMessagesInClass(class : String, flag : Boolean) : void
static bool ConsoleSetDisplayMessagesInClass(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	messageClass;
	bool					flag;

	messageClass = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (messageClass.has_value() && ooscript::valueToBoolean(context, OOJS_ARGV[1], &flag))
	{
		oo::log::logger().setDisplay(*messageClass, flag);
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function writeLogMarker() : void
static bool ConsoleWriteLogMarker(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	OOLogInsertMarker();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function writeMemoryStats() : void
static bool ConsoleWriteMemoryStats(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJS_BEGIN_FULL_NATIVE(context)
	OODebugMonitor::sharedDebugMonitor()->dumpMemoryStatistics();
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function writeJSMemoryStats() : void
static bool ConsoleWriteJSMemoryStats(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJS_BEGIN_FULL_NATIVE(context)
	OODebugMonitor::sharedDebugMonitor()->dumpJSMemoryStatistics();
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function garbageCollect() : string
static bool ConsoleGarbageCollect(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	uint32_t bytesBefore = ooscript::getGCParameter(ooscript::getRuntime(context), ooscript::GCParam::Bytes);
	ooscript::gc(context);
	uint32_t bytesAfter = ooscript::getGCParameter(ooscript::getRuntime(context), ooscript::GCParam::Bytes);
	
	OOJS_RETURN_PLIST(oo::PList(oo::str::format("Bytes before: %u Bytes after: %u", bytesBefore, bytesAfter)));
	
	OOJS_NATIVE_EXIT
}


#if DEBUG
typedef struct
{
	ooscript::Context context;
	FILE			*file;
} DumpCallbackData;

static void DumpCallback(const char *name, void *rp, ooscript::RootKind type, void *datap)
{
	assert(type == ooscript::RootKind::Value || type == ooscript::RootKind::GCThing);
	
	DumpCallbackData *data = static_cast<DumpCallbackData *>(datap);
	
	const char *typeString = "unknown type";
	ooscript::Value value;
	switch (type)
	{
		case ooscript::RootKind::Value:
			typeString = "value";
			value = *(ooscript::Value *)rp;
			break;
			
		case ooscript::RootKind::GCThing:
			typeString = "gc-thing";
			value = ooscript::objectValue(*(ooscript::Object *)rp);
	}
	
	fprintf(data->file, "%s @ %p (%s): %s\n", name, rp, typeString, cxx_OOJSDescribeValue(data->context, value, false).c_str());
}


static bool ConsoleDumpNamedRoots(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	bool OK = false;
	{
		const std::optional<std::string> diagnosticDirectory = ResourceManager::diagnosticFileLocation();
		const std::string path = diagnosticDirectory.has_value() ? oo::str::appendingPathComponent(*diagnosticDirectory, "js-roots.txt") : std::string();
		FILE *file = fopen(path.c_str(), "w");
		if (file != NULL)
		{
			DumpCallbackData data =
			{
				.context = context,
				.file = file
			};
			ooscript::dumpNamedRoots(ooscript::getRuntime(context), DumpCallback, &data);
			fclose(file);
			OK = true;
		}
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


static bool ConsoleDumpHeap(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	bool OK = false;
	const std::optional<std::string> diagnosticDirectory = ResourceManager::diagnosticFileLocation();
	const std::string path = diagnosticDirectory.has_value() ? oo::str::appendingPathComponent(*diagnosticDirectory, "js-heaps.txt") : std::string();
	FILE *file = fopen(path.c_str(), "w");
	if (file != NULL)
	{
		OK = ooscript::dumpHeap(context, file);
		fclose(file);
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
#endif


#if OOJS_PROFILE

// function profile(func : function [, Object this = debugConsole.script]) : String
static bool ConsoleProfile(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		cxx_OOJSReportError(context, "Profiling functions may not be called while already profiling.");
		return false;
	}
	
	bool result;
	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		oo::Ref<OOTimeProfile>	profile;
		
		result = PerformProfiling(context, "profile", oojsArgs.count(), OOJS_ARGV, NULL, false, &profile);
		if (result)
		{
			OOJS_SET_RVAL(OOJSValueFromPList(context, profile ? oo::PList(profile->description().value_or("(null)")) : oo::PList()));
		}
	}
	
	return result;
	
	OOJS_NATIVE_EXIT
}


// function getProfile(func : function [, Object this = debugConsole.script]) : Object { totalTime : Number, jsTime : Number, extensionTime : Number }
static bool ConsoleGetProfile(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		cxx_OOJSReportError(context, "Profiling functions may not be called while already profiling.");
		return false;
	}
	
	bool result;
	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		oo::Ref<OOTimeProfile>	profile;
		
		result = PerformProfiling(context, "getProfile", oojsArgs.count(), OOJS_ARGV, NULL, false, &profile);
		if (result)
		{
			OOJS_SET_RVAL(profile ? profile->oo_jsValueInContext(context) : ooscript::undefinedValue());
		}
	}
	
	return result;
	
	OOJS_NATIVE_EXIT
}


// function trace(func : function [, Object this = debugConsole.script]) : [return type of func]
static bool ConsoleTrace(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		cxx_OOJSReportError(context, "Profiling functions may not be called while already profiling.");
		return false;
	}
	
	ooscript::Value				rval;
	bool result;
	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		result = PerformProfiling(context, "trace", oojsArgs.count(), OOJS_ARGV, &rval, true, NULL);
		if (result)
		{
			OOJS_SET_RVAL(rval);
		}
	}
	
	return result;
	
	OOJS_NATIVE_EXIT
}


namespace {

bool PerformProfiling(ooscript::Context context, const char *nominalFunction, unsigned argc, ooscript::Value *argv, ooscript::Value *outRval, bool trace, oo::Ref<OOTimeProfile> *outProfile)
{
	// Get function.
	ooscript::Value function = argv[0];
	if (!OOJSValueIsFunction(context, function))
	{
		cxx_OOJSReportBadArguments(context, "Console", nominalFunction, 1, argv, std::nullopt, "function");
		return false;
	}
	
	// Get "this" object.
	ooscript::Value thisVal;
	if (argc > 1)  thisVal = argv[1];
	else
	{
		ooscript::Value debugConsole = OODebugMonitor::sharedDebugMonitor()->jsValueInContext(context);	// the facade's -oo_jsValueInContext: until bead oo-9ht.74
		assert(ooscript::isObjectOrNull(debugConsole) && !ooscript::isNull(debugConsole));
		ooscript::getProperty(context, ooscript::toObject(debugConsole), "script", &thisVal);
	}
	
	ooscript::Object thisObj;
	if (!ooscript::valueToObject(context, thisVal, &thisObj))  thisObj = NULL;
	
	ooscript::Value ignored;
	if (outRval == NULL)  outRval = &ignored;
	
	// Fiddle with time limiter.
	// We want to save the current limit, reset the limiter, and set the time limit to a long time.
#define LONG_TIME (1e7)	// A long time - 115.7 days - but, crucially, finite.
	
	OOTimeDelta originalLimit = OOJSGetTimeLimiterLimit();
	OOJSSetTimeLimiterLimit(LONG_TIME);
	OOJSResetTimeLimiter();
	
	OOJSBeginProfiling(trace);
	
	// Call the function.
	bool result = ooscript::callFunctionValue(context, thisObj, function, 0, NULL, outRval);
	
	// Get results.
	oo::Ref<OOTimeProfile> profile = OOJSEndProfiling();
	if (outProfile != NULL)  *outProfile = std::move(profile);
	
	// Restore original timer state.
	OOJSSetTimeLimiterLimit(originalLimit);
	OOJSResetTimeLimiter();
	
	ooscript::reportPendingException(context);
	
	return result;
}

}	// namespace

#endif // OOJS_PROFILE

#endif /* NDEBUG */
