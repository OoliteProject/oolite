/*

OOJavaScriptEngine.m

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

#include "OOJavaScriptEngine.h"
#include "OOJSEngineTimeManagement.h"
#include "OOJSScript.h"

#include "ooscript/JSEngine.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"
#include <cstring>
#include "oofnd/StdLib.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): every engine call goes through its ooscript:: equivalent, and
	the natives shared with the class files (OOJSUnconstructableConstruct,
	OOJSObjectWrapperToString, OOJSObjectWrapperFinalize) take the façade signatures directly.

	The debugging support below -- the stack walk in OOJSDumpStack, GetLocationNameAndLine and
	DumpVariable, and the `debugger` statement hook -- uses the façade's "Debugging and
	profiling" section (frameIterator / frameScript / frameScopeChain / getScopeVariables /
	setDebuggerHandler, bead oo-1gc.3). The engine's local root scopes around
	the array and dictionary value converters (now OOJSValueFromPList's helpers)
	are superseded by explicit roots, as
	ooscript/README.md describes: ooscript::RootedValue roots the value about to be handed to
	the caller.

	Three façade functions were added for this file (ooscript::internUCStringN,
	ooscript::clearScope, ooscript::setCStringsAreUTF8), each a 1:1 wrap of the engine call of
	the same name. Two more, ooscript::isThreadsafeBuild and ooscript::gcZealSupported, report
	the engine build-configuration values this file used to test with preprocessor guards, so
	the two guarded blocks below are runtime `if`s with identical behaviour.
*/

#include "OOObjCPList.h"		// Object nodes (OOJSValueFromPList)
#include "OOJSPrivateObject.h"
#include "Universe.h"
#include "OOPlanetEntity.h"
#include "EntityOOJavaScriptExtensions.h"
#include "ResourceManager.h"
#include "OOConstToJSString.h"
#include "OOVisualEffectEntity.h"
#include "OOWaypointEntity.h"

#include "OOJSGlobal.h"
#include "OOJSMissionVariables.h"
#include "OOJSMission.h"
#include "OOJSVector.h"
#include "OOJSQuaternion.h"
#include "OOJSEntity.h"
#include "OOJSShip.h"
#include "OOJSStation.h"
#include "OOJSDock.h"
#include "OOJSVisualEffect.h"
#include "OOJSExhaustPlume.h"
#include "OOJSFlasher.h"
#include "OOJSWormhole.h"
#include "OOJSWaypoint.h"
#include "OOJSPlayer.h"
#include "OOJSPlayerShip.h"
#include "OOJSManifest.h"
#include "OOJSPlanet.h"
#include "OOJSSystem.h"
#include "OOJSOolite.h"
#include "OOJSTimer.h"
#include "OOJSClock.h"
#include "OOJSSun.h"
#include "OOJSWorldScripts.h"
#include "OOJSSound.h"
#include "OOJSSoundSource.h"
#include "OOJSSpecialFunctions.h"
#include "OOJSSpecialFunctions.h"
#include "OOJSSystemInfo.h"
#include "OOJSEquipmentInfo.h"
#include "OOJSShipGroup.h"
#include "OOJSFrameCallbacks.h"
#include "OOJSFont.h"

#include "OOProfilingStopwatch.h"
#include "OOLoggingExtended.h"
#include "oofnd/objc/OOException.h"

#include "oofnd/objc/OOAssert.h"

#include <stdlib.h>


#define OOJSENGINE_JSVERSION		ooscript::Version::ECMA5
#ifdef DEBUG
#define JIT_OPTIONS					ooscript::ContextOption::None
#else
#define JIT_OPTIONS					(ooscript::ContextOption::Jit | ooscript::ContextOption::MethodJit | ooscript::ContextOption::Profiling)
#endif
#define OOJSENGINE_CONTEXT_OPTIONS	(ooscript::ContextOption::VarObjFix | ooscript::ContextOption::RegExpLimit | ooscript::ContextOption::AnonFunFix | JIT_OPTIONS)


#define OOJS_STACK_SIZE				8192
#define OOJS_RUNTIME_SIZE_MiB			256


namespace {
static OOJavaScriptEngine	*sSharedEngine = nullptr;	// the one +1 is never released (amendment oo-r7m0 item 1)
} // namespace
namespace {
static unsigned				sErrorHandlerStackSkip = 0;
} // namespace

ooscript::Context gOOJSMainThreadContext = NULL;


const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";
const char * const kOOJavaScriptEngineDidResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine did reset";


namespace {
static void ReportJSError(ooscript::Context context, const char *message, const ooscript::ErrorReport *report);
} // namespace

namespace {
static oo::PList JSArrayConverter(ooscript::Context context, ooscript::Object object);
} // namespace
namespace {
static oo::PList JSStringConverter(ooscript::Context context, ooscript::Object object);
} // namespace
namespace {
static oo::PList JSNumberConverter(ooscript::Context context, ooscript::Object object);
} // namespace
namespace {
static oo::PList JSBooleanConverter(ooscript::Context context, ooscript::Object object);
} // namespace
namespace {
static oo::PList JSPlainObjectConverter(ooscript::Context context, ooscript::Object object);
} // namespace


namespace {
static void UnregisterObjectConverters(void);
} // namespace
namespace {
static void UnregisterSubclasses(void);
} // namespace


namespace {
static void ReportJSError(ooscript::Context context, const char *message, const ooscript::ErrorReport *report)
{
	std::string			severity = "error";
	std::string			messageText;
	std::string			lineBuf;
	std::string			messageClass;
	std::string			highlight = "*****";
	std::string			activeScript;
OOJavaScriptEngine	*jsEng = OOJavaScriptEngine::sharedEngine();
	bool				showLocation = jsEng->showErrorLocations();
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use the engine while paused.
	OOJSPauseTimeLimiter();
	
	static const ooscript::Char16 emptyUC[1] = { 0 };
	ooscript::ErrorReport blankReport =
	{
		.filename = "<unspecified file>",
		.lineno = 0,
		.flags = 0,
		.errorNumber = 0,
		.ucmessage = emptyUC,
		.linebuf = emptyUC
	};
	if (EXPECT_NOT(report == NULL))  report = &blankReport;
	if (EXPECT_NOT(message == NULL || *message == '\0'))  message = "<unspecified error>";
	
	// Type of problem: error, warning or exception? (Strict flag wilfully ignored.)
	if (report->flags & static_cast<unsigned>(ooscript::ReportFlag::Exception)) severity = "exception";
	else if (report->flags & static_cast<unsigned>(ooscript::ReportFlag::Warning))
	{
		severity = "warning";
		highlight = "-----";
	}

	// The error message itself
	messageText = message;

	// Get offending line, if present, and trim trailing line breaks
	// The report's linebuf may be NULL (ooscript's ErrorReport; the QuickJS engine never sets it):
	// a string_view of NULL read through a null pointer and crashed every report (bead
	// oo-9ht.142). NULL reads as no line, as it did before the Foundation sweep (oo-3rb.203).
	if (report->linebuf != NULL)  lineBuf = oo::utf16ToUtf8(std::u16string_view(report->linebuf));
	while (oo::str::hasSuffix(lineBuf, "\n") || oo::str::hasSuffix(lineBuf, "\r"))  lineBuf.pop_back();

	// Get string for error number, for useful log message classes
	const oo::PList errorNames = ResourceManager::dictionaryFromFilesNamed("javascript-errors.plist", "Config", true);
	const std::string errorNumberStr = oo::str::format("%u", report->errorNumber);
	const std::string errorName = errorNames.get<std::string>(errorNumberStr, errorNumberStr);

	// Log message class
	messageClass = "script.javaScript." + severity + "." + errorName;

	// Skip the rest if this is a warning being ignored.
	if ((report->flags & static_cast<unsigned>(ooscript::ReportFlag::Warning)) == 0 || oo::log::willDisplay(messageClass))
	{
		// First line: problem description
		// avoid windows DEP exceptions!
		// The running script (C++ since bead oo-9ht.133; null when none runs, or once a script a timer or
		// definition pushed weakly has gone: a message to nil).
		OOJSScript *runningScript = OOJSScript::currentlyRunningScript();
		activeScript = ((runningScript != nullptr) ? runningScript->displayName() : std::nullopt).value_or("<unidentified script>");

		OO_LOG(messageClass, "{} JavaScript {} ({}): {}", highlight, severity, activeScript, messageText);

		if (showLocation && sErrorHandlerStackSkip == 0 && report->filename != NULL)
		{
			// Second line: where error occured, and line if provided. (The line is only provided for compile-time errors, not run-time errors.)
			if (!lineBuf.empty())
			{
				OO_LOG(messageClass, "      {}, line {}: {}", report->filename, report->lineno, lineBuf);
			}
			else
			{
				OO_LOG(messageClass, "      {}, line {}.", report->filename, report->lineno);
			}
		}

#ifndef NDEBUG
		bool dump;
		if (report->flags & static_cast<unsigned>(ooscript::ReportFlag::Warning))  dump = jsEng->dumpStackForWarnings();
		else  dump = jsEng->dumpStackForErrors();
		if (dump)  OOJSDumpStack((context));
#endif
		
#if OOJSENGINE_MONITOR_SUPPORT
		ooscript::ExceptionState *exState = ooscript::saveExceptionState(context);
		ooscript::ErrorReport nativeReport = *report;
		OOJavaScriptEngine::sharedEngine()->sendMonitorError(&nativeReport, messageText, (context));
		ooscript::restoreExceptionState(context, exState);
#endif
	}
	
	OOJSResumeTimeLimiter();
}
} // namespace


//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	if (sSharedEngine == nullptr)
	{
		// The one +1, never released (amendment oo-r7m0 item 1). Recorded before init() runs, as
		// -init recorded self before it made the context, so a re-entrant sharedEngine() answers
		// the engine being set up (amendment oo-3bgz item 3).
		OOJavaScriptEngine *engine = oo::makeRef<OOJavaScriptEngine>().leakRef();
		sSharedEngine = engine;
		engine->init();
	}

	return sSharedEngine;
}


