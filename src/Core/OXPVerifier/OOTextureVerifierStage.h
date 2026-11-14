/*

OOTextureVerifierStage.h

OOOXPVerifierStage which keeps track of textures (and images) that are used
and ensures they are loadable.


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

#include "OOFileScannerVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-0iq2): the used texture names are a sorted
        std::vector (a set), checked in byte order of the name. nameForReverseDependencyForVerifier() is a shared name
        (the other stages declare it) and, flipped with the others, returns a std::string (bead oo-3rb.274.2).

        C++20 since bead oo-tuq8 (proposed ADR-0056 Amendment 1, amendment oo-up4b items 2 and 6).
        OOTextureVerifierStage is a leaf of OOFileHandlingVerifierStage; it is global and has no
        facade, because nothing outside this file messages it (the verifier makes it from its name,
        kCxxStages in OOOXPVerifier.mm). OOTextureHandlingStage is an intermediate class that the ship
        data and model stages subclass; its Objective-C facade was deleted by bead oo-9ht.45 once they
        were C++ (ADR-0056 amendment "deleting a facade"), with the verifier's -textureVerifierStage.
*/
class OOTextureVerifierStage : public OOFileHandlingVerifierStage {
public:
    // Returns name to be used in dependents() by other stages.
    static std::string nameForReverseDependencyForVerifier(OOOXPVerifier* verifier); // flipped with its family (bead oo-3rb.274.2)

    std::optional<std::string> name() override;
    bool shouldRun() override;
    void run() override;

    /*	This can be called by other stages *before* the texture stage runs.
            The context specifies where the texture is used; something like
            "fooShip.dat" or "shipdata.plist materials dictionary for ship \"foo\"".
            It should make sense with "Texture \"foo\" referenced in " in front of it.
    */
    void textureNamed(const std::string& name, const std::string& context); // an empty name is ignored, as nil was

private:
    void checkTextureNamed(const std::string& name, const std::string& folder);

    std::vector<std::string> _usedTextures = { }; // sorted, no duplicates
};

// Convenience base class for stages that need to run before OOTextureHandlingStage.
class OOTextureHandlingStage : public OOFileHandlingVerifierStage {
public:
    std::optional<std::vector<std::string>> dependents() override;
};

#endif
