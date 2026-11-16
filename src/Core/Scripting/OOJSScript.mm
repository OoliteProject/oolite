/*

OOJSScript.m (QuickJS-ng)

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

#ifndef OO_CACHE_JS_SCRIPTS
#define OO_CACHE_JS_SCRIPTS 1
#endif

#import "OOJSScript.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJavaScriptEngine.h"
#include "oofnd/Notification.hpp"

#import "Entity.h"
#import "EntityOOJavaScriptExtensions.h"
#if OO_CACHE_JS_SCRIPTS
#import "OOCacheManager.h"
#endif
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OODebugStandards.h"
#import "OOFoundationBridge.h"
#import "OOLogging.h"
#import "OOManifestProperties.h"
#import "OOPListParsing.h"
#import "OOPListView.h"
#include "oofnd/Encoding.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

#include <string>
#include <unordered_map>

typedef struct RunningStack RunningStack;
struct RunningStack {
    RunningStack* back;
    OOJSScript* current;
};

static JSClassID sScriptClassID;
static RunningStack* sRunningStack = NULL;

static void AddStackToArrayReversed(std::vector<oo::ObjCRef<OOJSScript*>>& array, RunningStack* stack);

static BOOL RunScriptWithName(JSContext* context, const std::optional<std::string>& path, JSValueConst object, std::optional<std::string>* outErrorMessage);

static std::optional<std::string> StrippedName(const std::optional<std::string>& string);
static NSString* RewriteLegacyConst(JSContext* context, NSString* source);
static BOOL HasModernScopeDirective(NSString* source);

#if OO_CACHE_JS_SCRIPTS
static JSValue CachedCompiledScript(JSContext* context, NSString* path, NSData* source);
static void CacheCompiledScript(JSContext* context, NSString* path, NSData* source, JSValueConst compiled);
#endif

// The value as text (its -description as an object; a string is itself): null stays nullopt.
static std::optional<std::string> DescriptionOrNil(const oo::PList& value);

// -oo_stringForKey: with its nil; a string value for -setObject:forKey:, which raised on nil.
static std::optional<std::string> StringForKey(const oo::PList& dictionary, const std::string& key);
static std::string ValueForKey(const std::optional<std::string>& value, id key);

static JSClassDef sScriptClass = {
    .class_name = "Script",
    .finalizer = OOJSObjectWrapperFinalize,
};

static const JSCFunctionListEntry sScriptMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
};

@interface OOJSScript (OOPrivate)

- (std::string)scriptNameFromPath:(const std::optional<std::string>&)path;
- (oo::PList::Dict)defaultPropertiesFromPath:(const std::optional<std::string>&)path;
- (void)checkForTickle:(JSContext*)context;

@end

@implementation OOJSScript

+ (id)scriptWithPath:(const std::optional<std::string>&)path properties:(const oo::PList&)properties
{
    return [[[self alloc] initWithPath:path properties:properties] autorelease];
}

- (id)initWithPath:(const std::optional<std::string>&)path properties:(const oo::PList&)properties
{
    JSContext* context = NULL;
    std::optional<std::string> problem; // Acts as error flag.

    self = [super init];
    if (self == nil)
        problem = "allocation failure";
    else {
        context = OOJSAcquireContext();

        if (JS_HasException(context)) {
            JS_FreeValue(context, JS_GetException(context));
            OO_LOG_ERR("script.javaScript.load.waitingException", "Prior to loading script {}, there was a pending JavaScript exception, which has been cleared. This is an internal error, please report it.", path.value_or("(null)"));
        }

        // Set up JS object
        if (!problem.has_value()) {
            _jsSelf = JS_NewObjectClass(context, (int)sScriptClassID);
            if (JS_IsException(_jsSelf)) {
                JS_FreeValue(context, JS_GetException(context));
                _jsSelf = JS_UNDEFINED;
                problem = "allocation failure";
            }
        }

        if (!problem.has_value()) {
            JS_SetOpaque(_jsSelf, OOConsumeReference([self weakRetain]));
        }

        // Push self on stack of running scripts.
        RunningStack stackElement = {
            .back = sRunningStack,
            .current = self
        };
        sRunningStack = &stackElement;

        filePath = path;

        // Set default properties from manifest.plist
        // Order-sensitive: the properties are set in key order (they were set in hash order).
        const oo::PList::Dict defaultProperties = [self defaultPropertiesFromPath:path];
        for (const auto& [key, property] : defaultProperties) {
            if (key == kLocalManifestProperty) {
                // this must not be editable
                [self defineProperty:oo::ObjectFromPList(property) named:key];
            } else {
                // can be overwritten by script itself
                [self setProperty:oo::ObjectFromPList(property) named:key];
            }
        }

        // Set properties. (read-only)
        // Order-sensitive: defined in key order (they were defined in hash order).
        if (!problem.has_value() && !properties.isNull()) {
            if (const oo::PList::Dict* propertyDict = properties.getIf<oo::PList::Dict>()) {
                for (const auto& [key, property] : *propertyDict) {
                    [self defineProperty:oo::ObjectFromPList(property) named:key];
                }
            }
        }

        /*	Set initial name (in case of script error during initial run).
                The "name" ivar is not set here, so the property can be fetched from JS
                if we fail during setup. However, the "name" ivar is set later so that
                the script object can't be renamed after the initial run. This could
                probably also be achieved by fiddling with JS property attributes.
        */
        JSAtom nameID = OOJSID("name");
        [self setProperty:oo::NSStringFrom([self scriptNameFromPath:path]) withID:nameID inContext:context];

        // Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
        if (!problem.has_value()) {
            OO_LOG("script.javaScript.willLoad", "About to load JavaScript {}", path.value_or("(null)"));
            oo::log::indentIf("script.javaScript.willLoad");

            if (!RunScriptWithName(context, path, _jsSelf, &problem)) {
                if (!problem.has_value())
                    problem = "could not run script";
            }
        }

        sRunningStack = stackElement.back;

        if (!problem.has_value()) {
            [self checkForTickle:context];

            // Get display attributes from script
            name.reset();
            name = StrippedName(DescriptionOrNil([self cxx_propertyWithID:nameID inContext:context]));
            if (!name.has_value()) {
                name = [self scriptNameFromPath:path];
                [self setProperty:oo::NSStringFrom(*name) withID:nameID inContext:context];
            }

            version = DescriptionOrNil([self cxx_propertyWithID:OOJSID("version") inContext:context]);
            description = DescriptionOrNil([self cxx_propertyWithID:OOJSID("description") inContext:context]);

            OO_LOG("script.javaScript.load.success", "Loaded JavaScript: {} -- {}", [self displayName].value_or("(null)"), description.value_or("(no description)"));
        }

        oo::log::outdentIf("script.javaScript.willLoad");

        filePath.reset(); // Only used for error reporting during startup.
    }

    if (problem.has_value()) {
        OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- {}", path.value_or("(null)"), *problem);
        if (context != NULL && JS_HasException(context))
            OOJSReportPendingException(context);
        DESTROY(self);
    }

    OOJSRelinquishContext(context);

    if (self != nil) {
        oo::NotificationCenter::defaultCenter().addObserver(self, kOOJavaScriptEngineWillResetNotificationName,
            [OOJavaScriptEngine sharedEngine],
            [self](const oo::Notification& notification) { [self javaScriptEngineWillReset:notification]; });
    }

    return self;
}

