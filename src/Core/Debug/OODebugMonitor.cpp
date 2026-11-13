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

#ifdef OO_DEBUG_MONITOR_ENABLED

#include "OODebugMonitor.h"

#include <algorithm>
#include <cstddef>
#include <format>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "OOConcreteTexture.h"
#include "OODescription.h"
#include "OODrawable.h"
#include "OOJSConsole.h"
#include "OOJSEngineTimeManagement.h"
#include "OOJSScript.h"
#include "OOJSSpecialFunctions.h"
#include "OOTexture.h"
#include "ResourceManager.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/Encoding.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

namespace {

// The one monitor, never released (sharedDebugMonitor()).
OODebugMonitor* sSingleton = nullptr;

}  // namespace

/*	The monitor's private "application will terminate" notification: posted
   by applicationWillTerminate() (GameControllercalls it on exit) and observed
   by the monitor itself, on oo::NotificationCenter with no object. On Mac OS
   X it was AppKit's notification, which oo::NotificationCenter does not
   receive (that build is not maintained).
*/
constexpr std::string_view
    kOODebugMonitorApplicationWillTerminateNotificationName =
        "ApplicationWillTerminate";

// Was -init; [super init] could not fail, so its guarded statements stand in a
// plain block.
void OODebugMonitor::init() {
  {
    _configFromOXPs =
        normalizeConfigDictionary(ResourceManager::dictionaryFromFilesNamed(
            "debugConfig.plist", "Config", true));

    _configOverrides = normalizeConfigDictionary(
        oo::Defaults::standard().dictionaryForKey("debug-settings-override"));

    _TCPIgnoresDroppedPackets = false;

    ::OOJavaScriptEngine* jsEng = OOJavaScriptEngine::sharedEngine();
#if OOJSENGINE_MONITOR_SUPPORT
    jsEng->setMonitor(
        this);  // the C++ monitor interface; the engine borrows it
#endif

    setUpDebugConsoleScript();

    oo::NotificationCenter::defaultCenter().addObserver(
        this, kOODebugMonitorApplicationWillTerminateNotificationName, nullptr,
        [this](const oo::Notification& notification) {
          applicationWillTerminate(notification);
        });

    oo::NotificationCenter::defaultCenter().addObserver(
        this, kOOJavaScriptEngineWillResetNotificationName, jsEng,
        [this](const oo::Notification& notification) {
          javaScriptEngineWillReset(notification);
        });

    oo::NotificationCenter::defaultCenter().addObserver(
        this, kOOJavaScriptEngineDidResetNotificationName, jsEng,
        [this](const oo::Notification&) { setUpDebugConsoleScript(); });
  }
}

/*	-dealloc is not translated: it never ran. The singleton boilerplate made
   -release do nothing, and the one monitor is never released.
*/

OODebugMonitor* OODebugMonitor::sharedDebugMonitor() {
  // NOTE: assumes single-threaded access. The debug monitor is not, on the
  // whole, thread safe.
  if (sSingleton == nullptr) {
    // Recorded before init(), as +allocWithZone: recorded it before -init ran.
    sSingleton = oo::makeRef<OODebugMonitor>().leakRef();
    sSingleton->init();
  }

  return sSingleton;
}

bool OODebugMonitor::setDebugger(OODebuggerInterface* newDebugger) {
  std::optional<std::string> error;  // -connectDebugMonitor:errorMessage:

  if (newDebugger != _debugger.get()) {
    // Disconnect existing debugger, if any.
    if (newDebugger != nullptr) {
      disconnectDebuggerWithMessage("New debugger set.");
    } else {
      disconnectDebuggerWithMessage("Debugger disconnected programatically.");
    }

    // If a new debugger was specified, try to connect it.
    if (newDebugger != nullptr) {
      try {
        if (newDebugger->connectDebugMonitor(this, &error)) {
          newDebugger->debugMonitor(this, mergedConfiguration());
          _debugger = oo::Ref<OODebuggerInterface>(newDebugger);
        } else {
          OO_LOG(
              "debugMonitor.setDebugger.failed",
              "Could not connect to debugger {}, because an error occurred: {}",
              newDebugger->description(), error.value_or("(null)"));
        }
      } catch (...) {
        const auto exception = oo::CurrentOOException();
        if (!exception) throw;  // not an OOException: it goes on up, as before
        OO_LOG("debugMonitor.setDebugger.failed",
               "Could not connect to debugger {}, because an exception "
               "occurred: {} -- {}",
               newDebugger->description(), exception->name(),
               exception->reason());
      }
    }
  }

  return _debugger.get() == newDebugger;
}

