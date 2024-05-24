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
// Make sure that a high performance GPU is
// selected, if more than one are available
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
#endif

GameController* controller;
#endif


#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

/**
 * \ingroup cli
 * Entry point for Linux and Windows systems.
 * Initializes logging. If -load is passed, the argument after that is loaded
 * as savegame.
 *
 * @param argc the number of command line arguments
 * @param argv the string array values of the command line arguments
 * @return returns 0 on success, or EXITFAILURE when an exception is caught
 */
int main(int argc, char *argv[])
{
#ifdef GNUSTEP
	int i;

#if (GNUSTEP_BASE_MAJOR_VERSION == 1 && (GNUSTEP_BASE_MINOR_VERSION == 24 && GNUSTEP_BASE_SUBMINOR_VERSION >= 9) || (GNUSTEP_BASE_MINOR_VERSION > 24)) || (GNUSTEP_BASE_MAJOR_VERSION > 1)
	[NSDate class]; // See github issue #202
#endif
	
#if OOLITE_WINDOWS

	#define OO_SHOW_MSG(ooMsg, ooMsgTitle, ooMsgFlags)	MessageBox(NULL, ooMsg, ooMsgTitle, ooMsgFlags)
 	
 	// Detect current working directory and set up GNUstep environment variables
	#define MAX_PATH_LEN 256
	char currentWorkingDir[MAX_PATH_LEN];
	char envVarString[2 * MAX_PATH_LEN];
	DWORD bufferSize = MAX_PATH_LEN;
	
	QueryFullProcessImageName(GetCurrentProcess(), 0, currentWorkingDir, &bufferSize);
	// Strip the exe filenameb (from last backslash onwards), leave just the path
	char *probeString = strrchr(currentWorkingDir, '\\');
	if (probeString)  *probeString = '\0'; // currentWorkingDir now contains the path we need
	
	// Prepend system PATH env variable with our own executable's path
	char finalPath[16 * MAX_PATH_LEN];
	char *systemPath = SDL_getenv("PATH");
	strcpy(finalPath, currentWorkingDir);
	strcat(finalPath, ";");
	strcat(finalPath, systemPath);

	#define SETENVVAR(var, value) do {\
			sprintf(envVarString, "%s=%s", (var), (value));\
			SDL_putenv (envVarString);\
			} while (0);
	
	SETENVVAR("GNUSTEP_PATH_HANDLING", "windows");
	SETENVVAR("PATH", finalPath);
	SETENVVAR("GNUSTEP_SYSTEM_ROOT", currentWorkingDir);
	SETENVVAR("GNUSTEP_LOCAL_ROOT", currentWorkingDir);
	SETENVVAR("GNUSTEP_NETWORK_ROOT", currentWorkingDir);
	SETENVVAR("GNUSTEP_USERS_ROOT", currentWorkingDir);
	SETENVVAR("HOMEPATH", currentWorkingDir);
	
	SetCurrentDirectory(currentWorkingDir);

	/*	Windows amibtiously starts apps with the C library locale set to the
		system locale rather than the "C" locale as per spec. Fixing here so
		numbers don't behave strangely.
	*/
	setlocale(LC_ALL, "C");

#else // Linux
	#define OO_SHOW_MSG(ooMsg, ooTitle, ooFlags)	fprintf(stdout, ooMsg)
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
		
		for (i = 1; i < argc; i++)
		{
			if (strcmp("-load", argv[i]) == 0)
			{
				i++;
				if (i < argc)
					[controller setPlayerFileToLoad: [NSString stringWithCString: argv[i]]];
			}

   			if (!strcmp("-help", argv[i]) || !strcmp("--help", argv[i]))
			{
				char const *processName = [[[NSProcessInfo processInfo] processName] UTF8String];
				char s[2048];
				snprintf(s, sizeof(s), "Usage: %s [options]\n\n"
							"Options can be any of the following: \n\n"
							"--compile-sysdesc\t\t\tCompile system descriptions *\n"
							"--export-sysdesc\t\t\tExport system descriptions *\n"
#if OOLITE_WINDOWS
							"-hdr\t\t\t\tStart up in HDR mode\n"
#endif
							"-load [filepath]:\t\t\tLoad commander from [filepath]\n"
							"-message [messageString]\t\tDisplay [messageString] at startup\n"
							"-noshaders\t\t\tStart up with shaders disabled\n"
							"-nosplash\t\t\t\tForce disable splash screen on startup\n"
							"-nosound\t\t\t\tStart up with sound disabled\n"
							"-novsync\t\t\t\tForce disable V-Sync\n"
							"--openstep\t\t\tWhen compiling or exporting system\n\t\t\t\tdescriptions, use openstep format *\n"
							"-showversion\t\t\tDisplay version at startup screen\n"
							"-splash\t\t\t\tForce splash screen on startup\n"
							"-verify-oxp [filepath]\t\t\tVerify OXP at [filepath] *\n"
							"--xml\t\t\t\tWhen compiling or exporting system \n\t\t\t\tdescriptions, use xml format *\n"
							"\n"
							"Options marked with \"*\" are available only in Test Release configuration.\n\n", processName);
				OO_SHOW_MSG(s, processName, MB_OK);
    				OOLog(@"process.args", @"%s option detected, exiting after help page has been displayed.", argv[i]);
				return 0;
			}
		}
		
		// Release anything allocated during the controller initialisation that
		// is no longer required.
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