void OOJavaScriptEngine::runMissionCallback()
{
	MissionRunCallback();
}


void OOJavaScriptEngine::init()
{
	// -init asserted that no engine existed yet; sharedEngine() makes only this one.
	OOCAssert(sSharedEngine == this, "Attempt to create multiple OOJavaScriptEngines.");

	ooscript::setCStringsAreUTF8();

	oo::Defaults &defaults = oo::Defaults::standard();
#ifndef NDEBUG
	/*	Set stack trace preferences from preferences. These will be overriden
		by the debug OXP script if installed, but being able to enable traces
		without setting up the debug console could be useful for debugging
		users' problems.
	*/
	setDumpStackForErrors(defaults.boolForKey("dump-stack-for-errors"));
	setDumpStackForWarnings(defaults.boolForKey("dump-stack-for-warnings"));
#endif
	
	assert(sizeof(ooscript::Char16) == sizeof(uint16_t));
	
	// initialize the JS run time, and return result in runtime.
	const oo::PList jsRuntimeSize = defaults.object("jsruntime-size-mib");
	uint32_t jsRuntimeInMiB = static_cast<uint32_t>(oo::PListGet<int>::from(jsRuntimeSize.isNull() ? nullptr : &jsRuntimeSize, OOJS_RUNTIME_SIZE_MiB));
	_runtime = ooscript::newRuntime(jsRuntimeInMiB * 1024L * 1024L);
	
	// if runtime creation failed, end the program here.
	if (_runtime == NULL)
	{
		OO_LOG("script.javaScript.init.error", "***** FATAL ERROR: failed to create JavaScript runtime with size {}MiB.", static_cast<unsigned>(jsRuntimeInMiB));
		exit(1);
	}
	
	// OOJSTimeManagementInit() must be called before any context is created!
	OOJSTimeManagementInit(this, _runtime);	// the watchdog holds the engine
	
	createMainThreadContext();
}


void OOJavaScriptEngine::createMainThreadContext()
{
	OOCAssert(gOOJSMainThreadContext == NULL, "-[OOJavaScriptEngine createMainThreadContext] called while the main thread context exists.");
	
	// create a context and associate it with the JS runtime.
	gOOJSMainThreadContext = (ooscript::newContext(_runtime, OOJS_STACK_SIZE));
	
	// if context creation failed, end the program here.
	if (gOOJSMainThreadContext == NULL)
	{
		OO_LOG("script.javaScript.init.error", "{}", "***** FATAL ERROR: failed to create JavaScript context.");
		exit(1);
	}
	
	ooscript::beginRequest((gOOJSMainThreadContext));
	
	ooscript::setOptions((gOOJSMainThreadContext), OOJSENGINE_CONTEXT_OPTIONS);  // NOLINT(clang-analyzer-optin.core.EnumCastOutOfRange): OOJSENGINE_CONTEXT_OPTIONS ORs ContextOption flag bits through JSEngine.hpp's own constexpr operator|; the enum is a bitmask, not a closed set, so the analyzer's "value not a declared enumerator" is a false positive on every legitimate flag combination -- see JSEngine.hpp's own operator| for the same pattern used by OOJSVector.mm's PropertyFlag/ClassFlag tables.
	ooscript::setVersion((gOOJSMainThreadContext), OOJSENGINE_JSVERSION);
	
	if (ooscript::gcZealSupported())
	{
		const oo::PList gcZealValue = oo::Defaults::standard().object("js-gc-zeal");
		uint8_t gcZeal = static_cast<uint8_t>(oo::PListGet<unsigned char>::from(gcZealValue.isNull() ? nullptr : &gcZealValue, 0));
		if (gcZeal > 0)
		{
			// Useful js-gc-zeal values are 0 (off), 1 and 2.
			OO_LOG("script.javaScript.debug.gcZeal", "Setting JavaScript garbage collector zeal to {}.", static_cast<unsigned>(gcZeal));
			ooscript::setGCZeal((gOOJSMainThreadContext), gcZeal);
		}
	}
	
	ooscript::setErrorReporter((gOOJSMainThreadContext), ReportJSError);
	
	// Create the global object.
	CreateOOJSGlobal(gOOJSMainThreadContext, &_globalObject);
	
	// Initialize the built-in JS objects and the global object.
	ooscript::initStandardClasses((gOOJSMainThreadContext), (_globalObject));
	if (!lookUpStandardClassPointers())
	{
		OO_LOG("script.javaScript.init.error", "{}", "***** FATAL ERROR: failed to look up standard JavaScript classes.");
		exit(1);
	}
	registerStandardObjectConverters();
	
	SetUpOOJSGlobal(gOOJSMainThreadContext, _globalObject);
	OOConstToJSStringInit(gOOJSMainThreadContext);
	
	// Initialize Oolite classes.
	InitOOJSMissionVariables(gOOJSMainThreadContext, _globalObject);
	InitOOJSMission(gOOJSMainThreadContext, _globalObject);
	InitOOJSOolite(gOOJSMainThreadContext, _globalObject);
	InitOOJSVector(gOOJSMainThreadContext, _globalObject);
	InitOOJSQuaternion(gOOJSMainThreadContext, _globalObject);
	InitOOJSSystem(gOOJSMainThreadContext, _globalObject);
	InitOOJSEntity(gOOJSMainThreadContext, _globalObject);
	InitOOJSShip(gOOJSMainThreadContext, _globalObject);
	InitOOJSStation(gOOJSMainThreadContext, _globalObject);
	InitOOJSDock(gOOJSMainThreadContext, _globalObject);
	InitOOJSVisualEffect(gOOJSMainThreadContext, _globalObject);
	InitOOJSExhaustPlume(gOOJSMainThreadContext, _globalObject);
	InitOOJSFlasher(gOOJSMainThreadContext, _globalObject);
	InitOOJSWormhole(gOOJSMainThreadContext, _globalObject);
	InitOOJSWaypoint(gOOJSMainThreadContext, _globalObject);
	InitOOJSPlayer(gOOJSMainThreadContext, _globalObject);
	InitOOJSPlayerShip(gOOJSMainThreadContext, _globalObject);
	InitOOJSManifest(gOOJSMainThreadContext, _globalObject);
	InitOOJSSun(gOOJSMainThreadContext, _globalObject);
	InitOOJSPlanet(gOOJSMainThreadContext, _globalObject);
	InitOOJSScript(gOOJSMainThreadContext, _globalObject);
	InitOOJSTimer(gOOJSMainThreadContext, _globalObject);
	InitOOJSClock(gOOJSMainThreadContext, _globalObject);
	InitOOJSWorldScripts(gOOJSMainThreadContext, _globalObject);
	InitOOJSSound(gOOJSMainThreadContext, _globalObject);
	InitOOJSSoundSource(gOOJSMainThreadContext, _globalObject);
	InitOOJSSpecialFunctions(gOOJSMainThreadContext, _globalObject);
	InitOOJSSystemInfo(gOOJSMainThreadContext, _globalObject);
	InitOOJSEquipmentInfo(gOOJSMainThreadContext, _globalObject);
	InitOOJSShipGroup(gOOJSMainThreadContext, _globalObject);
	InitOOJSFrameCallbacks(gOOJSMainThreadContext, _globalObject);
	InitOOJSFont(gOOJSMainThreadContext, _globalObject);
	
	// Run prefix scripts.
	OOScriptAutorelease(OOScript::jsScriptFromFileNamed("oolite-global-prefix.js",	// (nothing keeps it)
														oo::PList(oo::PList::Dict{{"special", OOJSValueObjectNode(JSSpecialFunctionsObjectWrapper(gOOJSMainThreadContext).get())}})));

	ooscript::endRequest((gOOJSMainThreadContext));
	
	OO_LOG("script.javaScript.init.success", "{}", "Set up JavaScript context.");
}


void OOJavaScriptEngine::destroyMainThreadContext()
{
	if (gOOJSMainThreadContext != NULL)
	{
		ooscript::Context context = OOJSAcquireContext();
		ooscript::clearScope((gOOJSMainThreadContext), (_globalObject));
		
		_globalObject = NULL;
		_objectClass = NULL;
		_stringClass = NULL;
		_arrayClass = NULL;
		_numberClass = NULL;
		_booleanClass = NULL;
		
		UnregisterObjectConverters();
		UnregisterSubclasses();
		OOConstToJSStringDestroy();
		
		OOJSRelinquishContext(context);
		
		_globalObject = NULL;
		ooscript::destroyContext((gOOJSMainThreadContext));	// Forces unconditional GC.
		gOOJSMainThreadContext = NULL;
	}
}


bool OOJavaScriptEngine::reset()
{
	OOCAssert(gOOJSMainThreadContext != NULL, "JavaScript engine not active. Can't reset.");
	
	OOJSFrameCallbacksRemoveAll();
	
# if 0
	// deferred JS reset - test harness.
	static int counter = 3;		// loading a savegame with different strict mode calls js reset twice
	if (counter-- == 0) {
	counter = 3;
	OO_LOG("script.javascript.init.error", "{}", "JavaScript processes still pending. Can't reset JavaScript engine.");
		return false;
	}
	else
	{
		OO_LOG("script.javascript.init", "{}", "JavaScript reset successful.");
	}
#endif
		
	if (ooscript::isThreadsafeBuild())
	{
		//OOAssert(!ooscript::isInRequest((gOOJSMainThreadContext)), "JavaScript processes still pending. Can't reset JavaScript engine.");
		
		if (ooscript::isInRequest((gOOJSMainThreadContext)))
		{
			// some threads are still pending, this should mean timers are still being removed.
			OO_LOG("script.javascript.init.error", "{}", "JavaScript processes still pending. Can't reset JavaScript engine.");
			return false;
		}
		else
		{
			OO_LOG("script.javascript.init", "{}", "JavaScript reset successful.");
		}
	}
	
	ooscript::Context context = OOJSAcquireContext();
	oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, this);	// the engine: what observers filter on
OOJSRelinquishContext(context);
	
	destroyMainThreadContext();
	createMainThreadContext();
	
	context = OOJSAcquireContext();
	oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineDidResetNotificationName, this);
