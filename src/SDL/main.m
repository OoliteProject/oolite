/*

main.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/


#ifdef GNUSTEP
#import <Foundation/NSAutoreleasePool.h>
#if (GNUSTEP_BASE_MAJOR_VERSION == 1 && (GNUSTEP_BASE_MINOR_VERSION == 24 && GNUSTEP_BASE_SUBMINOR_VERSION >= 9) || (GNUSTEP_BASE_MINOR_VERSION > 24)) || (GNUSTEP_BASE_MAJOR_VERSION > 1)
#import <Foundation/NSDate.h>
#endif
#import <Foundation/NSString.h>

#import "GameController.h"
#import "OOLoggingExtended.h"

#if OOLITE_WINDOWS
#include <locale.h>
#include <SDL.h>
#endif
GameController* controller;
#endif


#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


int main(int argc, char *argv[])
{
#ifdef GNUSTEP
	int i;

#if (GNUSTEP_BASE_MAJOR_VERSION == 1 && (GNUSTEP_BASE_MINOR_VERSION == 24 && GNUSTEP_BASE_SUBMINOR_VERSION >= 9) || (GNUSTEP_BASE_MINOR_VERSION > 24)) || (GNUSTEP_BASE_MAJOR_VERSION > 1)
	[NSDate class]; // See github issue #202
#endif
	
#if OOLITE_WINDOWS

	// Detect current working directory and set up GNUstep environment variables
	#define MAX_PATH_LEN 256
	char currentWorkingDir[MAX_PATH_LEN];
	char envVarString[2 * MAX_PATH_LEN];
	GetCurrentDirectory(MAX_PATH_LEN - 1, currentWorkingDir);

	#define SETENVVAR(var, value) do {\
			sprintf(envVarString, "%s=%s", (var), (value));\
			SDL_putenv (envVarString);\
			} while (0);
	
	SETENVVAR("GNUSTEP_PATH_HANDLING", "windows");
	SETENVVAR("GNUSTEP_SYSTEM_ROOT", currentWorkingDir);
	SETENVVAR("GNUSTEP_LOCAL_ROOT", currentWorkingDir);
	SETENVVAR("GNUSTEP_NETWORK_ROOT", currentWorkingDir);
	SETENVVAR("GNUSTEP_USERS_ROOT", currentWorkingDir);
	SETENVVAR("HOMEPATH", currentWorkingDir);

	/*	Windows amibtiously starts apps with the C library locale set to the
		system locale rather than the "C" locale as per spec. Fixing here so
		numbers don't behave strangely.
	*/
	setlocale(LC_ALL, "C");
#endif

	// Need this because we're not using the default run loop's autorelease
	// pool.
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	OOLoggingInit();
	
	@try
	{
		// dajt: allocate and set the NSApplication delegate manually because not
		// using NIB to do this
		controller = [[GameController alloc] init];
		
		// Release anything allocated during the controller initialisation that
		// is no longer required.

		for (i = 1; i < argc; i++)
		{
			if (strcmp("-load", argv[i]) == 0)
			{
				i++;
				if (i < argc)
					[controller setPlayerFileToLoad: [NSString stringWithCString: argv[i]]];
			}
		}

		DESTROY(pool);
		
		// Call applicationDidFinishLaunching because NSApp is not running in
		// GNUstep port.
		[controller applicationDidFinishLaunching: nil];
	}
	@catch (NSException *exception)
	{
		OOLogERR(kOOLogException, @"Root exception handler hit - terminating. This is an internal error, please report it. Exception name: %@, reason: %@", [exception name], [exception reason]);
		return EXIT_FAILURE;
	}
#endif

	// never reached
	return 0;
}
