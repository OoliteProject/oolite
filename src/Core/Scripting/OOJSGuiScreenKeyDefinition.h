/*

OOJSGuiScreenKeyDefinition.h (QuickJS-ng)

The JS global object makes it and the player keeps it as oo::Ref.


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

#include <quickjs.h>

#include <optional>
#include <string>

#include "OOFoundation.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

class OOJSScript;  // imported by the .mm, so that a test can stand in for it

/*	The definition owns references to its callback and callbackThis, which
   are released on destruction and when the JavaScript engine is reset.
*/
class OOJSGuiScreenKeyDefinition : public oo::RefCounted {
 public:
  // The old -init after [super init] (oo::makeRef).
  OOJSGuiScreenKeyDefinition();
  ~OOJSGuiScreenKeyDefinition() override;

  std::optional<std::string> name();  // nullopt until set
  void setName(const std::optional<std::string>& name);
  oo::PList registerKeys();
  void setRegisterKeys(const oo::PList& registerKeys);
  // Returned values are owned by the caller.
  JSValue callback();
  void setCallback(JSValueConst callback);
  JSValue callbackThis();
  void setCallbackThis(JSValueConst callbackthis);

  void runCallback(const std::string& key);

  OOComparisonResult interfaceCompare(OOJSGuiScreenKeyDefinition* other);

 private:
  void deleteJSPointers();

  JSValue _callback = JS_UNDEFINED;       // Owned.
  JSValue _callbackThis = JS_UNDEFINED;   // Owned.
  oo::WeakRef<OOJSScript> _owningScript;  // a weak reference

  std::optional<std::string> _name;  // nullopt until set (was nil)
  oo::PList
      _registerKeys;  // key name -> key definitions; null until set (was nil)
};
