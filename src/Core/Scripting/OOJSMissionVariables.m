/*

OOJSMissionVariables.h

JavaScript mission variables object.


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

#import "OOJSMissionVariables.h"
#import "OOIsNumberLiteral.h"
#import "OOJavaScriptEngine.h"

#import "OOJSPlayer.h"

/*	SpiderMonkey called the MissionVariables class's get, set and delete hooks
        for every property access, and its enumerate hook for for-in. QuickJS
        has no such hooks; the class's exotic methods provide the same view
        instead: every mission variable appears as an enumerable own property,
        assignments and deletions go to the player's mission variables, and
        reading a missing (non-"_") name gives null, as before. Names starting
        with "_" are not mission variables; reading them falls back to the
        prototype (Object.prototype) and assigning them is an error. Properties
        of Object.prototype (such as toString) are found there unless a mission
        variable of the same name exists.
*/

// Property name for a string property ID, or nil for other IDs (symbols).
static NSString* NameForPropertyID(JSContext* context, JSAtom propID)
{
    NSString* result = nil;
    JSValue idValue = JS_AtomToValue(context, propID);
    // SpiderMonkey's hooks ignored integer IDs; QuickJS uses integer atoms for names like "0".
    if (JS_IsString(idValue)) {
        result = OOStringFromJSValue(context, idValue);
    }
    JS_FreeValue(context, idValue);
    return result;
}

static NSString* KeyForPropertyName(NSString* name)
{
    if (name == nil || [name hasPrefix:@"_"])
        return nil;
    return [@"mission_" stringByAppendingString:name];
}

static int MissionVariablesGetOwnProperty(JSContext* context, JSPropertyDescriptor* desc, JSValueConst object, JSAtom propID);
static int MissionVariablesGetOwnPropertyNames(JSContext* context, JSPropertyEnum** outTable, uint32_t* outCount, JSValueConst object);
static int MissionVariablesDeleteProperty(JSContext* context, JSValueConst object, JSAtom propID);
static int MissionVariablesDefineOwnProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst getter, JSValueConst setter, int flags);
static JSValue MissionVariablesGetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst receiver);
static int MissionVariablesSetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst receiver, int flags);

#ifndef NDEBUG
static id MissionVariablesConverter(JSContext* context, JSValueConst object);
#endif

static JSClassExoticMethods sMissionVariablesExoticMethods = {
    .get_own_property = MissionVariablesGetOwnProperty,
    .get_own_property_names = MissionVariablesGetOwnPropertyNames,
    .delete_property = MissionVariablesDeleteProperty,
    .define_own_property = MissionVariablesDefineOwnProperty,
    .get_property = MissionVariablesGetProperty,
    .set_property = MissionVariablesSetProperty,
};

static JSClassID sMissionVariablesClassID;
static JSClassDef sMissionVariablesClass = {
    .class_name = "MissionVariables",
    .exotic = &sMissionVariablesExoticMethods,
};

void InitOOJSMissionVariables(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sMissionVariablesClassID, &sMissionVariablesClass);

    // As with JS_DefineObject() with a NULL prototype, the prototype is Object.prototype.
    JSValue objectPrototype = OOJSObjectPrototype(context);
    JSValue missionVariables = JS_NewObjectProtoClass(context, objectPrototype, sMissionVariablesClassID);
    JS_FreeValue(context, objectPrototype);
    JS_DefinePropertyValueStr(context, global, "missionVariables", missionVariables, OOJS_PROP_READONLY);

#ifndef NDEBUG
    // Allow callObjC() on missionVariables to call methods on the mission variables dictionary.
    OOJSRegisterObjectConverter(sMissionVariablesClassID, MissionVariablesConverter);
#endif
}

#ifndef NDEBUG
static id MissionVariablesConverter(JSContext* context, JSValueConst object)
{
    return [PLAYER missionVariables];
}
#endif

// Owned value of a mission variable, or JS_UNDEFINED if it doesn't exist.
static JSValue ValueForMissionVariable(JSContext* context, NSString* key)
{
    PlayerEntity* player = OOPlayerForScripting();
    id mvar = [player missionVariableForKey:key];

    if (mvar == nil)
        return JS_UNDEFINED;

    if ([mvar isKindOfClass:[NSString class]]) // Currently there should only be strings, but we may want to change this.
    {
        if (OOIsNumberLiteral(mvar, YES)) {
            return JS_NewNumber(context, [mvar doubleValue]);
        }
    }

    return OOJSValueFromNativeObject(context, mvar);
}