- (void)dealloc
{
    oo::NotificationCenter::defaultCenter().removeObserver(self, kOOJavaScriptEngineWillResetNotificationName,
        [OOJavaScriptEngine sharedEngine]);

    if (JS_IsObject(_jsSelf)) {
        JSContext* context = OOJSAcquireContext();

        // Release weakref to self, as the finalizer would; the JS object may outlive us.
        JSClassID ignored;
        [(id)JS_GetAnyOpaque(_jsSelf, &ignored) release];
        JS_SetOpaque(_jsSelf, NULL);
        JS_FreeValue(context, _jsSelf);
        _jsSelf = JS_UNDEFINED;

        OOJSRelinquishContext(context);
    }

    [weakSelf weakRefDrop];

    [super dealloc];
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return std::string("Script");
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    if (JS_IsObject(_jsSelf))
        return [super cxx_descriptionComponents];
    else
        return "invalid script";
}

- (void)javaScriptEngineWillReset:(const oo::Notification&)notification
{
    // All scripts become invalid when the JS engine resets.
    if (JS_IsObject(_jsSelf)) {
        JS_FreeValue(OOJSAcquireContext(), _jsSelf);
        _jsSelf = JS_UNDEFINED;
    }
}

+ (OOJSScript*)currentlyRunningScript
{
    if (sRunningStack == NULL)
        return NULL;
    return sRunningStack->current;
}

