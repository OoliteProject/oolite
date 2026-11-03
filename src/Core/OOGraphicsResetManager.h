/*

OOGraphicsResetManager.h

Tracks objects with state that needs to be reset when the graphics context is
modified (for instance, when switching between windowed and full-screen mode
in SDL builds). This means re-uploading all textures, and also resetting any
display lists relying on old texture names. All objects which have display
lists must therefore register with the OOGraphicsResetManager on init, and
unregister on dealloc.

C++20 since bead oo-jpd8 (proposed ADR-0056). The class is cxx::OOGraphicsResetManager while
OOGraphicsResetManager+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OOGraphicsResetManager its unconverted callers message, and the OOGraphicsResetClient protocol its
clients adopt; the bridge's deletion bead moves the class out of namespace cxx.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#ifndef OOGRAPHICSRESETMANAGER_H
#define OOGRAPHICSRESETMANAGER_H

#import "OOFoundation.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

namespace cxx {

// A converted client (amendment oo-jpd8 item 3, added by bead oo-4jjl for OOSkyDrawable): the
// protocol OOGraphicsResetClient's method as a pure virtual. It registers with registerCxxClient().
class OOGraphicsResetClient {
public:
    virtual ~OOGraphicsResetClient() = default;
    virtual void resetGraphicsState() = 0;
};

// A client is an Objective-C object adopting OOGraphicsResetClient (OOGraphicsResetManager+ObjCBridge.h),
// which is sent -resetGraphicsState.
class OOGraphicsResetManager : public oo::RefCounted {
public:
    // The shared manager, made on first use; borrowed, never released (proposed ADR-0056
    // amendment oo-r7m0).
    static OOGraphicsResetManager* sharedManager();

    ~OOGraphicsResetManager();

    // Clients are not retained.
    void registerClient(id client);
    void unregisterClient(id client);

    // The same for a C++ client (not retained either; null is never registered).
    void registerCxxClient(OOGraphicsResetClient* client);
    void unregisterCxxClient(OOGraphicsResetClient* client);

    // Forwarded to all clients, after resetting textures.
    void resetGraphicsState();

private:
    std::unordered_set<id> clients = { }; // not retained; was a Foundation mutable set of boxed values (bead oo-3rb.10)
    std::unordered_set<OOGraphicsResetClient*> cxxClients = { }; // not retained
};

} // namespace cxx

// Transitional: the Objective-C OOGraphicsResetManager and the OOGraphicsResetClient protocol, for
// code not yet converted. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOGraphicsResetManager+ObjCBridge.h"

#endif // OOGRAPHICSRESETMANAGER_H
