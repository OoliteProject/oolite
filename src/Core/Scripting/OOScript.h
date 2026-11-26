/*

OOScript.h

Abstract base class for scripts.
Currently, Oolite supports two types of script: the original property list
scripts and JavaScript scripts. OOS, a format that translated into plist
scripts, was supported until 1.69.1, but never used. OOScript unifies the
interfaces to the script types and abstracts loading. Additionally, it falls
back to a more "primitive" script if loading of one type fails; specifically,
the order of precedence is:
        script.js		(JavaScript)
//	script.oos		(OOS)
        script.plist	(property list)

C++20 since bead oo-604l (proposed ADR-0056, Amendment 1 of bead oo-cwz: a hierarchy root, as
amendment oo-6bux's OOJoystickManager). The script is cxx::OOScript. Its subclasses are still
Objective-C (OOJSScript) or a facade that subclasses the Objective-C root (OOPListScript, amendment
oo-o89), as are the callers, so the Objective-C OOScript in OOScript+ObjCBridge.h (imported at the
end of this header) is both their facade and the subclasses' superclass. The methods a subclass
overrides (name, scriptDescription, version, requiresTickle, runWithTarget, and the description's
components) are virtual; an Objective-C subclass's C++ part is an adapter whose overrides message
it. The class methods that load scripts are static members; they still make the subclasses'
Objective-C objects, which they answer as the root's facade.

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

#ifndef OOSCRIPT_H
#define OOSCRIPT_H

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

class OOScript : public oo::RefCounted {
public:
    /*	Looks for path/world-scripts.plist, path/script.js, then path/script.plist.
            May return zero or more scripts; nullopt (was nil) when none could be loaded.
    */
    static std::optional<std::vector<oo::ObjCRef<::OOScript*>>> worldScriptsAtPath(const std::string& path);

    //	Load named scripts from Scripts folders. nullopt where these returned nil.
    static std::optional<std::vector<oo::ObjCRef<::OOScript*>>> scriptsFromFileNamed(const std::string& fileName);
    static std::vector<oo::ObjCRef<::OOScript*>> scriptsFromList(const std::vector<std::string>& fileNames);

    static std::optional<std::vector<oo::ObjCRef<::OOScript*>>> scriptsFromFileAtPath(const std::string& filePath);

    //	Load a single JavaScript script (an OOJSScript, or nil). The properties may hold live objects (oo::PList Object nodes).
    static id jsScriptFromFileNamed(const std::string& fileName, const oo::PList& properties);
    //  As above, but load from the "AIs" directory
    static id jsAIScriptFromFileNamed(const std::string& fileName, const oo::PList& properties);

    // The subclass responsibilities (Amendment 1 item 2). The root's own answer none, logging an error.
    virtual std::optional<std::string> descriptionComponents();
    virtual std::optional<std::string> name(); // nullopt: none (bead oo-3rb.289.6)
    virtual std::optional<std::string> scriptDescription(); // nullopt: none
    virtual std::optional<std::string> version(); // nullopt: none (bead oo-3rb.291.1)
    virtual bool requiresTickle();
    virtual void runWithTarget(::Entity* target);

    std::optional<std::string> displayName(); // flipped with its family (bead oo-3rb.267): "name version" if version is defined, otherwise just "name".
};

} // namespace cxx

// Transitional: the Objective-C OOScript, for callers and subclasses not yet converted. Deleted,
// with namespace cxx above, by the bridge's deletion bead.
#import "OOScript+ObjCBridge.h"

#endif // OOSCRIPT_H
