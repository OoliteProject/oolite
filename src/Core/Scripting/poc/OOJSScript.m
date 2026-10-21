/*

OOJSScript.m (QuickJS-ng proof of concept)

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

@interface OOJSScript (Private)

- (BOOL)loadScriptWithContext:(JSContext*)context;
- (NSString*)stringPropertyNamed:(const char*)name inContext:(JSContext*)context;

@end

@implementation OOJSScript

+ (id)scriptWithPath:(NSString*)path
{
    return [[[self alloc] initWithPath:path] autorelease];
}

- (id)initWithPath:(NSString*)path
{
    if (!(self = [super init]))
        return nil;

    JSContext* context = OOJSAcquireContext();
    _path = [path copy];

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
        OOLog(@"script.javaScript.load.failed", @"***** Error loading JavaScript script %@ -- could not run script", path);
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

    [_name release];
    [_version release];
    [_path release];

    [super dealloc];
}

+ (OOJSScript*)currentlyRunningScript
{
    if (sRunningStack == NULL)
        return nil;
    return sRunningStack->current;
}

- (NSString*)name
{
    return _name;
}

- (NSString*)version
{
    return _version;
}

- (NSString*)displayName
{
    if (_version != nil)
        return [NSString stringWithFormat:@"%@ %@", _name, _version];
    return _name;
}

- (JSValueConst)scriptObject
{
    return _jsSelf;
}

- (BOOL)callMethodNamed:(NSString*)methodName
          withArguments:(JSValueConst*)argv
                  count:(int)argc
                 result:(JSValue*)outResult
{
    JSContext* context = OOJSAcquireContext();
    BOOL OK = NO;

    JSValue method = JS_GetPropertyStr(context, _jsSelf, [methodName UTF8String]);
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
    NSString* source = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:NULL];
    if (source == nil) {
        OOLog(@"script.javaScript.load.failed", @"***** Error loading JavaScript script %@ -- could not load file", _path);
        return NO;
    }

    // Initial name, in case of script error during initial run.
    _name = [[[_path lastPathComponent] stringByDeletingPathExtension] retain];
    JS_SetPropertyStr(context, _jsSelf, "name", OOJSValueFromNativeObject(context, _name));

    RunningStack stackElement = {
        .back = sRunningStack,
        .current = self
    };
    sRunningStack = &stackElement;

    // Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
    NSData* wrapped = [OOJSWrapScriptSource(source) dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* terminated = [NSMutableData dataWithData:wrapped];
    [terminated appendBytes:"" length:1]; // JS_Eval requires a terminating NUL.

    OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
    JSValue result = JS_EvalThis(context, _jsSelf, [terminated bytes], [wrapped length], [_path UTF8String], JS_EVAL_TYPE_GLOBAL);
    OOJSStopTimeLimiter();

    BOOL OK = !JS_IsException(result);
    if (OK)
        JS_FreeValue(context, result);
    else
        OOJSReportPendingException(context);

    sRunningStack = stackElement.back;

    if (OK) {
        // The script can't be renamed after the initial run.
        NSString* name = [self stringPropertyNamed:"name" inContext:context];
        if (name != nil) {
            [_name release];
            _name = [name retain];
        }
        _version = [[self stringPropertyNamed:"version" inContext:context] retain];
    }

    return OK;
}

- (NSString*)stringPropertyNamed:(const char*)name inContext:(JSContext*)context
{
    JSValue value = JS_GetPropertyStr(context, _jsSelf, name);
    NSString* result = JS_IsString(value) ? OOStringFromJSValue(context, value) : nil;
    JS_FreeValue(context, value);
    return result;
}

@end

void InitOOJSScript(JSContext* context, JSValueConst global)
{
    JSRuntime* runtime = JS_GetRuntime(context);
    JS_NewClassID(runtime, &sScriptClassID);
    JS_NewClass(runtime, sScriptClassID, &sScriptClass);
}
