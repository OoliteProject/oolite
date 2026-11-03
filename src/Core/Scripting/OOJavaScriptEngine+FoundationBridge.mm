/*

OOJavaScriptEngine+FoundationBridge.mm

TRANSITIONAL: see OOJavaScriptEngine+FoundationBridge.h. Each function forwards to its cxx_
counterpart and converts the result exactly as the old function produced it (nil for nil).
The NSString (OOJavaScriptExtensions) category retires here (ADR-0043 Amendment 1 item 7): its
-oo_jsValueInContext: and -oo_jsClassName are the JS glue for NSString objects and go with
gnustep-base.

*/

#import "OOFoundationBridge.h"
#import "OOJavaScriptEngine.h" // declares the bridge at its end

NSString* const kOOJavaScriptEngineWillResetNotification = @"org.aegidian.oolite OOJavaScriptEngine will reset";
NSString* const kOOJavaScriptEngineDidResetNotification = @"org.aegidian.oolite OOJavaScriptEngine did reset";

NSString* OOStringFromJSValueEvenIfNull(JSContext* context, JSValueConst value)
{
    return oo::NSStringOrNil(cxx_OOStringFromJSValueEvenIfNull(context, value));
}

NSString* OOStringFromJSValue(JSContext* context, JSValueConst value)
{
    return oo::NSStringOrNil(cxx_OOStringFromJSValue(context, value));
}

NSString* OOStringFromJSPropertyMagic(int magic, const JSCFunctionListEntry* list, size_t count)
{
    return oo::NSStringFrom(cxx_OOStringFromJSPropertyMagic(magic, list, count));
}

NSString* OOStringFromJSID(JSAtom propID)
{
    return oo::NSStringOrNil(cxx_OOStringFromJSID(propID));
}

JSAtom OOJSIDFromString(NSString* string)
{
    if (EXPECT_NOT(string == nil))
        return JS_ATOM_NULL;
    return cxx_OOJSIDFromString(oo::StdString(string));
}

NSString* OOJSDescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects)
{
    return oo::NSStringFrom(cxx_OOJSDescribeValue(context, value, abbreviateObjects));
}

void OOJSReportError(JSContext* context, NSString* format, ...)
{
    va_list args;

    va_start(args, format);
    OOJSReportErrorWithArguments(context, format, args);
    va_end(args);
}

void OOJSReportErrorForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...)
{
    va_list args;
    NSString* msg = nil;

    @try {
        va_start(args, format);
        msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        cxx_OOJSReportErrorForCaller(context, oo::OptionalString(scriptClass), oo::OptionalString(function), "%s", [msg UTF8String]);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

void OOJSReportErrorWithArguments(JSContext* context, NSString* format, va_list args)
{
    NSString* msg = nil;

    @try {
        msg = [[NSString alloc] initWithFormat:format arguments:args];
        cxx_OOJSReportError(context, "%s", [msg UTF8String]);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

void OOJSReportWarning(JSContext* context, NSString* format, ...)
{
    va_list args;

    va_start(args, format);
    OOJSReportWarningWithArguments(context, format, args);
    va_end(args);
}

void OOJSReportWarningForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...)
{
    va_list args;
    NSString* msg = nil;

    @try {
        va_start(args, format);
        msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        cxx_OOJSReportWarningForCaller(context, oo::OptionalString(scriptClass), oo::OptionalString(function), "%s", [msg UTF8String]);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

void OOJSReportWarningWithArguments(JSContext* context, NSString* format, va_list args)
{
    NSString* msg = nil;

    @try {
        msg = [[NSString alloc] initWithFormat:format arguments:args];
        cxx_OOJSReportWarning(context, "%s", [msg UTF8String]);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

void OOJSReportBadArguments(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, NSString* message, NSString* expectedArgsDescription)
{
    cxx_OOJSReportBadArguments(context, oo::OptionalString(scriptClass), oo::OptionalString(function), argc, argv, oo::OptionalString(message), oo::OptionalString(expectedArgsDescription));
}

BOOL OOJSArgumentListGetNumber(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed)
{
    return cxx_OOJSArgumentListGetNumber(context, oo::OptionalString(scriptClass), oo::OptionalString(function), argc, argv, outNumber, outConsumed);
}

@implementation NSString (OOJavaScriptExtensions)

+ (NSString*)stringWithJavaScriptParameters:(JSValueConst*)params count:(int)count inContext:(JSContext*)context
{
    return oo::NSStringOrNil(cxx_OOJSStringWithJavaScriptParameters(params, count, context));
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    NSData* utf8 = [self dataUsingEncoding:NSUTF8StringEncoding];
    return JS_NewStringLen(context, (const char*)[utf8 bytes], [utf8 length]);
}

+ (NSString*)concatenationOfStringsFromJavaScriptValues:(JSValueConst*)values count:(size_t)count separator:(NSString*)separator inContext:(JSContext*)context
{
    return oo::NSStringOrNil(cxx_OOJSConcatenationOfStringsFromJavaScriptValues(values, count, oo::StdString(separator), context));
}

- (NSString*)escapedForJavaScriptLiteral
{
    return oo::NSStringFrom(cxx_OOJSEscapedForJavaScriptLiteral(oo::StdString(self)));
}

- (NSString*)oo_jsClassName
{
    return @"String";
}

@end

// The JavaScript glue for Foundation objects: categories on Foundation classes, retiring with
// gnustep-base (ADR-0043 Amendment 1 item 7; moved verbatim), and their helpers.

static JSValue JSArrayFromNSArray(JSContext* context, NSArray* array)
{
    if (array == nil)
        return JS_UNDEFINED;

    JSValue result = JS_NewArray(context);
    if (JS_IsException(result))
        return JS_UNDEFINED;

    @try {
        NSUInteger i, count = [array count];
        for (i = 0; i != count; ++i) {
            // JS_SetPropertyUint32() takes ownership of the value.
            JSValue value = [[array objectAtIndex:i] oo_jsValueInContext:context];
            if (EXPECT_NOT(JS_SetPropertyUint32(context, result, (uint32_t)i, value) < 0)) {
                JS_FreeValue(context, result);
                return JS_UNDEFINED;
            }
        }
    }
    @catch (id ex) {
        JS_FreeValue(context, result);
        return JS_UNDEFINED;
    }

    return result;
}

/*	Convert an NSDictionary to a JavaScript Object.
        Only properties whose keys are either strings or non-negative NSNumbers,
        and	whose values have a non-void JS representation, are converted.
*/
static JSValue JSObjectFromNSDictionary(JSContext* context, NSDictionary* dictionary)
{
    if (dictionary == nil)
        return JS_UNDEFINED;

    JSValue result = JS_NewObject(context);
    if (JS_IsException(result))
        return JS_UNDEFINED;

    BOOL OK = YES;
    @try {
        id key = nil;
        foreachkey(key, dictionary)
        {
            JSValue value = JS_UNDEFINED;
            if ([key isKindOfClass:[NSString class]] && [key length] != 0) {
                value = [[dictionary objectForKey:key] oo_jsValueInContext:context];
                if (!JS_IsUndefined(value)) {
                    OK = JS_SetProperty(context, result, OOJSIDFromString(key), value) >= 0;
                }
            } else if ([key isKindOfClass:[NSNumber class]]) {
                int index = [key intValue];
                if (0 < index) {
                    value = [[dictionary objectForKey:key] oo_jsValueInContext:context];
                    if (!JS_IsUndefined(value)) {
                        OK = JS_SetPropertyUint32(context, result, (uint32_t)index, value) >= 0;
                    }
                }
            }

            if (EXPECT_NOT(!OK))
                break;
        }
    }
    @catch (id exception) {
        OK = NO;
    }

    if (EXPECT_NOT(!OK)) {
        JS_FreeValue(context, result);
        return JS_UNDEFINED;
    }

    return result;
}

@implementation NSObject (OOJavaScript)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_UNDEFINED;
}

- (NSString*)oo_jsClassName
{
    return nil;
}

- (NSString*)oo_jsDescription
{
    return [self oo_jsDescriptionWithClassName:[self oo_jsClassName]];
}

- (NSString*)oo_jsDescriptionWithClassName:(NSString*)className
{
    NSString* components = nil;
    NSString* description = nil;

    components = [self descriptionComponents];
    if (className == nil)
        className = [[self class] description];

    if (components != nil) {
        description = [NSString stringWithFormat:@"[%@ %@]", className, components];
    } else {
        description = [NSString stringWithFormat:@"[object %@]", className];
    }

    return description;
}

- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
}

@end

@implementation NSArray (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JSArrayFromNSArray(context, self);
}

@end

@implementation NSDictionary (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JSObjectFromNSDictionary(context, self);
}

@end

@implementation NSNumber (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    // As with SpiderMonkey, all NSNumbers (including booleans) become JS numbers.
    BOOL isFloat = NO;
    // Former NSNumber (OOExtensions) float/double objCType test.
#if __COREFOUNDATION_CFNUMBER__
    isFloat = CFNumberIsFloatType((CFNumberRef)self);
#else
    {
        const char* type = [self objCType];
        isFloat = (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0);
    }
#endif
    if (isFloat)
        return JS_NewFloat64(context, [self doubleValue]);
    return JS_NewNumber(context, (double)[self longLongValue]);
}

- (NSString*)oo_jsClassName
{
    return @"Number";
}

@end

// Integer-like property names become NSNumbers, as SpiderMonkey's int jsids did.
static id KeyForAtom(JSContext* context, JSAtom atom)
{
    NSString* key = OOStringFromJSID(atom);
    if ([key length] != 0 && [key length] < 10) {
        unichar first = [key characterAtIndex:0];
        if ((first >= '1' && first <= '9') || [key isEqualToString:@"0"]) {
            NSScanner* scanner = [NSScanner scannerWithString:key];
            int intValue;
            if ([scanner scanInt:&intValue] && [scanner isAtEnd]) {
                return [NSNumber numberWithInt:intValue];
            }
        }
    }
    return key;
}

NSDictionary* OOJSDictionaryFromJSObject(JSContext* context, JSValueConst object)
{
    JSPropertyEnum* properties = NULL;
    uint32_t i, count;

    if (JS_GetOwnPropertyNames(context, &properties, &count, object, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return nil;
    }

    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:count];
    for (i = 0; i != count; ++i) {
        id objKey = KeyForAtom(context, properties[i].atom);
        JSValue value = JS_GetProperty(context, object, properties[i].atom);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            continue;
        }

        if (objKey != nil && !JS_IsUndefined(value)) {
            id objValue = OOJSNativeObjectFromJSValue(context, value);
            if (objValue != nil) {
                [result setObject:objValue forKey:objKey];
            }
        }
        JS_FreeValue(context, value);
    }

    JS_FreePropertyEnum(context, properties, count);
    return result;
}
