/*

OODebugMonitor.h

Debugging services object for Oolite.

The debug controller implements Oolite's part of debugging support. It can
connect to one debugger object, which conforms to the OODebuggerInterface
formal protocol. This can either be (part of) a debugger loaded into Oolite
itself (as in the Mac Debug OXP), or provide communications with an external
debugger (for instance, over Distributed Objects or TCP/IP).


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

#import "OODebuggerInterface.h"
#import "OOFoundation.h"
#import "OOWeakReference.h"
#include <quickjs.h>

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#include <map>
#include <optional>
#include <string>
#include <vector>

@class OOJSScript, OOColor;

@protocol OODebugMonitorInterface

// Note: disconnectDebugger:message: will cause a disconnectDebugMonitor:message: message to be sent to the debugger. The debugger should not send disconnectDebugger:message: in response to disconnectDebugMonitor:message:.
- (void)disconnectDebugger:(id<OODebuggerInterface>)debugger
                   message:(const std::optional<std::string>&)message;

// *** JavaScript console support.

// Perform a JS command as though entered at the console, including echoing.
- (void)performJSConsoleCommand:(const std::string&)command;

- (oo::PList)configurationValueForKey:(const std::string&)key;
- (void)setConfigurationValue:(const oo::PList&)value forKey:(const std::string&)key;

- (std::string)sourceCodeForFile:(const std::string&)filePath line:(unsigned)line;

@end

@interface OODebugMonitor : OOWeakRefObject <OODebugMonitorInterface> {
@private
    id<OODebuggerInterface> _debugger;

    // JavaScript console support.
    OOJSScript* _script;
    JSValue _jsSelf; // Owned; released when the JS engine resets.

    oo::PList _configFromOXPs; // Settings from debugConfig.plist (a Dict, never null after -init)
    oo::PList _configOverrides; // Settings from preferences, modifiable through JS (a Dict; values may be Object nodes).

    // Caches
    std::map<std::string, oo::ObjCRef<OOColor*>, std::less<>> _fgColors,
        _bgColors;
    std::map<std::string, std::vector<std::string>, std::less<>> _sourceFiles; // lines of each source file shown so far
    // TCP options
    BOOL _TCPIgnoresDroppedPackets;
    BOOL _usingPlugInController;
}

+ (OODebugMonitor*)sharedDebugMonitor;
- (BOOL)setDebugger:(id<OODebuggerInterface>)debugger;

// *** JavaScript console support.
- (void)appendJSConsoleLine:(id)string
                   colorKey:(const std::optional<std::string>&)colorKey
              emphasisRange:(NSRange)emphasisRange;

- (void)appendJSConsoleLine:(id)string
                   colorKey:(const std::optional<std::string>&)colorKey;

- (void)clearJSConsole;
- (void)showJSConsole;

- (id)cxx_configurationValueForKey:(const std::string&)key class:(Class)klass defaultValue:(id)value;
- (long long)configurationIntValueForKey:(const std::string&)key defaultValue:(long long)value;

- (std::vector<std::string>)configurationKeys; // sorted case-insensitively

- (BOOL)debuggerConnected;

- (void)dumpMemoryStatistics;
- (size_t)dumpJSMemoryStatistics;

- (void)setTCPIgnoresDroppedPackets:(BOOL)flag;
- (BOOL)TCPIgnoresDroppedPackets;

- (void)setUsingPlugInController:(BOOL)flag;
- (BOOL)usingPlugInController;

#if OOLITE_SDL
- (void)applicationWillTerminate;
#endif

@end