OOJSRelinquishContext(context);
	
	garbageCollectionOpportunity(true);
	return true;
}


OOJavaScriptEngine::~OOJavaScriptEngine()
{
	sSharedEngine = nullptr;
	
	OOJSFrameCallbacksRemoveAll();
	
	destroyMainThreadContext();
	ooscript::destroyRuntime(_runtime);
}


bool OOJavaScriptEngine::lookUpStandardClassPointers()
{
	ooscript::Object templateObject = NULL;
	
	templateObject = (ooscript::newObject((gOOJSMainThreadContext), NULL, NULL, NULL));
	if (EXPECT_NOT(templateObject == NULL))  return false;
	_objectClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	{
		ooscript::Object obj = (templateObject);
		if (EXPECT_NOT(!ooscript::valueToObject((gOOJSMainThreadContext), ooscript::emptyStringValue((gOOJSMainThreadContext)), &obj)))  return false;
		templateObject = (obj);
	}
	_stringClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	templateObject = (ooscript::newArrayObject((gOOJSMainThreadContext), 0, NULL));
	if (EXPECT_NOT(templateObject == NULL))  return false;
	_arrayClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	{
		ooscript::Object obj = (templateObject);
		if (EXPECT_NOT(!ooscript::valueToObject((gOOJSMainThreadContext), ooscript::int32Value(0), &obj)))  return false;
		templateObject = (obj);
	}
	_numberClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	{
		ooscript::Object obj = (templateObject);
		if (EXPECT_NOT(!ooscript::valueToObject((gOOJSMainThreadContext), ooscript::falseValue(), &obj)))  return false;
		templateObject = (obj);
	}
	_booleanClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	return true;
}


void OOJavaScriptEngine::registerStandardObjectConverters()
{
	OOJSRegisterObjectConverter(objectClass(), JSPlainObjectConverter);
	OOJSRegisterObjectConverter(stringClass(), JSStringConverter);
	OOJSRegisterObjectConverter(arrayClass(), JSArrayConverter);
	OOJSRegisterObjectConverter(numberClass(), JSNumberConverter);
	OOJSRegisterObjectConverter(booleanClass(), JSBooleanConverter);
}



ooscript::Object OOJavaScriptEngine::globalObject()
{
	return _globalObject;
}


bool OOJavaScriptEngine::callJSFunction(ooscript::Value function, ooscript::Object jsThis, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult)
{
	ooscript::Context context = NULL;
	bool						result;
	
	OOCParameterAssert(OOJSValueIsFunction(context, function));
	
	context = OOJSAcquireContext();
	
	OOJSStartTimeLimiter();
	result = ooscript::callFunctionValue((context), (jsThis), (function), argc, (argv), (outResult));
	OOJSStopTimeLimiter();
	
	ooscript::reportPendingException((context));
	OOJSRelinquishContext(context);
	
	return result;
}


void OOJavaScriptEngine::removeGCObjectRoot(ooscript::Object *rootPtr)
{
	ooscript::Context context = OOJSAcquireContext();
	ooscript::removeObjectRoot((context), rootPtr);
	OOJSRelinquishContext(context);
}


void OOJavaScriptEngine::removeGCValueRoot(ooscript::Value *rootPtr)
{
	ooscript::Context context = OOJSAcquireContext();
	ooscript::removeValueRoot((context), (rootPtr));
	OOJSRelinquishContext(context);
}


void OOJavaScriptEngine::garbageCollectionOpportunity(bool force)
{
	ooscript::Context context = OOJSAcquireContext();
	if (force)
	{
		ooscript::gc((context));
	}
	else
	{
		ooscript::maybeGC((context));
	}
	OOJSRelinquishContext(context);
}


bool OOJavaScriptEngine::showErrorLocations()
{
	return _showErrorLocations;
}


void OOJavaScriptEngine::setShowErrorLocations(bool value)
{
	_showErrorLocations = !!value;
}


ooscript::ClassDef *OOJavaScriptEngine::objectClass()
{
	return _objectClass;
}


ooscript::ClassDef *OOJavaScriptEngine::stringClass()
{
	return _stringClass;
}


ooscript::ClassDef *OOJavaScriptEngine::arrayClass()
{
	return _arrayClass;
}


ooscript::ClassDef *OOJavaScriptEngine::numberClass()
{
	return _numberClass;
}


ooscript::ClassDef *OOJavaScriptEngine::booleanClass()
{
	return _booleanClass;
}


#ifndef NDEBUG


namespace {
static void DebuggerHook(ooscript::Context context, void * /*closure*/)
{
	OOJSPauseTimeLimiter();
	
	OOJSScript *runningScript = OOJSScript::currentlyRunningScript();
	OO_LOG("script.javaScript.debugger", "debugger invoked during {}:", ((runningScript != nullptr) ? runningScript->displayName() : std::nullopt).value_or("(null)"));
	OOJSDumpStack(context);
	
	OOJSResumeTimeLimiter();
}
} // namespace



bool OOJavaScriptEngine::dumpStackForErrors()
{
	return _dumpStackForErrors;
}


void OOJavaScriptEngine::setDumpStackForErrors(bool value)
{
	_dumpStackForErrors = !!value;
}


bool OOJavaScriptEngine::dumpStackForWarnings()
{
	return _dumpStackForWarnings;
}


void OOJavaScriptEngine::setDumpStackForWarnings(bool value)
{
	_dumpStackForWarnings = !!value;
}


void OOJavaScriptEngine::enableDebuggerStatement()
{
	ooscript::setDebuggerHandler(_runtime, DebuggerHook, this);	// the closure is unused
}
#endif



#if OOJSENGINE_MONITOR_SUPPORT


void OOJavaScriptEngine::setMonitor(OOJavaScriptEngineMonitor *inMonitor)
{
	_monitor = inMonitor;
}


void OOJavaScriptEngine::sendMonitorError(ooscript::ErrorReport *errorReport, const std::string &message, ooscript::Context theContext)
{
	if (_monitor != nullptr)
	{
		_monitor->jsEngine(this, theContext, errorReport, sErrorHandlerStackSkip, showErrorLocations(), message);
	}
}


void OOJavaScriptEngine::sendMonitorLogMessage(const std::optional<std::string> &message, const std::optional<std::string> &messageClass, ooscript::Context theContext)
{
	if (_monitor != nullptr)
	{
		_monitor->jsEngine(this, theContext, message.value_or(""), messageClass);
	}
}


#endif


#ifndef NDEBUG

namespace {
static void DumpVariable(ooscript::Context context, ooscript::Variable *prop)
{
	ooscript::Value nameVal = ooscript::undefinedValue();
	ooscript::idToValue(context, prop->id, &nameVal);
	// ("%@" of a nil name printed "(null)")
	const std::string name = cxx_OOStringFromJSValueEvenIfNull(context, nameVal).value_or("(null)");
	const std::string value = cxx_OOJSDescribeValue(context, prop->value, YES);

	enum   // NOLINT(performance-enum-size): kInterestingFlags is a bitwise complement of small flag values; forcing a narrow base type would truncate the ~ result.
	{
		kInterestingFlags = ~(static_cast<unsigned>(ooscript::VariableFlag::Enumerate) | static_cast<unsigned>(ooscript::VariableFlag::Permanent) | static_cast<unsigned>(ooscript::VariableFlag::Variable) | static_cast<unsigned>(ooscript::VariableFlag::Argument))
	};
	
	std::string flagStr;
	if ((prop->flags & kInterestingFlags) != 0)
	{
		std::vector<std::string> flags;
		if (prop->flags & static_cast<unsigned>(ooscript::VariableFlag::ReadOnly))  flags.emplace_back("read-only");
		if (prop->flags & static_cast<unsigned>(ooscript::VariableFlag::Alias))  flags.push_back("alias (" + cxx_OOJSDescribeValue(context, prop->alias, YES) + ")");
		if (prop->flags & static_cast<unsigned>(ooscript::VariableFlag::Exception))  flags.emplace_back("exception");
		if (prop->flags & static_cast<unsigned>(ooscript::VariableFlag::Error))  flags.emplace_back("error");

		flagStr = " [";
		for (std::size_t i = 0; i != flags.size(); ++i)
		{
			if (i != 0)  flagStr += ", ";
			flagStr += flags[i];
		}
		flagStr += "]";
	}

	OO_LOG("script.javaScript.stackTrace", "    {}: {}{}", name, value, flagStr);
}
} // namespace


