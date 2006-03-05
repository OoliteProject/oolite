#import <AppKit/NSApplication.h>

#ifdef GNUSTEP
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>

#import "GameController.h"

GameController* controller;
#endif

int debug = NO;


#ifdef OOLITE_SDL_MAC
#define main SDL_main
#endif


int main(int argc, char *argv[])
{
#ifdef GNUSTEP && !OOLITE_SDL_MAC
	int i;

	// This is still necessary for NSFont calls.
	[NSApplication sharedApplication];

	// Need this because we're not using the default run loop's autorelease
	// pool.
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	// dajt: allocate and set the NSApplication delegate manually because not
	// using NIB to do this
	controller = [[GameController alloc] init];
	
	// Release anything allocated during the controller initialisation that
	// is no longer required.
	[pool release];

	for (i = 0; i < argc; i++)
	{
		if (strcmp("-fullscreen", argv[i]) == 0)
			[controller setFullScreenMode: YES];

		if (strcmp("-load", argv[i]) == 0)
		{
			i++;
			if (i < argc)
				[controller setPlayerFileToLoad: [NSString stringWithCString: argv[i]]];
		}
	}

	// Call applicationDidFinishLaunching because NSApp is not running in
	// GNUstep port.
	[controller applicationDidFinishLaunching: nil];
#else
	return NSApplicationMain(argc, (const char *)argv);
#endif

	// never reached
	return 0;
}

/*
 * This is called from a couple of places, and having it here saves one more
 * AppKit dependency.
 */
//void NSBeep()
//{
//}

