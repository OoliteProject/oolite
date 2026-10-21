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

#import "Entity.h"
#import "EntityOOJavaScriptExtensions.h"
#import "NSStringOOExtensions.h"
#import "OOCollectionExtractors.h"
#if OO_CACHE_JS_SCRIPTS
#import "OOCacheManager.h"
#endif
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OODebugStandards.h"
#import "OOLogging.h"
#import "OOManifestProperties.h"
#import "OOPListParsing.h"

typedef struct RunningStack RunningStack;
struct RunningStack {
    RunningStack* back;
    OOJSScript* current;
};

static JSClassID sScriptClassID;
static RunningStack* sRunningStack = NULL;

static void AddStackToArrayReversed(NSMutableArray* array, RunningStack* stack);

static BOOL RunScriptWithName(JSContext* context, NSString* path, JSValueConst object, NSString** outErrorMessage);

static NSString* StrippedName(NSString* string);
static NSString* RewriteLegacyConst(JSContext* context, NSString* source);
static BOOL HasModernScopeDirective(NSString* source);

#if OO_CACHE_JS_SCRIPTS
static JSValue CachedCompiledScript(JSContext* context, NSString* path, NSData* source);
static void CacheCompiledScript(JSContext* context, NSString* path, NSData* source, JSValueConst compiled);
#endif

static JSClassDef sScriptClass = {
    .class_name = "Script",
    .finalizer = OOJSObjectWrapperFinalize,
};

static const JSCFunctionListEntry sScriptMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
};

@interface OOJSScript (OOPrivate)

- (NSString*)scriptNameFromPath:(NSString*)path;
- (NSDictionary*)defaultPropertiesFromPath:(NSString*)path;
- (void)checkForTickle:(JSContext*)context;

@end

@implementation OOJSScript

+ (id)scriptWithPath:(NSString*)path properties:(NSDictionary*)properties
{
    return [[[self alloc] initWithPath:path properties:properties] autorelease];
}