void OODebugMonitor::performJSConsoleCommand(const std::string& command) {
  JSContext* context = OOJSAcquireContext();
  OOJSVal commandVal = OOJSValueFromPList(context, oo::PList(command));
  OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
  if (_script != nullptr)
    _script->callMethod(OOJSID("consolePerformJSCommand"), context, &commandVal,
                        1, nullptr);
  OOJSStopTimeLimiter();
  OOJSFreeValue(context, commandVal);
  OOJSRelinquishContext(context);
}

void OODebugMonitor::appendJSConsoleLine(
    const std::string& string, const std::optional<std::string>& colorKey,
    NSRange emphasisRange) {
  OOJSPauseTimeLimiter();
  try {
    if (_debugger != nullptr)
      _debugger->debugMonitor(this, string, colorKey, emphasisRange);
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    OO_LOG("debugMonitor.debuggerConnection.exception",
           "Exception while attempting to send JavaScript console text to "
           "debugger: {} -- {}",
           exception->name(), exception->reason());
  }
  OOJSResumeTimeLimiter();
}

void OODebugMonitor::appendJSConsoleLine(
    const std::string& string, const std::optional<std::string>& colorKey) {
  appendJSConsoleLine(string, colorKey, NSMakeRange(0, 0));
}

void OODebugMonitor::clearJSConsole() {
  OOJSPauseTimeLimiter();
  try {
    if (_debugger != nullptr) _debugger->debugMonitorClearConsole(this);
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    OO_LOG("debugMonitor.debuggerConnection.exception",
           "Exception while attempting to clear JavaScript console: {} -- {}",
           exception->name(), exception->reason());
  }
  OOJSResumeTimeLimiter();
}

void OODebugMonitor::showJSConsole() {
  OOJSPauseTimeLimiter();
  try {
    if (_debugger != nullptr) _debugger->debugMonitorShowConsole(this);
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    OO_LOG("debugMonitor.debuggerConnection.exception",
           "Exception while attempting to show JavaScript console: {} -- {}",
           exception->name(), exception->reason());
  }
  OOJSResumeTimeLimiter();
}

oo::PList OODebugMonitor::configurationValueForKey(const std::string& key) {
  // The override, else (when it is missing or null) the OXPs' value; an OONull
  // in either reads as null (an OONull override hides the OXPs' value). Any
  // Object node but the null's reads as nil.
  const auto isNil = [](const oo::PList* v) {
    return v == nullptr || v->isNull() ||
           (v->type() == oo::PList::Type::Object && !OOIsNullObjectNode(*v));
  };
  const oo::PList* result = _configOverrides.find(key);
  if (isNil(result)) result = _configFromOXPs.find(key);
  if (isNil(result) || OOIsNullObjectNode(*result)) return oo::PList();
  return *result;
}

long long OODebugMonitor::configurationIntValueForKey(const std::string& key,
                                                      long long value) {
  // -longLongValue of the stored NSString or NSNumber; anything else gives the
  // default.
  const oo::PList object = configurationValueForKey(key);
  switch (object.type()) {
    case oo::PList::Type::String:
      return oo::str::longLongValue(*object.getIf<std::string>());
    case oo::PList::Type::Bool:
      return *object.getIf<bool>() ? 1 : 0;
    case oo::PList::Type::Integer: {
      const oo::PList::Integer& integer = *object.getIf<oo::PList::Integer>();
      return integer.isUnsigned
                 ? static_cast<long long>(integer.unsignedValue())
                 : integer.value;
    }
    case oo::PList::Type::Real:
      return static_cast<long long>(*object.getIf<double>());
    default:
      return value;
  }
}

