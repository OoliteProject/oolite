//#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#ifdef GNUSTEP
#import "GameController.h"

GameController* controller;
#endif

int debug = NO;

int main(int argc, const char *argv[])
{
#ifdef GNUSTEP
	[NSApplication sharedApplication];

	// dajt: allocate and set the NSApplication delegate manually because not using NIB to do this
	controller = [[GameController alloc] init];
	[NSApp setDelegate: controller];
#endif

	return NSApplicationMain(argc, argv);
}


