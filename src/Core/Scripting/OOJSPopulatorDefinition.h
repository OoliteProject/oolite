/*

OOJSPopulatorDefinition.h (QuickJS-ng)

An oo::RefCounted: OOJSSystem makes it with oo::makeRef and Universe keeps it
as a PList::Object node (OOJSPopulatorDefinitionToPList /
OOJSPopulatorDefinitionIn below).


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

#include "OOFoundation.h"
#include "OOMaths.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class OOJSScript;  // included by the .cpp, so that a test can stand in for it

/*	The definition owns references to its callback and callbackThis, which
   are released on destruction and when the JavaScript engine is reset.
*/
class OOJSPopulatorDefinition : public oo::RefCounted {
 public:
  OOJSPopulatorDefinition();
  ~OOJSPopulatorDefinition() override;

  // Returned values are owned by the caller.
  JSValue callback();
  void setCallback(JSValueConst callback);
  JSValue callbackThis();
  void setCallbackThis(JSValueConst callbackthis);

  void runPopulatorCallback(HPVector location);

 private:
  void deleteJSPointers();

  JSValue _callback = JS_UNDEFINED;         // Owned.
  JSValue _callbackThis = JS_UNDEFINED;     // Owned.
  std::weak_ptr<OOJSScript> _owningScript;  // a weak reference
};

// A PList::Object node holding the definition (strongly), as the settings'
// callbackObj.
oo::PList OOJSPopulatorDefinitionToPList(
    std::shared_ptr<OOJSPopulatorDefinition> definition);
// The definition inside such a node; nullptr for any other node.
OOJSPopulatorDefinition* OOJSPopulatorDefinitionIn(const oo::PList& plist);
