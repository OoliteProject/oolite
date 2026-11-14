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
#include "oofnd/objc/OOObjCRef.h"

@class OOPListSchemaVerifier;
class OOAIStateMachineVerifierStage; // C++ since bead oo-94qk
struct OOPListSchemaVerifierError;

/*	Foundation sweep (proposed ADR-0043, bead oo-v1zb): shipdata.plist and the entry being checked
        are oo::PList; the key and role sets are sorted std::vectors of strings.

        C++20 since bead oo-1v2w (proposed ADR-0056 Amendment 1, amendments oo-up4b and oo-rmd7): a
        subclass of cxx::OOTextureHandlingStage. It is global and has no facade: nothing outside this
        file names it, and the Objective-C verifier makes it from its name (kCxxStages in
        OOOXPVerifier.mm) and holds it as an OOOXPVerifierStage (oo::ToObjC). It is the schema
        verifier's delegate, an Objective-C role, through a helper object that stays Objective-C until
        OOPListSchemaVerifier is C++: OOCheckShipDataPListVerifierStage+ObjCBridge.h, imported at the
        end of this header.
*/
class OOCheckShipDataPListVerifierStage : public cxx::OOTextureHandlingStage {
public:
    std::optional<std::string> name() override;
    std::optional<std::vector<std::string>> dependents() override;
    bool shouldRun() override;
    void run() override;

    /*	The schema verifier's delegate methods (OOPListSchemaVerifierDelegate), which the helper
            OOCheckShipDataPListVerifierStageSchemaDelegate forwards here. Both selectors start with
            verifier:, which would hide verifier(), so each name adds its distinguishing keyword.
    */
    bool verifierTestProperty(OOPListSchemaVerifier* verifier,
        const oo::PList& rootPList,
        const std::string& name,
        const oo::PList& subPList,
        const oo::PList& keyPath,
        const oo::PList& typeKey,
        std::optional<OOPListSchemaVerifierError>* outError);
    bool verifierFailedForProperty(OOPListSchemaVerifier* verifier,
        const oo::PList& rootPList,
        const std::string& name,
        const oo::PList& subPList,
        const OOPListSchemaVerifierError& error,
        const oo::PList& localSchema);

private:
    void verifyShipInfo(const oo::PList& info, const std::string& name);

    void reportMessage(const std::string& message); // formatted by the caller, oo::str::formatRuntime (was -message:, renamed so AI's -message: could flip; bead oo-3rb.276; bead oo-qps.24)
    void verboseMessage(const std::string& message);

    void getRoles();
    void checkKeys();
    void checkSchema();
    void checkModel();

    std::vector<std::string> rolesFromString(const std::string& string);

    oo::PList _shipdataPList = { };
    std::vector<std::string> _ooliteShipNames = { };
    std::vector<std::string> _basicKeys = { },
                             _stationKeys = { },
                             _playerKeys = { },
                             _allKeys = { };
    OOPListSchemaVerifier* _schemaVerifier = { }; // Not retained (autoreleased in run()).
    oo::ObjCRef<id> _schemaDelegate = { }; // The helper that is the schema verifier's delegate.
    OOAIStateMachineVerifierStage* _aiVerifierStage = { }; // Not retained (the verifier holds it).

    // Info about ship currently being checked.
    std::string _name = { };
    oo::PList _info = { };
    std::vector<std::string> _roles = { };
    bool _isStation = { },
         _isPlayer = { },
         _isTemplate = { },
         _havePrintedMessage = { };
};

// Transitional: the schema verifier's delegate, an Objective-C helper. Deleted by the bridge's
// deletion bead once OOPListSchemaVerifier is C++.
#import "OOCheckShipDataPListVerifierStage+ObjCBridge.h"

#endif
