/*

OOGraphicsResetManager.mm


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

#include "OOGraphicsResetManager.h"
#include "OOOpenGLExtensionManager.h"
#include "OOTexture.h"
#include "oofnd/Log.hpp"
#include "oofnd/objc/OOException.h"

namespace {

OOGraphicsResetManager* sSingleton = nullptr; // +1, never released (the retained singleton)

} // namespace

OOGraphicsResetManager::~OOGraphicsResetManager()
{
    if (sSingleton == this)
        sSingleton = nullptr;
}

OOGraphicsResetManager* OOGraphicsResetManager::sharedManager()
{
    if (sSingleton == nullptr)
        sSingleton = oo::makeRef<OOGraphicsResetManager>().leakRef();
    return sSingleton;
}

void OOGraphicsResetManager::registerCxxClient(OOGraphicsResetClient* client)
{
    if (client != nullptr) {
        cxxClients.insert(client);
    }
}

void OOGraphicsResetManager::unregisterCxxClient(OOGraphicsResetClient* client)
{
    cxxClients.erase(client);
}

void OOGraphicsResetManager::resetGraphicsState()
{
    OOGL(glFinish());

    OO_LOG("rendering.reset.start", "{}", "Resetting graphics state.");
    oo::log::indentIf("rendering.reset.start");

    OOOpenGLExtensionManager::sharedManager()->reset();
    OOTexture::rebindAllTextures();

    // A copy, so a client may register or unregister during the reset (one unregistered by an
    // earlier client is skipped). Unordered, as the Foundation set was: its order was pointer-hash order,
    // so it already varied from run to run. (The Objective-C clients, told first, went with the
    // protocol: bead oo-9ht.23.)
    const std::vector<OOGraphicsResetClient*> cxxSnapshot(cxxClients.begin(), cxxClients.end());
    for (OOGraphicsResetClient* client : cxxSnapshot) {
        if (cxxClients.find(client) == cxxClients.end())
            continue;
        try {
            client->resetGraphicsState();
        } catch (...) {
            const auto exception = oo::CurrentOOException();
            if (!exception)
                throw; // not an OOException: it goes on up, as before
            OO_LOG(cxx_kOOLogException, "***** EXCEPTION -- {} : {} -- ignored during graphics reset.", exception->name(), exception->reason());
        }
    }

    oo::log::outdentIf("rendering.reset.start");
    OO_LOG("rendering.reset.end", "{}", "End of graphics state reset.");
}

// The singleton category (+allocWithZone:, and -retain/-release/-autorelease doing nothing) is
// not translated: the one instance is made only by sharedManager() and never released (proposed
// ADR-0056 amendment oo-r7m0).
