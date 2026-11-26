/*

OOJSScript.cpp (QuickJS-ng proof of concept)

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

#include "OOJSScript.h"

#include "oofnd/Data.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

namespace {
struct RunningStack {
    RunningStack* back = nullptr;
    OOJSScript* current = nullptr;
};

RunningStack* sRunningStack = nullptr;

JSClassID sScriptClassID;

JSClassDef sScriptClass = {
    .class_name = "Script",
};

// [[path lastPathComponent] stringByDeletingPathExtension]
std::string ScriptNameFromPath(const std::string& path)
{
    std::string name = oo::str::lastPathComponent(path);
    const std::size_t dot = name.rfind('.');
    if (dot != std::string::npos && dot != 0)
        name.erase(dot);
    return name;
}
} // namespace

oo::Ref<OOJSScript> OOJSScript::scriptWithPath(const std::string& path)
{
    oo::Ref<OOJSScript> script = oo::makeRef<OOJSScript>();
    if (!script->initWithPath(path))
        return nullptr;
    return script;
}

bool OOJSScript::initWithPath(const std::string& path)
{
    JSContext* context = OOJSAcquireContext();
    _path = path;

    /*	The JS object refers back to us without retaining, as the
            SpiderMonkey version did through a weak reference; the destructor
            clears it.
    */
    _jsSelf = JS_NewObjectClass(context, sScriptClassID);
    if (JS_IsException(_jsSelf)) {
        OOJSReportPendingException(context);
        _jsSelf = JS_UNDEFINED;
        return false;
    }
    JS_SetOpaque(_jsSelf, this);

    bool OK = loadScriptWithContext(context);
    if (!OK) {
        OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- could not run script", path);
    }

    OOJSRelinquishContext(context);
    return OK;
}

OOJSScript::~OOJSScript()
{
    if (JS_IsObject(_jsSelf)) {
        JSContext* context = OOJSAcquireContext();
        JS_SetOpaque(_jsSelf, nullptr);
        JS_FreeValue(context, _jsSelf);
        OOJSRelinquishContext(context);
    }
}

OOJSScript* OOJSScript::currentlyRunningScript()
{
    if (sRunningStack == nullptr)
        return nullptr;
    return sRunningStack->current;
}

std::optional<std::string> OOJSScript::name()
{
    return _name;
}

std::optional<std::string> OOJSScript::version()
{
    return _version;
}

std::optional<std::string> OOJSScript::displayName()
{
    if (_version.has_value() && _name.has_value())
        return *_name + " " + *_version;
    if (_version.has_value())
        return "(null) " + *_version;
    return _name;
}

JSValueConst OOJSScript::scriptObject()
{
    return _jsSelf;
}

bool OOJSScript::callMethodNamed(const std::string& methodName, JSValueConst* argv, int argc, JSValue* outResult)
{
    JSContext* context = OOJSAcquireContext();
    bool OK = false;

    JSValue method = JS_GetPropertyStr(context, _jsSelf, methodName.c_str());
    if (JS_IsFunction(context, method)) {
        RunningStack stackElement = {
            .back = sRunningStack,
            .current = this
        };
        sRunningStack = &stackElement;

        OK = OOJavaScriptEngine::sharedEngine()->callJSFunction(method, _jsSelf, argc, argv, outResult);

        sRunningStack = stackElement.back;
    } else if (JS_IsException(method)) {
        OOJSReportPendingException(context);
    }
    JS_FreeValue(context, method);

    OOJSRelinquishContext(context);
    return OK;
}

bool OOJSScript::loadScriptWithContext(JSContext* context)
{
    oo::fs::Result<oo::Data> contents = oo::fs::readFile(oo::fs::pathFromUTF8(_path));
    if (!contents) {
        OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- could not load file", _path);
        return false;
    }
    const std::string source(contents->stringView());

    // Initial name, in case of script error during initial run.
    _name = ScriptNameFromPath(_path);
    JS_SetPropertyStr(context, _jsSelf, "name", JS_NewStringLen(context, _name->data(), _name->size()));

    RunningStack stackElement = {
        .back = sRunningStack,
        .current = this
    };
    sRunningStack = &stackElement;

    /*	Run the script (allowing it to set up the properties we need, as well as
            setting up those event handlers). JS_Eval requires a terminating NUL,
            which std::string's c_str() has.
    */
    const std::string wrapped = OOJSWrapScriptSource(source);

    OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
    JSValue result = JS_EvalThis(context, _jsSelf, wrapped.c_str(), wrapped.size(), _path.c_str(), JS_EVAL_TYPE_GLOBAL);
    OOJSStopTimeLimiter();

    bool OK = !JS_IsException(result);
    if (OK)
        JS_FreeValue(context, result);
    else
        OOJSReportPendingException(context);

    sRunningStack = stackElement.back;

    if (OK) {
        // The script can't be renamed after the initial run.
        std::optional<std::string> name = stringPropertyNamed("name", context);
        if (name.has_value())
            _name = name;
        _version = stringPropertyNamed("version", context);
    }

    return OK;
}

std::optional<std::string> OOJSScript::stringPropertyNamed(const char* name, JSContext* context)
{
    JSValue value = JS_GetPropertyStr(context, _jsSelf, name);
    std::optional<std::string> result = JS_IsString(value) ? cxx_OOStringFromJSValue(context, value) : std::nullopt;
    JS_FreeValue(context, value);
    return result;
}

void InitOOJSScript(JSContext* context, JSValueConst /*global*/)
{
    JSRuntime* runtime = JS_GetRuntime(context);
    JS_NewClassID(runtime, &sScriptClassID);
    JS_NewClass(runtime, sScriptClassID, &sScriptClass);
}
