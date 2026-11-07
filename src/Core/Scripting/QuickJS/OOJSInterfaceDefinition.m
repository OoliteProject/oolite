/*

OOJSInterfaceDefinition.m (QuickJS-ng)


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

#import "OOJSInterfaceDefinition.h"
#import "OOJavaScriptEngine.h"

@implementation OOJSInterfaceDefinition

- (id)init
{
    self = [super init];
    _callback = JS_UNDEFINED;
    _callbackThis = JS_UNDEFINED;

    _owningScript = [[OOJSScript currentlyRunningScript] weakRetain];

    // Stays registered until dealloc, so values set after a reset are also released on the next one.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deleteJSPointers)
                                                 name:kOOJavaScriptEngineWillResetNotification
                                               object:[OOJavaScriptEngine sharedEngine]];

    return self;
}

- (void)deleteJSPointers
{
    JSContext* context = OOJSAcquireContext();
    JS_FreeValue(context, _callback);
    _callback = JS_UNDEFINED;
    JS_FreeValue(context, _callbackThis);
    _callbackThis = JS_UNDEFINED;
    OOJSRelinquishContext(context);
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kOOJavaScriptEngineWillResetNotification
                                                  object:[OOJavaScriptEngine sharedEngine]];

    [_owningScript release];
    [_title release];
    [_summary release];
    [_category release];

    [self deleteJSPointers];

    [super dealloc];
}

- (NSString*)title
{
    return _title;
}

- (void)setTitle:(NSString*)title
{
    [_title autorelease];
    _title = [title retain];
}

- (NSString*)category
{
    return _category;
}

- (void)setCategory:(NSString*)category
{
    [_category autorelease];
    _category = [category retain];
}

- (NSString*)summary
{
    return _summary;
}

- (void)setSummary:(NSString*)summary
{
    [_summary autorelease];
    _summary = [summary retain];
}

- (JSValue)callback
{
    return JS_DupValue(OOJSAcquireContext(), _callback);
}

- (void)setCallback:(JSValueConst)callback
{
    JSContext* context = OOJSAcquireContext();
    JSValue old = _callback;
    _callback = JS_DupValue(context, callback);
    JS_FreeValue(context, old);
    OOJSRelinquishContext(context);
}

- (JSValue)callbackThis
{
    return JS_DupValue(OOJSAcquireContext(), _callbackThis);
}

- (void)setCallbackThis:(JSValueConst)callbackThis
{
    JSContext* context = OOJSAcquireContext();
    JSValue old = _callbackThis;
    _callbackThis = JS_DupValue(context, callbackThis);
    JS_FreeValue(context, old);
    OOJSRelinquishContext(context);
}

- (void)runCallback:(NSString*)key
{
    OOJavaScriptEngine* engine = [OOJavaScriptEngine sharedEngine];
    JSContext* context = OOJSAcquireContext();
    JSValue rval = JS_UNDEFINED;

    if (!JS_IsFunction(context, _callback)) {
        // The callback was released by an engine reset.
        OOJSRelinquishContext(context);
        return;
    }

    JSValue cKey = OOJSValueFromNativeObject(context, key);

    OOJSScript* owner = [_owningScript retain]; // local copy needed
    [OOJSScript pushScript:owner];

    // Hold our own references in case the callback replaces them.
    JSValue callback = JS_DupValue(context, _callback);
    JSValue callbackThis = JS_IsObject(_callbackThis) ? JS_DupValue(context, _callbackThis) : JS_UNDEFINED;
    [engine callJSFunction:callback
                 forObject:callbackThis
                      argc:1
                      argv:&cKey
                    result:&rval];
    JS_FreeValue(context, callback);
    JS_FreeValue(context, callbackThis);

    [OOJSScript popScript:owner];
    [owner release];

    JS_FreeValue(context, rval);
    JS_FreeValue(context, cKey);
    OOJSRelinquishContext(context);
}

- (NSComparisonResult)interfaceCompare:(OOJSInterfaceDefinition*)other
{
    NSComparisonResult byCategory = [_category caseInsensitiveCompare:[other category]];
    if (byCategory == NSOrderedSame) {
        return [_title caseInsensitiveCompare:[other title]];
    } else {
        return byCategory;
    }
}

@end
