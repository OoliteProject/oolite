/*

OOShipRegistry+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-3bgz): the Objective-C OOShipRegistry, a facade over the
C++ cxx::OOShipRegistry (OOShipRegistry.h), for the code that is not converted yet: the callers
that message [OOShipRegistry sharedRegistry] (Universe, the player and ship entities, the
scripting bindings, the shader synthesizer). (The OODataLoader category, which was a category of
this facade while slices 2 and 3 of docs/phases/3-slices/OOShipRegistry.md were Objective-C, is
C++ members since beads oo-r9gn and oo-ugw3.) Its interface is the one OOShipRegistry.h declared before the
conversion, copied exactly (same selectors, same types), less the ivars, which are the C++
class's members; each method forwards to its C++ member. Imported as the last line of
OOShipRegistry.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOShipRegistry * (this facade)  nothing: messages as before
        converted (C++)                        cxx::OOShipRegistry::sharedRegistry(), borrowed
          handing the registry to Objective-C                                  oo::ToObjC(registry)
          taking it from Objective-C                                           oo::ToCxx(objcRegistry)

+sharedRegistry answers one facade for the life of the registry, retained once and cached
(amendment oo-r7m0 item 5), so [OOShipRegistry sharedRegistry] == [OOShipRegistry sharedRegistry].
After +reload it answers the new registry's facade; the old one stays alive, as the old registry
did (its -release did nothing). Never add to this file; converted code does not message the
facade. Deleted by its deletion bead once no file outside OOShipRegistry.* names the Objective-C
class.

Copyright (C) 2008-2013 Jens Ayton and contributors

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

#ifndef OOSHIPREGISTRY_OBJCBRIDGE_H
#define OOSHIPREGISTRY_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOShipRegistry : OOObject {
@private
    oo::Ref<cxx::OOShipRegistry> _cxxRegistry;
}

+ (OOShipRegistry*)sharedRegistry;

+ (void)reload;

// A null PList where there is no such entry (was nil).
- (oo::PList)cxx_shipInfoForKey:(const std::string&)key;
- (void)cxx_setShipInfoForKey:(const std::string&)key with:(const oo::PList&)newShipData;
- (oo::PList)cxx_effectInfoForKey:(const std::string&)key;
- (oo::PList)cxx_shipyardInfoForKey:(const std::string&)key;
- (OOProbabilitySet*)cxx_probabilitySetForRole:(const std::string&)role;

- (oo::PList)cxx_demoShipKeys; // arrays (one per class) of demo ship dictionaries
- (std::vector<std::string>)cxx_playerShipKeys;

@end

@interface OOShipRegistry (OOConveniences)

- (std::vector<std::string>)cxx_shipKeys; // in key order
- (std::vector<std::string>)cxx_shipRoles; // in role order
- (std::vector<std::string>)cxx_shipKeysWithRole:(const std::string&)role;
- (std::optional<std::string>)cxx_randomShipKeyForRole:(const std::string&)role; // nullopt: no ship has the role

@end

namespace oo {

// The registry's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOShipRegistry* ToObjC(cxx::OOShipRegistry* registry);
// The C++ registry behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOShipRegistry* ToCxx(OOShipRegistry* registry);

} // namespace oo

#endif // OOSHIPREGISTRY_OBJCBRIDGE_H