+ (std::vector<oo::ObjCRef<OOJSScript*>>)scriptStack
{
    std::vector<oo::ObjCRef<OOJSScript*>> result;

    AddStackToArrayReversed(result, sRunningStack);
    return result;
}

- (id)weakRetain
{
    if (weakSelf == nil)
        weakSelf = [OOWeakReference weakRefWithObject:self];
    return [weakSelf retain];
}

- (void)weakRefDied:(OOWeakReference*)weakRef
{
    if (weakRef == weakSelf)
        weakSelf = nil;
}

- (std::optional<std::string>)cxx_name
{
    // (the property as text: a string is itself, anything else its -description)
    if (!name.has_value())
        name = DescriptionOrNil([self cxx_propertyNamed:"name"]);
    if (!name.has_value())
        return [self scriptNameFromPath:filePath]; // Special case for parse errors during load.
    return name;
}

- (std::optional<std::string>)scriptDescription
{
    return description;
}

- (std::optional<std::string>)cxx_version
{
    return version;
}

- (void)runWithTarget:(Entity*)target
{
}

- (BOOL)callMethod:(JSAtom)methodID
         inContext:(JSContext*)context
     withArguments:(JSValueConst*)argv
             count:(int)argc
            result:(JSValue*)outResult
{
    OOParameterAssert(name.has_value() && (argv != NULL || argc == 0) && context != NULL);
    if (outResult != NULL)
        *outResult = JS_UNDEFINED;
    if (!JS_IsObject(_jsSelf))
        return NO;

    BOOL OK = NO;

    JSValue method = JS_GetProperty(context, _jsSelf, methodID);
    if (EXPECT_NOT(JS_IsException(method))) {
        OOJSReportPendingException(context);
        return NO;
    }

    if (EXPECT(!JS_IsUndefined(method))) {
#ifndef NDEBUG
        if (JS_HasException(context)) {
            OO_LOG("script.internalBug", "Exception pending on context before calling method in {}, clearing. This is an internal error, please report it.", __PRETTY_FUNCTION__);
            JS_FreeValue(context, JS_GetException(context));
        }

        OO_LOG("script.javaScript.call", "Calling [{}].{}()", [self cxx_name].value_or("(null)"), (cxx_OOStringFromJSID(methodID)).value_or("(null)"));
        oo::log::indentIf("script.javaScript.call");
#endif

        // Push self on stack of running scripts.
        RunningStack stackElement = {
            .back = sRunningStack,
            .current = self
        };
        sRunningStack = &stackElement;

        // Call the method.
        OOJSStartTimeLimiter();
        JSValue result = JS_Call(context, method, _jsSelf, argc, argv);
        OOJSStopTimeLimiter();

        if (JS_IsException(result)) {
            OOJSReportPendingException(context);
            OK = NO;
        } else {
            OK = YES;
            if (outResult != NULL)
                *outResult = result;
            else
                JS_FreeValue(context, result);
        }

        // Pop running scripts stack
        sRunningStack = stackElement.back;

#ifndef NDEBUG
        oo::log::outdentIf("script.javaScript.call");
#endif
    }

    JS_FreeValue(context, method);
    return OK;
}

- (oo::PList)cxx_propertyWithID:(JSAtom)propID inContext:(JSContext*)context
{
    OOParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return oo::PList();

    JSValue jsValue = JS_GetProperty(context, _jsSelf, propID);
    if (JS_IsException(jsValue)) {
        JS_FreeValue(context, JS_GetException(context));
        return oo::PList();
    }

    oo::PList result = cxx_OOJSPListFromJSValue(context, jsValue);
    JS_FreeValue(context, jsValue);
    return result;
}

- (BOOL)setProperty:(id)value withID:(JSAtom)propID inContext:(JSContext*)context
{
    OOParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return NO;

    // JS_SetProperty() takes ownership of the value.
    return JS_SetProperty(context, _jsSelf, propID, OOJSValueFromNativeObject(context, value)) >= 0;
}

- (BOOL)defineProperty:(id)value withID:(JSAtom)propID inContext:(JSContext*)context
{
    OOParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return NO;

    // JS_DefinePropertyValue() takes ownership of the value.
    return JS_DefinePropertyValue(context, _jsSelf, propID, OOJSValueFromNativeObject(context, value), OOJS_PROP_READONLY) >= 0;
}