void OOJSDumpStack(ooscript::Context context)
{
	{
		oo::AutoreleaseScope pool;	// was an Objective-C autorelease pool (oo-31u.8)
		try
		{
			ooscript::StackFrame	frame = NULL;
			unsigned		idx = 0;
			unsigned		skip = sErrorHandlerStackSkip;
			
			while (ooscript::frameIterator(context, &frame) != NULL)
			{
				ooscript::Script script = ooscript::frameScript(context, frame);
				std::string			desc;
ooscript::VariableList	properties = { 0, NULL, NULL };
				BOOL				gotProperties = NO;
				
				idx++;
				
				if (!ooscript::frameIsScript(context, frame))
				{
					continue;
				}
				
				if (skip != 0)
				{
					skip--;
					continue;
				}
				
				if (script != NULL)
				{
					const std::optional<std::string> location = OOJSDescribeLocation(context, frame);
ooscript::Object scope = ooscript::frameScopeChain(context, frame);
					
					if (scope != NULL)  gotProperties = ooscript::getScopeVariables(context, scope, &properties);
					
					std::string funcDesc;
					ooscript::Function function = ooscript::frameFunction(context, frame);
					if (function != NULL)
					{
						ooscript::String funcName = ooscript::getFunctionId(function);
						if (funcName != NULL)
						{
							// (a nil name: -stringByAppendingString: to nil stayed nil, "%@" printed "(null)")
							const std::optional<std::string> name = cxx_OOStringFromJSString(context, funcName);
							if (!ooscript::frameIsConstructor(context, frame))
							{
								funcDesc = name.has_value() ? *name + "()" : std::string("(null)");
							}
							else
							{
								funcDesc = "new " + name.value_or("(null)") + "()";
							}

						}
						else
						{
							funcDesc = "<anonymous function>";
						}
					}
					else
					{
						funcDesc = "<not a function frame>";
					}

					desc = "(" + location.value_or("(null)") + ") " + funcDesc;
				}
				else if (ooscript::frameIsDebugger(context, frame))
				{
					desc = "<debugger frame>";
				}
				else
				{
					desc = "<Oolite native>";
				}

				OO_LOG("script.javaScript.stackTrace", "{:2} {}", idx - 1, desc);

				if (gotProperties)
				{
					ooscript::Value thisVal;
					if (ooscript::frameThis(context, frame, &thisVal))
					{
						static BOOL haveThis = NO;
						static ooscript::PropertyId thisAtom;
						if (EXPECT_NOT(!haveThis))
						{
							ooscript::valueToId(context, ooscript::stringValue((ooscript::internString((context), "this"))), &thisAtom);
							haveThis = YES;
						}
						ooscript::Variable thisDesc = { .id = thisAtom, .value = thisVal, .flags = 0, .alias = ooscript::undefinedValue() };
						DumpVariable(context, &thisDesc);
					}
					
					// Dump arguments.
					unsigned i;
					for (i = 0; i < properties.length; i++)
					{
						ooscript::Variable *prop = &properties.vars[i];
						if (prop->flags & static_cast<unsigned>(ooscript::VariableFlag::Argument))  DumpVariable(context, prop);
					}
					
					// Dump locals.
					for (i = 0; i < properties.length; i++)
					{
						ooscript::Variable *prop = &properties.vars[i];
						if (prop->flags & static_cast<unsigned>(ooscript::VariableFlag::Variable))  DumpVariable(context, prop);
					}
					
					// Dump anything else.
					for (i = 0; i < properties.length; i++)
					{
						ooscript::Variable *prop = &properties.vars[i];
						if (!(prop->flags & (static_cast<unsigned>(ooscript::VariableFlag::Argument) | static_cast<unsigned>(ooscript::VariableFlag::Variable))))  DumpVariable(context, prop);
					}
					
					ooscript::destroyScopeVariables(context, &properties);
				}
			}
		}
		catch (...)
		{
			// Was @catch (OOException *): an OOException is logged, anything else goes on up as before
			// (amendment oo-10qz).
			// (Asked of oo::CurrentOOException() where it was asked through the root's JS bridge, which
			// went with bead oo-4aq6a.6.2.)
			const auto exception = oo::CurrentOOException();	// nullopt: not what @catch (OOException *) caught
			if (!exception)  throw;
			const std::string name = exception->name(), reason = exception->reason();
			OO_LOG(cxx_kOOLogException, "Exception during JavaScript stack trace: {}:{}", name, reason);
		}
	}
}


namespace {
static const char *sConsoleScriptName;	// Lifetime is lifetime of script object, which is forever.
} // namespace
namespace {
static NSUInteger sConsoleEvalLineNo;
} // namespace


namespace {
static void GetLocationNameAndLine(ooscript::Context context, ooscript::StackFrame stackFrame, const char **name, NSUInteger *line)
{
	OOCParameterAssert(context != NULL && stackFrame != NULL && name != NULL && line != NULL);
	
	*name = NULL;
	*line = 0;
	
	ooscript::Script script = ooscript::frameScript(context, stackFrame);
	if (script != NULL)
	{
		*name = ooscript::scriptFilename(context, script);
		if (name != NULL)
		{
			*line = ooscript::frameLineNumber(context, stackFrame);
		}
	}
	else if (ooscript::frameIsDebugger(context, stackFrame))
	{
		*name = "<debugger frame>";
	}
}
} // namespace


std::optional<std::string> OOJSDescribeLocation(ooscript::Context context, ooscript::StackFrame stackFrame)
{
	OOCParameterAssert(context != NULL && stackFrame != NULL);

	const char	*fileName;
	NSUInteger	lineNo;
	GetLocationNameAndLine(context, stackFrame, &fileName, &lineNo);
	if (fileName == NULL)  return std::nullopt;

	// If this stops working, we probably need to switch to strcmp().
	if (fileName == sConsoleScriptName && lineNo >= sConsoleEvalLineNo)  return std::string("<console input>");

	// Stringify it. (A name that is not UTF-8 survives the WTF-8 round trip, standing in for the
	// Latin-1 fallback.)
	std::string	fileNameStr = oo::utf16ToUtf8(oo::utf8ToUtf16(fileName));

	std::string	shortFileName = oo::str::lastPathComponent(fileNameStr);
	if (oo::str::lowercase(shortFileName) != "script.js")  fileNameStr = shortFileName;

	return oo::str::format("%s:%zu", fileNameStr.c_str(), static_cast<std::size_t>(lineNo));
}


void OOJSMarkConsoleEvalLocation(ooscript::Context context, ooscript::StackFrame stackFrame)
{
	GetLocationNameAndLine(context, stackFrame, &sConsoleScriptName, &sConsoleEvalLineNo);
}
#endif


void OOJSInitJSIDCachePRIVATE(const char *name, ooscript::PropertyId *idCache)
{
	OOCParameterAssert(name != NULL && name[0] != '\0' && idCache != NULL);
	
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::String string = (ooscript::internString((context), name));
	if (EXPECT_NOT(string == NULL))
	{
		OORaiseException(OOGenericException, "Failed to initialize JS ID cache for \"%s\".", name);
	}
	
	// The string is interned, so the engine's value-to-id conversion returns its atom id unchanged.
	if (EXPECT_NOT(!ooscript::valueToId(context, ooscript::stringValue(string), idCache)))
	{
		OORaiseException(OOGenericException, "Failed to initialize JS ID cache for \"%s\".", name);
	}
	
	OOJSRelinquishContext(context);
}


ooscript::PropertyId cxx_OOJSIDFromString(const std::string &string)
{
	ooscript::Context context = OOJSAcquireContext();
	
	const std::u16string units = oo::utf8ToUtf16(string);
	ooscript::String jsString = (ooscript::internUCStringN((context), units.data(), units.size()));
	
	// The string is interned, so the engine's value-to-id conversion returns its atom id unchanged.
	ooscript::PropertyId result = ooscript::voidId();
	if (EXPECT(jsString != NULL) && !ooscript::valueToId(context, ooscript::stringValue(jsString), &result))  result = ooscript::voidId();
	
	OOJSRelinquishContext(context);
	
	return result;
}


std::optional<std::string> cxx_OOStringFromJSID(ooscript::PropertyId propID)
{
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::Value	value;
	std::optional<std::string>	result;
	if (ooscript::idToValue((context), (propID), &value))
	{
		result = cxx_OOStringFromJSString(context, (ooscript::valueToString((context), value)));
	}
	
	OOJSRelinquishContext(context);
	
	return result;
}


namespace {
static std::string CallerPrefix(const std::optional<std::string> &scriptClass, const std::optional<std::string> &function)
{
	if (!function)  return std::string();
	if (!scriptClass)  return *function + ": ";
	return *scriptClass + "." + *function + ": ";
}
} // namespace


void cxx_OOJSReportError(ooscript::Context context, const char *format, ...)
{
	va_list					args;

	va_start(args, format);
	cxx_OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void cxx_OOJSReportErrorForCaller(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list					args;

	try
	{
		va_start(args, format);
		std::string msg = oo::str::vformat(format, args);
		va_end(args);

		cxx_OOJSReportError(context, "%s%s", CallerPrefix(scriptClass, function).c_str(), msg.c_str());
	}
	catch (...)
	{
		// Squash any secondary errors during error handling: nothing more to do.
		return;
	}
}


void cxx_OOJSReportErrorWithArguments(ooscript::Context context, const char *format, va_list args)
{
	OOCParameterAssert(ooscript::isInRequest((context)));

	try
	{
		std::string msg = oo::str::vformat(format, args);
		ooscript::reportError((context), msg.c_str());
	}
	catch (...)
	{
		// Squash any secondary errors during error handling: nothing more to do.
		return;
	}
}


// OOJSReportCurrentException() is in OOJSEngineNativeWrappers.mm (OOJSReportWrappedException() went with bead oo-rskgl.1).


#ifndef NDEBUG

void OOJSUnreachable(const char *function, const char *file, unsigned line)
{
	OO_LOG("fatal.unreachable", "Supposedly unreachable statement reached in {} ({}:{}) -- terminating.", function, oo::log::abbreviatedFileName(file), static_cast<unsigned>(line));
	abort();
}

#endif


void cxx_OOJSReportWarning(ooscript::Context context, const char *format, ...)
{
	va_list					args;

	va_start(args, format);
	cxx_OOJSReportWarningWithArguments(context, format, args);
	va_end(args);
}


void cxx_OOJSReportWarningForCaller(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list					args;

	try
	{
		va_start(args, format);
		std::string msg = oo::str::vformat(format, args);
		va_end(args);

		cxx_OOJSReportWarning(context, "%s%s", CallerPrefix(scriptClass, function).c_str(), msg.c_str());
	}
	catch (...)
	{
		// Squash any secondary errors during error handling: nothing more to do.
		return;
	}
}


void cxx_OOJSReportWarningWithArguments(ooscript::Context context, const char *format, va_list args)
{
	try
	{
		std::string msg = oo::str::vformat(format, args);
		ooscript::reportWarning((context), msg.c_str());
	}
	catch (...)
	{
		// Squash any secondary errors during error handling: nothing more to do.
		return;
	}
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object thisObj, ooscript::PropertyId propID, ooscript::PropertySpec *propertySpec)
{
	std::optional<std::string>	propName = cxx_OOStringFromJSPropertyIDAndSpec(context, propID, propertySpec);
	const char	*className = OOJSGetClass(context, thisObj)->name;

	// %@ of a nil name printed "(null)".
	cxx_OOJSReportError(context, "Invalid property identifier %s for instance of %s.", propName ? propName->c_str() : "(null)", className);
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object thisObj, ooscript::PropertyId propID, ooscript::PropertySpec *propertySpec, ooscript::Value value)
{
	std::optional<std::string>	propName = cxx_OOStringFromJSPropertyIDAndSpec(context, propID, propertySpec);
	const char	*className = OOJSGetClass(context, thisObj)->name;
	std::string	valueDesc = cxx_OOJSDescribeValue(context, value, YES);

	cxx_OOJSReportError(context, "Cannot set property %s of instance of %s to invalid value %s.", propName ? propName->c_str() : "(null)", className, valueDesc.c_str());
}


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	try
	{
		std::string text = message ? *message : std::string("Invalid arguments");
		std::optional<std::string> parameters = cxx_OOJSStringWithJavaScriptParameters(argv, argc, context);
		text += " " + (parameters ? *parameters : std::string("(null)"));
		if (expectedArgsDescription)  text += " -- expected " + *expectedArgsDescription;

		cxx_OOJSReportErrorForCaller(context, scriptClass, function, "%s.", text.c_str());
	}
	catch (...)
	{
		// Squash any secondary errors during error handling: nothing more to do.
		return;
	}
}


