/*

OOCheckShipDataPListVerifierStage.h

OOOXPVerifierStage which checks shipdata.plist.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

@class OOPListSchemaVerifier;
class OOAIStateMachineVerifierStage; // C++ since bead oo-94qk

/*	Foundation sweep (proposed ADR-0043, bead oo-v1zb): shipdata.plist and the entry being checked
        are oo::PList; the key and role sets are sorted std::vectors of strings.
*/
@interface OOCheckShipDataPListVerifierStage : OOTextureHandlingStage {
@private
    oo::PList _shipdataPList;
    std::vector<std::string> _ooliteShipNames;
    std::vector<std::string> _basicKeys,
        _stationKeys,
        _playerKeys,
        _allKeys;
    OOPListSchemaVerifier* _schemaVerifier;
    OOAIStateMachineVerifierStage* _aiVerifierStage; // Not retained (the verifier holds it).

    // Info about ship currently being checked.
    std::string _name;
    oo::PList _info;
    std::vector<std::string> _roles;
    uint32_t _isStation : 1,
        _isPlayer : 1,
        _isTemplate : 1,
        _havePrintedMessage : 1;
}
@end

#endif
