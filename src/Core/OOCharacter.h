/*

OOCharacter.h

Represents an NPC person (as opposed to an NPC ship).

C++20 since bead oo-8kx7 (Phase 3, proposed ADR-0056). The class is cxx::OOCharacter while
OOCharacter+ObjCBridge.h, imported at the end of this header, keeps the Objective-C OOCharacter its
unconverted callers message (ships' crews, JS); the bridge's deletion bead moves it out of
namespace cxx.

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

#ifndef OOCHARACTER_H
#define OOCHARACTER_H

#import "OOJSPropID.h"
#import "OOTypes.h"
#import "legacy_random.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOJSScript;

namespace cxx {

class OOCharacter : public oo::RefCounted {
public:
    OOCharacter() = default; // [[OOCharacter alloc] init]: every field zero
    OOCharacter(const std::string& role, OOSystemID s);

    static oo::Ref<OOCharacter> characterWithRole(const std::string& c_role, OOSystemID s);
    static oo::Ref<OOCharacter> randomCharacterWithRole(const std::string& c_role, OOSystemID s);
    static oo::Ref<OOCharacter> characterWithDictionary(const oo::PList& c_dict); // a dictionary (JS crew definitions may hold any object, as an Object node)

    std::optional<std::string> planetOfOrigin();
    OOSystemID planetIDOfOrigin();
    std::optional<std::string> species();

    void basicSetUp();
    bool castInRole(const std::string& role);

    std::optional<std::string> name(); // nullopt: none (bead oo-3rb.289.9)
    void setName(const std::optional<std::string>& value);

    std::optional<std::string> shortDescription();
    void setShortDescription(const std::optional<std::string>& value); // nullopt: none (bead oo-qps.51)

    int legalStatus();
    void setLegalStatus(int value);

    OOCreditsQuantity insuranceCredits();
    void setInsuranceCredits(OOCreditsQuantity value);

    oo::PList legacyScript(); // an array of script actions; null: none
    void setLegacyScript(const oo::PList& scriptActions);
    OOJSScript* script();
    void setCharacterScript(const std::string& scriptName);
    void doScriptEvent(OOJSPropID message);

    oo::PList infoForScripting(); // a dictionary

    // What "%@" prints between the braces of <OOCharacter 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;
    // The JavaScript class of the character's Objective-C object (-oo_jsClassName).
    std::optional<std::string> oo_jsClassName();

private:
    OOCharacter(Random_Seed characterSeed, OOSystemID systemSeed); // -initWithGenSeed:andOriginalSystem:
    void setCharacterFromDictionary(const oo::PList& dict);

    void setOriginSystem(OOSystemID value);
    Random_Seed genSeed();
    void setGenSeed(Random_Seed value);

    std::optional<std::string> _name;
    std::optional<std::string> _shortDescription;
    OOSystemID _originSystem = { };
    Random_Seed _genSeed = { };
    int _legalStatus = { };
    OOCreditsQuantity _insuranceCredits = { };
    oo::PList _scriptActions; // an array; null: none
    oo::ObjCRef<OOJSScript*> _script;
};

} // namespace cxx

// Transitional: the Objective-C OOCharacter, for callers not yet converted. Deleted, with namespace
// cxx above, by the bridge's deletion bead.
#import "OOCharacter+ObjCBridge.h"

#endif // OOCHARACTER_H
