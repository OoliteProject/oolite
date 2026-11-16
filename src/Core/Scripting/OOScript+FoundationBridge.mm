/*

OOScript+FoundationBridge.mm

TRANSITIONAL: see OOScript+FoundationBridge.h. Each method forwards to its cxx_ counterpart and
converts arguments and results at the boundary (nil for nil; the properties dictionary, which may
hold live objects, through oo::PListFrom).

*/

#import "OOFoundationBridge.h"
#import "OOScript.h" // declares the bridge category at its end

@implementation OOScript (OOFoundationBridge)

+ (NSArray*)worldScriptsAtPath:(NSString*)path
{
    if (path == nil)
        return nil; // every path built from nil was nil: nothing was found
    std::optional<std::vector<oo::ObjCRef<OOScript*>>> scripts = [self cxx_worldScriptsAtPath:oo::StdString(path)];
    return scripts.has_value() ? oo::NSArrayFromObjects(*scripts) : nil;
}

+ (id)jsScriptFromFileNamed:(NSString*)fileName properties:(NSDictionary*)properties
{
    return [self cxx_jsScriptFromFileNamed:oo::StdString(fileName) properties:oo::PListFrom(properties)];
}

+ (id)jsAIScriptFromFileNamed:(NSString*)fileName properties:(NSDictionary*)properties
{
    return [self cxx_jsAIScriptFromFileNamed:oo::StdString(fileName) properties:oo::PListFrom(properties)];
}

@end
