/*

OOGraphicsResetManager.h

Tracks objects with state that needs to be reset when the graphics context is
modified (for instance, when switching between windowed and full-screen mode
in SDL builds). This means re-uploading all textures, and also resetting any
display lists relying on old texture names. All objects which have display
lists must therefore register with the OOGraphicsResetManager on init, and
unregister on dealloc.

C++20 since bead oo-jpd8 (proposed ADR-0056). Its Objective-C facade and the OOGraphicsResetClient
protocol were deleted by bead oo-9ht.23 (ADR-0056 amendment "deleting a facade"): the class is
global, and every client is a C++ OOGraphicsResetClient.


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

#include "OOFoundation.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

// A client (amendment oo-jpd8 item 3, added by bead oo-4jjl for OOSkyDrawable): the deleted
// protocol OOGraphicsResetClient's method as a pure virtual. It registers with registerCxxClient().
class OOGraphicsResetClient {
public:
    virtual ~OOGraphicsResetClient() = default;
    virtual void resetGraphicsState() = 0;
};

class OOGraphicsResetManager : public oo::RefCounted {
public:
    // The shared manager, made on first use; borrowed, never released (proposed ADR-0056
    // amendment oo-r7m0).
    static OOGraphicsResetManager* sharedManager();

    ~OOGraphicsResetManager();

    // Clients are not retained; null is never registered (bead oo-9ht.23 deleted the overloads
    // that took an Objective-C client).
    void registerCxxClient(OOGraphicsResetClient* client);
    void unregisterCxxClient(OOGraphicsResetClient* client);

    // Forwarded to all clients, after resetting textures.
    void resetGraphicsState();

private:
    std::unordered_set<OOGraphicsResetClient*> cxxClients = { }; // not retained
};

#endif // OOGRAPHICSRESETMANAGER_H
