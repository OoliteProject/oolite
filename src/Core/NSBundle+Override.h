#import <Foundation/Foundation.h>

@interface NSBundle (Override)

/**
 * Overrides the standard -infoDictionary method via a category name-clash.
 * Forces the bundle to manually load and return the contents of 'info-gnustep.plist'.
 */
- (NSDictionary *)infoDictionary;

/**
 * Locates the cross-platform built-in Oolite Resources directory.
 * Resolves different structures across Windows local installs, macOS app bundles,
 * and Linux/GNUstep global / local file hierarchies.
 *
 * @return A standardized absolute string path to the active 'Resources' directory.
 */
+ (NSString *)builtInPath;

@end