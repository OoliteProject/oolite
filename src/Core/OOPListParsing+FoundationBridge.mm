/*

OOPListParsing+FoundationBridge.mm

TRANSITIONAL: see OOPListParsing+FoundationBridge.h. OOPropertyListFrom* forward to their cxx_
counterparts and answer oo::ObjectFromPList of the result, which builds immutable containers as
NSPropertyListImmutable did (nil for no property list). The typed wrappers keep ValueIfClass and
its plist.wrongType log unchanged.

*/

#import "OOFoundationBridge.h"
#import "OOLogging.h"
#import "OOPListParsing.h" // declares the bridge at its end

namespace {

// Ensure that object is of desired class.
id ValueIfClass(id value, Class klass)
{
    if (value != nil && ![value isKindOfClass:klass]) {
        OOLog(@"plist.wrongType", @"Property list is wrong type - expected %@, got %@.", klass, [value class]);
        value = nil;
    }
    return value;
}

} // namespace

id OOPropertyListFromData(NSData* data, NSString* whereFrom)
{
    std::optional<oo::Data> bytes;
    if (data != nil)
        bytes = oo::Data([data bytes], [data length]);
    return oo::ObjectFromPList(cxx_OOPropertyListFromData(bytes, oo::OptionalString(whereFrom)));
}

id OOPropertyListFromFile(NSString* path)
{
    if (path == nil)
        return nil;
    return oo::ObjectFromPList(cxx_OOPropertyListFromFile(oo::StdString(path)));
}

// Wrappers which ensure that the plist contains the right type of object.
NSDictionary* OODictionaryFromData(NSData* data, NSString* whereFrom)
{
    id result = OOPropertyListFromData(data, whereFrom);
    return ValueIfClass(result, [NSDictionary class]);
}

NSDictionary* OODictionaryFromFile(NSString* path)
{
    id result = OOPropertyListFromFile(path);
    return ValueIfClass(result, [NSDictionary class]);
}

NSArray* OOArrayFromData(NSData* data, NSString* whereFrom)
{
    id result = OOPropertyListFromData(data, whereFrom);
    return ValueIfClass(result, [NSArray class]);
}

NSArray* OOArrayFromFile(NSString* path)
{
    id result = OOPropertyListFromFile(path);
    return ValueIfClass(result, [NSArray class]);
}