static int MissionVariablesGetOwnProperty(JSContext* context, JSPropertyDescriptor* desc, JSValueConst object, JSAtom propID)
{
    @try {
        NSString* key = KeyForPropertyName(NameForPropertyID(context, propID));
        if (key == nil)
            return NO;

        JSValue value = ValueForMissionVariable(context, key);
        if (JS_IsUndefined(value))
            return NO;

        if (desc != NULL) {
            desc->flags = JS_PROP_C_W_E;
            desc->value = value;
            desc->getter = JS_UNDEFINED;
            desc->setter = JS_UNDEFINED;
        } else {
            JS_FreeValue(context, value);
        }
        return YES;
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}

static int MissionVariablesGetOwnPropertyNames(JSContext* context, JSPropertyEnum** outTable, uint32_t* outCount, JSValueConst object)
{
    @try {
        // -allKeys implicitly makes a copy, which is good since the enumerating code might mutate.
        NSArray* mvars = [[PLAYER missionVariables] allKeys];
        NSUInteger count = [mvars count];
        assert(count <= INT32_MAX);

        JSPropertyEnum* table = js_malloc(context, sizeof *table * MAX(count, (NSUInteger)1));
        if (table == NULL)
            return -1;

        uint32_t used = 0;
        NSString* next = nil;
        foreach (next, mvars) {
            if (![next hasPrefix:@"mission_"])
                continue; // Skip mission instructions, which aren't visible through missionVariables.

            next = [next substringFromIndex:8]; // Cut off "mission_".

            JSAtom atom = JS_NewAtom(context, [next UTF8String]);
            if (atom == JS_ATOM_NULL) {
                JS_FreePropertyEnum(context, table, used);
                return -1;
            }
            table[used].is_enumerable = true;
            table[used].atom = atom;
            used++;
        }

        // QuickJS frees the table and its atoms.
        *outTable = table;
        *outCount = used;
        return 0;
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}

static int MissionVariablesDeleteProperty(JSContext* context, JSValueConst object, JSAtom propID)
{
    @try {
        PlayerEntity* player = OOPlayerForScripting();

        NSString* name = NameForPropertyID(context, propID);
        if (name != nil) {
            NSString* key = KeyForPropertyName(name);
            [player setMissionVariable:nil forKey:key];
        }
        return YES;
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}

static JSValue MissionVariablesGetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst receiver)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = KeyForPropertyName(NameForPropertyID(context, propID));
    if (key != nil) {
        JSValue value = ValueForMissionVariable(context, key);
        if (!JS_IsUndefined(value))
            return value;
    }

    // Not a mission variable; look in the prototype chain.
    JSValue prototype = JS_GetPrototype(context, object);
    if (JS_IsException(prototype))
        return JS_EXCEPTION;

    JSValue result = JS_UNDEFINED;
    if (JS_IsObject(prototype)) {
        int found = (key != nil) ? JS_HasProperty(context, prototype, propID) : YES;
        if (found < 0) {
            result = JS_EXCEPTION;
        } else if (found) {
            result = JS_GetProperty(context, prototype, propID);
        } else {
            // Missing mission variables read as null (OOJSValueFromNativeObject(nil)).
            result = JS_NULL;
        }
    } else if (key != nil) {
        result = JS_NULL;
    }
    JS_FreeValue(context, prototype);
    return result;

    OOJS_NATIVE_EXIT
}

static BOOL SetMissionVariable(JSContext* context, JSAtom propID, JSValueConst value)
{
    PlayerEntity* player = OOPlayerForScripting();

    NSString* name = NameForPropertyID(context, propID);
    if (name != nil) {
        NSString* key = KeyForPropertyName(name);
        if (key == nil) {
            OOJSReportError(context, @"Invalid mission variable name \"%@\".", [name escapedForJavaScriptLiteral]);
            return NO;
        }

        NSString* objValue = OOStringFromJSValue(context, value);

        if ([objValue isKindOfClass:[NSNull class]])
            objValue = nil;
        [player setMissionVariable:objValue forKey:key];
    }
    return YES;
}

static int MissionVariablesSetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst receiver, int flags)
{
    @try {
        return SetMissionVariable(context, propID, value) ? YES : -1;
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}

static int MissionVariablesDefineOwnProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst getter, JSValueConst setter, int flags)
{
    /*	Object.defineProperty() and friends. Mission variables can't be
            accessors; a defined value is stored like an assignment.
    */
    @try {
        if (flags & (JS_PROP_HAS_GET | JS_PROP_HAS_SET)) {
            OOJSReportError(context, @"Invalid mission variable name \"%@\".", [OOStringFromJSID(propID) escapedForJavaScriptLiteral]);
            return -1;
        }
        if (!(flags & JS_PROP_HAS_VALUE))
            return YES;
        return SetMissionVariable(context, propID, value) ? YES : -1;
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}