- (id)initWithPath:(NSString*)path properties:(NSDictionary*)properties
{
    JSContext* context = NULL;
    NSString* problem = nil; // Acts as error flag.
    NSString* key = nil;
    id property = nil;

    self = [super init];
    if (self == nil)
        problem = @"allocation failure";
    else {
        context = OOJSAcquireContext();

        if (JS_HasException(context)) {
            JS_FreeValue(context, JS_GetException(context));
            OOLogERR(@"script.javaScript.load.waitingException", @"Prior to loading script %@, there was a pending JavaScript exception, which has been cleared. This is an internal error, please report it.", path);
        }

        // Set up JS object
        if (!problem) {
            _jsSelf = JS_NewObjectClass(context, (int)sScriptClassID);
            if (JS_IsException(_jsSelf)) {
                JS_FreeValue(context, JS_GetException(context));
                _jsSelf = JS_UNDEFINED;
                problem = @"allocation failure";
            }
        }

        if (!problem) {
            JS_SetOpaque(_jsSelf, OOConsumeReference([self weakRetain]));
        }

        // Push self on stack of running scripts.
        RunningStack stackElement = {
            .back = sRunningStack,
            .current = self
        };
        sRunningStack = &stackElement;

        filePath = [path retain];

        // Set default properties from manifest.plist
        NSDictionary* defaultProperties = [self defaultPropertiesFromPath:path];
        foreachkey(key, defaultProperties)
        {
            if ([key isKindOfClass:[NSString class]]) {
                property = [defaultProperties objectForKey:key];
                if ([key isEqualToString:kLocalManifestProperty]) {
                    // this must not be editable
                    [self defineProperty:property named:key];
                } else {
                    // can be overwritten by script itself
                    [self setProperty:property named:key];
                }
            }
        }

        // Set properties. (read-only)
        if (!problem && properties != nil) {
            foreachkey(key, properties)
            {
                if ([key isKindOfClass:[NSString class]]) {
                    property = [properties objectForKey:key];
                    [self defineProperty:property named:key];
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
        [self setProperty:[self scriptNameFromPath:path] withID:nameID inContext:context];

        // Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
        if (!problem) {
            OOLog(@"script.javaScript.willLoad", @"About to load JavaScript %@", path);
            OOLogIndentIf(@"script.javaScript.willLoad");

            if (!RunScriptWithName(context, path, _jsSelf, &problem)) {
                if (problem == nil)
                    problem = @"could not run script";
            }
        }

        sRunningStack = stackElement.back;

        if (!problem) {
            [self checkForTickle:context];

            // Get display attributes from script
            DESTROY(name);
            name = [StrippedName([[self propertyWithID:nameID inContext:context] description]) copy];
            if (name == nil) {
                name = [[self scriptNameFromPath:path] retain];
                [self setProperty:name withID:nameID inContext:context];
            }

            version = [[[self propertyWithID:OOJSID("version") inContext:context] description] copy];
            description = [[[self propertyWithID:OOJSID("description") inContext:context] description] copy];

            OOLog(@"script.javaScript.load.success", @"Loaded JavaScript: %@ -- %@", [self displayName], description ? description : (NSString*)@"(no description)");
        }

        OOLogOutdentIf(@"script.javaScript.willLoad");

        DESTROY(filePath); // Only used for error reporting during startup.
    }

    if (problem) {
        OOLog(@"script.javaScript.load.failed", @"***** Error loading JavaScript script %@ -- %@", path, problem);
        if (context != NULL && JS_HasException(context))
            OOJSReportPendingException(context);
        DESTROY(self);
    }

    OOJSRelinquishContext(context);

    if (self != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(javaScriptEngineWillReset:)
                                                     name:kOOJavaScriptEngineWillResetNotification
                                                   object:[OOJavaScriptEngine sharedEngine]];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kOOJavaScriptEngineWillResetNotification
                                                  object:[OOJavaScriptEngine sharedEngine]];

    DESTROY(name);
    DESTROY(description);
    DESTROY(version);
    DESTROY(filePath);

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

- (NSString*)oo_jsClassName
{
    return @"Script";
}

- (NSString*)descriptionComponents
{
    if (JS_IsObject(_jsSelf))
        return [super descriptionComponents];
    else
        return @"invalid script";
}

- (void)javaScriptEngineWillReset:(NSNotification*)notification
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

+ (NSArray*)scriptStack
{
    NSMutableArray* result = nil;

    result = [NSMutableArray array];
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

- (NSString*)name
{
    if (name == nil)
        name = [[self propertyNamed:@"name"] copy];
    if (name == nil)
        return [self scriptNameFromPath:filePath]; // Special case for parse errors during load.
    return name;
}

- (NSString*)scriptDescription
{
    return description;
}

- (NSString*)version
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
    NSParameterAssert(name != NULL && (argv != NULL || argc == 0) && context != NULL);
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
            OOLog(@"script.internalBug", @"Exception pending on context before calling method in %s, clearing. This is an internal error, please report it.", __PRETTY_FUNCTION__);
            JS_FreeValue(context, JS_GetException(context));
        }

        OOLog(@"script.javaScript.call", @"Calling [%@].%@()", [self name], OOStringFromJSID(methodID));
        OOLogIndentIf(@"script.javaScript.call");
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
        OOLogOutdentIf(@"script.javaScript.call");
#endif
    }

    JS_FreeValue(context, method);
    return OK;
}

- (id)propertyWithID:(JSAtom)propID inContext:(JSContext*)context
{
    NSParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return nil;

    JSValue jsValue = JS_GetProperty(context, _jsSelf, propID);
    if (JS_IsException(jsValue)) {
        JS_FreeValue(context, JS_GetException(context));
        return nil;
    }

    id result = OOJSNativeObjectFromJSValue(context, jsValue);
    JS_FreeValue(context, jsValue);
    return result;
}

- (BOOL)setProperty:(id)value withID:(JSAtom)propID inContext:(JSContext*)context
{
    NSParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return NO;

    // JS_SetProperty() takes ownership of the value.
    return JS_SetProperty(context, _jsSelf, propID, OOJSValueFromNativeObject(context, value)) >= 0;
}

- (BOOL)defineProperty:(id)value withID:(JSAtom)propID inContext:(JSContext*)context
{
    NSParameterAssert(context != NULL);
    if (!JS_IsObject(_jsSelf))
        return NO;

    // JS_DefinePropertyValue() takes ownership of the value.
    return JS_DefinePropertyValue(context, _jsSelf, propID, OOJSValueFromNativeObject(context, value), OOJS_PROP_READONLY) >= 0;
}

- (id)propertyNamed:(NSString*)propName
{
    if (propName == nil)
        return nil;
    if (!JS_IsObject(_jsSelf))
        return nil;

    JSContext* context = OOJSAcquireContext();
    id result = [self propertyWithID:OOJSIDFromString(propName) inContext:context];
    OOJSRelinquishContext(context);

    return result;
}

- (BOOL)setProperty:(id)value named:(NSString*)propName
{
    if (value == nil || propName == nil)
        return NO;
    if (!JS_IsObject(_jsSelf))
        return NO;

    JSContext* context = OOJSAcquireContext();
    BOOL result = [self setProperty:value withID:OOJSIDFromString(propName) inContext:context];
    OOJSRelinquishContext(context);

    return result;
}

- (BOOL)defineProperty:(id)value named:(NSString*)propName
{
    if (value == nil || propName == nil)
        return NO;
    if (!JS_IsObject(_jsSelf))
        return NO;

    JSContext* context = OOJSAcquireContext();
    BOOL result = [self defineProperty:value withID:OOJSIDFromString(propName) inContext:context];
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

    element = malloc(sizeof *element);
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
- (NSString*)scriptNameFromPath:(NSString*)path
{
    NSString* lastComponent = nil;
    NSString* truncatedPath = nil;
    NSString* theName = nil;

    if (path == nil)
        theName = [NSString stringWithFormat:@"%p", self];
    else {
        lastComponent = [path lastPathComponent];
        if (![lastComponent hasPrefix:@"script."])
            theName = lastComponent;
        else {
            truncatedPath = [path stringByDeletingLastPathComponent];
            if (NSOrderedSame == [[truncatedPath lastPathComponent] caseInsensitiveCompare:@"Config"]) {
                truncatedPath = [truncatedPath stringByDeletingLastPathComponent];
            }
            if (NSOrderedSame == [[truncatedPath pathExtension] caseInsensitiveCompare:@"oxp"]) {
                truncatedPath = [truncatedPath stringByDeletingPathExtension];
            }

            lastComponent = [truncatedPath lastPathComponent];
            theName = lastComponent;
        }
    }

    if (0 == [theName length])
        theName = path;

    return StrippedName([theName stringByAppendingString:@".anon-script"]);
}

- (NSDictionary*)defaultPropertiesFromPath:(NSString*)path
{
    // remove file name, remove OXP subfolder, add manifest.plist
    NSString* manifestPath = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"manifest.plist"];
    NSDictionary* manifest = OODictionaryFromFile(manifestPath);
    NSMutableDictionary* properties = [NSMutableDictionary dictionaryWithCapacity:3];
    /* __oolite.tmp.* is allocated for OXPs without manifests. Its
     * values are meaningless and shouldn't be used here */
    if (manifest != nil && ![[manifest oo_stringForKey:kOOManifestIdentifier] hasPrefix:@"__oolite.tmp."]) {
        if ([manifest objectForKey:kOOManifestVersion] != nil) {
            [properties setObject:[manifest oo_stringForKey:kOOManifestVersion] forKey:@"version"];
        }
        if ([manifest objectForKey:kOOManifestIdentifier] != nil) {
            // used for system info
            [properties setObject:[manifest oo_stringForKey:kOOManifestIdentifier] forKey:kLocalManifestProperty];
        }
        if ([manifest objectForKey:kOOManifestAuthor] != nil) {
            [properties setObject:[manifest oo_stringForKey:kOOManifestAuthor] forKey:@"author"];
        }
        if ([manifest objectForKey:kOOManifestLicense] != nil) {
            [properties setObject:[manifest oo_stringForKey:kOOManifestLicense] forKey:@"license"];
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
        OOJSReportWarning(context, @"Script %@ appears to use the tickle() event handler, which is no longer supported.", [self name]);
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

static void AddStackToArrayReversed(NSMutableArray* array, RunningStack* stack)
{
    if (stack != NULL) {
        AddStackToArrayReversed(array, stack->back);
        [array addObject:stack->current];
    }
}

/*	Compile and run a script file with object as its this and, unless the
        script opts out with the "use oolite modern" directive, at the head of
        its scope chain.
*/
static BOOL RunScriptWithName(JSContext* context, NSString* path, JSValueConst object, NSString** outErrorMessage)
{
    NSString* fileContents = nil;

    NSCParameterAssert(outErrorMessage != NULL);
    *outErrorMessage = nil;

    fileContents = [NSString stringWithContentsOfUnicodeFile:path];
    if (fileContents == nil) {
        *outErrorMessage = @"could not load file";
        return NO;
    }

#ifndef NDEBUG
    /* FIXME: this isn't strictly the right test, since strict
     * mode can be enabled with this string within a function
     * definition, but it seems unlikely anyone is actually doing
     * that here. */
    if ([fileContents rangeOfString:@"\"use strict\";"].location == NSNotFound && [fileContents rangeOfString:@"'use strict';"].location == NSNotFound) {
        OOStandardsDeprecated([NSString stringWithFormat:@"Script %@ does not \"use strict\";", path]);
        if (OOEnforceStandards()) {
            // prepend it anyway (before wrapping: see OOJSWrapScriptSource())
            // TODO: some time after 1.82, make this required
            fileContents = [@"\"use strict\";\n" stringByAppendingString:fileContents];
        }
    }
#endif

    /*	Scripts marked with the "use oolite modern" directive (for example by
            tools/oxp-upgrade) don't rely on SpiderMonkey 1.8.5 scoping, so they
            run without its emulation: no with(this) and no const rewrite.
    */
    BOOL modern = HasModernScopeDirective(fileContents);
    if (modern) {
        OOLog(@"script.javaScript.load.modern", @"Script %@ uses modern scoping.", path);
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
    compiled = CachedCompiledScript(context, path, source);
#endif

    if (JS_IsUndefined(compiled)) {
        NSMutableData* terminated = [NSMutableData dataWithData:source];
        [terminated appendBytes:"" length:1]; // JS_Eval requires a terminating NUL.

        compiled = JS_Eval(context, [terminated bytes], [source length], [path UTF8String], JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY);
        if (JS_IsException(compiled)) {
            OOJSReportPendingException(context);
            *outErrorMessage = @"compilation failed";
            return NO;
        }
#if OO_CACHE_JS_SCRIPTS
        CacheCompiledScript(context, path, source, compiled);
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
        *outErrorMessage = @"could not run script";
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
    const uint8_t* bytes = [source bytes];
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
    NSDictionary* entry = [[OOCacheManager sharedCache] objectForKey:path inCache:kCompiledScriptCache];
    if (![entry isKindOfClass:[NSDictionary class]])
        return JS_UNDEFINED;

    NSData* bytecode = [entry objectForKey:kCompiledScriptKeyBytecode];
    if (![bytecode isKindOfClass:[NSData class]]
        || [entry oo_unsignedIntForKey:kCompiledScriptKeyFormat] != kCompiledScriptFormat
        || ![[entry oo_stringForKey:kCompiledScriptKeyEngine] isEqualToString:[NSString stringWithUTF8String:JS_GetVersion()]]
        || ![[entry oo_stringForKey:kCompiledScriptKeyHash] isEqualToString:SourceHash(source)]) {
        OOLog(@"script.javaScript.cache.stale", @"Compiled script cache entry for %@ is out of date.", path);
        return JS_UNDEFINED;
    }

    // Trusted input: the cache is written only by CacheCompiledScript().
    JSValue compiled = JS_ReadObject(context, [bytecode bytes], [bytecode length], JS_READ_OBJ_BYTECODE);
    if (JS_IsException(compiled)) {
        JS_FreeValue(context, JS_GetException(context));
        OOLog(@"script.javaScript.cache.readFailed", @"Could not read compiled script cache entry for %@; compiling instead.", path);
        return JS_UNDEFINED;
    }

    OOLog(@"script.javaScript.cache.load", @"Loaded compiled script %@ from cache.", path);
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

    [[OOCacheManager sharedCache] setObject:entry forKey:path inCache:kCompiledScriptCache];
    OOLog(@"script.javaScript.cache.store", @"Cached compiled script %@.", path);
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
        compatibility script's __ooliteRewriteLegacyConst() replaces the const
        keyword with var (keeping line and column positions).
*/
static NSString* RewriteLegacyConst(JSContext* context, NSString* source)
{
    if ([source rangeOfString:@"const"].location == NSNotFound)
        return source;

    JSValue global = JS_GetGlobalObject(context);
    JSValue rewriter = JS_GetPropertyStr(context, global, "__ooliteRewriteLegacyConst");
    NSString* result = source;

    if (JS_IsFunction(context, rewriter)) {
        JSValue argument = OOJSValueFromNativeObject(context, source);
        JSValue rewritten = JS_Call(context, rewriter, global, 1, (JSValueConst*)&argument);
        if (JS_IsException(rewritten))
            OOJSReportPendingException(context);
        else
            result = OOStringFromJSValue(context, rewritten) ?: source;
        JS_FreeValue(context, rewritten);
        JS_FreeValue(context, argument);
    }

    JS_FreeValue(context, rewriter);
    JS_FreeValue(context, global);
    return result;
}

static NSString* StrippedName(NSString* string)
{
    static NSCharacterSet* invalidSet = nil;
    if (invalidSet == nil)
        invalidSet = [[NSCharacterSet characterSetWithCharactersInString:@"_ \t\n\r\v"] retain];

    return [string stringByTrimmingCharactersInSet:invalidSet];
}