void OOJSSetWarningOrErrorStackSkip(unsigned skip)
{
	sErrorHandlerStackSkip = skip;
}


BOOL cxx_OOJSArgumentListGetNumber(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed)
{
	if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed))
	{
		return YES;
	}
	else
	{
		cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv,
									   std::string("Expected number, got"), std::nullopt);
		return NO;
	}
}


BOOL OOJSArgumentListGetNumberNoError(ooscript::Context context, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed)
{
	OOJS_PROFILE_ENTER
	
	double					value;
	
	OOCParameterAssert(context != NULL && (argv != NULL || argc == 0) && outNumber != NULL);
	
	// Get value, if possible.
	if (EXPECT_NOT(!ooscript::valueToNumber((context), (argv[0]), &value) || isnan(value)))
	{
		if (outConsumed != NULL)  *outConsumed = 0;
		return NO;
	}
	
	// Success.
	*outNumber = value;
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
	
	OOJS_PROFILE_EXIT
}


// (The root-class JS glue for classes rooted on OOObject - OOObjectJSValueInContext(),
// OOObjectJSClassName(), OOObjectJSDescription(), OOObjectJSDescriptionWithClassName() - went with
// the root's JS bridges, bead oo-4aq6a.6.2: no game object is an Objective-C object.)


namespace {
// The Foundation array's glue (JSArrayFromNSArray + JSNewNSArrayValue) over ObjectFromPList's array: null elements dropped.
static ooscript::Value JSArrayValueFromPList(ooscript::Context context, const oo::PList::Array &array)
{
	OOJS_PROFILE_ENTER

	ooscript::Value			value = ooscript::undefinedValue();
	ooscript::Object		result = NULL;

	// NOTE: rooted for GC reasons for the duration of the conversion, per ooscript/README.md's
	// "Not in the façade" note on EnterLocalRootScope / LeaveLocalRootScopeWithResult.
	ooscript::RootedValue rootedResult((context), ooscript::Value{0}, "JSNewNSArrayValue.result");

	std::size_t fullCount = 0;
	for (const oo::PList &element : array)  if (!element.isNull())  ++fullCount;
	if (EXPECT(fullCount <= INT32_MAX))
	{
		result = (ooscript::newArrayObject((context), 0, NULL));
		if (result != NULL)
		{
			uint32_t i = 0;
			for (const oo::PList &element : array)
			{
				if (element.isNull())  continue;
				ooscript::Value elementValue = OOJSValueFromPList(context, element);
				if (EXPECT_NOT(!ooscript::setElement((context), (result), i, &elementValue)))
				{
					result = NULL;
					break;
				}
				++i;
			}
		}
	}

	if (result != NULL)  value = ooscript::objectValue(result);
	rootedResult.set((value));
	return value;

	OOJS_PROFILE_EXIT_JSVAL
}


// The Foundation dictionary's glue (JSObjectFromNSDictionary + JSNewNSDictionaryValue) over ObjectFromPList's
// dictionary: null values dropped, empty keys skipped, key order.
static ooscript::Value JSObjectValueFromPList(ooscript::Context context, const oo::PList::Dict &dict)
{
	OOJS_PROFILE_ENTER

	ooscript::Value			value = ooscript::undefinedValue();
	ooscript::Object		result = NULL;

	// NOTE: rooted for GC reasons for the duration of the conversion, per ooscript/README.md's
	// "Not in the façade" note on EnterLocalRootScope / LeaveLocalRootScopeWithResult.
	ooscript::RootedValue rootedResult((context), ooscript::Value{0}, "JSNewNSDictionaryValue.result");

	result = (ooscript::newObject((context), NULL, NULL, NULL));	// create object of class Object
	if (result != NULL)
	{
		for (const auto &[key, element] : dict)
		{
			if (element.isNull() || key.empty())  continue;
			ooscript::Value elementValue = OOJSValueFromPList(context, element);
			if (!ooscript::isUndefined(elementValue))
			{
				if (EXPECT_NOT(!ooscript::setPropertyById((context), (result), (cxx_OOJSIDFromString(key)), (&elementValue))))
				{
					result = NULL;
					break;
				}
			}
		}
	}

	if (result != NULL)  value = ooscript::objectValue(result);
	rootedResult.set((value));
	return value;

	OOJS_PROFILE_EXIT_JSVAL
}


// The Foundation number's glue: an integer outside int32 range, or a real, as a double.
static ooscript::Value JSNumberValue(ooscript::Context context, double number)
{
	ooscript::Value result;
	if (!ooscript::newNumberValue((context), number, (&result)))  result = ooscript::undefinedValue();
	return result;
}
} // namespace


// (OOJSValueFromNativeObject(), the JS value of an Objective-C object - null for nil, the root's JS
// glue - went with bead oo-4aq6a.6.2: no game object is an Objective-C object.)


ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	OOJS_PROFILE_ENTER

	switch (plist.type())
	{
		case oo::PList::Type::Null:
			return ooscript::nullValue();

		case oo::PList::Type::Bool:
			// +numberWithBool: is not a float type: an int32.
			return ooscript::int32Value(*plist.getIf<bool>() ? 1 : 0);

		case oo::PList::Type::Integer:
		{
			const oo::PList::Integer &integer = *plist.getIf<oo::PList::Integer>();
			if (integer.isUnsigned)
			{
				const unsigned long long u = integer.unsignedValue();
				if (u <= static_cast<unsigned long long>(INT32_MAX))  return ooscript::int32Value(static_cast<int32_t>(u));
				return JSNumberValue(context, static_cast<double>(u));
			}
			const long long v = integer.value;
			if (static_cast<long long>(INT32_MIN) <= v && v <= static_cast<long long>(INT32_MAX))  return ooscript::int32Value(static_cast<int32_t>(v));
			return JSNumberValue(context, static_cast<double>(v));
		}

		case oo::PList::Type::Real:
		{
			double d = *plist.getIf<double>();
			if (plist.isSinglePrecision())  d = static_cast<double>(static_cast<float>(d));	// +numberWithFloat: -doubleValue
			return JSNumberValue(context, d);
		}

		case oo::PList::Type::String:
		{
			const std::u16string units = oo::utf8ToUtf16(*plist.getIf<std::string>());
			if (units.empty())  return ooscript::emptyStringValue((context));
			ooscript::String string = (ooscript::newUCStringCopyN((context), reinterpret_cast<const ooscript::Char16*>(units.data()), units.size()));
			return ooscript::stringValue(string);
		}

		case oo::PList::Type::Data:
		case oo::PList::Type::Date:
			return ooscript::undefinedValue();	// Foundation data and dates: the root class's glue

		case oo::PList::Type::Array:
			return JSArrayValueFromPList(context, *plist.getIf<oo::PList::Array>());

		case oo::PList::Type::Dict:
			return JSObjectValueFromPList(context, *plist.getIf<oo::PList::Dict>());

		case oo::PList::Type::Object:
		{
			// A C++ object that is its own JS glue (OOJSPrivateObject.h), else an Objective-C object.
			if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())
			{
				if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(node->get()))  return OOJSValueFromCxxObject(context, glue);
				if (OONativeVector *box = dynamic_cast<OONativeVector *>(node->get()))  return OONativeVectorJSValueInContext(box, context);
				// An entity's node (bead oo-dpyk8): the entity's JS value, which its object's forwarded to.
				if (const auto *held = dynamic_cast<const oo::EntityPListForeign *>(node->get()))  return OOJSEntityJSValue(held->entity(), context);
				// An entity held weakly (bead oo-w9pi2): the entity's value, undefined once it has gone, as
				// the weak reference forwarded to its object's.
				if (const auto *weak = dynamic_cast<const oo::EntityWeakPListForeign *>(node->get()))
				{
					Entity *entity = weak->entity();
					return entity != nullptr ? OOJSEntityJSValue(entity, context) : ooscript::undefinedValue();
				}
				// The one null and a held value: their own JS glue, which their facades forwarded to (bead oo-wdqw1).
				if (OONull *null = dynamic_cast<OONull *>(node->get()))  return null->jsValueInContext(context);
				if (OOJSValue *held = dynamic_cast<OOJSValue *>(node->get()))  return held->jsValueInContext(context);
			}
			// A node that holds no Objective-C object (a C++ one): no JS glue. (The Objective-C object's
			// node went with bead oo-4aq6a.5: no game object is one.)
			return ooscript::undefinedValue();
		}
	}
	return ooscript::undefinedValue();

	OOJS_PROFILE_EXIT_JSVAL
}


// (OOJSObjectFromNativeObject() went with OOJSValueFromNativeObject(), bead oo-4aq6a.6.2.)



oo::Ref<OOJSValue> OOJSValue::valueWithJSValue(ooscript::Value value, ooscript::Context context)
{
	OOJS_PROFILE_ENTER

	oo::Ref<OOJSValue> result = oo::makeRef<OOJSValue>();
	result->initWithJSValue(value, context);
	return result;

	OOJS_PROFILE_EXIT_VAL(nullptr)
}