void OODebugMonitor::setConfigurationValue(const oo::PList& value,
                                           const std::string& key) {
  if (key.empty()) return;

  const std::string& keyString = key;
  const oo::PList normalized = normalizeConfigValue(value, keyString);

  if (!_configOverrides.isDict())
    _configOverrides = oo::PList(oo::PList::Dict());
  oo::PList::Dict& overrides = *_configOverrides.getIf<oo::PList::Dict>();
  if (!normalized) {
    overrides.erase(keyString);
  } else {
    overrides[keyString] = normalized;
  }

  // Send changed value to debugger
  oo::PList notifyValue;
  if (!normalized) {
    // Setting a null value removes an override, and may reveal an underlying
    // OXP-defined value
    notifyValue = configurationValueForKey(keyString);
  } else {
    notifyValue = normalized;
  }
  try {
    if (_debugger != nullptr)
      _debugger->debugMonitor(this, notifyValue, keyString);
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    OO_LOG("debugMonitor.debuggerConnection.exception",
           "Exception while attempting to send configuration update to "
           "debugger: {} -- {}",
           exception->name(), exception->reason());
  }
}

std::vector<std::string> OODebugMonitor::configurationKeys() {
  std::set<std::string> keys;

  for (const oo::PList* config : {&_configFromOXPs, &_configOverrides}) {
    if (const oo::PList::Dict* entries = config->getIf<oo::PList::Dict>()) {
      for (const auto& entry : *entries) keys.insert(entry.first);
    }
  }

  std::vector<std::string> result(keys.begin(), keys.end());
  std::stable_sort(result.begin(), result.end(),
                   [](const std::string& a, const std::string& b) {
                     return oo::str::caseInsensitiveCompare(a, b) < 0;
                   });
  return result;
}

bool OODebugMonitor::debuggerConnected() { return _debugger != nullptr; }

void OODebugMonitor::writeMemStat(const std::string& line) {
  OO_LOG("debug.memStats", "{}", line);
  appendJSConsoleLine(line, "command-result");
}

namespace {

std::string SizeString(size_t size) {
  constexpr int kThreshold = 2;  // 2 KiB, 2 MiB etc.

  unsigned magnitude = 0;

  if (size < kThreshold << 10) {
    return std::format("{} bytes", size);
  }
  std::string_view suffix;
  if (size < kThreshold << 20) {
    magnitude = 1;
    suffix = "KiB";
  } else if (size < (static_cast<size_t>(kThreshold) << 30)) {
    magnitude = 2;
    suffix = "MiB";
  } else {
    magnitude = 3;
    suffix = "GiB";
  }

  float unit = 1 << (magnitude * 10);
  float sizef = static_cast<float>(size) / unit;
  sizef = round(sizef * 100.0f) / 100.f;

  return std::format("{:.2f} {}", sizef, suffix);
}

}  // namespace

// Sets of objects by identity (the mutable sets of textures and entities
// compared by identity).
struct OODebugMonitor::EntityDumpState {
  std::set<oo::Ref<OOTexture>> entityTextures;
  std::set<oo::Ref<OOTexture>> visibleEntityTextures;
  std::map<Entity*, oo::EntityHold>
      seenEntities;  // each held, as its object was retained
  unsigned seenCount = 0;
  size_t totalEntityObjSize = 0;
  size_t totalDrawableSize = 0;
};

