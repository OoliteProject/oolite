/*

OODebugTCPConsoleClient+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-kq7 and oo-4nhg): the Objective-C
OODebugTCPConsoleClient, a facade over the C++ cxx::OODebugTCPConsoleClient
(OODebugTCPConsoleClient.h), for its callers: the debug support, which makes it, and the debug
monitor, which holds it as its debugger (id<OODebuggerInterface>) and sends it the protocol's
messages. Its interface is the one OODebugTCPConsoleClient.h declared before the conversion,
copied exactly (same selectors, same types, same superclass and protocol), so it compiles and
behaves unchanged. Imported as the last line of OODebugTCPConsoleClient.h; do not import it
directly.

-initWithAddress:port: makes the C++ client (which connects) and answers nil when that fails, as
before; otherwise the facade owns the client and is its peer, so oo::ToObjC answers it while it
lives.

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once every caller is C++ and the debugger interface is.


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

#ifndef OODEBUGTCPCONSOLECLIENT_OBJCBRIDGE_H
#define OODEBUGTCPCONSOLECLIENT_OBJCBRIDGE_H

@interface OODebugTCPConsoleClient : OOObject <OODebuggerInterface> {
@private
    oo::Ref<cxx::OODebugTCPConsoleClient> _cxxClient;
}

- (id)initWithAddress:(const std::optional<std::string>&)address // Pass nullopt for localhost
                 port:(uint16_t)port; // Pass 0 for default port

@end

namespace oo {

// The client's facade: its live peer, else a new one (autoreleased); nil for null.
OODebugTCPConsoleClient* ToObjC(cxx::OODebugTCPConsoleClient* client);

// The C++ client behind the facade, borrowed (the facade retains it); null for nil.
cxx::OODebugTCPConsoleClient* ToCxx(OODebugTCPConsoleClient* client);

} // namespace oo

#endif // OODEBUGTCPCONSOLECLIENT_OBJCBRIDGE_H