oo::Ref<OOJSValue> OOJSValue::valueWithJSObject(ooscript::Object object, ooscript::Context context)
{
	OOJS_PROFILE_ENTER

	oo::Ref<OOJSValue> result = oo::makeRef<OOJSValue>();
	result->initWithJSObject(object, context);
	return result;

	OOJS_PROFILE_EXIT_VAL(nullptr)
}


void OOJSValue::initWithJSValue(ooscript::Value value, ooscript::Context context)
{
	OOJS_PROFILE_ENTER

	{
		bool tempCtxt = false;
		if (context == NULL)
		{
			context = OOJSAcquireContext();
			tempCtxt = true;
		}

		_val = value;
		if (!ooscript::isUndefined(_val))
		{
			ooscript::addNamedValueRoot((context), (&_val), "OOJSValue");

			// The engine: the sender of its reset notifications. Kept for removing the
			// observer, so the destructor does not ask for the engine (which could make it).
			_resetSender = OOJavaScriptEngine::sharedEngine();
			oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
																_resetSender,
																[this](const oo::Notification &) { deleteJSValue(); });
		}

		if (tempCtxt)  OOJSRelinquishContext(context);
	}

	OOJS_PROFILE_EXIT_VOID
}


void OOJSValue::initWithJSObject(ooscript::Object object, ooscript::Context context)
{
	initWithJSValue(ooscript::objectValue(object), context);
}


void OOJSValue::deleteJSValue()
{
	if (!ooscript::isUndefined(_val))
	{
		ooscript::Context context = OOJSAcquireContext();
		ooscript::removeValueRoot((context), (&_val));
		OOJSRelinquishContext(context);

		_val = ooscript::undefinedValue();
		oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
																_resetSender);
	}
}


OOJSValue::~OOJSValue()
{
	deleteJSValue();
}


ooscript::Value OOJSValue::jsValueInContext(ooscript::Context /*context*/)
{
	return _val;
}


std::string OOJSValue::className() const
{
	return "OOJSValue";
}


std::string OOJSValue::description() const
{
	return oo::str::format("<OOJSValue %s>", oo::str::pointerDescription(this).c_str());
}



void OOJSStrLiteralCachePRIVATE(const char *string, ooscript::Value *strCache, BOOL *inited)
{
	OOCParameterAssert(string != NULL && strCache != NULL && inited != NULL && !*inited);
	
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::String jsString = (ooscript::internString((context), string));
	if (EXPECT_NOT(string == NULL))
	{
		OORaiseException(OOGenericException, "Failed to initialize JavaScript string literal cache for \"%s\".", cxx_OOJSEscapedForJavaScriptLiteral(string != NULL ? std::string_view(string) : std::string_view()).c_str());
	}
	
	*strCache = ooscript::stringValue(jsString);
	*inited = YES;
	
	OOJSRelinquishContext(context);
}


std::optional<std::string> cxx_OOStringFromJSString(ooscript::Context context, ooscript::String string)
{
	OOJS_PROFILE_ENTER
	
	if (EXPECT_NOT(string == NULL))  return std::nullopt;
	
	size_t length;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength((context), (string), &length);
	
	if (EXPECT(chars != NULL))
	{
		return oo::utf16ToUtf8(std::u16string_view(chars, length));
	}
	else
	{
		return std::nullopt;
	}
	
	OOJS_PROFILE_EXIT_VAL(std::nullopt)
}


std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(ooscript::Context context, ooscript::Value value)
{
	OOJS_PROFILE_ENTER
	
	OOCParameterAssert(context != NULL && ooscript::isInRequest((context)));
	
	ooscript::String string = (ooscript::valueToString((context), (value)));	// Calls the value's toString method if needed.
	return cxx_OOStringFromJSString(context, string);
	
	OOJS_PROFILE_EXIT_VAL(std::nullopt)
}


std::optional<std::string> cxx_OOStringFromJSValue(ooscript::Context context, ooscript::Value value)
{
	OOJS_PROFILE_ENTER
	
	if (EXPECT(!ooscript::isNull(value) && !ooscript::isUndefined(value)))
	{
		return cxx_OOStringFromJSValueEvenIfNull(context, value);
	}
	return std::nullopt;
	
	OOJS_PROFILE_EXIT_VAL(std::nullopt)
}


std::optional<std::string> cxx_OOStringFromJSPropertyIDAndSpec(ooscript::Context context, ooscript::PropertyId propID, ooscript::PropertySpec *propertySpec)
{
	if (ooscript::isStringId(propID))
	{
		return cxx_OOStringFromJSString(context, ooscript::idToString(propID));
	}
	else if (ooscript::isInt32Id(propID) && propertySpec != NULL)
	{
		int tinyid = ooscript::idToInt32(propID);
		
		while (propertySpec->name != NULL)
		{
			if (propertySpec->tinyid == tinyid)  return std::string(propertySpec->name);
			propertySpec++;
		}
	}
	
	ooscript::Value value;
	if (!ooscript::idToValue((context), (propID), (&value)))  return std::string("unknown");
	return cxx_OOStringFromJSString(context, (ooscript::valueToString((context), (value))));
}


namespace {
static std::string DescribeValue(ooscript::Context context, ooscript::Value value, BOOL abbreviateObjects, BOOL recursing)
{
	OOJS_PROFILE_ENTER
	
	OOCParameterAssert(context != NULL && ooscript::isInRequest((context)));
	
	if (OOJSValueIsFunction(context, value))
	{
		ooscript::String name = (ooscript::getFunctionId(ooscript::valueToFunction((context), (value))));
		if (name != NULL)
		{
			// "function %@": a nil name printed "(null)".
			std::optional<std::string> nameString = cxx_OOStringFromJSString(context, name);
			return "function " + (nameString ? *nameString : std::string("(null)"));
		}
		else  return "function";
	}
	
	std::optional<std::string>	result;
	ooscript::ClassDef				*valueClass = NULL;
	OOJavaScriptEngine	*jsEng = OOJavaScriptEngine::sharedEngine();
	
	if (ooscript::isObjectOrNull(value) && !ooscript::isNull(value))
	{
		valueClass = OOJSGetClass(context, ooscript::toObject(value));
	}
	
	// Convert String objects to strings.
	if (valueClass == jsEng->stringClass())
	{
		value = ooscript::stringValue((ooscript::valueToString((context), (value))));
	}
	
	if (ooscript::isString(value))
	{
		enum : std::uint8_t { kMaxLength = 200 };
		
		ooscript::String string = ooscript::toString(value);
		size_t length;
		const ooscript::Char16 *chars = ooscript::getStringCharsAndLength((context), (string), &length);
		
		// Truncated to kMaxLength UTF-16 units before conversion, as the old code cut its string.
		std::string truncated = (chars != NULL) ? oo::utf16ToUtf8(std::u16string_view(chars, MIN(length, (size_t)kMaxLength))) : std::string();
		result = "\"" + cxx_OOJSEscapedForJavaScriptLiteral(truncated) + ((length > kMaxLength) ? "..." : "") + "\"";
	}
	else if (valueClass == jsEng->arrayClass())
	{
		// Descibe up to four elements of an array.
		uint32_t count;
		ooscript::Object obj = ooscript::toObject(value);
		if (ooscript::getArrayLength((context), (obj), &count))
		{
			if (!recursing)
			{
				std::string arrayDesc = "[";
				uint32_t i, effectiveCount = MIN(count, (uint32_t)4);
				for (i = 0; i < effectiveCount; i++)
				{
					ooscript::Value item;
					std::string itemDesc = "?";
					if (ooscript::getElement((context), (obj), i, (&item)))
					{
						itemDesc = DescribeValue(context, item, YES /* always abbreviate objects in arrays */, YES);
					}
					if (i != 0)  arrayDesc += ", ";
					arrayDesc += itemDesc;
				}
				if (effectiveCount != count)
				{
					arrayDesc += oo::str::format(", ... <%u items total>]", count);
				}
				else
				{
					arrayDesc += "]";
				}
				
				result = arrayDesc;
			}
			else
			{
				result = oo::str::format("[<%u items>]", count);
			}
		}
		else
		{
			result = "[...]";
		}

	}
	
	if (!result)
	{
		result = cxx_OOStringFromJSValueEvenIfNull(context, value);
		
		if (abbreviateObjects && valueClass == jsEng->objectClass() && result && *result == "[object Object]")
		{
			result = "{...}";
		}
		
		if (!result)  result = "?";
	}
	
	return *result;
	
	OOJS_PROFILE_EXIT_VAL(std::string())
}
} // namespace


std::string cxx_OOJSDescribeValue(ooscript::Context context, ooscript::Value value, BOOL abbreviateObjects)
{
	return DescribeValue(context, value, abbreviateObjects, NO);
}


std::optional<std::string> cxx_OOJSStringWithJavaScriptParameters(ooscript::Value *params, unsigned count, ooscript::Context context)
{
	OOJS_PROFILE_ENTER
	
	if (params == NULL && count != 0) return std::nullopt;
	
	unsigned					i;
	std::string				result = "(";
	
	for (i = 0; i < count; ++i)
	{
		if (i != 0)  result += ", ";
		result += cxx_OOJSDescribeValue(context, params[i], NO);
	}
	
	result += ")";
	return result;
	
	OOJS_PROFILE_EXIT_VAL(std::nullopt)
}


std::optional<std::string> cxx_OOJSConcatenationOfStringsFromJavaScriptValues(ooscript::Value *values, size_t count, const std::string &separator, ooscript::Context context)
{
	OOJS_PROFILE_ENTER
	
	size_t					i;
	std::optional<std::string>	result;
	
	if (count < 1) return std::nullopt;
	if (values == NULL) return std::nullopt;
	
	for (i = 0; i != count; ++i)
	{
		std::optional<std::string> element = cxx_OOStringFromJSValueEvenIfNull(context, values[i]);
		if (!result)  result = element;	// a nil element left the result nil, as -mutableCopy of nil did
		else
		{
			*result += separator;
			if (element)  *result += *element;
		}
	}
	
	return result;
	
	OOJS_PROFILE_EXIT_VAL(std::nullopt)
}


