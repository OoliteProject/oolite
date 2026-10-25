/*

OOJSInterfaceDefinition.h

C++20 since bead oo-8fpc (proposed ADR-0056, the OOColor house style; amendment oo-o89). Bead
oo-9ht.61 deleted its Objective-C facade (a weak-referenceable object) and moved it to the global namespace:
the station keeps its definitions as oo::Ref, and the player reads them as C++.


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

#ifndef OOJSINTERFACEDEFINITION_H
#define OOJSINTERFACEDEFINITION_H

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"

#include <optional>
#include <string>
#include "oofnd/Ref.hpp"
#include "oofnd/Ref.hpp"

class OOJSScript;	// imported by the .mm, so that a test can stand in for it (ADR-0056 amendment oo-fg7i item 5)


class OOJSInterfaceDefinition : public oo::RefCounted
{
public:
	// The old -init after [super init] (oo::makeRef).
	OOJSInterfaceDefinition();
	~OOJSInterfaceDefinition() override;

	std::optional<std::string> title();	// nullopt: none (bead oo-3rb.290)
	void setTitle(const std::optional<std::string> &title);	// bead oo-3rb.290
	std::optional<std::string> category();
	void setCategory(const std::string &category);
	std::optional<std::string> summary();
	void setSummary(const std::string &summary);
	ooscript::Value callback();
	void setCallback(ooscript::Value callback);
	ooscript::Object callbackThis();
	void setCallbackThis(ooscript::Object callbackthis);

	void runCallback(const std::string &key);

	OOComparisonResult interfaceCompare(OOJSInterfaceDefinition *other);

private:
	void deleteJSPointers();

	ooscript::Value				_callback = {};
	ooscript::Object _callbackThis = {};
	oo::WeakRef<OOJSScript>		_owningScript;	// a weak reference (was the facade's weak reference proxy)

	std::optional<std::string>	_title;		// nullopt until set (was nil)
	std::optional<std::string>	_summary;
	std::optional<std::string>	_category;
};

#endif	// OOJSINTERFACEDEFINITION_H