- (oo::PList)cxx_propertyNamed:(const std::string&)propName
{
    if (!JS_IsObject(_jsSelf))
        return oo::PList();

    JSContext* context = OOJSAcquireContext();
    oo::PList result = [self cxx_propertyWithID:cxx_OOJSIDFromString(propName) inContext:context];
    OOJSRelinquishContext(context);

    return result;
}

- (BOOL)setProperty:(id)value named:(const std::string&)propName
{
    if (value == nil)
        return NO;
    if (!JS_IsObject(_jsSelf))
        return NO;

    JSContext* context = OOJSAcquireContext();
    BOOL result = [self setProperty:value withID:cxx_OOJSIDFromString(propName) inContext:context];
    OOJSRelinquishContext(context);

    return result;
}

- (BOOL)defineProperty:(id)value named:(const std::string&)propName
{
    if (value == nil)
        return NO;
    if (!JS_IsObject(_jsSelf))
        return NO;

    JSContext* context = OOJSAcquireContext();
    BOOL result = [self defineProperty:value withID:cxx_OOJSIDFromString(propName) inContext:context];
    OOJSRelinquishContext(context);

    return result;
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    if (!JS_IsObject(_jsSelf))
        return JS_UNDEFINED;
    return JS_DupValue(context, _jsSelf);
}

+ (void)pushScript:(OOJSScript*)script
{
    RunningStack* element = NULL;

    element = (RunningStack*)malloc(sizeof *element);
    if (element == NULL)
        exit(EXIT_FAILURE);

    element->back = sRunningStack;
    element->current = script;
    sRunningStack = element;
}

+ (void)popScript:(OOJSScript*)script
{
    RunningStack* element = NULL;

    assert(sRunningStack->current == script);

    element = sRunningStack;
    sRunningStack = sRunningStack->back;
    free(element);
}

@end

@implementation OOJSScript (OOPrivate)

/*	Generate default name for script which doesn't set its name property when
        first run.

        The generated name is <name>.anon-script, where <name> is selected as
        follows:
        * If path is nil (futureproofing), use the address of the script object.
        * If the file's name is something other than script.*, use the file name.
        * If the containing directory is something other than Config, use the
        containing directory's name.
        * Otherwise, use the containing directory's parent (which will generally
                                                                                                                be an OXP root directory).
        * If either of the two previous steps results in an empty string, fall
        back on the full path.
*/
- (std::string)scriptNameFromPath:(const std::optional<std::string>&)path
{
    std::string lastComponent;
    std::string truncatedPath;
    std::string theName;

    if (!path.has_value())
        theName = oo::str::pointerDescription(self);
    else {
        lastComponent = oo::str::lastPathComponent(*path);
        if (!oo::str::hasPrefix(lastComponent, "script."))
            theName = lastComponent;
        else {
            truncatedPath = oo::str::deletingLastPathComponent(*path);
            if (0 == oo::str::caseInsensitiveCompare(oo::str::lastPathComponent(truncatedPath), "Config")) {
                truncatedPath = oo::str::deletingLastPathComponent(truncatedPath);
            }
            const std::string extension = oo::str::pathExtension(truncatedPath);
            if (0 == oo::str::caseInsensitiveCompare(extension, "oxp")) {
                // -stringByDeletingPathExtension: the ".oxp" at the end goes (the path has no trailing
                // separator, having just lost a component).
                truncatedPath.resize(truncatedPath.size() - extension.size() - 1);
            }

            lastComponent = oo::str::lastPathComponent(truncatedPath);
            theName = lastComponent;
        }
    }

    if (theName.empty())
        theName = path.value_or("");

    return *StrippedName(theName + ".anon-script");
}

