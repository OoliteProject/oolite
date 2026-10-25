/*

OODebugMonitor.m


Oolite debug support

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

#ifndef NDEBUG


#include "OODebugMonitor.h"
#include "ResourceManager.h"

#include "OOJSConsole.h"
#include "OOJSScript.h"
#include "OOObjCPList.h"
#include "OOJSEngineTimeManagement.h"
#include "OOJSSpecialFunctions.h"

#include "OOTexture.h"
#include "oofnd/String.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/Encoding.hpp"
#include "oofnd/FileSystem.hpp"
#include "OOConcreteTexture.h"
#include "OODrawable.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/Notification.hpp"
#include <map>


namespace {

// The one monitor, never released (sharedDebugMonitor()).
OODebugMonitor *sSingleton = nullptr;

}	// namespace


/*	The monitor's private "application will terminate" notification: posted by
	applicationWillTerminate() (GameControllercalls it on exit) and observed by the monitor
	itself, on oo::NotificationCenter with no object (bead oo-3rb.40). Was the same text as a
	Foundation notification name on the Foundation center; on Mac OS X it was AppKit's
	notification, which oo::NotificationCenter does not receive (that build is not maintained,
	ADR-0009).
*/
static const char * const kOODebugMonitorApplicationWillTerminateNotificationName = "ApplicationWillTerminate";


// Was -init; [super init] could not fail, so its guarded statements stand in a plain block.
void OODebugMonitor::init()
{
	{
		_configFromOXPs = normalizeConfigDictionary(ResourceManager::dictionaryFromFilesNamed("debugConfig.plist", "Config", YES));

		_configOverrides = normalizeConfigDictionary(oo::Defaults::standard().dictionaryForKey("debug-settings-override"));

		_TCPIgnoresDroppedPackets = false;

		::OOJavaScriptEngine *jsEng = OOJavaScriptEngine::sharedEngine();
#if OOJSENGINE_MONITOR_SUPPORT
		jsEng->setMonitor(this);	// the C++ monitor interface (bead oo-9ht.74.1); the engine borrows it
#endif

		setUpDebugConsoleScript();

		oo::NotificationCenter::defaultCenter().addObserver(this, kOODebugMonitorApplicationWillTerminateNotificationName,
															nullptr,
															[this](const oo::Notification &notification) { applicationWillTerminate(notification); });

		oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
															jsEng,
															[this](const oo::Notification &notification) { javaScriptEngineWillReset(notification); });

		oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineDidResetNotificationName,
															jsEng,
															[this](const oo::Notification &) { setUpDebugConsoleScript(); });
	}
}


/*	-dealloc is not translated: it never ran. The singleton boilerplate made -release do nothing,
	and the one monitor is never released (proposed ADR-0056, amendment oo-kq7).
*/


OODebugMonitor *OODebugMonitor::sharedDebugMonitor()
{
	// NOTE: assumes single-threaded access. The debug monitor is not, on the whole, thread safe.
	if (sSingleton == nullptr)
	{
		// Recorded before init(), as +allocWithZone: recorded it before -init ran (amendment oo-z1s4 item 2).
		sSingleton = oo::makeRef<OODebugMonitor>().leakRef();
		sSingleton->init();
	}

	return sSingleton;
}


