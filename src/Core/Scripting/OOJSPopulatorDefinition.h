/*

OOJSPopulatorDefinition.h

C++20 since bead oo-1h0h (proposed ADR-0056, the OOColor house style). An oo::RefCounted, global
namespace since bead oo-9ht.60: OOJSSystem makes it with oo::makeRef and Universe keeps it as a
PList::Object node (OOJSPopulatorDefinitionToPList / OOJSPopulatorDefinitionIn below).


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

#ifndef OOJSPOPULATORDEFINITION_H
#define OOJSPOPULATORDEFINITION_H

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "OOMaths.h"
#include "oofnd/Ref.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class OOJSScript;	// imported by the .mm, so that a test can stand in for it (ADR-0056 amendment oo-fg7i item 5)


class OOJSPopulatorDefinition : public oo::RefCounted
{
public:
	OOJSPopulatorDefinition();
	~OOJSPopulatorDefinition() override;

	ooscript::Value callback();
	void setCallback(ooscript::Value callback);
	ooscript::Object callbackThis();
	void setCallbackThis(ooscript::Object callbackthis);

	void runPopulatorCallback(HPVector location);

private:
	void deleteJSPointers();

	ooscript::Value				_callback = {};
	ooscript::Object _callbackThis = {};
	oo::WeakRef<OOJSScript>		_owningScript;	// a weak reference (was the facade's weak reference proxy)
};


// A PList::Object node holding the definition (strongly), as the settings' callbackObj.
oo::PList OOJSPopulatorDefinitionToPList(oo::Ref<OOJSPopulatorDefinition> definition);
// The definition inside such a node; nullptr for any other node.
OOJSPopulatorDefinition *OOJSPopulatorDefinitionIn(const oo::PList &plist);

#endif	// OOJSPOPULATORDEFINITION_H
