#import <Foundation/Foundation.h>

@interface NSBundle (ResourceOverride)

- (NSString *)oolite_resolvedResourcesPath;
- (NSString *)oolite_resourcePath;
- (NSDictionary *)oolite_infoDictionary;

@end