- (oo::PList::Dict)defaultPropertiesFromPath:(const std::optional<std::string>&)path
{
    // remove file name, remove OXP subfolder, add manifest.plist (a nil path messaged nil: no manifest)
    oo::PList manifest = path.has_value() ? cxx_OOPropertyListFromFile(oo::str::appendingPathComponent(oo::str::deletingLastPathComponent(oo::str::deletingLastPathComponent(*path)), "manifest.plist")) : oo::PList();
    if (!manifest.isDict())
        manifest = oo::PList(); // a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
    oo::PList::Dict properties;
    /* __oolite.tmp.* is allocated for OXPs without manifests. Its
     * values are meaningless and shouldn't be used here */
    const std::optional<std::string> identifier = StringForKey(manifest, std::string(kOOManifestIdentifier));
    if (manifest && !(identifier.has_value() && oo::str::hasPrefix(*identifier, "__oolite.tmp."))) {
        if (manifest.get<oo::PList>(std::string(kOOManifestVersion)) != nullptr) {
            properties["version"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestVersion)), @"version");
        }
        if (manifest.get<oo::PList>(std::string(kOOManifestIdentifier)) != nullptr) {
            // used for system info
            properties[kLocalManifestProperty] = ValueForKey(identifier, oo::NSStringFrom(kLocalManifestProperty));
        }
        if (manifest.get<oo::PList>(std::string(kOOManifestAuthor)) != nullptr) {
            properties["author"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestAuthor)), @"author");
        }
        if (manifest.get<oo::PList>(std::string(kOOManifestLicense)) != nullptr) {
            properties["license"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestLicense)), @"license");
        }
    }
    return properties;
}

/*	Complain about scripts using the tickle event handler. SpiderMonkey
        reported this from the class's addProperty hook; QuickJS has no such
        hook, so check once the script's top level has run (which is where
        handlers are normally defined).
*/
- (void)checkForTickle:(JSContext*)context
{
    JSValue tickle = JS_GetPropertyStr(context, _jsSelf, "tickle");
    if (JS_IsException(tickle)) {
        JS_FreeValue(context, JS_GetException(context));
    } else if (!JS_IsUndefined(tickle)) {
        cxx_OOJSReportWarning(context, "Script %s appears to use the tickle() event handler, which is no longer supported.", [self cxx_name].value_or("(null)").c_str());
    }
    JS_FreeValue(context, tickle);
}

@end

@implementation OOScript (JavaScriptEvents)

- (BOOL)callMethod:(JSAtom)methodID
         inContext:(JSContext*)context
     withArguments:(JSValueConst*)argv
             count:(int)argc
            result:(JSValue*)outResult
{
    if (outResult != NULL)
        *outResult = JS_UNDEFINED;
    return NO;
}

@end

void InitOOJSScript(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sScriptClassID, &sScriptClass);
    OOJSInitClass(context, global, sScriptClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, NULL, 0, sScriptMethods, OOJS_COUNT(sScriptMethods), NULL, 0);
    OOJSRegisterObjectConverter(sScriptClassID, OOJSBasicPrivateObjectConverter);
}

static void AddStackToArrayReversed(std::vector<oo::ObjCRef<OOJSScript*>>& array, RunningStack* stack)
{
    if (stack != NULL) {
        AddStackToArrayReversed(array, stack->back);
        // -addObject: raised on the nil a script-less push leaves (GNUstep 1.31.1's text).
        if (stack->current == nil)
            [OOException raise:OOInvalidArgumentException format:"Tried to add nil to array"];
        array.emplace_back(stack->current);
    }
}

