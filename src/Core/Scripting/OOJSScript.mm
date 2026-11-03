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
#import "OOLogging.h"
#import "OOManifestProperties.h"
#import "OOPListParsing.h"
#include "oofnd/Encoding.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

#include "oofnd/String.hpp"

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
static std::string RewriteLegacyConst(JSContext* context, const std::string& source);
static BOOL HasModernScopeDirective(std::string_view source);

#if OO_CACHE_JS_SCRIPTS
static JSValue CachedCompiledScript(JSContext* context, const std::string& path, std::string_view source);
static void CacheCompiledScript(JSContext* context, const std::string& path, std::string_view source, JSValueConst compiled);
#endif

// The value as text (its -description as an object; a string is itself): null stays nullopt.
static std::optional<std::string> DescriptionOrNil(const oo::PList& value);

// -oo_stringForKey: with its nil; a string value for -setObject:forKey:, which raised on nil.
static std::optional<std::string> StringForKey(const oo::PList& dictionary, const std::string& key);
static std::string ValueForKey(const std::optional<std::string>& value, std::string_view key);

static JSClassDef sScriptClass = {
    .class_name = "Script",
    .finalizer = OOJSObjectWrapperFinalize,
};

static const JSCFunctionListEntry sScriptMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
};

namespace cxx {

bool OOJSScript::initWithPath(const std::optional<std::string>& path, const oo::PList& properties)
{
    JSContext* context = NULL;
    std::optional<std::string> problem; // Acts as error flag.

    // (the facade's [super init] ran before this, and failed with nil: "allocation failure")
    {
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
            JS_SetOpaque(_jsSelf, OOConsumeReference(weakRetain()));
        }

        // Push self on stack of running scripts.
        RunningStack stackElement = {
            .back = sRunningStack,
            .current = oo::ToObjC(this)
        };
        sRunningStack = &stackElement;

        _filePath = path;

        // Set default properties from manifest.plist
        // Order-sensitive: the properties are set in key order (they were set in hash order).
        const oo::PList::Dict defaultProperties = defaultPropertiesFromPath(path);
        for (const auto& [key, property] : defaultProperties) {
            if (key == kLocalManifestProperty) {
                // this must not be editable
                defineProperty(property, key);
            } else {
                // can be overwritten by script itself
                setProperty(property, key);
            }
        }

        // Set properties. (read-only)
        // Order-sensitive: defined in key order (they were defined in hash order).
        if (!problem.has_value() && !properties.isNull()) {
            if (const oo::PList::Dict* propertyDict = properties.getIf<oo::PList::Dict>()) {
                for (const auto& [key, property] : *propertyDict) {
                    defineProperty(property, key);
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
        setProperty(oo::PList(scriptNameFromPath(path)), nameID, context);

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
            checkForTickle(context);

            // Get display attributes from script
            _name.reset();
            _name = StrippedName(DescriptionOrNil(propertyWithID(nameID, context)));
            if (!_name.has_value()) {
                _name = scriptNameFromPath(path);
                setProperty(oo::PList(*_name), nameID, context);
            }

            _version = DescriptionOrNil(propertyWithID(OOJSID("version"), context));
            _description = DescriptionOrNil(propertyWithID(OOJSID("description"), context));

            OO_LOG("script.javaScript.load.success", "Loaded JavaScript: {} -- {}", displayName().value_or("(null)"), _description.value_or("(no description)"));
        }

        oo::log::outdentIf("script.javaScript.willLoad");

        _filePath.reset(); // Only used for error reporting during startup.
    }

    if (problem.has_value()) {
        OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- {}", path.value_or("(null)"), *problem);
        if (context != NULL && JS_HasException(context))
            OOJSReportPendingException(context);
        // (was DESTROY(self) here: the facade releases itself when this answers false, after the
        // context below is relinquished)
    }

    OOJSRelinquishContext(context);

    if (!problem.has_value()) {
        oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
            [::OOJavaScriptEngine sharedEngine],
            [this](const oo::Notification& notification) { javaScriptEngineWillReset(notification); });
    }

    return !problem.has_value();
}

void OOJSScript::willDealloc()
{
    oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
        [::OOJavaScriptEngine sharedEngine]);

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

    [_weakSelf weakRefDrop];
}

std::optional<std::string> OOJSScript::jsClassName()
{
    return std::string("Script");
}

std::optional<std::string> OOJSScript::descriptionComponents()
{
    if (JS_IsObject(_jsSelf))
        return OOScript::descriptionComponents();
    else
        return "invalid script";
}

