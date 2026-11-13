/*

OOJavaScriptEngine.h (QuickJS-ng)

JavaScript support for Oolite, ported from SpiderMonkey 1.8.5 to QuickJS-ng.
See https://github.com/OoliteProject/oolite/issues/580.

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

#include <quickjs.h>  // IWYU pragma: export

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOFoundation.h"
#include "OOTypes.h"
#include "oofnd/Object.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOObject.h"

#if !OOJS_POC_HARNESS
#include "PlayerEntity.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "Universe.h"
#endif

/*	The plain C++ part of the engine API: reporters, converters, argument
   and return macros, the native wrappers. A binding includes only that header.
*/
#include "OOJSEngineCore.h"  // IWYU pragma: export

#define OOJSENGINE_MONITOR_SUPPORT OO_DEBUG_MONITOR_ENABLED

#if OOJSENGINE_MONITOR_SUPPORT
#include "OOJavaScriptEngineMonitor.h"
#endif

/*	The engine: the singleton that owns the JS runtime and the main thread
   context. A global class; it is the sender of its reset notifications.
*/
class OOJavaScriptEngine : public oo::Object {
 public:
  // The shared engine, made on first use; borrowed, never released.
  static OOJavaScriptEngine* sharedEngine();

  ~OOJavaScriptEngine();

  JSContext* context();
  // The global object, borrowed; invalidated by reset().
  JSValueConst globalObject();

  void runMissionCallback();

  /*	Tear down context and global object and rebuild them from scratch. This
          invalidates globalObject() and all prototypes.
  */
  bool reset();

  // Call a JS function. *outResult (may be NULL) is owned by the caller.
  // Exceptions are reported and cleared.
  bool callJSFunction(JSValueConst function, JSValueConst jsThis, int argc,
                      JSValueConst* argv, JSValue* outResult);

  void garbageCollectionOpportunity(bool force);

  bool showErrorLocations();
  void setShowErrorLocations(bool value);

#ifdef OO_DEBUG_MONITOR_ENABLED
  bool dumpStackForErrors();
  void setDumpStackForErrors(bool value);

  bool dumpStackForWarnings();
  void setDumpStackForWarnings(bool value);

  // Install handler for JS "debugger" statment. (Not supported by QuickJS; does
  // nothing.)
  void enableDebuggerStatement();
#endif

  /*	Destroy the context and runtime. All native objects holding JSValues
     must have released them first. Returns the number of JS objects still alive
          after a final garbage collection; if it is non-zero, they are logged
          and the runtime is abandoned rather than freed.
  */
  std::size_t shutDown();

#if OOJSENGINE_MONITOR_SUPPORT
  // (OOMonitorSupport)
  void setMonitor(OOJavaScriptEngineMonitor* monitor);  // borrowed

  // (OOMonitorSupportInternal)
  // file is nullopt when the stack gives no location (a nil file before).
  void sendMonitorProblem(const std::string& severity,
                          const std::optional<std::string>& file, unsigned line,
                          const std::string& message, JSContext* context);
  // nullopt is meaningful to the monitor (Log() with a null message; no class
  // for Log()).
  void sendMonitorLogMessage(const std::optional<std::string>& message,
                             const std::optional<std::string>& messageClass,
                             JSContext* context);
#endif

 private:
  void init();  // -init's body after [super init]: run by sharedEngine() on the
                // new object

  void createMainThreadContext();
  void destroyMainThreadContext();

  JSRuntime* _runtime = nullptr;
  JSContext* _context = nullptr;
  JSValue _globalObject = JS_UNDEFINED;  // owned
  bool _showErrorLocations = {};

#ifdef OO_DEBUG_MONITOR_ENABLED
  bool _dumpStackForErrors = {};
  bool _dumpStackForWarnings = {};
#endif
#if OOJSENGINE_MONITOR_SUPPORT
  OOJavaScriptEngineMonitor* _monitor =
      nullptr;  // borrowed: the debug monitor lives as long as the process
#endif
};

// A vector box's JS value (OOJSValueFromPList, for an Object node that holds
// one), owned by the
// caller.
class OONativeVector;
JSValue OONativeVectorJSValueInContext(OONativeVector* vector,
                                       JSContext* context);

/*	OONull: the placeholder for null inside native collections, which cannot
   hold nil. A JS array element that is null or undefined becomes [OONull null]
   in the native array, and [OONull null] becomes JS null, so JS null
   round-trips. Game code uses it where a collection slot is empty (MFD
   settings, target memory, script event arguments). It describes itself as
   "<null>", and -copy returns itself. A property list holds it as an Object
   node whose foreign object it is (OONullObjectNode()).
*/
class OONull : public oo::PListForeign {
 public:
  // The one null, made on first use; borrowed, never released.
  static OONull* null();

  JSValue jsValueInContext(JSContext* context);  // JS null

  // oo::PListForeign: the class name, and "%@" as "<null>".
  std::string className() const override;
  std::string description() const override;  // "<null>"
};

// The one null as a PList::Object node ([OONull null] through
// oo::PListObject()), and whether a node is that null (oo::ObjectIn(node) ==
// [OONull null]).
inline oo::PList OONullObjectNode() {
  return oo::PList(oo::PList::Object(oo::share(OONull::null())));
}

inline bool OOIsNullObjectNode(const oo::PList& plist) {
  const oo::PList::Object* node = plist.getIf<oo::PList::Object>();
  return node != nullptr && node->get() == OONull::null();
}

// OOJSValue is declared in OOJSEngineCore.h (a plain C++ header, so C++-only
// bindings can use it).

#if !OOJS_POC_HARNESS

class Entity;

// OOEntityFilterPredicate wrapping a JavaScript function.
typedef struct {
  JSContext* context;
  JSValueConst function;  // Caller is responsible for ensuring this is a
                          // function object (using OOJSValueIsFunction()).
  JSValueConst jsThis;
  bool errorFlag;  // Set if a JS exception occurs. The
                   // exception will have been reported.
                   // This also supresses further filtering.
} JSFunctionPredicateParameter;
bool JSFunctionPredicate(Entity* entity, void* parameter);

// YES for ships and (normal) planets. Parameter: ignored.
bool JSEntityIsJavaScriptVisiblePredicate(Entity* entity, void* parameter);

// YES for ships other than sub-entities and menu-display ships, and planets
// other than atmospheres and menu miniatures. Parameter: ignored.
bool JSEntityIsJavaScriptSearchablePredicate(Entity* entity, void* parameter);

// YES for menu-display ships. Parameter: ignored
bool JSEntityIsDemoShipPredicate(Entity* entity, void* parameter);

#endif

/*	OOJSGetCxxPrivate() (OOJSPrivateObject.h) reads the C++ object every JS
   object's private slot holds.
*/
#include "OOFoundation.h"
