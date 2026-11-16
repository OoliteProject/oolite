/*

OOJSScript.h (QuickJS-ng proof of concept)

Minimal JavaScript script loader: enough to load a world script and call its
event handlers. The full OOJSScript (manifest properties, script caching,
OOScript subclassing) is the game's, in src/Core/Scripting.

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

#include "OOJavaScriptEngine.h"
#include "oofnd/Ref.hpp"

#include <optional>
#include <string>

class OOJSScript : public oo::RefCounted {
public:
    // Null (after logging) if the script cannot be loaded or its top level throws.
    static oo::Ref<OOJSScript> scriptWithPath(const std::string& path);
    ~OOJSScript() override;

    static OOJSScript* currentlyRunningScript();

    std::optional<std::string> name();
    std::optional<std::string> version();
    std::optional<std::string> displayName();

    JSValueConst scriptObject();

    /*	Call a method of the script object with the script as this, as the
            game's OOJSScript::callMethod() does. Returns false if the method does
            not exist or throws. *outResult, if requested, is owned by the caller.
    */
    bool callMethodNamed(const std::string& methodName, JSValueConst* argv, int argc, JSValue* outResult);

private:
    bool initWithPath(const std::string& path);
    bool loadScriptWithContext(JSContext* context);
    std::optional<std::string> stringPropertyNamed(const char* name, JSContext* context);

    JSValue _jsSelf = JS_UNDEFINED; // Owned; freed in the destructor.
    std::optional<std::string> _name;
    std::optional<std::string> _version;
    std::string _path;
};

void InitOOJSScript(JSContext* context, JSValueConst global);
