/*

OOJSFunction.m


JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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

#import "OOJSFunction.h"
#import "OOFoundationBridge.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSScript.h"
#include "oofnd/Notification.hpp"
#include "oofnd/objc/OOAssert.h"

#include <vector>

@implementation OOJSFunction

- (id)initWithFunction:(JSValueConst)function context:(JSContext*)context
{
    OOParameterAssert(context != NULL);

    if (!JS_IsFunction(context, function)) {
        [self release];
        return nil;
    }

    if ((self = [super init])) {
        _function = JS_DupValue(context, function);

        // QuickJS has no JS_GetFunctionId(); use the function's name property.
        JSValue nameValue = JS_GetPropertyStr(context, function, "name");
        if (JS_IsException(nameValue)) {
            JS_FreeValue(context, JS_GetException(context));
        } else {
            std::optional<std::string> name = oo::OptionalString(OOStringFromJSValue(context, nameValue));
            if (name.has_value() && !name->empty())
                _name = name;
        }
        JS_FreeValue(context, nameValue);

        oo::NotificationCenter::defaultCenter().addObserver(self, kOOJavaScriptEngineWillResetNotificationName,
            [OOJavaScriptEngine sharedEngine],
            [self](const oo::Notification&) { [self deleteJSValue]; });
    }

    return self;
}

- (id)initWithName:(const std::optional<std::string>&)name
             scope:(JSValueConst)scope
              code:(const std::optional<std::string>&)code
     argumentCount:(NSUInteger)argCount
     argumentNames:(const char**)argNames
          fileName:(const std::optional<std::string>&)fileName
        lineNumber:(NSUInteger)lineNumber
           context:(JSContext*)context
{
    BOOL OK = YES;
    BOOL releaseContext = NO;
    JSValue function = JS_UNDEFINED;

    if (context == NULL) {
        context = OOJSAcquireContext();
        releaseContext = YES;
    }

    /*	SpiderMonkey's JS_CompileUCFunction() could compile the function in an
            arbitrary scope object. QuickJS has no equivalent, so the function is
            always compiled in the global scope. (The only caller passed NULL,
            meaning the global object, anyway.)
    */
    (void)scope;

    if (!code.has_value() || (argCount > 0 && argNames == NULL))
        OK = NO;

    if (OK) {
        assert(argCount < INT_MAX && lineNumber < INT_MAX);

        /*	QuickJS has no API to compile a function from a body and argument
                names, so evaluate a function expression. The wrapper is kept on
                the first line so that line numbers in the body are unchanged.
        */
        std::string source = "(function(";
        NSUInteger i;
        for (i = 0; i < argCount; i++) {
            if (i != 0)
                source += ",";
            source += argNames[i];
        }
        source += "){" + *code + "\n})";

        JSEvalOptions options = {
            .version = JS_EVAL_OPTIONS_VERSION,
            .eval_flags = JS_EVAL_TYPE_GLOBAL,
            .filename = fileName.has_value() ? fileName->c_str() : "<anonymous>",
            .line_num = (int)lineNumber
        };
        // JS_Eval2() requires a NUL-terminated buffer, which c_str() is.
        function = JS_Eval2(context, source.c_str(), source.size(), &options);
        if (JS_IsException(function)) {
            OOJSReportPendingException(context);
            function = JS_UNDEFINED;
            OK = NO;
        } else if (!JS_IsFunction(context, function)) {
            OK = NO;
        }
    }

    if (OK && name.has_value()) {
        // Function expression names are read-only but configurable; redefine it.
        JS_DefinePropertyValueStr(context, function, "name", JS_NewStringLen(context, name->data(), name->size()), JS_PROP_CONFIGURABLE);
    }

    if (OK) {
        self = [self initWithFunction:function context:context];
    } else {
        DESTROY(self);
    }
    JS_FreeValue(context, function);

    if (releaseContext)
        OOJSRelinquishContext(context);

    return self;
}

- (void)deleteJSValue
{
    // _function is zero-filled (not an object) if never set.
    if (JS_IsObject(_function)) {
        JSContext* context = OOJSAcquireContext();
        JS_FreeValue(context, _function);
        OOJSRelinquishContext(context);

        _function = JS_NULL;
        oo::NotificationCenter::defaultCenter().removeObserver(self, kOOJavaScriptEngineWillResetNotificationName,
            [OOJavaScriptEngine sharedEngine]);
    }
}

- (void)dealloc
{
    [self deleteJSValue];

    [super dealloc];
}

