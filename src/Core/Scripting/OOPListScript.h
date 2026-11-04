/*

OOPListScript.h

Property list-based script.

I started off reimplementing plist scripting here, in order to remove one of
PlayerEntity's many overloaded functions. The scale of the task was such that
I've stepped back, and this simply wraps the old plist scripting in
PlayerEntity.

The class is global and derives from OOScript, overriding its members. A plist
script is held as oo::Ref<OOScript>.


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

#include <optional>
#include <string>
#include <vector>

#include "OOFoundation.h"
#include "OOScript.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

class Entity;

class OOPListScript : public OOScript {
 public:
  // The old -initWithName:scriptArray:metadata: after [super init].
  OOPListScript(const std::string& name, const oo::PList& script,
                const oo::PList* metadata);

  // The scripts of a legacy script file, each a new OOPListScript; nullopt when
  // the file is not a dictionary.
  static std::optional<std::vector<oo::Ref<OOScript>>> scriptsInPListFile(
      const std::string& filePath);

  // OOScript overrides.
  std::optional<std::string> name() override;
  std::optional<std::string> scriptDescription() override;
  std::optional<std::string> version() override;
  bool requiresTickle() override;
  void runWithTarget(Entity* target) override;

 private:
  static std::vector<oo::Ref<OOScript>> scriptsFromDictionaryOfScripts(
      const oo::PList& dictionary, const std::string& filePath);
  static std::vector<oo::Ref<OOScript>> loadCachedScripts(
      const oo::PList& cachedScripts);

  oo::PList _script;  // the sanitized script actions (an array)
  oo::PList
      _metadata;  // a dictionary: name, and the file's !metadata! if it had one
};
