/*

OOStringParsing+FoundationBridge.mm

TRANSITIONAL: see OOStringParsing+FoundationBridge.h. Each function forwards to its cxx_
counterpart and converts the result exactly as the old function produced it (nil for nil,
the same mutable/immutable collections).

*/

#import "OOFoundation.h"
#import "OOFoundationBridge.h"
#import "OOStringParsing.h" // declares the bridge at its end

// oo-3rb.124: scanners, points, random seeds

NSMutableArray* ScanTokensFromString(NSString* values)
{
    // a nil string has no tokens, as before
    return [NSMutableArray arrayWithArray:oo::NSArrayFromStrings(oo::str::tokens(oo::StdString(values)))];
}

BOOL ScanVectorFromString(NSString* xyzString, Vector* outVector)
{
    return cxx_ScanVectorFromString(oo::OptionalString(xyzString), outVector);
}

BOOL ScanHPVectorFromString(NSString* xyzString, HPVector* outVector)
{
    return cxx_ScanHPVectorFromString(oo::OptionalString(xyzString), outVector);
}

BOOL ScanQuaternionFromString(NSString* wxyzString, Quaternion* outQuaternion)
{
    return cxx_ScanQuaternionFromString(oo::OptionalString(wxyzString), outQuaternion);
}

BOOL ScanVectorAndQuaternionFromString(NSString* xyzwxyzString, Vector* outVector, Quaternion* outQuaternion)
{
    return cxx_ScanVectorAndQuaternionFromString(oo::OptionalString(xyzwxyzString), outVector, outQuaternion);
}

Vector VectorFromString(NSString* xyzString, Vector defaultValue)
{
    return cxx_VectorFromString(oo::OptionalString(xyzString), defaultValue);
}

Quaternion QuaternionFromString(NSString* wxyzString, Quaternion defaultValue)
{
    return cxx_QuaternionFromString(oo::OptionalString(wxyzString), defaultValue);
}

NSString* StringFromPoint(NSPoint point)
{
    return oo::NSStringFrom(cxx_StringFromPoint(point));
}

NSPoint PointFromString(NSString* xyString)
{
    // nil has no tokens, as the empty string has none: the zero point either way
    return cxx_PointFromString(oo::StdString(xyString));
}

Random_Seed RandomSeedFromString(NSString* abcdefString)
{
    return cxx_RandomSeedFromString(oo::OptionalString(abcdefString));
}

NSString* StringFromRandomSeed(Random_Seed seed)
{
    return oo::NSStringFrom(cxx_StringFromRandomSeed(seed));
}

// oo-3rb.124: the NSString (OOUtilities) category, moved here verbatim

@implementation NSString (OOUtilities)

- (BOOL)pathHasExtension:(NSString*)extension
{
    return [[self pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame;
}

- (BOOL)pathHasExtensionInArray:(NSArray*)extensions
{
    NSString* extension = nil;

    foreach (extension, extensions) {
        if ([[self pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame)
            return YES;
    }

    return NO;
}

@end

// oo-3rb.125: credits, em padding, versions, clock

NSString* OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits, BOOL includeDecimal, BOOL includeSymbol)
{
    return oo::NSStringFrom(cxx_OOStringFromDeciCredits(tenthsOfCredits, includeDecimal, includeSymbol));
}

NSString* OOPadStringToEms(NSString* string, float numEms)
{
    // nil reads as the empty string (its width and length are 0 either way)
    return oo::NSStringFrom(cxx_OOPadStringToEms(oo::StdString(string), numEms));
}

NSArray* ComponentsFromVersionString(NSString* string)
{
    // nil has no components (the empty string has one, 0)
    NSMutableArray* result = [NSMutableArray array];
    if (string == nil)
        return result;
    for (unsigned value : cxx_ComponentsFromVersionString(oo::StdString(string))) {
        [result addObject:[NSNumber numberWithUnsignedInt:value]];
    }
    return result;
}

NSComparisonResult CompareVersions(NSArray* version1, NSArray* version2)
{
    std::vector<unsigned> left, right;
    id component = nil;
    foreach (component, version1)
        left.push_back([component unsignedIntValue]);
    foreach (component, version2)
        right.push_back([component unsignedIntValue]);
    return cxx_CompareVersions(left, right);
}

NSString* ClockToString(double clock, BOOL adjusting)
{
    return oo::NSStringFrom(cxx_ClockToString(clock, adjusting));
}

// oo-3rb.126: GraphViz helpers

#if DEBUG_GRAPHVIZ

NSString* EscapedGraphVizString(NSString* string)
{
    if (string == nil)
        return nil; // messaging nil answered nil
    return oo::NSStringFrom(cxx_EscapedGraphVizString(oo::StdString(string)));
}

NSString* GraphVizTokenString(NSString* string, NSMutableSet* uniqueSet)
{
    // The set's strings go in, the new token comes back out into it (a nil set stays nil).
    std::set<std::string> unique;
    if (uniqueSet != nil) {
        for (std::string& name : oo::StringsFrom(uniqueSet))
            unique.insert(std::move(name));
    }
    const std::string token = cxx_GraphVizTokenString(oo::StdString(string), uniqueSet != nil ? &unique : nullptr);
    NSString* result = oo::NSStringFrom(token);
    [uniqueSet addObject:result];
    return result;
}

#endif // DEBUG_GRAPHVIZ
