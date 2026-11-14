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

#import "OOFoundation.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#import "oofnd/objc/OOObject.h"

@class Entity;

@interface OOScript : OOObject

/*	Looks for path/world-scripts.plist, path/script.js, then path/script.plist.
        May return zero or more scripts; nullopt (was nil) when none could be loaded.
*/
+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)cxx_worldScriptsAtPath:(const std::string&)path;

//	Load named scripts from Scripts folders. nullopt where these returned nil.
+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsFromFileNamed:(const std::string&)fileName;
+ (std::vector<oo::ObjCRef<OOScript*>>)scriptsFromList:(const std::vector<std::string>&)fileNames;

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsFromFileAtPath:(const std::string&)filePath;

//	Load a single JavaScript script. The properties may hold live objects (oo::PList Object nodes).
+ (id)cxx_jsScriptFromFileNamed:(const std::string&)fileName properties:(const oo::PList&)properties;
//  As above, but load from the "AIs" directory
+ (id)cxx_jsAIScriptFromFileNamed:(const std::string&)fileName properties:(const oo::PList&)properties;

- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.6)
- (std::optional<std::string>)scriptDescription; // nullopt: none
- (std::optional<std::string>)cxx_version; // nullopt: none (bead oo-3rb.291.1)
- (std::optional<std::string>)displayName; // flipped with its family (bead oo-3rb.267): "name version" if version is defined, otherwise just "name".

- (BOOL)requiresTickle;
- (void)runWithTarget:(Entity*)target;

@end