bool OODebugMonitor::setDebugger(OODebuggerInterface *newDebugger)
{
	std::optional<std::string>	error;	// -connectDebugMonitor:errorMessage:

	if (newDebugger != _debugger.get())
	{
		// Disconnect existing debugger, if any.
		if (newDebugger != nil)
		{
			disconnectDebuggerWithMessage("New debugger set.");
		}
		else
		{
			disconnectDebuggerWithMessage("Debugger disconnected programatically.");
		}

		// If a new debugger was specified, try to connect it.
		if (newDebugger != nil)
		{
			try
			{
				if (newDebugger->connectDebugMonitor(this, &error))
				{
					newDebugger->debugMonitor(this, mergedConfiguration());
					_debugger = oo::Ref<OODebuggerInterface>(newDebugger);
				}
				else
				{
					OO_LOG("debugMonitor.setDebugger.failed", "Could not connect to debugger {}, because an error occurred: {}", newDebugger->description(), error.value_or("(null)"));
				}
			}
			catch (...)
			{
				const auto exception = oo::CurrentOOException();
				if (!exception)  throw;	// not an OOException: it goes on up, as before
				OO_LOG("debugMonitor.setDebugger.failed", "Could not connect to debugger {}, because an exception occurred: {} -- {}", newDebugger->description(), exception->name(), exception->reason());
			}
		}
	}
	
	return _debugger.get() == newDebugger;
}


void OODebugMonitor::performJSConsoleCommand(const std::string &command)
{
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value commandVal = OOJSValueFromPList(context, oo::PList(command));
	OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
	if (_script != nullptr)  _script->callMethod(OOJSID("consolePerformJSCommand"), context, &commandVal, 1, NULL);
	OOJSStopTimeLimiter();
	OOJSRelinquishContext(context);
}


void OODebugMonitor::appendJSConsoleLine(const std::string &string,
										 const std::optional<std::string> &colorKey,
										 NSRange emphasisRange)
{
	OOJSPauseTimeLimiter();
	try
	{
		if (_debugger != nullptr)  _debugger->debugMonitor(this, string, colorKey, emphasisRange);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG("debugMonitor.debuggerConnection.exception", "Exception while attempting to send JavaScript console text to debugger: {} -- {}", exception->name(), exception->reason());
	}
	OOJSResumeTimeLimiter();
}


void OODebugMonitor::appendJSConsoleLine(const std::string &string,
										 const std::optional<std::string> &colorKey)
{
	appendJSConsoleLine(string,
						colorKey,
						NSMakeRange(0, 0));
}


void OODebugMonitor::clearJSConsole()
{
	OOJSPauseTimeLimiter();
	try
	{
		if (_debugger != nullptr)  _debugger->debugMonitorClearConsole(this);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG("debugMonitor.debuggerConnection.exception", "Exception while attempting to clear JavaScript console: {} -- {}", exception->name(), exception->reason());
	}
	OOJSResumeTimeLimiter();
}


void OODebugMonitor::showJSConsole()
{
	OOJSPauseTimeLimiter();
	try
	{
		if (_debugger != nullptr)  _debugger->debugMonitorShowConsole(this);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG("debugMonitor.debuggerConnection.exception", "Exception while attempting to show JavaScript console: {} -- {}", exception->name(), exception->reason());
	}
	OOJSResumeTimeLimiter();
}


oo::PList OODebugMonitor::configurationValueForKey(const std::string &key)
{
	// The override, else (when it is missing or null) the OXPs' value; an OONull in either reads as
	// null (an OONull override hides the OXPs' value).
	// (An Object node held no Objective-C object, which none is since bead oo-4aq6a.5, so any Object
	// node but the null's read as nil, as it did.)
	const auto isNil = [](const oo::PList *v) { return v == nullptr || v->isNull() || (v->type() == oo::PList::Type::Object && !OOIsNullObjectNode(*v)); };
	const oo::PList *result = _configOverrides.find(key);
	if (isNil(result))  result = _configFromOXPs.find(key);
	if (isNil(result) || OOIsNullObjectNode(*result))  return oo::PList();
	return *result;
}


long long OODebugMonitor::configurationIntValueForKey(const std::string &key, long long value)
{
	// -longLongValue of the stored NSString or NSNumber; anything else gives the default.
	const oo::PList object = configurationValueForKey(key);
	switch (object.type())
	{
		case oo::PList::Type::String:
			return oo::str::longLongValue(*object.getIf<std::string>());
		case oo::PList::Type::Bool:
			return *object.getIf<bool>() ? 1 : 0;
		case oo::PList::Type::Integer:
		{
			const oo::PList::Integer &integer = *object.getIf<oo::PList::Integer>();
			return integer.isUnsigned ? static_cast<long long>(integer.unsignedValue()) : integer.value;
		}
		case oo::PList::Type::Real:
			return static_cast<long long>(*object.getIf<double>());
		default:
			return value;
	}
}