std::string cxx_OOJSEscapedForJavaScriptLiteral(std::string_view string)
{
	// Byte-wise over UTF-8: every escaped character is ASCII, so multi-byte sequences pass through
	// unchanged, as the UTF-16 units they encode did.
	std::string result;
	result.reserve(string.size());
	
	for (char c : string)
	{
		switch (c)
		{
			case '\\':
				result += "\\\\";
				break;

			case '\b':
				result += "\\b";
				break;

			case '\f':
				result += "\\f";
				break;

			case '\n':
				result += "\\n";
				break;

			case '\r':
				result += "\\r";
				break;

			case '\t':
				result += "\\t";
				break;

			case '\v':
				result += "\\v";
				break;

			case '\'':
				result += "\\\'";
				break;
				
			case '\"':
				result += "\\\"";
				break;
			
			default:
				result += c;
		}
	}
	return result;
}


// A vector box's JS value, a Vector3D (was OONativeVector (OOJavaScriptConversion)'s
// -oo_jsValueInContext:, amendment oo-ppc item 3; the box's facade was deleted by bead oo-9ht.5).
ooscript::Value OONativeVectorJSValueInContext(OONativeVector *vector, ooscript::Context context)
{
	ooscript::Value value = ooscript::undefinedValue();
	VectorToJSValue(context, vector->getVector(), &value);
	return value;
}



OONull *OONull::null()
{
	static OONull *sNull = nullptr;	// the one +1 is never released (amendment oo-r7m0 item 1)
	if (sNull == nullptr)  sNull = oo::makeRef<OONull>().leakRef();
	return sNull;
}


// (-copyWithZone:, which answered the object itself, was the facade's: the one null is shared by reference.)


std::string OONull::className() const
{
	return "OONull";
}


std::string OONull::description() const
{
	return "<null>";
}


ooscript::Value OONull::jsValueInContext(ooscript::Context /*context*/)
{
	return ooscript::nullValue();
}



bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ooscript::Function function = ooscript::valueToFunction((context), oojsArgs.callee());
	std::optional<std::string> name = cxx_OOStringFromJSString(context, (ooscript::getFunctionId(function)));

	// %@ of a nil name printed "(null)".
	cxx_OOJSReportError(context, "%s cannot be used as a constructor.", name ? name->c_str() : "(null)");
	return NO;
	
	OOJS_NATIVE_EXIT
}


// The slot holds a C++ object (bead oo-4aq6a.6): the C++ finalizer, which tells it its wrapper is
// gone (clearJSSelf, as -oo_clearJSSelf: was sent), releases the slot's retain and empties the slot.
void OOJSObjectWrapperFinalize(ooscript::Context context, ooscript::Object thisObj)
{
	OOJSCxxObjectWrapperFinalize(context, thisObj);
}


// Only an Objective-C object found through the class's converter described itself (its
// -cxx_oo_jsDescription, else -description); a C++ node's object never did, and no slot holds an
// Objective-C object since bead oo-4aq6a.6: the JS class names it.
bool OOJSObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	description;
	ooscript::ClassDef					*jsClass = NULL;

	jsClass = OOJSGetClass(context, OOJS_THIS);
	if (jsClass != NULL)
	{
		description = oo::str::format("[object %s]", jsClass->name);
	}
	if (!description.has_value())  description = std::string("[object]");
	
	OOJS_RETURN_STRING_OR_NULL(description);
	
	OOJS_NATIVE_EXIT
}


BOOL JSFunctionPredicate(Entity *entity, void *parameter)
{
	OOJS_PROFILE_ENTER
	
	JSFunctionPredicateParameter	*param = static_cast<JSFunctionPredicateParameter*>(parameter);
	ooscript::Value							args[1];
	ooscript::Value							rval = ooscript::undefinedValue();
	bool							result = NO;
	
	OOCParameterAssert(entity != nil && param != NULL);
	OOCParameterAssert(param->context != NULL && ooscript::isInRequest((param->context)));
	OOCParameterAssert(OOJSValueIsFunction(param->context, param->function));
	
	if (EXPECT_NOT(param->errorFlag))  return NO;
	
	args[0] = OOJSEntityJSValue(entity, param->context);	// the C++ entity's glue (bead oo-9ht.39.25); entity is required to be non-nil (asserted above).
	
	OOJSStartTimeLimiter();
	OOJSResumeTimeLimiter();
	BOOL success = ooscript::callFunctionValue((param->context), (param->jsThis), (param->function), 1, (args), (&rval));
	OOJSPauseTimeLimiter();
	OOJSStopTimeLimiter();
	
	if (success)
	{
		bool boolResult = false;
		if (!ooscript::valueToBoolean((param->context), (rval), &boolResult))  boolResult = false;
		result = static_cast<bool>(static_cast<unsigned char>(boolResult));
		if (ooscript::isExceptionPending((param->context)))
		{
			ooscript::reportPendingException((param->context));
			param->errorFlag = YES;
		}
	}
	else
	{
		param->errorFlag = YES;
	}
	
	return result;
	
	OOJS_PROFILE_EXIT
}


namespace {

/*	What the entity predicates ask an entity (amendment oo-nge8 item 5): C++, moved from
	OOObject+OOJavaScript.mm, whose one-line bridges they were (bead oo-t7o84, ADR-0056 amendment
	oo-9ht.184).
*/
bool OOJavaScriptEngineIsVisibleToScripts(Entity *entity)
{
	return OOJSEntityIsVisibleToScripts(entity);	// the C++ entity's answer, which the root facade's selector forwarded to (bead oo-9ht.39.8.9)
}


// The root facade's -isShip, -isSubEntity, -isPlanet and -status forwarded to these members (bead
// oo-9ht.39.25; an Objective-C stand-in was asked until bead oo-j12i2).
bool OOJavaScriptEngineIsShip(Entity *entity)
{
	return entity != nullptr && entity->getIsShip();
}


bool OOJavaScriptEngineIsSubEntity(Entity *entity)
{
	return entity != nullptr && entity->getIsSubEntity();
}


bool OOJavaScriptEngineIsPlanet(Entity *entity)
{
	return entity != nullptr && entity->isPlanet();
}


OOEntityStatus OOJavaScriptEngineStatus(Entity *entity)
{
	return entity != nullptr ? entity->status() : OOEntityStatus{};
}

}	// namespace


BOOL JSEntityIsJavaScriptVisiblePredicate(Entity *entity, void * /*parameter*/)
{
	OOJS_PROFILE_ENTER
	
	return OOJavaScriptEngineIsVisibleToScripts(entity);
	
	OOJS_PROFILE_EXIT
}


BOOL JSEntityIsJavaScriptSearchablePredicate(Entity *entity, void * /*parameter*/)
{
	OOJS_PROFILE_ENTER
	
	if (!OOJavaScriptEngineIsVisibleToScripts(entity))  return NO;
	if (OOJavaScriptEngineIsShip(entity))
	{
		if (OOJavaScriptEngineIsSubEntity(entity))  return NO;
		if (OOJavaScriptEngineStatus(entity) == STATUS_COCKPIT_DISPLAY)  return NO;	// Demo ship
		return YES;
	}
	else if (OOJavaScriptEngineIsPlanet(entity))
	{
		switch (static_cast<OOPlanetEntity *>(entity)->planetType())	// a planet: not nil (C++ since bead oo-9ht.129)
		{
			case STELLAR_TYPE_MOON:
			case STELLAR_TYPE_NORMAL_PLANET:
			case STELLAR_TYPE_SUN:
				return YES;
				
			case STELLAR_TYPE_MINIATURE:
				return NO;
		}
	}
	
	return YES;	// would happen if we added a new script-visible class
	
	OOJS_PROFILE_EXIT
}


BOOL JSEntityIsDemoShipPredicate(Entity *entity, void * /*parameter*/)
{
	return (OOJavaScriptEngineIsVisibleToScripts(entity) && OOJavaScriptEngineIsShip(entity) && OOJavaScriptEngineStatus(entity) == STATUS_COCKPIT_DISPLAY && !OOJavaScriptEngineIsSubEntity(entity));
}

namespace {
// JS subclass -> superclass, by pointer. Was a non-owned pointer map table (bead oo-3rb.20).
static std::unordered_map<const ooscript::ClassDef *, ooscript::ClassDef *> *sRegisteredSubClasses;
} // namespace

void OOJSRegisterSubclass(ooscript::ClassDef *subclass, ooscript::ClassDef *superclass)
{
	OOCParameterAssert(subclass != NULL && superclass != NULL);
	
	if (sRegisteredSubClasses == NULL)
	{
		sRegisteredSubClasses = new std::unordered_map<const ooscript::ClassDef *, ooscript::ClassDef *>;
	}

	OOCAssert(sRegisteredSubClasses->count(subclass) == 0, "A JS class cannot be registered as a subclass of multiple classes.");

	sRegisteredSubClasses->emplace(subclass, superclass);
}


namespace {
static void UnregisterSubclasses(void)
{
	delete sRegisteredSubClasses;
	sRegisteredSubClasses = NULL;
}
} // namespace


BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	OOCParameterAssert(putativeSubclass != NULL && superclass != NULL);
	OOCAssert(sRegisteredSubClasses != NULL, "OOJSIsSubclass() called before any subclasses registered (disallowed for hot path efficiency).");
	
	do
	{
		if (putativeSubclass == superclass)  return YES;
		
		auto registered = sRegisteredSubClasses->find(putativeSubclass);
		putativeSubclass = (registered != sRegisteredSubClasses->end()) ? registered->second : NULL;
	}
	while (putativeSubclass != NULL);
	
	return NO;
}


oo::PList OOJSDictionaryFromJSValue(ooscript::Context context, ooscript::Value value)
{
	OOJS_PROFILE_ENTER

	ooscript::Object object = nullptr;
	if (EXPECT_NOT(!ooscript::valueToObject((context), (value), &object) || object == nullptr))
	{
		return oo::PList();
	}
	return cxx_OOJSDictionaryFromJSObject(context, (object));

	OOJS_PROFILE_EXIT_VAL(oo::PList())
}