- (id)descriptionComponents // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom(oo::str::format("%s()", _name.value_or("<anonymous>").c_str()));
}

- (id)name // shared selector (proposed ADR-0043)
{
    return oo::NSStringOrNil(_name);
}

- (BOOL)isValid
{
    // _function is zero-filled (the integer 0) until set, and JS_NULL after reset.
    return JS_IsObject(_function);
}

- (JSValueConst)function
{
    return [self isValid] ? _function : JS_NULL;
}

- (JSValue)functionValue
{
    if (EXPECT([self isValid])) {
        return JS_DupValue(OOJSAcquireContext(), _function);
    } else {
        return JS_NULL;
    }
}

- (BOOL)evaluateWithContext:(JSContext*)context
                      scope:(JSValueConst)jsThis
                       argc:(int)argc
                       argv:(JSValueConst*)argv
                     result:(JSValue*)result
{
    OOParameterAssert(result != NULL);

    if (EXPECT_NOT(![self isValid])) {
        *result = JS_UNDEFINED;
        return NO;
    }

    // As with JS_CallFunction(), a missing this means the global object.
    JSValue global = JS_UNDEFINED;
    if (!JS_IsObject(jsThis)) {
        global = JS_GetGlobalObject(context);
        jsThis = global;
    }

    [OOJSScript pushScript:nil];
    OOJSStartTimeLimiter();
    JSValue rval = JS_Call(context, _function, jsThis, argc, argv);
    OOJSStopTimeLimiter();
    [OOJSScript popScript:nil];

    JS_FreeValue(context, global);

    if (JS_IsException(rval)) {
        *result = JS_UNDEFINED;
        return NO;
    }
    *result = rval;
    return YES;
}

// Semi-raw evaluation shared by convenience methods below. *result is owned on success; exceptions are reported.
- (BOOL)evaluateWithContext:(JSContext*)context
                      scope:(id)jsThis
                  arguments:(const std::vector<oo::ObjCRef<id>>&)arguments
                     result:(JSValue*)result
{
    NSUInteger i, argc = arguments.size();
    assert(argc < INT_MAX);
    std::vector<JSValue> argv(argc);

    for (i = 0; i < argc; i++) {
        argv[i] = [arguments[i].get() oo_jsValueInContext:context];
    }

    JSValue scopeObj = JS_UNDEFINED;
    BOOL OK = YES;
    if (jsThis != nil) {
        JSValue thisValue = [jsThis oo_jsValueInContext:context];
        // As with JS_ValueToObject(), null and undefined give no object (the global object is used).
        if (!JS_IsNull(thisValue) && !JS_IsUndefined(thisValue)) {
            scopeObj = JS_ToObject(context, thisValue);
            if (JS_IsException(scopeObj)) {
                scopeObj = JS_UNDEFINED;
                OK = NO;
            }
        }
        JS_FreeValue(context, thisValue);
    }
    if (OK)
        OK = [self evaluateWithContext:context
                                 scope:scopeObj
                                  argc:(int)argc
                                  argv:argv.data()
                                result:result];
    if (!OK) {
        /*	SpiderMonkey reported uncaught exceptions automatically when
                control returned from JS; QuickJS leaves them pending.
        */
        if (JS_HasException(context))
            OOJSReportPendingException(context);
        *result = JS_UNDEFINED;
    }

    JS_FreeValue(context, scopeObj);
    for (i = 0; i < argc; i++) {
        JS_FreeValue(context, argv[i]);
    }

    return OK;
}

- (id)evaluateWithContext:(JSContext*)context
                    scope:(id)jsThis
                arguments:(const std::vector<oo::ObjCRef<id>>&)arguments
{
    JSValue result;
    BOOL OK = [self evaluateWithContext:context
                                  scope:jsThis
                              arguments:arguments
                                 result:&result];
    if (!OK)
        return nil;

    id object = OOJSNativeObjectFromJSValue(context, result);
    JS_FreeValue(context, result);
    return object;
}

- (BOOL)evaluatePredicateWithContext:(JSContext*)context
                               scope:(id)jsThis
                           arguments:(const std::vector<oo::ObjCRef<id>>&)arguments
{
    JSValue result;
    BOOL OK = [self evaluateWithContext:context
                                  scope:jsThis
                              arguments:arguments
                                 result:&result];
    int retval = NO;
    if (OK) {
        retval = JS_ToBool(context, result);
        JS_FreeValue(context, result);
        if (retval < 0) {
            OOJSReportPendingException(context);
            OK = NO;
        }
    }
    return OK && retval;
}

@end