void OODebugMonitor::dumpEntity(Entity* entity, EntityDumpState* state,
                                bool parentVisible) {
  if (entity == nullptr || state->seenEntities.count(entity) != 0) return;
  state->seenEntities.emplace(entity, oo::EntityHold(entity));

  state->seenCount++;

  size_t entitySize =
      oo::EntityObjectSize(entity);  // its object's size, as the root's debug
                                     // size method answered it
  size_t drawableSize = 0;
  OOEntityWithDrawable* withDrawable =
      dynamic_cast<OOEntityWithDrawable*>(entity);
  if (withDrawable != nullptr) {
    OODrawable* drawable = withDrawable->getDrawable();
    drawableSize = (drawable != nullptr) ? drawable->totalSize() : 0;
  }

  bool visible =
      parentVisible &&
      entity->isVisible();  // the virtual member -isVisible forwarded to

  for (const oo::Ref<OOTexture>& texture : entity->allTextures()) {
    state->entityTextures.insert(texture);
    if (visible) state->visibleEntityTextures.insert(texture);
  }

  std::string extra;
  if (visible) {
    extra += ", visible";
  }

  if (drawableSize != 0) {
    extra += ", drawable: " + SizeString(drawableSize);
  }

  writeMemStat(std::format("{}: {}{}", oo::EntityShortDescription(entity),
                           SizeString(entitySize), extra));

  state->totalEntityObjSize += entitySize;
  state->totalDrawableSize += drawableSize;

  oo::log::indent();
  if (oo::EntityIsShip(entity)) {
    for (const auto& subRef : (oo::ToShip(entity) != nullptr
                                   ? oo::ToShip(entity)->subEntityEnumerator()
                                   : std::vector<oo::EntityHold>())) {
      dumpEntity(subRef.get(), state, visible);
    }

    if (oo::EntityIsPlayer(entity) && PLAYER != nullptr) {
      PlayerEntity* player = PLAYER;  // the entity that answers -isPlayer
      std::size_t i, count = player->dialMaxMissiles();
      for (i = 0; i < count; i++) {
        Entity* subentity = player->missileForPylon(i);
        if (subentity != nullptr) dumpEntity(subentity, state, false);
      }
    }
  }
  if (oo::EntityIsPlanet(entity)) {
    // FIXME: dump atmosphere texture.
  }
  if (entity->getIsWormhole()) {
    const oo::PList shipsInTransit =
        WormholeEntityShipsInTransit(entity);  // -shipsInTransit
    if (const oo::PList::Array* shipInfos =
            shipsInTransit.getIf<oo::PList::Array>()) {
      for (const oo::PList& shipInfo : *shipInfos) {
        const oo::PList* shipNode = shipInfo.find("ship");
        ::ShipEntity* ship = oo::ToShip(
            (shipNode != nullptr) ? oo::EntityIn(*shipNode)
                                  : nullptr);  // the ship's entity node
        dumpEntity(ship, state, false);
      }
    }
  }
  oo::log::outdent();
}

void OODebugMonitor::dumpMemoryStatistics() {
  OO_LOG("debug.memStats", "{}", "Memory statistics:");
  oo::log::indent();

  //	Get texture retain counts before the entity dumper starts messing with
  // them.
  const std::vector<oo::Ref<OOTexture>> allTextures = OOTexture::allTextures();
  std::map<OOTexture*, std::size_t> textureRefCounts;

  for (const oo::Ref<OOTexture>& tex : allTextures) {
    // We subtract one because allTextures retains the textures.
    textureRefCounts[tex.get()] = tex->retainCount() - 1;
  }

  size_t totalSize = 0;

  writeMemStat("Entitites:");
  oo::log::indent();

  EntityDumpState entityDumpState;

  for (const auto& entity :
       (UNIVERSE != nullptr ? UNIVERSE->entityList()
                            : std::vector<oo::EntityHold>())) {
    dumpEntity(entity.get(), &entityDumpState, true);
  }
  for (const oo::EntityHold& entityRef :
       (PLAYER != nullptr ? PLAYER->getScannedWormholes()
                          : std::vector<oo::EntityHold>())) {
    dumpEntity(entityRef.get(), &entityDumpState, true);
  }

  oo::log::outdent();
  writeMemStat(
      std::format("Total entity size (excluding {} entities not accounted "
                  "for): {} ({} entity objects, {} drawables)",
                  gLiveEntityCount - entityDumpState.seenCount,
                  SizeString(entityDumpState.totalEntityObjSize +
                             entityDumpState.totalDrawableSize),
                  SizeString(entityDumpState.totalEntityObjSize),
                  SizeString(entityDumpState.totalDrawableSize)));
  totalSize +=
      entityDumpState.totalEntityObjSize + entityDumpState.totalDrawableSize;

  /*	Sort textures so that textures in the "recent cache" come first by age,
          followed by others.
  */
  std::vector<oo::Ref<OOTexture>> textures = OOTexture::cachedTexturesByAge();

  for (const oo::Ref<OOTexture>& tex : allTextures) {
    if (std::find(textures.begin(), textures.end(), tex) == textures.end()) {
      textures.push_back(tex);
    }
  }

  size_t totalTextureObjSize = 0;
  size_t totalTextureDataSize = 0;
  size_t visibleTextureDataSize = 0;

  writeMemStat("Textures:");
  oo::log::indent();

  for (const oo::Ref<OOTexture>& texRef : textures) {
    OOTexture* tex = texRef.get();
    size_t objSize = sizeof *tex;  // the texture root's size
    size_t dataSize = tex->dataSize();

#if OOTEXTURE_RELOADABLE
    const char* byteCountSuffix = "";
#else
    const char* byteCountSuffix = " (* 2)";
#endif

    const char* usage = "";
    if (entityDumpState.visibleEntityTextures.count(texRef) != 0) {
      visibleTextureDataSize +=
          dataSize;  // NOT doubled if !OOTEXTURE_RELOADABLE, because we're
                     // interested in what the GPU sees.
      usage = ", visible";
    } else if (entityDumpState.entityTextures.count(texRef) != 0) {
      usage = ", active";
    }

    const auto counted = textureRefCounts.find(tex);
    unsigned refCount = (counted != textureRefCounts.end())
                            ? static_cast<unsigned>(counted->second)
                            : 0;

    writeMemStat(std::format("{}: [{} refs{}] {}{}",
                             tex->name().value_or("(null)"), refCount, usage,
                             SizeString(objSize + dataSize), byteCountSuffix));

    totalTextureDataSize += dataSize;
    totalTextureObjSize += objSize;
  }
  totalSize += totalTextureObjSize + totalTextureDataSize;

  oo::log::outdent();

#if !OOTEXTURE_RELOADABLE
  totalTextureDataSize *= 2;
#endif
  writeMemStat(std::format(
      "Total texture size: {} ({} object overhead, {} data, {} visible texture "
      "data)",
      SizeString(totalTextureObjSize + totalTextureDataSize),
      SizeString(totalTextureObjSize), SizeString(totalTextureDataSize),
      SizeString(visibleTextureDataSize)));

  totalSize += dumpJSMemoryStatistics();

  writeMemStat(std::format("Total: {}", SizeString(totalSize)));

  oo::log::outdent();
}

