// Import OpenStep main headers and define some Macisms and other compatibility stuff.

#if defined(GNUSTEP) && !defined(OOLITE_SDL_MAC)
#include <stdint.h>
#define Boolean unsigned char
#define Byte unsigned char
#define true 1
#define false 0

#define kCGDisplayWidth (@"Width")
#define kCGDisplayHeight (@"Height")
#define kCGDisplayRefreshRate (@"RefreshRate")

#define IBOutlet /**/
#define IBAction void

typedef int32_t CGMouseDelta;

#import "Comparison.h"

typedef char Str255[256];

/* Define the application support cache dir */
#define OOLITE_CACHE  [[[[[NSHomeDirectory() \
                  stringByAppendingPathComponent:@"GNUstep"] \
						stringByAppendingPathComponent:@"Library"] \
						stringByAppendingPathComponent:@"Application Support"] \
						stringByAppendingPathComponent:@"Oolite"] \
						stringByAppendingPathComponent:@"cache"];

#else

#define OOLITE_CACHE  [[[[NSHomeDirectory() \
						stringByAppendingPathComponent:@"Library"] \
						stringByAppendingPathComponent:@"Application Support"] \
						stringByAppendingPathComponent:@"Oolite"] \
						stringByAppendingPathComponent:@"cache"];
#endif

#import <math.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
