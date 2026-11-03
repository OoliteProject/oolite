/*

OOGraphicsResetManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-jpd8): the Objective-C OOGraphicsResetManager, a facade
over the C++ cxx::OOGraphicsResetManager (OOGraphicsResetManager.h), for callers that are not
converted yet, and the OOGraphicsResetClient protocol its clients adopt. Both are copied exactly
from OOGraphicsResetManager.h before the conversion, so callers and clients compile and behave
unchanged; each method forwards to its C++ member. Imported as the last line of
OOGraphicsResetManager.h; do not import it directly.

The manager is a singleton: +sharedManager answers one facade for the life of the process
(proposed ADR-0056 amendment oo-r7m0, item 5). A client stays an Objective-C object until a C++
client exists (amendment oo-jpd8). Never add to this file; converted code does not message the
facade. Deleted by its deletion bead once no file outside OOGraphicsResetManager.* names the
Objective-C class or the protocol.


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

#ifndef OOGRAPHICSRESETMANAGER_OBJCBRIDGE_H
#define OOGRAPHICSRESETMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@protocol OOGraphicsResetClient

- (void)resetGraphicsState;

@end

@interface OOGraphicsResetManager : OOObject {
@private
    oo::Ref<cxx::OOGraphicsResetManager> _cxxManager;
}

+ (OOGraphicsResetManager*)sharedManager;

// Clients are not retained.
- (void)registerClient:(id<OOGraphicsResetClient>)client;
- (void)unregisterClient:(id<OOGraphicsResetClient>)client;

// Forwarded to all clients, after resetting textures.
- (void)resetGraphicsState;

@end

namespace oo {

// The manager's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOGraphicsResetManager* ToObjC(cxx::OOGraphicsResetManager* manager);

// The C++ manager behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOGraphicsResetManager* ToCxx(OOGraphicsResetManager* manager);

} // namespace oo

#endif // OOGRAPHICSRESETMANAGER_OBJCBRIDGE_H
