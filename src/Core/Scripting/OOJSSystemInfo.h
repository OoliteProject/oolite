/*

OOJSSystemInfo.h

JavaScript object representing system info overrides.

C++20 since bead oo-6ia4 (proposed ADR-0056; amendment oo-ppc for the binding). OOSystemInfo,
the object a SystemInfo wraps, was an Objective-C class private to OOJSSystemInfo.mm. Only that
file makes one. Since bead oo-6symp.2 a SystemInfo's private slot holds it directly
(OOJSPrivateObject.h; proposed ADR-0056 amendment oo-6symp), and since bead oo-9ht.95 its
Objective-C facade is gone: it is a oo::PListForeign, so a PList can carry it (the engine turns
one back into its JS object with OOJSValueFromCxxObject).


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

#ifndef OOJSSYSTEMINFO_H
#define OOJSSYSTEMINFO_H

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "OOTypes.h"
#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/PList.hpp"
#include "OOJSPrivateObject.h"


// The system a SystemInfo stands for, and its data through the universe.
class OOSystemInfo : public oo::PListForeign, public ::OOJSPrivateObject
{
public:
	// -initWithGalaxy:system:, as a factory: null for a galaxy or system out of range (it answered
	// nil; amendment oo-novu item 1).
	static oo::Ref<OOSystemInfo> initWithGalaxy(OOGalaxyID galaxy, OOSystemID system);

	std::optional<std::string> descriptionComponents() const;
	std::optional<std::string> shortDescriptionComponents() const;
	std::optional<std::string> oo_jsClassName() const;

	bool isEqual(const OOSystemInfo *other) const;	// null: not equal
	NSUInteger hash() const;

	oo::PList valueForKey(const std::optional<std::string> &key);	// null for none
	void setValue(const oo::PList &value, const std::string &key);	// a null value removes

	std::vector<std::string> allKeys();

	OOGalaxyID galaxy() const;
	OOSystemID system() const;
	NSPoint coordinates();

	// The JS glue (OOJSPrivateObject): a new SystemInfo object holding this, remembered as the
	// latest; forgetting it when it is finalized; "[SystemInfo galaxy g, system s]".
	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
	std::optional<std::string> jsDescription() override;

	// oo::PListForeign: for the PList that carries this.
	std::string className() const override;
	std::string description() const override;

private:
	OOSystemInfo(OOGalaxyID galaxy, OOSystemID system);

	OOGalaxyID				_galaxy;
	OOSystemID				_system;
	std::string				_planetKey;
	ooscript::Object		_jsSelf = {};	// The latest JS SystemInfo object made for this.
};


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSSystemInfo(ooscript::Context context, ooscript::Object global);

// Returns ooscript::nullValue() on failure (with a JS warning, but no exception).
ooscript::Value GetJSSystemInfoForSystem(ooscript::Context context, OOGalaxyID galaxy, OOSystemID system);

#ifdef __cplusplus
}
#endif

#endif	// OOJSSYSTEMINFO_H
