/*

OODebugMonitor.h

Debugging services object for Oolite.

The debug controller implements Oolite's part of debugging support. It can
connect to one debugger object, which conforms to the OODebuggerInterface
formal protocol. This can either be (part of) a debugger loaded into Oolite
itself (as in the Mac Debug OXP), or provide communications with an external
debugger (for instance, over Distributed Objects or TCP/IP).

C++20 since bead oo-kq7, the Debug module's pattern seam (proposed ADR-0056, amendment oo-kq7).
The class is cxx::OODebugMonitor while OODebugMonitor+ObjCBridge.h, imported at the end of this
header, keeps the Objective-C OODebugMonitor that the debugger, the JavaScript console and the
game message; the bridge's deletion bead moves it out of namespace cxx.


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

#ifndef OODEBUGMONITOR_H
#define OODEBUGMONITOR_H

#import "OODebuggerInterface.h"
#import "OOFoundation.h"
#import "OOWeakReference.h"
#include <quickjs.h>

#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#include <map>
#include <optional>
#include <string>
#include <vector>

@class OOJSScript, OOColor, OOJavaScriptEngine;

namespace cxx {

/*	The one debug monitor (sharedDebugMonitor()). The debugger reaches it through the
        OODebugMonitorInterface protocol, and the JavaScript engine as its monitor
        (OOJavaScriptEngineMonitor); both are adopted by the Objective-C facade
        (OODebugMonitor+ObjCBridge.h), which is what the debugger, the engine and the console script
        are handed.
*/
class OODebugMonitor : public oo::RefCounted {
public:
    static OODebugMonitor* sharedDebugMonitor();
    bool setDebugger(id<OODebuggerInterface> debugger);

    // Note: disconnectDebugger() will cause a disconnectDebugMonitor:message: message to be sent to the debugger. The debugger should not send disconnectDebugger:message: in response to disconnectDebugMonitor:message:.
    void disconnectDebugger(id<OODebuggerInterface> debugger,
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
    long long configurationIntValueForKey(const std::string& key, long long value);
    void setConfigurationValue(const oo::PList& value, const std::string& key);

    std::vector<std::string> configurationKeys(); // sorted case-insensitively

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

    // The JavaScript engine's monitor (OOJavaScriptEngineMonitor): errors and warnings, and log
    // messages (messageClass nullopt if Log() is used rather than LogWithClass()).
    void jsEngine(::OOJavaScriptEngine* engine,
        JSContext* context,
        const std::string& severity,
        const std::optional<std::string>& file,
        unsigned line,
        unsigned stackSkip,
        bool showLocation,
        const std::string& message);
    void jsEngine(::OOJavaScriptEngine* engine,
        JSContext* context,
        const std::string& message,
        const std::optional<std::string>& messageClass);

    // The console's JavaScript object (the engine sends the facade -oo_jsValueInContext:).
    JSValue oo_jsValueInContext(JSContext* context); // owned

private:
    struct EntityDumpState;

    void init();

    void applicationWillTerminate(const oo::Notification& notification);
    void writeMemStat(const std::string& line);
    void dumpEntity(id entity, EntityDumpState* state, bool parentVisible);

    void setUpDebugConsoleScript();
    void javaScriptEngineWillReset(const oo::Notification& notification);

    void disconnectDebuggerWithMessage(const std::optional<std::string>& message); // nullopt: no message (the TCP client sends a bare close)

    oo::PList mergedConfiguration();

    /*	Convert a configuration dictionary to a standard form. In particular,
            convert all colour specifiers to RGBA arrays with values in [0, 1], and
            converts "show-console" values to booleans.
    */
    oo::PList normalizeConfigDictionary(const oo::PList& dictionary); // always a Dict (empty for null)
    oo::PList normalizeConfigValue(const oo::PList& value, const std::string& key); // null: dropped

    std::optional<std::vector<std::string>> loadSourceFile(const std::string& filePath); // nullopt: can't be read

    oo::ObjCRef<id<OODebuggerInterface>> _debugger;

    // JavaScript console support.
    oo::ObjCRef<::OOJSScript*> _script;
    JSValue _jsSelf = JS_UNDEFINED; // Owned; released when the JS engine resets.

    oo::PList _configFromOXPs; // Settings from debugConfig.plist (a Dict, never null after init())
    oo::PList _configOverrides; // Settings from preferences, modifiable through JS (a Dict; values may be Object nodes).

    // Caches
    std::map<std::string, oo::ObjCRef<OOColor*>, std::less<>> _fgColors,
        _bgColors;
    std::map<std::string, std::vector<std::string>, std::less<>> _sourceFiles; // lines of each source file shown so far
    // TCP options
    bool _TCPIgnoresDroppedPackets = { };
    bool _usingPlugInController = { };
};

} // namespace cxx

// Transitional: the Objective-C OODebugMonitor, for the debugger, the console and the game,
// which are not yet converted. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OODebugMonitor+ObjCBridge.h"

#endif // OODEBUGMONITOR_H