size_t OODebugMonitor::dumpJSMemoryStatistics() {
  JSContext* context = OOJSAcquireContext();

  JSRuntime* runtime = JS_GetRuntime(context);
  /*	QuickJS has no heap limit or collection count; report the allocated
          size and the threshold for the next cycle collection instead.
  */
  JSMemoryUsage usage;
  JS_ComputeMemoryUsage(runtime, &usage);
  size_t jsSize = static_cast<size_t>(usage.malloc_size);
  size_t jsGCThreshold = JS_GetGCThreshold(runtime);

  OOJSRelinquishContext(context);

  writeMemStat(
      std::format("JavaScript heap: {} ({} objects, next collection at {})",
                  SizeString(jsSize), static_cast<long long>(usage.obj_count),
                  SizeString(jsGCThreshold)));
  return jsSize;
}

void OODebugMonitor::setTCPIgnoresDroppedPackets(bool flag) {
  if (_TCPIgnoresDroppedPackets != flag) {
    OO_LOG("debugMonitor.TCPSettings", "The TCP console will {} TCP packets.",
           (flag ? "try to stay connected, ignoring dropped"
                 : "disconnect if an error affects"));
  }
  _TCPIgnoresDroppedPackets = flag;
}

bool OODebugMonitor::TCPIgnoresDroppedPackets() {
  return _TCPIgnoresDroppedPackets;
}

void OODebugMonitor::setUsingPlugInController(bool flag) {
  _usingPlugInController = flag;
}

bool OODebugMonitor::usingPlugInController() { return _usingPlugInController; }

std::string OODebugMonitor::sourceCodeForFile(const std::string& filePath,
                                              unsigned line) {
  const std::string& path = filePath;
  auto cached = _sourceFiles.find(path);

  if (cached == _sourceFiles.end()) {
    std::optional<std::vector<std::string>> lines = loadSourceFile(path);
    if (!lines.has_value())
      lines =
          std::vector<std::string>{std::format("<Can't load file {}>", path)};

    cached = _sourceFiles.emplace(path, std::move(*lines)).first;
  }

  const std::vector<std::string>& linesForFile = cached->second;
  if (linesForFile.size() < line || line == 0) return "<line out of range!>";

  return linesForFile[line - 1];
}

void OODebugMonitor::disconnectDebugger(
    OODebuggerInterface* debugger, const std::optional<std::string>& message) {
  if (debugger == nullptr) return;

  if (debugger == _debugger.get()) {
    disconnectDebuggerWithMessage(message);
  } else {
    OO_LOG("debugMonitor.disconnect.ignored",
           "Attempt to disconnect debugger {}, which is not current debugger; "
           "ignoring.",
           debugger->description());
  }
}

#if OOLITE_SDL
void OODebugMonitor::applicationWillTerminate() {
  oo::NotificationCenter::defaultCenter().post(
      kOODebugMonitorApplicationWillTerminateNotificationName, nullptr);
}
#endif

