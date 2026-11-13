/*

OODebugMonitor.h

Debugging services object for Oolite.

The debug controller implements Oolite's part of debugging support. It can
connect to one debugger object, which conforms to the OODebuggerInterface
formal protocol. This can either be (part of) a debugger loaded into Oolite
itself (as in the Mac Debug OXP), or provide communications with an external
debugger (for instance, over Distributed Objects or TCP/IP).

The console's JS objects hold the monitor itself, and the console script is
handed it as a property-list Object node (oo::PListForeign).


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

#pragma once

#include <quickjs.h>

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

#include "OODebuggerInterface.h"
#include "OOFoundation.h"
#include "OOJSPrivateObject.h"          // the console's JS glue
#include "OOJavaScriptEngineMonitor.h"  // the engine's monitor, a C++ interface
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class OOJavaScriptEngine;
#include "OOColor.h"   // the colour maps hold std::shared_ptr<OOColor>
#include "OOScript.h"  // the console script, oo::Ref<OOScript>

/*	The one debug monitor (sharedDebugMonitor(), made on first use and never
   released). The debugger reaches it as itself, the JavaScript engine as its
   monitor (the C++ OOJavaScriptEngineMonitor), the console's JS objects hold it
   in their private slot and the console script is handed it as an Object node.
*/
class OODebugMonitor : public oo::PListForeign,
                       public ::OOJavaScriptEngineMonitor,
                       public ::OOJSPrivateObject {
 public:
  static OODebugMonitor* sharedDebugMonitor();
  bool setDebugger(OODebuggerInterface* debugger);

  // Note: disconnectDebugger() will cause a disconnectDebugMonitor:message:
  // message to be sent to the debugger. The debugger should not send
  // disconnectDebugger:message: in response to disconnectDebugMonitor:message:.
  void disconnectDebugger(OODebuggerInterface* debugger,
                          const std::optional<std::string>& message);

  // *** JavaScript console support.

  // Perform a JS command as though entered at the console, including echoing.
  void performJSConsoleCommand(const std::string& command);

  void appendJSConsoleLine(const std::string& string,
                           const std::optional<std::string>& colorKey,
                           NSRange emphasisRange);

  void appendJSConsoleLine(const std::string& string,
                           const std::optional<std::string>& colorKey);

  void clearJSConsole();
  void showJSConsole();

  oo::PList configurationValueForKey(const std::string& key);
  long long configurationIntValueForKey(const std::string& key,
                                        long long value);
  void setConfigurationValue(const oo::PList& value, const std::string& key);

  std::vector<std::string> configurationKeys();  // sorted case-insensitively

  bool debuggerConnected();

  void dumpMemoryStatistics();
  size_t dumpJSMemoryStatistics();

  void setTCPIgnoresDroppedPackets(bool flag);
  bool TCPIgnoresDroppedPackets();

  void setUsingPlugInController(bool flag);
  bool usingPlugInController();

  std::string sourceCodeForFile(const std::string& filePath, unsigned line);

#if OOLITE_SDL
  void applicationWillTerminate();
#endif

  // The JavaScript engine's monitor (OOJavaScriptEngineMonitor): errors and
  // warnings, and log messages (messageClass nullopt if Log() is used rather
  // than LogWithClass()).
  void jsEngine(::OOJavaScriptEngine* engine, JSContext* context,
                const std::string& severity,
                const std::optional<std::string>& file, unsigned line,
                unsigned stackSkip, bool showLocation,
                const std::string& message) override;
  void jsEngine(::OOJavaScriptEngine* engine, JSContext* context,
                const std::string& message,
                const std::optional<std::string>& messageClass) override;

  // The console's JS glue (OOJSPrivateObject): its JavaScript object, made on
  // first use and kept; nothing when a wrapper is finalized.
  JSValue jsValueInContext(JSContext* context) override;  // owned
  void clearJSSelf(JSValueConst selfVal) override;

  // oo::PListForeign: the class name, and a description of the form
  // <OODebugMonitor 0x...>.
  std::string className() const override;
  std::string description() const override;

 private:
  struct EntityDumpState;

  void init();

  void applicationWillTerminate(const oo::Notification& notification);
  void writeMemStat(const std::string& line);
  void dumpEntity(Entity* entity, EntityDumpState* state,
                  bool parentVisible);  // the C++ entity

  void setUpDebugConsoleScript();
  void javaScriptEngineWillReset(const oo::Notification& notification);

  void disconnectDebuggerWithMessage(
      const std::optional<std::string>&
          message);  // nullopt: no message (the TCP client sends a bare close)

  oo::PList mergedConfiguration();

  /*	Convert a configuration dictionary to a standard form. In particular,
          convert all colour specifiers to RGBA arrays with values in [0, 1],
     and converts "show-console" values to booleans.
  */
  oo::PList normalizeConfigDictionary(
      const oo::PList& dictionary);  // always a Dict (empty for null)
  oo::PList normalizeConfigValue(const oo::PList& value,
                                 const std::string& key);  // null: dropped

  std::optional<std::vector<std::string>> loadSourceFile(
      const std::string& filePath);  // nullopt: can't be read

  oo::Ref<OODebuggerInterface> _debugger;  // a C++ interface

  // JavaScript console support.
  oo::Ref<OOScript> _script;       // the console script (an OOJSScript)
  JSValue _jsSelf = JS_UNDEFINED;  // Owned; released when the JS engine resets.

  oo::PList _configFromOXPs;   // Settings from debugConfig.plist (a Dict, never
                               // null after init())
  oo::PList _configOverrides;  // Settings from preferences, modifiable through
                               // JS (a Dict; values may be Object nodes).

  // Caches
  std::map<std::string, std::shared_ptr<OOColor>, std::less<>> _fgColors,
      _bgColors;
  std::map<std::string, std::vector<std::string>, std::less<>>
      _sourceFiles;  // lines of each source file shown so far
  // TCP options
  bool _TCPIgnoresDroppedPackets = {};
  bool _usingPlugInController = {};
};