void OODebugMonitor::setConfigurationValue(const oo::PList &value, const std::string &key)
{
	if (key.empty())  return;

	const std::string keyString = key;
	const oo::PList normalized = normalizeConfigValue(value, keyString);

	if (!_configOverrides.isDict())  _configOverrides = oo::PList(oo::PList::Dict());
	oo::PList::Dict &overrides = *_configOverrides.getIf<oo::PList::Dict>();
	if (!normalized)
	{
		overrides.erase(keyString);
	}
	else
	{
		overrides[keyString] = normalized;
	}

	// Send changed value to debugger
	oo::PList notifyValue;
	if (!normalized)
	{
		// Setting a null value removes an override, and may reveal an underlying OXP-defined value
		notifyValue = configurationValueForKey(keyString);
	}
	else
	{
		notifyValue = normalized;
	}
	try
	{
		if (_debugger != nullptr)  _debugger->debugMonitor(this, notifyValue, keyString);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG("debugMonitor.debuggerConnection.exception", "Exception while attempting to send configuration update to debugger: {} -- {}", exception->name(), exception->reason());
	}
}


std::vector<std::string> OODebugMonitor::configurationKeys()
{
	std::set<std::string>		keys;

	for (const oo::PList *config : { &_configFromOXPs, &_configOverrides })
	{
		if (const oo::PList::Dict *entries = config->getIf<oo::PList::Dict>())
		{
			for (const auto &entry : *entries)  keys.insert(entry.first);
		}
	}

	std::vector<std::string> result(keys.begin(), keys.end());
	std::stable_sort(result.begin(), result.end(), [](const std::string &a, const std::string &b) { return oo::str::caseInsensitiveCompare(a, b) < 0; });
	return result;
}


bool OODebugMonitor::debuggerConnected()
{
	return _debugger != nullptr;
}


void OODebugMonitor::writeMemStat(const std::string &line)
{
	OO_LOG("debug.memStats", "{}", line);
	appendJSConsoleLine(line, "command-result");
}


namespace {

std::string SizeString(size_t size)
{
	enum
	{
		kThreshold = 2	// 2 KiB, 2 MiB etc.
	};

	unsigned magnitude = 0;
	
	if (size < kThreshold << 10)
	{
		return oo::str::format("%zu bytes", size);
	}
	const char *suffix;
	if (size < kThreshold << 20)
	{
		magnitude = 1;
		suffix = "KiB";
	}
	else if (size < ((size_t)kThreshold << 30))
	{
		magnitude = 2;
		suffix = "MiB";
	}
	else
	{
		magnitude = 3;
		suffix = "GiB";
	}

	float unit = 1 << (magnitude * 10);
	float sizef = (float)size / unit;
	sizef = round(sizef * 100.0f) / 100.f;

	return oo::str::format("%.2f %s", sizef, suffix);
}


} // namespace


// Sets of objects by identity (the mutable sets of textures and entities compared by identity).
struct OODebugMonitor::EntityDumpState
{
	std::set<oo::Ref<OOTexture>>	entityTextures;
	std::set<oo::Ref<OOTexture>>	visibleEntityTextures;
	std::map<Entity *, oo::EntityHold>	seenEntities;	// each held, as its object was retained (bead oo-w9pi2)
	unsigned					seenCount = 0;
	size_t						totalEntityObjSize = 0;
	size_t						totalDrawableSize = 0;
};