void OODebugMonitor::applicationWillTerminate(
    const oo::Notification& /*notification*/) {
  if (_configOverrides) {
    oo::Defaults::standard().setObject("debug-settings-override",
                                       _configOverrides);
  }

  disconnectDebuggerWithMessage("Oolite is terminating.");
}

void OODebugMonitor::setUpDebugConsoleScript() {
  JSContext* context = OOJSAcquireContext();
  /*	The path to the console script is saved in this here static variable
          so that we can reload it when resetting into strict mode.
          -- Ahruman 2011-02-06
  */
  static std::optional<std::string> path;

  if (!path) {
    path = ResourceManager::pathForFileNamed("oolite-debug-console.js",
                                             std::string("Scripts"));
  }
  if (path) {
    // Live objects as Object nodes; a nil special-functions wrapper leaves
    // "special" out, as the nil-terminated list did. The console is the monitor
    // itself (oo::PListForeign), whose JS value is the console object
    // (jsValueInContext()).
    oo::PList::Dict jsProps;
    jsProps["console"] =
        oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(this)));
    JSValue special = JSSpecialFunctionsObjectWrapper(context);
    if (JS_IsObject(special)) {
      const oo::Ref<OOJSValue> specialWrapper =
          OOJSValue::valueWithJSValue(special, context);
      jsProps["special"] = OOJSValueObjectNode(specialWrapper.get());
    }
    JS_FreeValue(context, special);
    _script = OOJSScript::scriptWithPath(path, oo::PList(std::move(jsProps)));
  }

  // If no script, just make console visible globally as debugConsole.
  if (!_script) {
    JS_DefinePropertyValueStr(
        context, OOJavaScriptEngine::sharedEngine()->globalObject(),
        "debugConsole", jsValueInContext(context), JS_PROP_ENUMERABLE);
  }

  OOJSRelinquishContext(context);
}

void OODebugMonitor::javaScriptEngineWillReset(
    const oo::Notification& /*notification*/) {
  _script = nullptr;
  if (JS_IsObject(_jsSelf)) {
    JS_FreeValue(OOJSAcquireContext(), _jsSelf);
  }
  _jsSelf = JS_UNDEFINED;
}

void OODebugMonitor::disconnectDebuggerWithMessage(
    const std::optional<std::string>& message) {
  try {
    if (_debugger != nullptr) _debugger->disconnectDebugMonitor(this, message);
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    OO_LOG("debugMonitor.debuggerConnection.exception",
           "Exception while attempting to disconnect debugger: {} -- {}",
           exception->name(), exception->reason());
  }

  _debugger = nullptr;  // cleared, then released, as before
}

oo::PList OODebugMonitor::mergedConfiguration() {
  oo::PList::Dict result;

  if (const oo::PList::Dict* entries = _configFromOXPs.getIf<oo::PList::Dict>())
    result = *entries;
  if (const oo::PList::Dict* entries =
          _configOverrides.getIf<oo::PList::Dict>()) {
    for (const auto& [key, value] : *entries) result[key] = value;
  }

  return oo::PList(std::move(result));
}

std::optional<std::vector<std::string>> OODebugMonitor::loadSourceFile(
    const std::string& filePath) {
  // The Unicode-file reading of the file's bytes (read from inside an OXZ too,
  // as before).
  const std::optional<oo::Data> data = OODataFromOXZFile(filePath);
  if (!data.has_value()) return std::nullopt;
  const std::string contents = oo::str::decodeUnicodeText(data->stringView());

  /*	Extract lines from file.
FIXME: this works with CRLF and LF, but not CR.
          */
  return oo::str::split(contents, "\n");
}

oo::PList OODebugMonitor::normalizeConfigDictionary(
    const oo::PList& dictionary) {
  oo::PList::Dict result;

  // Order-free: builds another map.
  if (const oo::PList::Dict* entries = dictionary.getIf<oo::PList::Dict>()) {
    for (const auto& [key, value] : *entries) {
      oo::PList normalized = normalizeConfigValue(value, key);
      if (normalized) result[key] = std::move(normalized);
    }
  }

  return oo::PList(std::move(result));
}