void OOJSScript::javaScriptEngineWillReset(const oo::Notification&)
{
    // All scripts become invalid when the JS engine resets.
    if (JS_IsObject(_jsSelf)) {
        JS_FreeValue(OOJSAcquireContext(), _jsSelf);
        _jsSelf = JS_UNDEFINED;
    }
}

::OOJSScript* OOJSScript::currentlyRunningScript()
{
    if (sRunningStack == NULL)
        return NULL;
    return sRunningStack->current;
}

std::vector<oo::ObjCRef<::OOJSScript*>> OOJSScript::scriptStack()
{
    std::vector<oo::ObjCRef<::OOJSScript*>> result;

    AddStackToArrayReversed(result, sRunningStack);
    return result;
}

id OOJSScript::weakRetain()
{
    if (_weakSelf == nil)
        _weakSelf = [::OOWeakReference weakRefWithObject:oo::ToObjC(this)];
    return [_weakSelf retain];
}

void OOJSScript::weakRefDied(::OOWeakReference* weakRef)
{
    if (weakRef == _weakSelf)
        _weakSelf = nil;
}

std::optional<std::string> OOJSScript::name()
{
    // (the property as text: a string is itself, anything else its -description)
    if (!_name.has_value())
        _name = DescriptionOrNil(propertyNamed("name"));
    if (!_name.has_value())
        return scriptNameFromPath(_filePath); // Special case for parse errors during load.
    return _name;
}

std::optional<std::string> OOJSScript::scriptDescription()
{
    return _description;
}

std::optional<std::string> OOJSScript::version()
{
    return _version;
}

void OOJSScript::runWithTarget(::Entity*)
{
}

bool OOJSScript::callMethod(JSAtom methodID,
    JSContext* context,
    JSValueConst* argv, int argc,
    JSValue* outResult)
{
    OOCParameterAssert(_name.has_value() && (argv != NULL || argc == 0) && context != NULL);
    if (outResult != NULL)
        *outResult = JS_UNDEFINED;
    if (!JS_IsObject(_jsSelf))
        return false;

    bool OK = false;

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

        OO_LOG("script.javaScript.call", "Calling [{}].{}()", name().value_or("(null)"), (cxx_OOStringFromJSID(methodID)).value_or("(null)"));
        oo::log::indentIf("script.javaScript.call");
#endif

        // Push self on stack of running scripts.
        RunningStack stackElement = {
            .back = sRunningStack,
            .current = oo::ToObjC(this)
        };
        sRunningStack = &stackElement;

        // Call the method.
        OOJSStartTimeLimiter();
        JSValue result = JS_Call(context, method, _jsSelf, argc, argv);
        OOJSStopTimeLimiter();

        if (JS_IsException(result)) {
            OOJSReportPendingException(context);
            OK = false;
        } else {
            OK = true;
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

oo::PList OOJSScript::propertyWithID(JSAtom propID, JSContext* context)
{
    OOCParameterAssert(context != NULL);
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

bool OOJSScript::setProperty(const oo::PList& value, JSAtom propID, JSContext* context)
{
    OOCParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return false;

    // JS_SetProperty() takes ownership of the value.
    return JS_SetProperty(context, _jsSelf, propID, OOJSValueFromPList(context, value)) >= 0;
}

bool OOJSScript::defineProperty(const oo::PList& value, JSAtom propID, JSContext* context)
{
    OOCParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return false;

    // JS_DefinePropertyValue() takes ownership of the value.
    return JS_DefinePropertyValue(context, _jsSelf, propID, OOJSValueFromPList(context, value), OOJS_PROP_READONLY) >= 0;
}

oo::PList OOJSScript::propertyNamed(const std::string& propName)
{
    if (!JS_IsObject(_jsSelf))
        return oo::PList();

    JSContext* context = OOJSAcquireContext();
    oo::PList result = propertyWithID(cxx_OOJSIDFromString(propName), context);
    OOJSRelinquishContext(context);

    return result;
}

bool OOJSScript::setProperty(const oo::PList& value, const std::string& propName)
{
    if (value.isNull())
        return false;
    if (!JS_IsObject(_jsSelf))
        return false;

    JSContext* context = OOJSAcquireContext();
    bool result = setProperty(value, cxx_OOJSIDFromString(propName), context);
    OOJSRelinquishContext(context);

    return result;
}

bool OOJSScript::defineProperty(const oo::PList& value, const std::string& propName)
{
    if (value.isNull())
        return false;
    if (!JS_IsObject(_jsSelf))
        return false;

    JSContext* context = OOJSAcquireContext();
    bool result = defineProperty(value, cxx_OOJSIDFromString(propName), context);
    OOJSRelinquishContext(context);

    return result;
}

JSValue OOJSScript::jsValueInContext(JSContext* context)
{
    if (!JS_IsObject(_jsSelf))
        return JS_UNDEFINED;
    return JS_DupValue(context, _jsSelf);
}

void OOJSScript::pushScript(::OOJSScript* script)
{
    RunningStack* element = NULL;

    element = (RunningStack*)malloc(sizeof *element);
    if (element == NULL)
        exit(EXIT_FAILURE);

    element->back = sRunningStack;
    element->current = script;
    sRunningStack = element;
}

void OOJSScript::popScript(::OOJSScript* script)
{
    RunningStack* element = NULL;

    assert(sRunningStack->current == script);

    element = sRunningStack;
    sRunningStack = sRunningStack->back;
    free(element);
}

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
std::string OOJSScript::scriptNameFromPath(const std::optional<std::string>& path)
{
    std::string lastComponent;
    std::string truncatedPath;
    std::string theName;

    if (!path.has_value())
        theName = oo::str::pointerDescription(oo::ToObjC(this)); // (the facade's address, as self's was)
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

oo::PList::Dict OOJSScript::defaultPropertiesFromPath(const std::optional<std::string>& path)
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
            properties["version"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestVersion)), "version");
        }
        if (manifest.get<oo::PList>(std::string(kOOManifestIdentifier)) != nullptr) {
            // used for system info
            properties[kLocalManifestProperty] = ValueForKey(identifier, kLocalManifestProperty);
        }
        if (manifest.get<oo::PList>(std::string(kOOManifestAuthor)) != nullptr) {
            properties["author"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestAuthor)), "author");
        }
        if (manifest.get<oo::PList>(std::string(kOOManifestLicense)) != nullptr) {
            properties["license"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestLicense)), "license");
        }
    }
    return properties;
}