oo::PList cxx_OOJSDictionaryFromJSObject(ooscript::Context context, ooscript::Object object)
{
	OOJS_PROFILE_ENTER

	ooscript::IdArray			*ids = NULL;
	std::size_t					i;
	oo::PList::Dict				result;
	ooscript::Value						value = ooscript::undefinedValue();

	ids = ooscript::enumerate((context), (object));
	if (EXPECT_NOT(ids == NULL))
	{
		return oo::PList();
	}

	for (i = 0; i != ids->length; ++i)
	{
		ooscript::PropertyId thisID = (ids->ids[i]);
		std::optional<std::string>	key;

		if (ooscript::isStringId(thisID))
		{
			key = cxx_OOStringFromJSString(context, ooscript::idToString(thisID));
		}
		else if (ooscript::isInt32Id(thisID))
		{
			/*	An integer-like property is keyed by its decimal text, the name JS itself
				gives it (proposed ADR-0051). The Foundation converter kept it as a number
				key no native code could look up (CIM 15/2/13 asked whether the key should be
				a string), and this function gave a null PList for the whole object.
			*/
			key = std::to_string(ooscript::idToInt32(thisID));
		}

		value = ooscript::undefinedValue();
		if (key.has_value() && !ooscript::lookupPropertyById((context), (object), (thisID), (&value)))  value = ooscript::undefinedValue();

		if (key.has_value() && !ooscript::isUndefined(value))
		{
			oo::PList element = cxx_OOJSPListFromJSValue(context, value);
			if (!element.isNull())  result.insert_or_assign(*key, std::move(element));
		}
	}

	ooscript::destroyIdArray((context), ids);
	return oo::PList(std::move(result));

	OOJS_PROFILE_EXIT_VAL(oo::PList())
}


oo::PList OOJSDictionaryFromStringTable(ooscript::Context context, ooscript::Value tableValue)
{
	OOJS_PROFILE_ENTER

	ooscript::Object				tableObject = nullptr;
	ooscript::IdArray			*ids;
	std::size_t					i;
	oo::PList::Dict				result;
	ooscript::Value						value = ooscript::undefinedValue();

	if (EXPECT_NOT(ooscript::isNull(tableValue) || !ooscript::valueToObject((context), (tableValue), &tableObject)))
	{
		return oo::PList();
	}

	ids = ooscript::enumerate((context), tableObject);
	if (EXPECT_NOT(ids == NULL))
	{
		return oo::PList();
	}

	for (i = 0; i != ids->length; ++i)
	{
		ooscript::PropertyId thisID = (ids->ids[i]);
		std::optional<std::string>	key;

		if (ooscript::isStringId(thisID))
		{
			key = cxx_OOStringFromJSString(context, ooscript::idToString(thisID));
		}

		value = ooscript::undefinedValue();
		if (key && !ooscript::lookupPropertyById((context), tableObject, (thisID), (&value)))  value = ooscript::undefinedValue();

		if (key && !ooscript::isUndefined(value))
		{
			std::optional<std::string> string = cxx_OOStringFromJSValueEvenIfNull(context, value);

			if (string)
			{
				result.insert_or_assign(*key, oo::PList(std::move(*string)));
			}
		}
	}

	ooscript::destroyIdArray((context), ids);
	return oo::PList(std::move(result));

	OOJS_PROFILE_EXIT_VAL(oo::PList())
}


namespace {
/*	JS class -> converter. Was an NSMutableDictionary of boxed class and function pointers
	(bead oo-3rb.50); allocated on first registration and deleted by
	UnregisterObjectConverters(), as the dictionary was released there.
*/
static std::unordered_map<const ooscript::ClassDef *, OOJSClassConverterCallback> *sObjectConverters;
} // namespace


oo::PList cxx_OOJSPListFromJSValue(ooscript::Context context, ooscript::Value value)
{
	OOJS_PROFILE_ENTER

	if (ooscript::isNull(value) || ooscript::isUndefined(value))  return oo::PList();

	if (ooscript::isInt32(value))
	{
		return oo::PList::signedInteger(ooscript::toInt32(value));
	}
	if (ooscript::isDouble(value))
	{
		return oo::PList(ooscript::toDouble(value));
	}
	if (ooscript::isBoolean(value))
	{
		return oo::PList(static_cast<bool>(ooscript::toBoolean(value)));
	}
	if (ooscript::isString(value))
	{
		std::optional<std::string> string = cxx_OOStringFromJSValue(context, value);
		return string.has_value() ? oo::PList(std::move(*string)) : oo::PList();
	}
	if (ooscript::isObjectOrNull(value))
	{
		return cxx_OOJSPListFromJSObject(context, ooscript::toObject(value));
	}
	return oo::PList();

	OOJS_PROFILE_EXIT_VAL(oo::PList())
}


namespace {
static oo::PList PListFromJSArray(ooscript::Context context, ooscript::Object array);
static oo::PList PListFromJSStringObject(ooscript::Context context, ooscript::Object object);
static oo::PList PListFromJSNumberObject(ooscript::Context context, ooscript::Object object);
static oo::PList PListFromJSBooleanObject(ooscript::Context context, ooscript::Object object);
} // namespace


oo::PList cxx_OOJSPListFromJSObject(ooscript::Context context, ooscript::Object tableObject)
{
	OOJS_PROFILE_ENTER

	OOJSClassConverterCallback converter = NULL;
	ooscript::ClassDef					*tableClass = NULL;

	if (tableObject == NULL)  return oo::PList();

	tableClass = OOJSGetClass(context, tableObject);
	if (sObjectConverters != NULL)
	{
		auto found = sObjectConverters->find(tableClass);
		if (found != sObjectConverters->end())  converter = found->second;
	}
	if (converter == NULL)  return oo::PList();

	// The engine's own converters build the PList; a private-object converter gives an Object node.
	return converter(context, tableObject);

	OOJS_PROFILE_EXIT_VAL(oo::PList())
}


// The slot holds a C++ object (bead oo-4aq6a.6): a node of it when it is a node's foreign object,
// else none; an empty slot is a null PList, as nil was.
oo::PList OOJSBasicPrivateObjectConverter(ooscript::Context context, ooscript::Object object)
{
	oo::RefCounted *held = static_cast<oo::RefCounted *>(ooscript::getPrivate((context), (object)));
	if (oo::PListForeign *foreign = dynamic_cast<oo::PListForeign *>(held))  return oo::PList(oo::PList::Object(foreign));
	return oo::PList();
}


void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, OOJSClassConverterCallback converter)
{
	if (theClass == NULL)  return;
	if (sObjectConverters == NULL)  sObjectConverters = new std::unordered_map<const ooscript::ClassDef *, OOJSClassConverterCallback>;

	if (converter != NULL)
	{
		(*sObjectConverters)[theClass] = converter;
	}
	else
	{
		sObjectConverters->erase(theClass);
	}
}


namespace {
static void UnregisterObjectConverters(void)
{
	delete sObjectConverters;
	sObjectConverters = NULL;
}
} // namespace


namespace {
static oo::PList PListFromJSArray(ooscript::Context context, ooscript::Object array)
{
	uint32_t						i, count;
	oo::PList::Array				values;
	ooscript::Value						value = ooscript::undefinedValue();

	// Convert a JS array to a native array by calling cxx_OOJSPListFromJSValue() on all its elements.
	if (!ooscript::isArrayObject((context), (array))) return oo::PList();
	if (!ooscript::getArrayLength((context), (array), &count)) return oo::PList();

	values.reserve(count);
	for (i = 0; i != count; ++i)
	{
		value = ooscript::undefinedValue();
		if (!ooscript::getElement((context), (array), i, (&value)))  value = ooscript::undefinedValue();

		oo::PList element = cxx_OOJSPListFromJSValue(context, value);
		if (element.isNull())
		{
			element = OONullObjectNode();	// [OONull null]
		}
		values.push_back(std::move(element));
	}

	return oo::PList(std::move(values));
}


static oo::PList JSArrayConverter(ooscript::Context context, ooscript::Object array)
{
	return PListFromJSArray(context, array);
}
} // namespace


namespace {
static oo::PList PListFromJSStringObject(ooscript::Context context, ooscript::Object object)
{
	std::optional<std::string> string = cxx_OOStringFromJSValue(context, ooscript::objectValue(object));
	return string.has_value() ? oo::PList(std::move(*string)) : oo::PList();
}


static oo::PList JSStringConverter(ooscript::Context context, ooscript::Object object)
{
	return PListFromJSStringObject(context, object);
}
} // namespace


namespace {
static oo::PList PListFromJSNumberObject(ooscript::Context context, ooscript::Object object)
{
	double value;
	if (ooscript::valueToNumber((context), (ooscript::objectValue(object)), &value))
	{
		return oo::PList(value);
	}
	return oo::PList();
}


static oo::PList JSNumberConverter(ooscript::Context context, ooscript::Object object)
{
	return PListFromJSNumberObject(context, object);
}
} // namespace


namespace {
static oo::PList PListFromJSBooleanObject(ooscript::Context context, ooscript::Object object)
{
	/*	Fun With JavaScript: Boolean(false) is a truthy value, since it's a
		non-null object. valueToBoolean() therefore reports true.
		However, Boolean objects are transformed to numbers sanely, so this
		works.
	*/
	double value;
	if (ooscript::valueToNumber((context), (ooscript::objectValue(object)), &value))
	{
		return oo::PList(value != 0);
	}
	return oo::PList();
}


static oo::PList JSBooleanConverter(ooscript::Context context, ooscript::Object object)
{
	return PListFromJSBooleanObject(context, object);
}


// A plain JS Object: cxx_OOJSDictionaryFromJSObject() (proposed ADR-0051; was the bridge's
// Foundation converter, which kept an integer-like key as a number).
static oo::PList JSPlainObjectConverter(ooscript::Context context, ooscript::Object object)
{
	return cxx_OOJSDictionaryFromJSObject(context, object);
}
} // namespace
