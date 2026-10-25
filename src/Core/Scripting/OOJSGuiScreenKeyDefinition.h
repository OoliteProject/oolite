/*

OOJSGuiScreenKeyDefinition.h

C++20 since bead oo-xg7g (proposed ADR-0056, the OOColor house style; amendment oo-o89). Bead
oo-9ht.62 deleted its Objective-C facade (a weak-referenceable object) and moved it to the global namespace:
the JS global object makes it and the player keeps it as oo::Ref.


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

#ifndef OOJSGUISCREENKEYDEFINITION_H
#define OOJSGUISCREENKEYDEFINITION_H

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"

#include <optional>
#include <string>
#include "oofnd/Ref.hpp"
#include "oofnd/Ref.hpp"

class OOJSScript;	// imported by the .mm, so that a test can stand in for it (ADR-0056 amendment oo-fg7i item 5)


class OOJSGuiScreenKeyDefinition : public oo::RefCounted
{
public:
	// The old -init after [super init] (oo::makeRef).
	OOJSGuiScreenKeyDefinition();
	~OOJSGuiScreenKeyDefinition() override;

	std::optional<std::string> name();	// nullopt until set (bead oo-3rb.289.7)
	void setName(const std::optional<std::string> &name);
	oo::PList registerKeys();
	void setRegisterKeys(const oo::PList &registerKeys);
	ooscript::Value callback();
	void setCallback(ooscript::Value callback);
	ooscript::Object callbackThis();
	void setCallbackThis(ooscript::Object callbackthis);

	void runCallback(const std::string &key);

	OOComparisonResult interfaceCompare(OOJSGuiScreenKeyDefinition *other);

private:
	void deleteJSPointers();

	ooscript::Value				_callback = {};
	ooscript::Object _callbackThis = {};
	oo::WeakRef<OOJSScript>		_owningScript;	// a weak reference (was the facade's weak reference proxy)

	std::optional<std::string>	_name;			// nullopt until set (was nil)
	oo::PList			_registerKeys;	// key name -> key definitions; null until set (was nil)
};

#endif	// OOJSGUISCREENKEYDEFINITION_H
