/*

OOJSSystemInfo.h (QuickJS-ng)

JavaScript object representing system info overrides.

OOSystemInfo, the object a SystemInfo wraps, is private to OOJSSystemInfo.cpp,
which is the only file that makes one. A SystemInfo's private slot holds it
directly (OOJSPrivateObject.h), and it is a oo::PListForeign, so a PList can
carry it (the engine turns one back into its JS object with
OOJSValueFromCxxObject).


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

#include "OOFoundation.h"
#include "OOJSPrivateObject.h"
#include "OOTypes.h"
#include <quickjs.h>

#include <optional>
#include <set>
#include <string>
#include <vector>

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

// The system a SystemInfo stands for, and its data through the universe.
class OOSystemInfo : public oo::PListForeign, public ::OOJSPrivateObject {
public:
    // -initWithGalaxy:system:, as a factory: null for a galaxy or system out of
    // range.
    static oo::Ref<OOSystemInfo> initWithGalaxy(OOGalaxyID galaxy, OOSystemID system);

    std::optional<std::string> descriptionComponents() const;
    std::optional<std::string> shortDescriptionComponents() const;
    std::optional<std::string> oo_jsClassName() const;

    bool isEqual(const OOSystemInfo* other) const; // null: not equal
    NSUInteger hash() const;

    oo::PList valueForKey(const std::optional<std::string>& key); // null for none
    void setValue(const oo::PList& value, const std::string& key); // a null value removes

    std::vector<std::string> allKeys();

    // Keys a script assigned null (see SystemInfoExoticSetProperty()).
    void setNullAssigned(bool flag, const std::string& key);
    bool isNullAssignedForKey(const std::string& key) const;

    OOGalaxyID galaxy() const;
    OOSystemID system() const;
    NSPoint coordinates();

    // The JS glue (OOJSPrivateObject): a new SystemInfo object holding this (no wrapper is
    // remembered, so clearJSSelf() has nothing to forget); "[SystemInfo galaxy g, system s]".
    JSValue jsValueInContext(JSContext* context) override; // owned
    void clearJSSelf(JSValueConst selfVal) override;
    std::optional<std::string> jsDescription() override;

    // oo::PListForeign: for the PList that carries this.
    std::string className() const override;
    std::string description() const override;

private:
    OOSystemInfo(OOGalaxyID galaxy, OOSystemID system);

    OOGalaxyID _galaxy;
    OOSystemID _system;
    std::string _planetKey;
    std::set<std::string> _nullAssignedKeys; // See SystemInfoExoticSetProperty().
};

void InitOOJSSystemInfo(JSContext* context, JSValueConst global);

// Returns an owned value, or JS_NULL on failure (with a JS warning, but no exception).
JSValue GetJSSystemInfoForSystem(JSContext* context, OOGalaxyID galaxy, OOSystemID system);
