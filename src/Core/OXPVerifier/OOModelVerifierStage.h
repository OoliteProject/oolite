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

#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-asx8): the models to check are a vector of
        distinct entries, in the order they were reported. Materials and shaders are plist data
        (oo::PList, null for none). +nameForReverseDependencyForVerifier: is a shared selector (the
        other stages declare it) and, flipped with the others, returns a std::string (bead oo-3rb.274.2).
*/
struct OOModelVerifierEntry {
    std::string name;
    std::string context;
    oo::PList materials;
    oo::PList shaders;

    friend bool operator==(const OOModelVerifierEntry&, const OOModelVerifierEntry&) = default;
};

@interface OOModelVerifierStage : OOTextureHandlingStage {
@private
    std::vector<OOModelVerifierEntry> _modelsToCheck;
}

// Returns name to be used in -dependents by other stages; also registers stage.
+ (std::string)nameForReverseDependencyForVerifier:(OOOXPVerifier*)verifier; // flipped with its family (bead oo-3rb.274.2)

/*	This can be called by other stages *before* the model stage runs.
        returns YES if the model is found, NO if it is not. Caller is responsible
        for complaining if it is not. An empty name is not found, as nil was; entryName may be absent.
*/
- (BOOL)modelNamed:(const std::string&)name
      usedForEntry:(const std::optional<std::string>&)entryName
            inFile:(const std::string&)fileName
     withMaterials:(const oo::PList&)materials
        andShaders:(const oo::PList&)shaders;

@end

@interface OOOXPVerifier (OOModelVerifierStage)

- (OOModelVerifierStage*)modelVerifierStage;

@end

#endif
