/*

OOModelVerifierStage.h

OOOXPVerifierStage which keeps track of models that are used and ensures they
are loadable.


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

#pragma once

#include "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-asx8): the models to check are a vector of
        distinct entries, in the order they were reported. Materials and shaders are plist data
        (oo::PList, null for none). nameForReverseDependencyForVerifier() is a shared name (the
        other stages declare it) and, flipped with the others, returns a std::string (bead oo-3rb.274.2).

        C++20 since bead oo-5zby (proposed ADR-0056 Amendment 1, amendments oo-up4b and oo-94qk): a
        subclass of OOTextureHandlingStage. It is global and has no facade: its one caller, the
        ship data stage, calls these members, and the verifier holds it (as its OOOXPVerifierStage
        facade until bead oo-9ht.4). The ship data stage finds it by name through the verifier's
        stage lookup (the verifier's category that answered it went with bead oo-9ht.56).
*/
struct OOModelVerifierEntry {
    std::string name;
    std::string context;
    oo::PList materials;
    oo::PList shaders;

    friend bool operator==(const OOModelVerifierEntry&, const OOModelVerifierEntry&) = default;
};

class OOModelVerifierStage : public OOTextureHandlingStage {
public:
    // The stage's name, as name() returns it (the ship data stage looks the stage up by it).
    static const char* const kName;

    // Returns name to be used in dependents() by other stages; also registers stage.
    static std::string nameForReverseDependencyForVerifier(OOOXPVerifier* verifier); // flipped with its family (bead oo-3rb.274.2)

    std::optional<std::string> name() override;
    bool shouldRun() override;
    void run() override;

    /*	This can be called by other stages *before* the model stage runs.
            returns true if the model is found, false if it is not. Caller is responsible
            for complaining if it is not. An empty name is not found, as nil was; entryName may be absent.
    */
    bool modelNamed(const std::string& name,
        const std::optional<std::string>& entryName,
        const std::string& fileName,
        const oo::PList& materials,
        const oo::PList& shaders);

private:
    void checkModel(const std::string& name,
        const std::string& context,
        const oo::PList& materials,
        const oo::PList& shaders);

    std::vector<OOModelVerifierEntry> _modelsToCheck = { };
};

#endif