oo::PList OODebugMonitor::normalizeConfigValue(const oo::PList& value,
                                               const std::string& key) {
  std::shared_ptr<OOColor> color;
  bool boolValue;

  if (value) {
    if (oo::str::hasSuffix(key, "-color") ||
        oo::str::hasSuffix(key, "-colour")) {
      // OOColor reads the same object; the normalized array holds
      // +numberWithFloat: values.
      color = OOColor::colorWithDescription(value);
      if (color == nullptr) return oo::PList();
      oo::PList::Array components;
      for (float component : color->normalizedArray())
        components.push_back(oo::PList::singleReal(component));
      return oo::PList(std::move(components));
    } else if (oo::str::hasPrefix(key, "show-console")) {
      boolValue = oo::plist_get::boolFrom(
          &value, false);  // OOBooleanFromObject (a null value: NO)
      return oo::PList(static_cast<bool>(boolValue));
    }
  }

  return value;
}

void OODebugMonitor::jsEngine(::OOJavaScriptEngine* /*engine*/,
                              JSContext* /*context*/,
                              const std::string& severity,
                              const std::optional<std::string>& filePath,
                              unsigned line, unsigned stackSkip,
                              bool showLocation, const std::string& message) {
  std::string colorKey;
  std::string prefix;
  std::optional<std::string> scriptLine;
  std::string formattedMessage;
  NSRange emphasisRange;
  std::string_view showKey;
  bool isWarning = (severity == "warning");

  if (_debugger == nullptr) return;

  // QuickJS reports errors as exceptions; there are no non-exception errors or
  // strict mode warnings.
  if (isWarning) {
    colorKey = "warning";
    prefix = "Warning";
  } else {
    colorKey = "exception";
    prefix = "Exception";
  }

  // Prefix and subsequent colon should be bold (the prefixes are ASCII, so
  // bytes are UTF-16 units):
  emphasisRange = NSMakeRange(0, prefix.size() + 1);

  formattedMessage = std::format("{}: {}", prefix, message);

  // Note that the "active script" isn't necessarily the one causing the
  // error, since one script can call another's methods.

  // avoid windows DEP exceptions!
  OOJSScript* thisScript = OOJSScript::currentlyRunningScript();
  scriptLine =
      (thisScript != nullptr) ? thisScript->displayName() : std::nullopt;

  if (scriptLine.has_value()) {
    formattedMessage += "\n    Active script: " + *scriptLine;
  }

  if (showLocation && stackSkip == 0 && filePath.has_value() &&
      !filePath->empty()) {
    // Append file name and line
    formattedMessage += std::format(
        "\n    {}, line {}", oo::str::lastPathComponent(*filePath), line);

    // Append source code
    formattedMessage += ":\n    " + sourceCodeForFile(*filePath, line);
  }

  appendJSConsoleLine(formattedMessage, colorKey, emphasisRange);

  if (isWarning)
    showKey = "show-console-on-warning";
  else
    showKey =
        "show-console-on-error";  // if not a warning, it's a proper error.
  const oo::PList showValue = configurationValueForKey(std::string(showKey));
  if (oo::plist_get::boolFrom(&showValue, false))  // OOBooleanFromObject
  {
    showJSConsole();
  }
}

void OODebugMonitor::jsEngine(
    ::OOJavaScriptEngine* /*engine*/, JSContext* /*context*/,
    const std::string& message,
    const std::optional<std::string>& /*messageClass*/) {
  appendJSConsoleLine(message, "log");
  const oo::PList showValue = configurationValueForKey("show-console-on-log");
  if (oo::plist_get::boolFrom(&showValue, false))  // OOBooleanFromObject
  {
    showJSConsole();
  }
}

JSValue OODebugMonitor::jsValueInContext(JSContext* context) {
  if (!JS_IsObject(_jsSelf)) {
    _jsSelf = DebugMonitorToJSConsole(context, this);
  }
  return JS_DupValue(context, _jsSelf);
}

void OODebugMonitor::clearJSSelf(JSValueConst /*selfVal*/) {
  // The console object is kept (owned) until the engine resets.
}

std::string OODebugMonitor::className() const { return "OODebugMonitor"; }

std::string OODebugMonitor::description() const {
  return std::format("<OODebugMonitor {}>", oo::str::pointerDescription(this));
}

/*	The one monitor is made by sharedDebugMonitor() and never released.
 */

#endif /* OO_DEBUG_MONITOR_ENABLED */