void OODebugMonitor::dumpEntity(Entity *entity, EntityDumpState *state, bool parentVisible)
{
	if (entity == nullptr || state->seenEntities.count(entity) != 0)  return;
	state->seenEntities.emplace(entity, oo::EntityHold(entity));

	state->seenCount++;

	size_t entitySize = oo::EntityObjectSize(entity);	// its object's size, as the root's debug size method answered it (bead oo-dpyk8)
	size_t drawableSize = 0;
	// -isKindOfClass:[OOEntityWithDrawable class] and -drawable until bead oo-9ht.40 deleted that facade
	OOEntityWithDrawable *withDrawable = dynamic_cast<OOEntityWithDrawable *>(entity);
	if (withDrawable != nullptr)
	{
		OODrawable *drawable = withDrawable->getDrawable();	// C++ since bead oo-hahfg
		drawableSize = (drawable != nullptr) ? drawable->totalSize() : 0;
	}

	bool visible = parentVisible && entity->isVisible();	// the virtual member -isVisible forwarded to

	for (const oo::Ref<OOTexture> &texture : entity->allTextures())
	{
		state->entityTextures.insert(texture);
		if (visible)  state->visibleEntityTextures.insert(texture);
	}

	std::string extra;
	if (visible)
	{
		extra += ", visible";
	}

	if (drawableSize != 0)
	{
		extra += ", drawable: " + SizeString(drawableSize);
	}

	writeMemStat(oo::str::format("%s: %s%s", oo::EntityShortDescription(entity).c_str(), SizeString(entitySize).c_str(), extra.c_str()));

	state->totalEntityObjSize += entitySize;
	state->totalDrawableSize += drawableSize;

	oo::log::indent();
	if (oo::EntityIsShip(entity))
	{
		for (const auto &subRef : (oo::ToShip(entity) != nullptr ? oo::ToShip(entity)->subEntityEnumerator() : std::vector<oo::EntityHold>()))
		{
			dumpEntity(subRef.get(), state, visible);
		}

		if (oo::EntityIsPlayer(entity) && PLAYER != nullptr)
		{
			PlayerEntity *player = PLAYER;	// the entity that answers -isPlayer (C++ since bead oo-9ht.177)
			NSUInteger i, count = player->dialMaxMissiles();
			for (i = 0; i < count; i++)
			{
				Entity *subentity = player->missileForPylon(i);
				if (subentity != nullptr)  dumpEntity(subentity, state, false);
			}
		}
	}
	if (oo::EntityIsPlanet(entity))
	{
		// FIXME: dump atmosphere texture.
	}
	if (entity->getIsWormhole())
	{
		const oo::PList shipsInTransit = WormholeEntityShipsInTransit(entity);	// -shipsInTransit (C++ since bead oo-9ht.112)
		if (const oo::PList::Array *shipInfos = shipsInTransit.getIf<oo::PList::Array>())
		{
			for (const oo::PList &shipInfo : *shipInfos)
			{
				const oo::PList *shipNode = shipInfo.find("ship");
				::ShipEntity *ship = oo::ToShip((shipNode != nullptr) ? oo::EntityIn(*shipNode) : nullptr);	// the ship's entity node (bead oo-9ht.39.5.3)
				dumpEntity(ship, state, false);
			}
		}
	}
	oo::log::outdent();
}


