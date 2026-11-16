/*

OOPListScript.h

Property list-based script.

I started off reimplementing plist scripting here, in order to remove one of
PlayerEntity's many overloaded functions. The scale of the task was such that
I've stepped back, and this simply wraps the old plist scripting in
PlayerEntity.

C++20 since bead oo-q9q4 (proposed ADR-0056, the OOColor house style). Bead oo-9ht.57 deleted its
Objective-C facade once OOScript was C++ (oo-604l; ADR-0056 amendments oo-o89 item 3 and "deleting
a facade"): the class is global and derives from cxx::OOScript, overriding its members, and
Objective-C sees a plist script as the root's facade, an OOScript.


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

#ifndef OOPLISTSCRIPT_H
#define OOPLISTSCRIPT_H

#import "OOFoundation.h"
#import "OOScript.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#include <optional>
#include <string>
#include <vector>

@class OOScript, Entity;

class OOPListScript : public cxx::OOScript {
public:
    // The old -initWithName:scriptArray:metadata: after [super init].
    OOPListScript(const std::string& name, const oo::PList& script, const oo::PList* metadata);

    // The scripts of a legacy script file, each the root's facade of a new OOPListScript, as the
    // Objective-C scripts were; nullopt when the file is not a dictionary.
    static std::optional<std::vector<oo::ObjCRef<::OOScript*>>> scriptsInPListFile(const std::string& filePath);

    // OOScript overrides.
    std::optional<std::string> name() override;
    std::optional<std::string> scriptDescription() override;
    std::optional<std::string> version() override;
    bool requiresTickle() override;
    void runWithTarget(::Entity* target) override;

private:
    static std::vector<oo::ObjCRef<::OOScript*>> scriptsFromDictionaryOfScripts(const oo::PList& dictionary, const std::string& filePath);
    static std::vector<oo::ObjCRef<::OOScript*>> loadCachedScripts(const oo::PList& cachedScripts);

    oo::PList _script; // the sanitized script actions (an array)
    oo::PList _metadata; // a dictionary: name, and the file's !metadata! if it had one
};

#endif // OOPLISTSCRIPT_H
