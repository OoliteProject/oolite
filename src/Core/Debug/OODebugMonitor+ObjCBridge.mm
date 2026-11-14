/*

OODebugMonitor+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-kq7): the Objective-C OODebugMonitor facade (see
OODebugMonitor+ObjCBridge.h). Every method forwards to its C++ member. The facade adopts the
JavaScript engine's OOJavaScriptEngineMonitor here, so that OODebugMonitor.h does not import the
engine's header, and keeps the canonical singleton boilerplate that was OODebugMonitor.mm's.
Deleted with OODebugMonitor+ObjCBridge.h.


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

#import "OODebugMonitor.h"
#import "OOJavaScriptEngine.h"

#include <climits>

namespace {

// The facade, recorded by +allocWithZone: (the singleton boilerplate below).
OODebugMonitor* sSingleton = nil;

} // namespace

@interface OODebugMonitor (OOObjCBridgePrivate)

- (id)initWithCxxMonitor:(cxx::OODebugMonitor*)monitor;

@end

// The JavaScript engine's monitor (was declared by the category OODebugMonitor (Private)).
@interface OODebugMonitor (OOJavaScriptEngineMonitor) <OOJavaScriptEngineMonitor>
@end

@implementation OODebugMonitor

/*	Inside the @implementation for the private ivar. No peer table: there is one monitor, and its
        facade, once made, is never deallocated (-release does nothing), so the facade is
        sSingleton for the life of the process.
*/
OODebugMonitor* oo::ToObjC(cxx::OODebugMonitor* monitor)
{
    if (monitor == nullptr)
        return nil;
    if (sSingleton == nil)
        sSingleton = [[OODebugMonitor alloc] initWithCxxMonitor:monitor]; // never released
    return sSingleton;
}

cxx::OODebugMonitor* oo::ToCxx(OODebugMonitor* monitor)
{
    if (monitor == nil)
        return nullptr;
    return monitor->_cxxMonitor.get();
}

- (id)initWithCxxMonitor:(cxx::OODebugMonitor*)monitor
{
    self = [super init];
    if (self != nil)
        _cxxMonitor = oo::Ref<cxx::OODebugMonitor>(monitor);
    return self;
}

+ (OODebugMonitor*)sharedDebugMonitor
{
    return oo::ToObjC(cxx::OODebugMonitor::sharedDebugMonitor());
}

- (BOOL)setDebugger:(id<OODebuggerInterface>)newDebugger
{
    return _cxxMonitor->setDebugger(newDebugger);
}

- (void)performJSConsoleCommand:(const std::string&)command
{
    _cxxMonitor->performJSConsoleCommand(command);
}

- (void)appendJSConsoleLine:(const std::string&)string
                   colorKey:(const std::optional<std::string>&)colorKey
              emphasisRange:(NSRange)emphasisRange
{
    _cxxMonitor->appendJSConsoleLine(string, colorKey, emphasisRange);
}

- (void)appendJSConsoleLine:(const std::string&)string
                   colorKey:(const std::optional<std::string>&)colorKey
{
    _cxxMonitor->appendJSConsoleLine(string, colorKey);
}

- (void)clearJSConsole
{
    _cxxMonitor->clearJSConsole();
}

- (void)showJSConsole
{
    _cxxMonitor->showJSConsole();
}

- (oo::PList)configurationValueForKey:(const std::string&)key
{
    return _cxxMonitor->configurationValueForKey(key);
}

- (long long)configurationIntValueForKey:(const std::string&)key defaultValue:(long long)value
{
    return _cxxMonitor->configurationIntValueForKey(key, value);
}

- (void)setConfigurationValue:(const oo::PList&)value forKey:(const std::string&)key
{
    _cxxMonitor->setConfigurationValue(value, key);
}

- (std::vector<std::string>)configurationKeys
{
    return _cxxMonitor->configurationKeys();
}

- (BOOL)debuggerConnected
{
    return _cxxMonitor->debuggerConnected();
}

- (void)dumpMemoryStatistics
{
    _cxxMonitor->dumpMemoryStatistics();
}

- (size_t)dumpJSMemoryStatistics
{
    return _cxxMonitor->dumpJSMemoryStatistics();
}

- (void)setTCPIgnoresDroppedPackets:(BOOL)flag
{
    _cxxMonitor->setTCPIgnoresDroppedPackets(flag);
}

- (BOOL)TCPIgnoresDroppedPackets
{
    return _cxxMonitor->TCPIgnoresDroppedPackets();
}

- (void)setUsingPlugInController:(BOOL)flag
{
    _cxxMonitor->setUsingPlugInController(flag);
}

- (BOOL)usingPlugInController
{
    return _cxxMonitor->usingPlugInController();
}

- (std::string)sourceCodeForFile:(const std::string&)filePath line:(unsigned)line
{
    return _cxxMonitor->sourceCodeForFile(filePath, line);
}

- (void)disconnectDebugger:(id<OODebuggerInterface>)debugger
                   message:(const std::optional<std::string>&)message
{
    _cxxMonitor->disconnectDebugger(debugger, message);
}

#if OOLITE_SDL
- (void)applicationWillTerminate
{
    _cxxMonitor->applicationWillTerminate();
}
#endif

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return _cxxMonitor->oo_jsValueInContext(context);
}

@end

@implementation OODebugMonitor (OOJavaScriptEngineMonitor)

- (void)jsEngine:(OOJavaScriptEngine*)engine
              context:(JSContext*)context
    problemOfSeverity:(const std::string&)severity
               inFile:(const std::optional<std::string>&)filePath
                 line:(unsigned)line
            stackSkip:(unsigned)stackSkip
      showingLocation:(BOOL)showLocation
          withMessage:(const std::string&)message
{
    _cxxMonitor->jsEngine(engine, context, severity, filePath, line, stackSkip, showLocation, message);
}

- (void)jsEngine:(OOJavaScriptEngine*)engine
         context:(JSContext*)context
      logMessage:(const std::string&)message
         ofClass:(const std::optional<std::string>&)messageClass
{
    _cxxMonitor->jsEngine(engine, context, message, messageClass);
}

@end

@implementation OODebugMonitor (Singleton)

/*	Canonical singleton boilerplate.
See Cocoa Fundamentals Guide: Creating a Singleton Instance.
See also +sharedDebugMonitor above.

NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(OOZone*)inZone
{
    if (sSingleton == nil) {
        sSingleton = [super allocWithZone:inZone];
        return sSingleton;
    }
    return nil;
}

- (id)copyWithZone:(OOZone*)inZone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return UINT_MAX;
}

- (void)release
{
}

- (id)autorelease
{
    return self;
}

@end

#endif /* OO_DEBUG_MONITOR_ENABLED */