void OODebugMonitor::dumpMemoryStatistics()
{
	OO_LOG("debug.memStats", "{}", "Memory statistics:");
	oo::log::indent();

	//	Get texture retain counts before the entity dumper starts messing with them.
	const std::vector<oo::Ref<OOTexture>> allTextures = OOTexture::allTextures();
	std::map<OOTexture *, NSUInteger> textureRefCounts;

	for (const oo::Ref<OOTexture> &tex : allTextures)
	{
		// We subtract one because allTextures retains the textures.
		textureRefCounts[tex.get()] = tex->retainCount() - 1;
	}

	size_t totalSize = 0;

	writeMemStat("Entitites:");
	oo::log::indent();

	EntityDumpState entityDumpState;

	for (const auto &entity : (UNIVERSE != nullptr ? UNIVERSE->entityList() : std::vector<oo::EntityHold>()))
	{
		dumpEntity(entity.get(), &entityDumpState, true);
	}
	for (const oo::EntityHold &entityRef : (PLAYER != nullptr ? PLAYER->getScannedWormholes() : std::vector<oo::EntityHold>()))
	{
		dumpEntity(entityRef.get(), &entityDumpState, true);
	}

	oo::log::outdent();
	writeMemStat(oo::str::format("Total entity size (excluding %u entities not accounted for): %s (%s entity objects, %s drawables)",
	 gLiveEntityCount - entityDumpState.seenCount,
	 SizeString(entityDumpState.totalEntityObjSize + entityDumpState.totalDrawableSize).c_str(),
	 SizeString(entityDumpState.totalEntityObjSize).c_str(),
	 SizeString(entityDumpState.totalDrawableSize).c_str()));
	totalSize += entityDumpState.totalEntityObjSize + entityDumpState.totalDrawableSize;

	/*	Sort textures so that textures in the "recent cache" come first by age,
		followed by others.
	*/
	std::vector<oo::Ref<OOTexture>> textures = OOTexture::cachedTexturesByAge();

	for (const oo::Ref<OOTexture> &tex : allTextures)
	{
		if (std::find(textures.begin(), textures.end(), tex) == textures.end())
		{
			textures.push_back(tex);
		}
	}

	size_t totalTextureObjSize = 0;
	size_t totalTextureDataSize = 0;
	size_t visibleTextureDataSize = 0;

	writeMemStat("Textures:");
	oo::log::indent();

	for (const oo::Ref<OOTexture> &texRef : textures)
	{
		OOTexture *tex = texRef.get();
		size_t objSize = sizeof *tex;	// the texture root's size (was its facade's instance size; bead oo-9ht.99)
		size_t dataSize = tex->dataSize();

#if OOTEXTURE_RELOADABLE
		const char *byteCountSuffix = "";
#else
		const char *byteCountSuffix = " (* 2)";
#endif

		const char *usage = "";
		if (entityDumpState.visibleEntityTextures.count(texRef) != 0)
		{
			visibleTextureDataSize += dataSize;	// NOT doubled if !OOTEXTURE_RELOADABLE, because we're interested in what the GPU sees.
			usage = ", visible";
		}
		else if (entityDumpState.entityTextures.count(texRef) != 0)
		{
			usage = ", active";
		}

		const auto counted = textureRefCounts.find(tex);
		unsigned refCount = (counted != textureRefCounts.end()) ? (unsigned)counted->second : 0;

		writeMemStat(oo::str::format("%s: [%u refs%s] %s%s",
		 tex->name().value_or("(null)").c_str(),
		 refCount,
		 usage,
		 SizeString(objSize + dataSize).c_str(),
		 byteCountSuffix));

		totalTextureDataSize += dataSize;
		totalTextureObjSize += objSize;
	}
	totalSize += totalTextureObjSize + totalTextureDataSize;

	oo::log::outdent();

#if !OOTEXTURE_RELOADABLE
	totalTextureDataSize *= 2;
#endif
	writeMemStat(oo::str::format("Total texture size: %s (%s object overhead, %s data, %s visible texture data)",
	 SizeString(totalTextureObjSize + totalTextureDataSize).c_str(),
	 SizeString(totalTextureObjSize).c_str(),
	 SizeString(totalTextureDataSize).c_str(),
	 SizeString(visibleTextureDataSize).c_str()));

	totalSize += dumpJSMemoryStatistics();

	writeMemStat(oo::str::format("Total: %s", SizeString(totalSize).c_str()));

	oo::log::outdent();
}


