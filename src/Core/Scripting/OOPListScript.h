/*

OOPListScript.h

Property list-based script.

I started off reimplementing plist scripting here, in order to remove one of
PlayerEntity's many overloaded functions. The scale of the task was such that
I've stepped back, and this simply wraps the old plist scripting in
PlayerEntity.

C++20 since bead oo-q9q4 (proposed ADR-0056, the OOColor house style). Its superclass, OOScript,
is still Objective-C, so the class is cxx::OOPListScript holding only its own ivars and methods,
and OOPListScript+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OOPListScript : OOScript that makes and owns it (ADR-0056 amendment oo-o89). The bridge's
deletion bead waits for OOScript's conversion.


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
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#include <optional>
#include <string>
#include <vector>

@class OOScript, Entity;

namespace cxx {

class OOPListScript : public oo::RefCounted {
public:
    // The old -initWithName:scriptArray:metadata: after [super init]. Made only by the facade
    // (amendment oo-o89 item 2), until OOScript is C++.
    OOPListScript(const std::string& name, const oo::PList& script, const oo::PList* metadata);

    // The scripts of a legacy script file, each an Objective-C OOPListScript; nullopt when the
    // file is not a dictionary.
    static std::optional<std::vector<oo::ObjCRef<::OOScript*>>> scriptsInPListFile(const std::string& filePath);

    // OOScript overrides, forwarded by the facade.
    std::optional<std::string> name();
    std::optional<std::string> scriptDescription();
    std::optional<std::string> version();
    bool requiresTickle();
    void runWithTarget(::Entity* target);

private:
    static std::vector<oo::ObjCRef<::OOScript*>> scriptsFromDictionaryOfScripts(const oo::PList& dictionary, const std::string& filePath);
    static std::vector<oo::ObjCRef<::OOScript*>> loadCachedScripts(const oo::PList& cachedScripts);

    oo::PList _script; // the sanitized script actions (an array)
    oo::PList _metadata; // a dictionary: name, and the file's !metadata! if it had one
};

} // namespace cxx

// Transitional: the Objective-C OOPListScript, for callers not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "OOPListScript+ObjCBridge.h"

#endif // OOPLISTSCRIPT_H