/*	Complain about scripts using the tickle event handler. SpiderMonkey
        reported this from the class's addProperty hook; QuickJS has no such
        hook, so check once the script's top level has run (which is where
        handlers are normally defined).
*/
void OOJSScript::checkForTickle(JSContext* context)
{
    JSValue tickle = JS_GetPropertyStr(context, _jsSelf, "tickle");
    if (JS_IsException(tickle)) {
        JS_FreeValue(context, JS_GetException(context));
    } else if (!JS_IsUndefined(tickle)) {
        cxx_OOJSReportWarning(context, "Script %s appears to use the tickle() event handler, which is no longer supported.", name().value_or("(null)").c_str());
    }
    JS_FreeValue(context, tickle);
}

} // namespace cxx

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
        cxx_OOStandardsDeprecated("Script " + path.value_or("(null)") + " does not \"use strict\";"); // "%@" of the path
        if (OOEnforceStandards()) {
            // prepend it anyway (before wrapping: see OOJSWrapScriptSource())
            // TODO: some time after 1.82, make this required
            utf8Contents = "\"use strict\";\n" + *utf8Contents;
        }
    }
#endif

    /*	Scripts marked with the "use oolite modern" directive (for example by
            tools/oxp-upgrade) don't rely on SpiderMonkey 1.8.5 scoping, so they
            run without its emulation: no with(this) and no const rewrite.
    */
    std::string wrapped;
    BOOL modern = HasModernScopeDirective(*utf8Contents);
    if (modern) {
        OO_LOG("script.javaScript.load.modern", "Script {} uses modern scoping.", path.value_or("(null)"));
        const char* lineEnd = oo::str::hasSuffix(*utf8Contents, "\n") ? "" : "\n";
        wrapped = "(function(){" + *utf8Contents + lineEnd + "})";
    } else {
        wrapped = "(function(){" + OOJSWrapScriptSource(RewriteLegacyConst(context, *utf8Contents)) + "})";
    }

    /*	QuickJS runs compiled (and cached) code only with the global object as
            its this (JS_EvalFunction()), so the wrapped script is compiled as a
            function expression, which is then called with the script object as
            this. The extra prefix is on the first line, so line numbers are
            unchanged.
    */
    JSValue compiled = JS_UNDEFINED;
#if OO_CACHE_JS_SCRIPTS
    compiled = CachedCompiledScript(context, path.value_or(""), wrapped); // (a nil path was the key "")