size_t OODebugMonitor::dumpJSMemoryStatistics()
{
	ooscript::Context context = OOJSAcquireContext();

	ooscript::Runtime runtime = ooscript::getRuntime(context);
	size_t jsSize = ooscript::getGCParameter(runtime, ooscript::GCParam::Bytes);
	size_t jsMax = ooscript::getGCParameter(runtime, ooscript::GCParam::MaxBytes);
	uint32_t jsGCCount = ooscript::getGCParameter(runtime, ooscript::GCParam::NumberOfGCs);

	OOJSRelinquishContext(context);

	writeMemStat(oo::str::format("JavaScript heap: %s (limit %s, %u collections to date)", SizeString(jsSize).c_str(), SizeString(jsMax).c_str(), jsGCCount));
	return jsSize;
}


void OODebugMonitor::setTCPIgnoresDroppedPackets(bool flag)
{
	if (_TCPIgnoresDroppedPackets != flag)
	{
		OO_LOG("debugMonitor.TCPSettings", "The TCP console will {} TCP packets.",
				(flag ? "try to stay connected, ignoring dropped" : "disconnect if an error affects"));
	}
	_TCPIgnoresDroppedPackets = flag;
}


bool OODebugMonitor::TCPIgnoresDroppedPackets()
{
	return _TCPIgnoresDroppedPackets;
}


void OODebugMonitor::setUsingPlugInController(bool flag)
{
	_usingPlugInController = flag;
}


bool OODebugMonitor::usingPlugInController()
{
	return _usingPlugInController;
}


std::string OODebugMonitor::sourceCodeForFile(const std::string &filePath, unsigned line)
{
	const std::string			path = filePath;
	auto						cached = _sourceFiles.find(path);

	if (cached == _sourceFiles.end())
	{
		std::optional<std::vector<std::string>> lines = loadSourceFile(path);
		if (!lines.has_value())  lines = std::vector<std::string>{ oo::str::format("<Can't load file %s>", path.c_str()) };

		cached = _sourceFiles.emplace(path, std::move(*lines)).first;
	}

	const std::vector<std::string> &linesForFile = cached->second;
	if (linesForFile.size() < line || line == 0)  return "<line out of range!>";

	return linesForFile[line - 1];
}


void OODebugMonitor::disconnectDebugger(OODebuggerInterface *debugger,
										const std::optional<std::string> &message)
{
	if (debugger == nullptr)  return;

	if (debugger == _debugger.get())
	{
		disconnectDebuggerWithMessage(message);
	}
	else
	{
		OO_LOG("debugMonitor.disconnect.ignored", "Attempt to disconnect debugger {}, which is not current debugger; ignoring.", debugger->description());
	}
}


#if OOLITE_GNUSTEP
void OODebugMonitor::applicationWillTerminate()
{
	oo::NotificationCenter::defaultCenter().post(kOODebugMonitorApplicationWillTerminateNotificationName, nullptr);
}
#endif


void OODebugMonitor::applicationWillTerminate(const oo::Notification & /*notification*/)
{
	if (_configOverrides)
	{
		oo::Defaults::standard().setObject("debug-settings-override", _configOverrides);
	}

	disconnectDebuggerWithMessage("Oolite is terminating.");
}


void OODebugMonitor::setUpDebugConsoleScript()
{
	ooscript::Context context = OOJSAcquireContext();
	/*	The path to the console script is saved in this here static variable
		so that we can reload it when resetting into strict mode.
		-- Ahruman 2011-02-06
	*/
	static std::optional<std::string> path;

	if (!path)
	{
		path = ResourceManager::pathForFileNamed("oolite-debug-console.js", std::string("Scripts"));
	}
	if (path)
	{
		// Live objects as Object nodes; a nil special-functions wrapper leaves "special" out, as the nil-terminated list did.
		// The console is the monitor itself (oo::PListForeign), whose JS value is the console object
		// (jsValueInContext()), as the facade's node's was (bead oo-9ht.74).
		oo::PList::Dict jsProps;
		jsProps["console"] = oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(this)));
		const oo::Ref<OOJSValue> special = JSSpecialFunctionsObjectWrapper(context);
		if (special != nullptr)  jsProps["special"] = OOJSValueObjectNode(special.get());
		_script = OOJSScript::scriptWithPath(path, oo::PList(std::move(jsProps)));
	}

	// If no script, just make console visible globally as debugConsole.
	if (!_script)
	{
		ooscript::Object global = OOJavaScriptEngine::sharedEngine()->globalObject();
		ooscript::defineProperty(context, global, "debugConsole", jsValueInContext(context), NULL, NULL, ooscript::PropertyFlag::Enumerate);
	}
	
	OOJSRelinquishContext(context);
}


