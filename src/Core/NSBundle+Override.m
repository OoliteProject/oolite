#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@implementation NSBundle (ResourceOverride)

+ (void)load {
    Class class = [self class];

    // Swizzle resourcePath
    Method origRes = class_getInstanceMethod(class, @selector(resourcePath));
    Method swizRes = class_getInstanceMethod(class, @selector(oolite_resourcePath));
    if (origRes && swizRes) {
        method_exchangeImplementations(origRes, swizRes);
    }

    // Swizzle infoDictionary
    Method origInfo = class_getInstanceMethod(class, @selector(infoDictionary));
    Method swizInfo = class_getInstanceMethod(class, @selector(oolite_infoDictionary));
    if (origInfo && swizInfo) {
        method_exchangeImplementations(origInfo, swizInfo);
    }
}

// Helper method to locate the Resources folder
- (NSString *)oolite_resolvedResourcesPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *startingDir = [fileManager currentDirectoryPath];
    NSString *primaryResourcesPath = [startingDir stringByAppendingPathComponent:@"Resources"];
    BOOL isDir = NO;

    if ([fileManager fileExistsAtPath:primaryResourcesPath isDirectory:&isDir] && isDir) {
        return primaryResourcesPath;
    }

    // Fallback: Standard Linux system layout
    NSString *fallbackPath = [[startingDir stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"share/oolite/Resources"];
    return [fallbackPath stringByStandardizingPath];
}

- (NSString *)oolite_resourcePath {
    NSString *path = [self bundlePath];
    if ([path hasSuffix:@".framework"] || [path hasSuffix:@".bundle"]) {
        return [self oolite_resourcePath]; // Original implementation
    }

    return [self oolite_resolvedResourcesPath];
}

- (NSDictionary *)oolite_infoDictionary {
    NSString *path = [self bundlePath];
    if ([path hasSuffix:@".framework"] || [path hasSuffix:@".bundle"]) {
        return [self oolite_infoDictionary]; // Original implementation
    }

    // Attempt standard loading first via original method
    NSDictionary *dict = [self oolite_infoDictionary];
    if (dict && [dict count] > 0) {
        return dict;
    }

    // Fallback: Explicitly load Info-gnustep.plist from resolved resources path
    NSString *resDir = [self oolite_resolvedResourcesPath];
    NSString *plistPath = [resDir stringByAppendingPathComponent:@"Info-gnustep.plist"];
    NSDictionary *gnustepPlist = [NSDictionary dictionaryWithContentsOfFile:plistPath];

    if (gnustepPlist) {
        return gnustepPlist;
    }

    return [NSDictionary dictionary]; // Return empty dictionary rather than nil to prevent crashes
}

@end