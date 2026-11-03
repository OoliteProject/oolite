/*

OOJSScript.mm (QuickJS-ng proof of concept)

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

#import "OOJSScript.h"

#include "oofnd/Data.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

typedef struct RunningStack RunningStack;
struct RunningStack {
    RunningStack* back;
    OOJSScript* current;
};

static RunningStack* sRunningStack = NULL;

static JSClassID sScriptClassID;

static JSClassDef sScriptClass = {
    .class_name = "Script",
};

// [[path lastPathComponent] stringByDeletingPathExtension]
static std::string ScriptNameFromPath(const std::string& path)
{
    std::string name = oo::str::lastPathComponent(path);
    const std::size_t dot = name.rfind('.');
    if (dot != std::string::npos && dot != 0)
        name.erase(dot);
    return name;
}

@interface OOJSScript (Private)

- (BOOL)loadScriptWithContext:(JSContext*)context;
- (std::optional<std::string>)stringPropertyNamed:(const char*)name inContext:(JSContext*)context;

@end

@implementation OOJSScript

+ (id)scriptWithPath:(const std::string&)path
{
    return [[[self alloc] initWithPath:path] autorelease];
}

- (id)initWithPath:(const std::string&)path
{
    if (!(self = [super init]))
        return nil;

    JSContext* context = OOJSAcquireContext();
    _path = path;

    /*	The JS object refers back to us without retaining, as the
            SpiderMonkey version did through a weak reference; -dealloc clears it.
    */
    _jsSelf = JS_NewObjectClass(context, sScriptClassID);
    if (JS_IsException(_jsSelf)) {
        OOJSReportPendingException(context);
        _jsSelf = JS_UNDEFINED;
        [self release];
        return nil;
    }
    JS_SetOpaque(_jsSelf, self);

    if (![self loadScriptWithContext:context]) {
        OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- could not run script", path);
        [self release];
        self = nil;
    }

    OOJSRelinquishContext(context);
    return self;
}

- (void)dealloc
{
    if (JS_IsObject(_jsSelf)) {
        JSContext* context = OOJSAcquireContext();
        JS_SetOpaque(_jsSelf, NULL);
        JS_FreeValue(context, _jsSelf);
        OOJSRelinquishContext(context);
    }

    [super dealloc];
}

+ (OOJSScript*)currentlyRunningScript
{
    if (sRunningStack == NULL)
        return nil;
    return sRunningStack->current;
}

- (std::optional<std::string>)name
{
    return _name;
}

- (std::optional<std::string>)version
{
    return _version;
}

- (std::optional<std::string>)displayName
{
    if (_version.has_value())
        return _name.value_or("(null)") + " " + *_version;
    return _name;
}

- (JSValueConst)scriptObject
{
    return _jsSelf;
}

- (BOOL)callMethodNamed:(const std::string&)methodName
          withArguments:(JSValueConst*)argv
                  count:(int)argc
                 result:(JSValue*)outResult
{
    JSContext* context = OOJSAcquireContext();
    BOOL OK = NO;

    JSValue method = JS_GetPropertyStr(context, _jsSelf, methodName.c_str());
    if (JS_IsFunction(context, method)) {
        RunningStack stackElement = {
            .back = sRunningStack,
            .current = self
        };
        sRunningStack = &stackElement;

        OK = [[OOJavaScriptEngine sharedEngine] callJSFunction:method
                                                     forObject:_jsSelf
                                                          argc:argc
                                                          argv:argv
                                                        result:outResult];

        sRunningStack = stackElement.back;
    } else if (JS_IsException(method)) {
        OOJSReportPendingException(context);
    }
    JS_FreeValue(context, method);

    OOJSRelinquishContext(context);
    return OK;
}

@end

@implementation OOJSScript (Private)

- (BOOL)loadScriptWithContext:(JSContext*)context
{
    oo::fs::Result<oo::Data> contents = oo::fs::readFile(oo::fs::pathFromUTF8(_path));
    if (!contents) {
        OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- could not load file", _path);
        return NO;
    }
    const std::string source(contents->stringView());

    // Initial name, in case of script error during initial run.
    _name = ScriptNameFromPath(_path);
    JS_SetPropertyStr(context, _jsSelf, "name", JS_NewStringLen(context, _name->data(), _name->size()));

    RunningStack stackElement = {
        .back = sRunningStack,
        .current = self
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

    BOOL OK = !JS_IsException(result);
    if (OK)
        JS_FreeValue(context, result);
    else
        OOJSReportPendingException(context);

    sRunningStack = stackElement.back;

    if (OK) {
        // The script can't be renamed after the initial run.
        std::optional<std::string> name = [self stringPropertyNamed:"name" inContext:context];
        if (name.has_value())
            _name = name;
        _version = [self stringPropertyNamed:"version" inContext:context];
    }

    return OK;
}

- (std::optional<std::string>)stringPropertyNamed:(const char*)name inContext:(JSContext*)context
{
    JSValue value = JS_GetPropertyStr(context, _jsSelf, name);
    std::optional<std::string> result = JS_IsString(value) ? cxx_OOStringFromJSValue(context, value) : std::nullopt;
    JS_FreeValue(context, value);
    return result;
}

@end

void InitOOJSScript(JSContext* context, JSValueConst /*global*/)
{
    JSRuntime* runtime = JS_GetRuntime(context);
    JS_NewClassID(runtime, &sScriptClassID);
    JS_NewClass(runtime, sScriptClassID, &sScriptClass);
}
