/*

OODebugTCPConsoleClient+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-kq7 and oo-4nhg): the Objective-C
OODebugTCPConsoleClient facade (see OODebugTCPConsoleClient+ObjCBridge.h). Every method forwards
to its C++ member; the debugger protocol's monitor crosses with oo::ToCxx. Deleted with
OODebugTCPConsoleClient+ObjCBridge.h.


Oolite Debug Support

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
#import "OODebugTCPConsoleClient.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OODebugTCPConsoleClient (OOObjCBridgePrivate)

- (id)initWithCxxClient:(cxx::OODebugTCPConsoleClient*)client;

@end

@implementation OODebugTCPConsoleClient

// Inside the @implementation for the private ivar.
OODebugTCPConsoleClient* oo::ToObjC(cxx::OODebugTCPConsoleClient* client)
{
    return Peers().peerFor(client, [client] { return [[OODebugTCPConsoleClient alloc] initWithCxxClient:client]; });
}

cxx::OODebugTCPConsoleClient* oo::ToCxx(OODebugTCPConsoleClient* client)
{
    if (client == nil)
        return nullptr;
    return client->_cxxClient.get();
}

- (id)initWithCxxClient:(cxx::OODebugTCPConsoleClient*)client
{
    self = [super init];
    if (self != nil)
        _cxxClient = oo::Ref<cxx::OODebugTCPConsoleClient>(client);
    return self;
}

- (id)init
{
    return [self initWithAddress:std::nullopt port:0];
}

- (id)initWithAddress:(const std::optional<std::string>&)address port:(uint16_t)port
{
    oo::Ref<cxx::OODebugTCPConsoleClient> client = cxx::OODebugTCPConsoleClient::clientWithAddress(address, port);
    if (client.get() == nullptr) {
        // The connection failed.
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;

    _cxxClient = std::move(client);
    @autoreleasepool {
        Peers().peerFor(_cxxClient.get(), [self] { return [self retain]; });
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxClient.get());
    [super dealloc];
}

- (BOOL)connectDebugMonitor:(OODebugMonitor*)debugMonitor
               errorMessage:(std::optional<std::string>*)message
{
    return _cxxClient->connectDebugMonitor(oo::ToCxx(debugMonitor), message);
}

- (void)disconnectDebugMonitor:(OODebugMonitor*)debugMonitor
                       message:(const std::optional<std::string>&)message
{
    _cxxClient->disconnectDebugMonitor(oo::ToCxx(debugMonitor), message);
}

- (void)debugMonitor:(OODebugMonitor*)debugMonitor
     jsConsoleOutput:(const std::string&)output
            colorKey:(const std::optional<std::string>&)colorKey
       emphasisRange:(NSRange)emphasisRange
{
    _cxxClient->debugMonitor(oo::ToCxx(debugMonitor), output, colorKey, emphasisRange);
}

- (void)debugMonitorClearConsole:(OODebugMonitor*)debugMonitor
{
    _cxxClient->debugMonitorClearConsole(oo::ToCxx(debugMonitor));
}

- (void)debugMonitorShowConsole:(OODebugMonitor*)debugMonitor
{
    _cxxClient->debugMonitorShowConsole(oo::ToCxx(debugMonitor));
}

- (void)debugMonitor:(OODebugMonitor*)debugMonitor
    noteConfiguration:(const oo::PList&)configuration
{
    _cxxClient->debugMonitor(oo::ToCxx(debugMonitor), configuration);
}

- (void)debugMonitor:(OODebugMonitor*)debugMonitor
    noteChangedConfigrationValue:(const oo::PList&)newValue
                          forKey:(const std::string&)key
{
    _cxxClient->debugMonitor(oo::ToCxx(debugMonitor), newValue, key);
}

@end

#endif /* OO_DEBUG_MONITOR_ENABLED */