/*	Compile and run a script file with object as its this and, unless the
        script opts out with the "use oolite modern" directive, at the head of
        its scope chain.
*/
static BOOL RunScriptWithName(JSContext* context, const std::optional<std::string>& path, JSValueConst object, std::optional<std::string>* outErrorMessage)
{
    std::optional<std::string> utf8Contents;

    OOCParameterAssert(outErrorMessage != NULL);
    outErrorMessage->reset();

    // decodeUnicodeText (it read through .oxz archives)
    if (path.has_value()) {
        if (const std::optional<oo::Data> bytes = OODataFromOXZFile(*path))
            utf8Contents = oo::str::decodeUnicodeText(bytes->stringView());
    }
    if (!utf8Contents.has_value()) {
        *outErrorMessage = "could not load file";
        return NO;
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    /* FIXME: this isn't strictly the right test, since strict
     * mode can be enabled with this string within a function
     * definition, but it seems unlikely anyone is actually doing
     * that here. */
    if (utf8Contents->find("\"use strict\";") == std::string::npos && utf8Contents->find("'use strict';") == std::string::npos) {
        cxx_OOStandardsDeprecated("Script " + oo::DescriptionOf(oo::NSStringOrNil(path)) + " does not \"use strict\";");
        if (OOEnforceStandards()) {
            // prepend it anyway (before wrapping: see OOJSWrapScriptSource())
            // TODO: some time after 1.82, make this required
            utf8Contents = "\"use strict\";\n" + *utf8Contents;
        }
    }
#endif

    // The scoping and caching below still work on the Foundation string.
    NSString* fileContents = oo::NSStringFrom(*utf8Contents);

    /*	Scripts marked with the "use oolite modern" directive (for example by
            tools/oxp-upgrade) don't rely on SpiderMonkey 1.8.5 scoping, so they
            run without its emulation: no with(this) and no const rewrite.
    */
    BOOL modern = HasModernScopeDirective(fileContents);
    if (modern) {
        OO_LOG("script.javaScript.load.modern", "Script {} uses modern scoping.", oo::DescriptionOf(oo::NSStringOrNil(path)));
        NSString* lineEnd = [fileContents hasSuffix:@"\n"] ? @"" : @"\n";
        fileContents = [NSString stringWithFormat:@"(function(){%@%@})", fileContents, lineEnd];
    } else {
        fileContents = [NSString stringWithFormat:@"(function(){%@})", OOJSWrapScriptSource(RewriteLegacyConst(context, fileContents))];
    }

    /*	QuickJS runs compiled (and cached) code only with the global object as
            its this (JS_EvalFunction()), so the wrapped script is compiled as a
            function expression, which is then called with the script object as
            this. The extra prefix is on the first line, so line numbers are
            unchanged.
    */
    NSString* wrapped = fileContents;
    NSData* source = [wrapped dataUsingEncoding:NSUTF8StringEncoding];

    JSValue compiled = JS_UNDEFINED;
#if OO_CACHE_JS_SCRIPTS
    compiled = CachedCompiledScript(context, oo::NSStringOrNil(path), source);
#endif

    if (JS_IsUndefined(compiled)) {
        NSMutableData* terminated = [NSMutableData dataWithData:source];
        [terminated appendBytes:"" length:1]; // JS_Eval requires a terminating NUL.

        compiled = JS_Eval(context, (const char*)[terminated bytes], [source length], path.has_value() ? path->c_str() : NULL, JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY);
        if (JS_IsException(compiled)) {
            OOJSReportPendingException(context);
            *outErrorMessage = "compilation failed";
            return NO;
        }
#if OO_CACHE_JS_SCRIPTS
        CacheCompiledScript(context, oo::NSStringOrNil(path), source, compiled);
#endif
    }

    OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
    JSValue result;
    JSValue function = JS_EvalFunction(context, compiled); // Takes ownership of compiled.
    if (JS_IsException(function)) {
        result = function;
    } else {
        result = JS_Call(context, function, object, 0, NULL);
        JS_FreeValue(context, function);
    }
    OOJSStopTimeLimiter();

    if (JS_IsException(result)) {
        OOJSReportPendingException(context);
        *outErrorMessage = "could not run script";
        return NO;
    }

    JS_FreeValue(context, result);
    return YES;
}

#if OO_CACHE_JS_SCRIPTS
/*	Compiled scripts are cached by path, like the SpiderMonkey version's XDR
        data, but under a different cache name. Each entry also records a hash of
        the exact text that was compiled (after the const rewrite and wrapping),
        the QuickJS version and the entry format, and is only used if all three
        match. As before, the whole cache is cleared when the Oolite version or
        the search paths change (see OOCacheManager and ResourceManager).
*/
static NSString* const kCompiledScriptCache = @"compiled QuickJS scripts";
static NSString* const kCompiledScriptKeyHash = @"source hash";
static NSString* const kCompiledScriptKeyEngine = @"engine";
static NSString* const kCompiledScriptKeyFormat = @"format";
static NSString* const kCompiledScriptKeyBytecode = @"bytecode";
enum {
    kCompiledScriptFormat = 1 // Increment when the compiled text or the way it is run changes.
};

// 64-bit FNV-1a and length. Only needs to detect changed source, not resist tampering.
static NSString* SourceHash(NSData* source)
{
    const uint8_t* bytes = (const uint8_t*)[source bytes];
    NSUInteger length = [source length];
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (NSUInteger i = 0; i < length; i++) {
        hash ^= bytes[i];
        hash *= 0x100000001b3ULL;
    }
    return [NSString stringWithFormat:@"%016llx:%lu", (unsigned long long)hash, (unsigned long)length];
}

// Owned compiled script from the cache, or JS_UNDEFINED if there is no usable entry.
static JSValue CachedCompiledScript(JSContext* context, NSString* path, NSData* source)
{
    NSDictionary* entry = [[OOCacheManager sharedCache] cxx_objectForKey:oo::StdString(path) inCache:oo::StdString(kCompiledScriptCache)];
    if (![entry isKindOfClass:[NSDictionary class]])
        return JS_UNDEFINED;

    NSData* bytecode = [entry objectForKey:kCompiledScriptKeyBytecode];
    if (![bytecode isKindOfClass:[NSData class]]
        || oo::PListView(entry).get<unsigned int>(kCompiledScriptKeyFormat) != kCompiledScriptFormat
        || ![oo::PListView(entry).get<NSString*>(kCompiledScriptKeyEngine) isEqualToString:[NSString stringWithUTF8String:JS_GetVersion()]]
        || ![oo::PListView(entry).get<NSString*>(kCompiledScriptKeyHash) isEqualToString:SourceHash(source)]) {
        OO_LOG("script.javaScript.cache.stale", "Compiled script cache entry for {} is out of date.", oo::DescriptionOf(path));
        return JS_UNDEFINED;
    }

    // Trusted input: the cache is written only by CacheCompiledScript().
    JSValue compiled = JS_ReadObject(context, (const uint8_t*)[bytecode bytes], [bytecode length], JS_READ_OBJ_BYTECODE);
    if (JS_IsException(compiled)) {
        JS_FreeValue(context, JS_GetException(context));
        OO_LOG("script.javaScript.cache.readFailed", "Could not read compiled script cache entry for {}; compiling instead.", oo::DescriptionOf(path));
        return JS_UNDEFINED;
    }

    OO_LOG("script.javaScript.cache.load", "Loaded compiled script {} from cache.", oo::DescriptionOf(path));
    return compiled;
}

static void CacheCompiledScript(JSContext* context, NSString* path, NSData* source, JSValueConst compiled)
{
    size_t length = 0;
    uint8_t* bytes = JS_WriteObject(context, &length, compiled, JS_WRITE_OBJ_BYTECODE);
    if (bytes == NULL) {
        if (JS_HasException(context))
            JS_FreeValue(context, JS_GetException(context));
        return;
    }

    NSData* bytecode = [NSData dataWithBytes:bytes length:length];
    js_free(context, bytes);

    NSDictionary* entry = [NSDictionary dictionaryWithObjectsAndKeys:
            bytecode, kCompiledScriptKeyBytecode,
        SourceHash(source), kCompiledScriptKeyHash,
        [NSString stringWithUTF8String:JS_GetVersion()], kCompiledScriptKeyEngine,
        [NSNumber numberWithUnsignedInt:kCompiledScriptFormat], kCompiledScriptKeyFormat,
        nil];

    [[OOCacheManager sharedCache] cxx_setObject:entry forKey:oo::StdString(path) inCache:oo::StdString(kCompiledScriptCache)];
    OO_LOG("script.javaScript.cache.store", "Cached compiled script {}.", oo::DescriptionOf(path));
}
#endif

/*	Whether the script's directive prologue (the string literal statements
        at its start, like "use strict") includes "use oolite modern".
*/
static BOOL HasModernScopeDirective(NSString* source)
{
    NSUInteger length = [source length];
    NSUInteger i = 0;
    if (length > 0 && [source characterAtIndex:0] == 0xFEFF)
        i = 1;

    for (;;) {
        // Skip white space and comments.
        BOOL skipped = YES;
        while (skipped && i < length) {
            skipped = NO;
            unichar c = [source characterAtIndex:i];
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == 0xA0 || c == 0xFEFF) {
                i++;
                skipped = YES;
            } else if (c == '/' && i + 1 < length && [source characterAtIndex:i + 1] == '/') {
                while (i < length && [source characterAtIndex:i] != '\n')
                    i++;
                skipped = YES;
            } else if (c == '/' && i + 1 < length && [source characterAtIndex:i + 1] == '*') {
                NSRange end = [source rangeOfString:@"*/" options:0 range:NSMakeRange(i + 2, length - i - 2)];
                if (end.location == NSNotFound)
                    return NO;
                i = end.location + 2;
                skipped = YES;
            }
        }
        if (i >= length)
            return NO;

        // A directive: a string literal, followed by ; or a line break.
        unichar quote = [source characterAtIndex:i];
        if (quote != '"' && quote != '\'')
            return NO;
        NSUInteger start = ++i;
        BOOL escaped = NO;
        while (i < length && [source characterAtIndex:i] != quote) {
            unichar c = [source characterAtIndex:i];
            if (c == '\\') {
                escaped = YES;
                i++;
            }
            if (c == '\n')
                return NO;
            i++;
        }
        if (i >= length)
            return NO;
        NSString* directive = [source substringWithRange:NSMakeRange(start, i - start)];
        i++;

        BOOL lineBreak = NO;
        while (i < length) {
            unichar c = [source characterAtIndex:i];
            if (c == '\n') {
                lineBreak = YES;
            } else if (c == '/' && i + 1 < length && [source characterAtIndex:i + 1] == '/') {
                while (i < length && [source characterAtIndex:i] != '\n')
                    i++;
                continue;
            } else if (c != ' ' && c != '\t' && c != '\r') {
                break;
            }
            i++;
        }
        if (i < length && [source characterAtIndex:i] == ';')
            i++;
        else if (!lineBreak && i < length && [source characterAtIndex:i] != '}')
            return NO; // Part of a larger expression, so not a directive.

        if (!escaped && [directive isEqualToString:@"use oolite modern"])
            return YES;
    }
}

