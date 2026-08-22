#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@implementation NSBundle (ResourceOverride)

+ (void)load {
  // Synchronously swizzle -resourcePath when the category is loaded into memory.
  Class class = [self class];
  SEL originalSelector = @selector(resourcePath);
  SEL swizzledSelector = @selector(oolite_resourcePath);

  Method originalMethod = class_getInstanceMethod(class, originalSelector);
  Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

  if (originalMethod && swizzledMethod) {
    method_exchangeImplementations(originalMethod, swizzledMethod);
  }
}

- (NSString *)oolite_resourcePath {
  // Guard: Only apply custom path resolution to the main application bundle.
  // GNUstep internal framework bundles will fall back to default behaviour.
  if (self != [NSBundle mainBundle]) {
    return [self oolite_resourcePath];
  }

  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *startingDir = [fileManager currentDirectoryPath];  // Start from cwd

  NSString *primaryResourcesPath = [startingDir stringByAppendingPathComponent:@"Resources"];
  BOOL isDir = NO;

  NSString *resourcesFolder = nil;
  if ([fileManager fileExistsAtPath:primaryResourcesPath isDirectory:&isDir] && isDir) {
    resourcesFolder = primaryResourcesPath;
  } else {
    // Fallback: Look in startingDir / ../share/oolite/Resources (Standard Linux system layout)
    NSString *fallbackPath = [[startingDir stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"share/oolite/Resources"];
    resourcesFolder = [fallbackPath stringByStandardizingPath];
  }

  return resourcesFolder;
}

@end