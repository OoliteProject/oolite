#import <Foundation/Foundation.h>

@interface NSBundle (Override)

/**
 * Overrides the standard -infoDictionary method via a category name-clash.
 * Forces the bundle to manually load and return the contents of 'info-gnustep.plist'.
 */
- (id)infoDictionary; // a dictionary. Shared selector (Foundation's NSBundle; proposed ADR-0043).

@end