#endif

    if (JS_IsUndefined(compiled)) {
        // JS_Eval requires a terminating NUL, which std::string's c_str() has.
        compiled = JS_Eval(context, wrapped.c_str(), wrapped.size(), path.has_value() ? path->c_str() : NULL, JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY);
        if (JS_IsException(compiled)) {
            OOJSReportPendingException(context);
            *outErrorMessage = "compilation failed";
            return NO;
        }
#if OO_CACHE_JS_SCRIPTS
        CacheCompiledScript(context, path.value_or(""), wrapped, compiled);
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
static constexpr char kCompiledScriptCache[] = "compiled QuickJS scripts";
static constexpr char kCompiledScriptKeyHash[] = "source hash";
static constexpr char kCompiledScriptKeyEngine[] = "engine";
static constexpr char kCompiledScriptKeyFormat[] = "format";
static constexpr char kCompiledScriptKeyBytecode[] = "bytecode";
enum {
    kCompiledScriptFormat = 1 // Increment when the compiled text or the way it is run changes.
};

// 64-bit FNV-1a and length. Only needs to detect changed source, not resist tampering.
static std::string SourceHash(std::string_view source)
{
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (char c : source) {
        hash ^= static_cast<unsigned char>(c);
        hash *= 0x100000001b3ULL;
    }
    return oo::str::format("%016llx:%lu", (unsigned long long)hash, (unsigned long)source.size());
}

// The entry's member, or null.
static const oo::PList* EntryMember(const oo::PList::Dict& entry, const char* key)
{
    auto found = entry.find(key);
    return (found != entry.end()) ? &found->second : nullptr;
}

// Owned compiled script from the cache, or JS_UNDEFINED if there is no usable entry.
static JSValue CachedCompiledScript(JSContext* context, const std::string& path, std::string_view source)
{
    const oo::PList cached = [[OOCacheManager sharedCache] cxx_pListForKey:path inCache:kCompiledScriptCache];
    const oo::PList::Dict* entry = cached.getIf<oo::PList::Dict>();
    if (entry == nullptr)
        return JS_UNDEFINED;

    const oo::PList* bytecode = EntryMember(*entry, kCompiledScriptKeyBytecode);
    const oo::PList* format = EntryMember(*entry, kCompiledScriptKeyFormat);
    const oo::PList* engine = EntryMember(*entry, kCompiledScriptKeyEngine);
    const oo::PList* hash = EntryMember(*entry, kCompiledScriptKeyHash);
    const oo::Data* bytecodeData = (bytecode != nullptr) ? bytecode->getIf<oo::PList::Data>() : nullptr;
    const oo::PList::Integer* formatNumber = (format != nullptr) ? format->getIf<oo::PList::Integer>() : nullptr;
    const std::string* engineName = (engine != nullptr) ? engine->getIf<std::string>() : nullptr;
    const std::string* hashText = (hash != nullptr) ? hash->getIf<std::string>() : nullptr;
    if (bytecodeData == nullptr
        || formatNumber == nullptr || formatNumber->value != kCompiledScriptFormat
        || engineName == nullptr || *engineName != JS_GetVersion()
        || hashText == nullptr || *hashText != SourceHash(source)) {
        OO_LOG("script.javaScript.cache.stale", "Compiled script cache entry for {} is out of date.", path);
        return JS_UNDEFINED;
    }

    // Trusted input: the cache is written only by CacheCompiledScript().
    JSValue compiled = JS_ReadObject(context, bytecodeData->bytes(), bytecodeData->length(), JS_READ_OBJ_BYTECODE);
    if (JS_IsException(compiled)) {
        JS_FreeValue(context, JS_GetException(context));
        OO_LOG("script.javaScript.cache.readFailed", "Could not read compiled script cache entry for {}; compiling instead.", path);
        return JS_UNDEFINED;
    }

    OO_LOG("script.javaScript.cache.load", "Loaded compiled script {} from cache.", path);
    return compiled;
}

static void CacheCompiledScript(JSContext* context, const std::string& path, std::string_view source, JSValueConst compiled)
{
    size_t length = 0;
    uint8_t* bytes = JS_WriteObject(context, &length, compiled, JS_WRITE_OBJ_BYTECODE);
    if (bytes == NULL) {
        if (JS_HasException(context))
            JS_FreeValue(context, JS_GetException(context));
        return;
    }

    oo::Data bytecode(bytes, length);
    js_free(context, bytes);

    oo::PList::Dict entry;
    entry.emplace(kCompiledScriptKeyBytecode, oo::PList(std::move(bytecode)));
    entry.emplace(kCompiledScriptKeyHash, oo::PList(SourceHash(source)));
    entry.emplace(kCompiledScriptKeyEngine, oo::PList(std::string(JS_GetVersion())));
    entry.emplace(kCompiledScriptKeyFormat, oo::PList::unsignedInteger(kCompiledScriptFormat));

    [[OOCacheManager sharedCache] cxx_setPList:oo::PList(std::move(entry)) forKey:path inCache:kCompiledScriptCache];
    OO_LOG("script.javaScript.cache.store", "Cached compiled script {}.", path);
}
#endif

/*	Whether the script's directive prologue (the string literal statements
        at its start, like "use strict") includes "use oolite modern". The
        source is UTF-8; the white space it skips includes U+00A0 and U+FEFF,
        as the UTF-16 scan did.
*/
static BOOL HasModernScopeDirective(std::string_view source)
{
    const std::size_t length = source.size();
    std::size_t i = 0;
    auto byteAt = [&](std::size_t k) { return static_cast<unsigned char>(source[k]); };
    auto isBOM = [&](std::size_t k) { return k + 2 < length && byteAt(k) == 0xEF && byteAt(k + 1) == 0xBB && byteAt(k + 2) == 0xBF; };
    auto isNBSP = [&](std::size_t k) { return k + 1 < length && byteAt(k) == 0xC2 && byteAt(k + 1) == 0xA0; };

    if (isBOM(0))
        i = 3;

    for (;;) {
        // Skip white space and comments.
        BOOL skipped = YES;
        while (skipped && i < length) {
            skipped = NO;
            char c = source[i];
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                i++;
                skipped = YES;
            } else if (isNBSP(i)) {
                i += 2;
                skipped = YES;
            } else if (isBOM(i)) {
                i += 3;
                skipped = YES;
            } else if (c == '/' && i + 1 < length && source[i + 1] == '/') {
                while (i < length && source[i] != '\n')
                    i++;
                skipped = YES;
            } else if (c == '/' && i + 1 < length && source[i + 1] == '*') {
                std::size_t end = source.find("*/", i + 2);
                if (end == std::string_view::npos)
                    return NO;
                i = end + 2;
                skipped = YES;
            }
        }
        if (i >= length)
            return NO;

        // A directive: a string literal, followed by ; or a line break.
        char quote = source[i];
        if (quote != '"' && quote != '\'')
            return NO;
        std::size_t start = ++i;
        BOOL escaped = NO;
        while (i < length && source[i] != quote) {
            char c = source[i];
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
        std::string_view directive = source.substr(start, i - start);
        i++;

        BOOL lineBreak = NO;
        while (i < length) {
            char c = source[i];
            if (c == '\n') {
                lineBreak = YES;
            } else if (c == '/' && i + 1 < length && source[i + 1] == '/') {
                while (i < length && source[i] != '\n')
                    i++;
                continue;
            } else if (c != ' ' && c != '\t' && c != '\r') {
                break;
            }
            i++;
        }
        if (i < length && source[i] == ';')
            i++;
        else if (!lineBreak && i < length && source[i] != '}')
            return NO; // Part of a larger expression, so not a directive.

        if (!escaped && directive == "use oolite modern")
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
static std::string RewriteLegacyConst(JSContext* context, const std::string& source)
{
    static std::unordered_map<std::string, std::string> sRewritten;

    if (source.find("const") == std::string::npos)
        return source;

    const auto cached = sRewritten.find(source);
    if (cached != sRewritten.end())
        return cached->second;

    JSValueConst rewriter = OOJSLegacyConstRewriter();
    std::string result = source;

    if (JS_IsFunction(context, rewriter)) {
        JSValue argument = JS_NewStringLen(context, source.data(), source.size());
        JSValue rewritten = JS_Call(context, rewriter, JS_UNDEFINED, 1, (JSValueConst*)&argument);
        if (JS_IsException(rewritten)) {
            OOJSReportPendingException(context);
        } else {
            result = cxx_OOStringFromJSValue(context, rewritten).value_or(source);
            sRewritten.emplace(source, result);
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
static std::string ValueForKey(const std::optional<std::string>& value, std::string_view key)
{
    if (!value.has_value())
        [OOException raise:OOInvalidArgumentException format:"Tried to add nil value for key '%s' to dictionary", std::string(key).c_str()];
    return *value;
}