/*	In SpiderMonkey 1.8.5, const declarations were function-scoped and usable
        before the declaration, like var; under ES2015 rules they are
        block-scoped with a temporal dead zone, which breaks some OXPs. The
        compatibility script's const rewriter (OOJSLegacyConstRewriter()) replaces the const
        keyword with var (keeping line and column positions).

        The rewriter is interpreted JavaScript, and a ship script is loaded again
        for every ship that uses it, so results are kept for the rest of the
        session, keyed by the source text.
*/
static NSString* RewriteLegacyConst(JSContext* context, NSString* source)
{
    static std::unordered_map<std::string, std::string> sRewritten;

    if ([source rangeOfString:@"const"].location == NSNotFound)
        return source;

    const auto cached = sRewritten.find(oo::StdString(source));
    if (cached != sRewritten.end())
        return oo::NSStringOrNil(cached->second);

    JSValueConst rewriter = OOJSLegacyConstRewriter();
    NSString* result = source;

    if (JS_IsFunction(context, rewriter)) {
        JSValue argument = OOJSValueFromNativeObject(context, source);
        JSValue rewritten = JS_Call(context, rewriter, JS_UNDEFINED, 1, (JSValueConst*)&argument);
        if (JS_IsException(rewritten)) {
            OOJSReportPendingException(context);
        } else {
            result = oo::NSStringOrNil(cxx_OOStringFromJSValue(context, rewritten)) ?: source;
            sRewritten.emplace(oo::StdString(source), oo::StdString(result));
        }
        JS_FreeValue(context, rewritten);
        JS_FreeValue(context, argument);
    }

    return result;
}

