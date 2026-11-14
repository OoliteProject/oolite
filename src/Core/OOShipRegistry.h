/*

OOShipRegistry.h

Manage the set of installed ships.


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

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOProbabilitySet;

@interface OOShipRegistry : OOObject {
@private
    oo::PList _shipData; // ship key -> ship dictionary (null until loaded)
    oo::PList _effectData; // effect key -> effect dictionary (null until loaded)
    oo::PList _demoShips; // demo ship entries (dictionaries) grouped in arrays by class
    std::vector<std::string> _playerShips; // shipyard keys, in shipyard.plist key order
    std::optional<std::map<std::string, oo::ObjCRef<OOProbabilitySet*>, std::less<>>> _probabilitySets; // role -> ship keys; nullopt: none cached yet
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

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API this header
        declared before its sweep (bead oo-92mj, chunks oo-3rb.114 ff.), forwarding to the cxx_ methods
        above, so unmigrated callers compile unchanged. Callers move to the cxx_ API in their own sweep
        beads; the bridge goes in its own bead.
*/
#import "OOShipRegistry+FoundationBridge.h"
