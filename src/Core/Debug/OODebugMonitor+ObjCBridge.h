/*

OODebugMonitor+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-kq7): the Objective-C OODebugMonitor, a facade over
the C++ cxx::OODebugMonitor (OODebugMonitor.h), for its callers: the debugger (the TCP console
client, which the golden harness drives the game through), the JavaScript console
(OOJSConsole.mm), the debug support, the player's controls and the game controller. Its
interface, and the OODebugMonitorInterface protocol it adopts, are the ones OODebugMonitor.h
declared before the conversion, copied exactly (same selectors, same types), so they compile and
behave unchanged. Imported as the last line of OODebugMonitor.h; do not import it directly.

The monitor is a singleton, and so is its facade: it is made on the first crossing
(oo::ToObjC), keeps the canonical singleton boilerplate (no second instance; -retain and
-release do nothing), and so lives as long as the process. It is the object the debugger, the
JavaScript engine (whose monitor it is: OOJavaScriptEngineMonitor, adopted in
OODebugMonitor+ObjCBridge.mm) and the console's JavaScript object are handed, and its superclass
OOWeakRefObject keeps its weak reference.

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once every caller is C++.


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

#ifndef OODEBUGMONITOR_OBJCBRIDGE_H
#define OODEBUGMONITOR_OBJCBRIDGE_H

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
    oo::Ref<cxx::OODebugMonitor> _cxxMonitor;
}

+ (OODebugMonitor*)sharedDebugMonitor;
- (BOOL)setDebugger:(id<OODebuggerInterface>)debugger;

// *** JavaScript console support.
- (void)appendJSConsoleLine:(const std::string&)string
                   colorKey:(const std::optional<std::string>&)colorKey
              emphasisRange:(NSRange)emphasisRange;

- (void)appendJSConsoleLine:(const std::string&)string
                   colorKey:(const std::optional<std::string>&)colorKey;

- (void)clearJSConsole;
- (void)showJSConsole;

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

namespace oo {

// The monitor's facade: made on the first call and kept for the life of the process; nil for null.
OODebugMonitor* ToObjC(cxx::OODebugMonitor* monitor);

// The C++ monitor behind the facade, borrowed (the facade retains it); null for nil.
cxx::OODebugMonitor* ToCxx(OODebugMonitor* monitor);

} // namespace oo

#endif // OODEBUGMONITOR_OBJCBRIDGE_H