void OODebugMonitor::javaScriptEngineWillReset(const oo::Notification & /*notification*/)
{
	_script = nullptr;
	_jsSelf = NULL;
	
	OOJSConsoleDestroy();
}


void OODebugMonitor::disconnectDebuggerWithMessage(const std::optional<std::string> &message)
{
	try
	{
		if (_debugger != nullptr)  _debugger->disconnectDebugMonitor(this, message);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG("debugMonitor.debuggerConnection.exception", "Exception while attempting to disconnect debugger: {} -- {}", exception->name(), exception->reason());
	}
	
	_debugger = nullptr;	// cleared, then released, as before
}


oo::PList OODebugMonitor::mergedConfiguration()
{
	oo::PList::Dict				result;

	if (const oo::PList::Dict *entries = _configFromOXPs.getIf<oo::PList::Dict>())  result = *entries;
	if (const oo::PList::Dict *entries = _configOverrides.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *entries)  result[key] = value;
	}

	return oo::PList(std::move(result));
}


std::optional<std::vector<std::string>> OODebugMonitor::loadSourceFile(const std::string &filePath)
{
	// The Unicode-file reading of the file's bytes (read from inside an OXZ too, as before).
	const std::optional<oo::Data> data = OODataFromOXZFile(filePath);
	if (!data.has_value())  return std::nullopt;
	const std::string contents = oo::str::decodeUnicodeText(data->stringView());

	/*	Extract lines from file.
FIXME: this works with CRLF and LF, but not CR.
		*/
	return oo::str::split(contents, "\n");
}


oo::PList OODebugMonitor::normalizeConfigDictionary(const oo::PList &dictionary)
{
	oo::PList::Dict			result;

	// Order-free: builds another map.
	if (const oo::PList::Dict *entries = dictionary.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *entries)
		{
			oo::PList normalized = normalizeConfigValue(value, key);
			if (normalized)  result[key] = std::move(normalized);
		}
	}

	return oo::PList(std::move(result));
}


oo::PList OODebugMonitor::normalizeConfigValue(const oo::PList &value, const std::string &key)
{
	oo::Ref<OOColor>	color;
	BOOL					boolValue;

	if (value)
	{
		if (oo::str::hasSuffix(key, "-color") || oo::str::hasSuffix(key, "-colour"))
		{
			// OOColor reads the same object; the normalized array holds +numberWithFloat: values.
			color = OOColor::colorWithDescription(value);
			if (color == nil)  return oo::PList();
			oo::PList::Array components;
			for (float component : color->normalizedArray())  components.push_back(oo::PList::singleReal(component));
			return oo::PList(std::move(components));
		}
		else if (oo::str::hasPrefix(key, "show-console"))
		{
			boolValue = oo::plist_get::boolFrom(&value, NO);	// OOBooleanFromObject (a null value: NO)
			return oo::PList(static_cast<bool>(boolValue));
		}
	}

	return value;
}