// -stringByTrimmingCharactersInSet: of "_", space, tab, LF, CR and VT (all ASCII, so UTF-8 bytes).
static std::optional<std::string> StrippedName(const std::optional<std::string>& string)
{
    if (!string.has_value())
        return std::nullopt;
    static constexpr std::string_view kInvalid = "_ \t\n\r\v";
    const std::size_t first = string->find_first_not_of(kInvalid);
    if (first == std::string::npos)
        return std::string();
    const std::size_t last = string->find_last_not_of(kInvalid);
    return string->substr(first, last - first + 1);
}

static std::optional<std::string> DescriptionOrNil(const oo::PList& value)
{
    if (value.isNull())
        return std::nullopt;
    if (const std::string* string = value.getIf<std::string>())
        return *string; // a string's -description is itself
    // Anything else prints as the object form did (cxx_OOJSPListFromJSValue() is oo::PListFrom() of it).
    return oo::DescriptionOf(value);
}

// -oo_stringForKey: with its nil: the string, a number's -stringValue, or nothing.
static std::optional<std::string> StringForKey(const oo::PList& dictionary, const std::string& key)
{
    const oo::PList* value = dictionary.get<oo::PList>(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dictionary.get<std::string>(key);
}

// A string value for -setObject:forKey:, which raised on nil (GNUstep 1.31.1's text).
static std::string ValueForKey(const std::optional<std::string>& value, id key)
{
    if (!value.has_value())
        [OOException raise:OOInvalidArgumentException format:"Tried to add nil value for key '%s' to dictionary", oo::DescriptionOf(key).c_str()];
    return *value;
}
