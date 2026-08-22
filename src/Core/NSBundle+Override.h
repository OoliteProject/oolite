#import <Foundation/Foundation.h>

@interface NSBundle (ResourceOverride)

// Declaring the swizzled method signature ensures clean compilation
// if referenced internally and establishes the category interface.
- (NSString *)oolite_resourcePath;

@end