void OODebugMonitor::jsEngine(::OOJavaScriptEngine * /*engine*/,
							  ooscript::Context /*context*/,
							  ooscript::ErrorReport *errorReport,
							  unsigned stackSkip,
							  bool showLocation,
							  const std::string &message)
{
	std::string					colorKey;
	std::string					prefix;
	std::string					filePath;
	std::optional<std::string>	scriptLine;
	std::string					formattedMessage;
	NSRange						emphasisRange;
	const char					*showKey = nullptr;

	if (_debugger == nullptr)  return;

	if (errorReport->flags & static_cast<unsigned>(ooscript::ReportFlag::Warning))
	{
		colorKey = "warning";
		prefix = "Warning";
	}
	else if (errorReport->flags & static_cast<unsigned>(ooscript::ReportFlag::Exception))
	{
		colorKey = "exception";
		prefix = "Exception";
	}
	else
	{
		colorKey = "error";
		prefix = "Error";
	}

	if (errorReport->flags & static_cast<unsigned>(ooscript::ReportFlag::Strict))
	{
		prefix += " (strict mode)";
	}

	// Prefix and subsequent colon should be bold (the prefixes are ASCII, so bytes are UTF-16 units):
	emphasisRange = NSMakeRange(0, prefix.size() + 1);

	formattedMessage = oo::str::format("%s: %s", prefix.c_str(), message.c_str());

	// Note that the "active script" isn't necessarily the one causing the
	// error, since one script can call another's methods.

	// avoid windows DEP exceptions!
	OOJSScript *thisScript = OOJSScript::currentlyRunningScript();
	scriptLine = (thisScript != nullptr) ? thisScript->displayName() : std::nullopt;

	if (scriptLine.has_value())
	{
		formattedMessage += "\n    Active script: " + *scriptLine;
	}

	if (showLocation && stackSkip == 0)
	{
		// Append file name and line
		if (errorReport->filename != NULL)  filePath = errorReport->filename;
		if (!filePath.empty())
		{
			formattedMessage += oo::str::format("\n    %s, line %u", oo::str::lastPathComponent(filePath).c_str(), errorReport->lineno);

			// Append source code
			formattedMessage += ":\n    " + sourceCodeForFile(filePath, errorReport->lineno);
		}
	}

	appendJSConsoleLine(formattedMessage,
						colorKey,
						emphasisRange);

	if (errorReport->flags & static_cast<unsigned>(ooscript::ReportFlag::Warning))  showKey = "show-console-on-warning";
	else  showKey = "show-console-on-error";	// if not a warning, it's a proper error.
	const oo::PList showValue = configurationValueForKey(showKey);
	if (oo::plist_get::boolFrom(&showValue, NO))	// OOBooleanFromObject
	{
		showJSConsole();
	}
}


void OODebugMonitor::jsEngine(::OOJavaScriptEngine * /*engine*/,
							  ooscript::Context /*context*/,
							  const std::string &message,
							  const std::optional<std::string> & /*messageClass*/)
{
	appendJSConsoleLine(message, "log");
	const oo::PList showValue = configurationValueForKey("show-console-on-log");
	if (oo::plist_get::boolFrom(&showValue, NO))	// OOBooleanFromObject
	{
		showJSConsole();
	}
}


ooscript::Value OODebugMonitor::jsValueInContext(ooscript::Context context)
{
	if (_jsSelf == NULL)
	{
		_jsSelf = DebugMonitorToJSConsole(context, this);
		if (_jsSelf != NULL)
		{
			if (!OOJSAddGCObjectRoot(context, &_jsSelf, "debug console"))
			{
				_jsSelf = NULL;
			}
		}
	}
	
	if (_jsSelf != NULL)  return ooscript::objectValue(_jsSelf);
	else  return ooscript::nullValue();
}


void OODebugMonitor::clearJSSelf(ooscript::Object /*selfVal*/)
{
	// OOObject's -oo_clearJSSelf:, which the facade did not override: the console object is kept
	// (a GC root) until the engine resets.
}


std::string OODebugMonitor::className() const
{
	return "OODebugMonitor";
}


std::string OODebugMonitor::description() const
{
	return oo::str::format("<OODebugMonitor %s>", oo::str::pointerDescription(this).c_str());
}


/*	The canonical singleton boilerplate (the category OODebugMonitor (Singleton)) was the facade's
	(bead oo-9ht.74 deleted it): the one monitor is made by sharedDebugMonitor() and never released.
*/

#endif /* NDEBUG */
