/*

OODebugSupport.m


Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OO_EXCLUDE_DEBUG_SUPPORT


#import "OODebugSupport.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "OODebugMonitor.h"
#import "OODebugTCPConsoleClient.h"

#if OOLITE_MAC_OS_X
static id LoadDebugPlugIn(NSString *path);
#else
#define LoadDebugPlugIn(path) nil
#endif


@interface NSObject (OODebugPlugInController)

- (id<OODebuggerInterface>) setUpDebugger;

@end


void OOInitDebugSupport(void)
{
	NSString				*debugOXPPath = nil;
	id						plugInController = nil;
	NSDictionary			*debugSettings = nil;
	NSString				*consoleHost = nil;
	unsigned short			consolePort = nil;
	id<OODebuggerInterface>	debugger = nil;
	
	// Check that the debug OXP is installed. If not, we don't enable debug support.
	debugOXPPath = [ResourceManager pathForFileNamed:@"DebugOXPLocatorBeacon.magic" inFolder:@"nil"];
	if (debugOXPPath != nil)
	{
		// Load plug-in debugging code on platforms where this is supported.
		plugInController = LoadDebugPlugIn(debugOXPPath);
		
		// Load debug settings.
		debugSettings = [ResourceManager dictionaryFromFilesNamed:@"debugConfig.plist"
														 inFolder:@"Config"
														mergeMode:MERGE_BASIC
															cache:NO];
		
		consoleHost = [debugSettings stringForKey:@"console-host"];
		consolePort = [debugSettings unsignedShortForKey:@"console-port"];
		
		// If consoleHost is nil, and the debug plug-in can set up a debugger, use that.
		if (consoleHost == nil && [plugInController respondsToSelector:@selector(registerIntegratedDebugConsole)])
		{
			debugger = [plugInController setUpDebugger];
		}
		
		// Otherwise, use TCP debugger connection.
		if (debugger == nil)
		{
			debugger = [[OODebugTCPConsoleClient alloc] initWithAddress:consoleHost
																   port:consolePort];
			[debugger autorelease];
		}
		
		// Set up monitor and register debugger, if any.
		if (debugger != nil)
		{
			[[OODebugMonitor sharedDebugMonitor] setDebugger:debugger];
		}
	}
}


#if OOLITE_MAC_OS_X

// Note: it should in principle be possible to use this code to load a plug-in under GNUstep, too.
static id LoadDebugPlugIn(NSString *path)
{
	Class					principalClass = Nil;
	NSString				*bundlePath = nil;
	NSBundle				*bundle = nil;
	id						debugController = nil;
	
	bundlePath = [path stringByDeletingLastPathComponent];
	bundle = [NSBundle bundleWithPath:bundlePath];
	if ([bundle load])
	{
		principalClass = [bundle principalClass];
		if (principalClass != Nil)
		{
			// Instantiate principal class of debug bundle, and let it do whatever it wants.
			debugController = [[principalClass alloc] init];
		}
		else
		{
			OOLog(@"debugOXP.load.failed", @"Failed to find principal class of debug bundle.");
		}
	}
	else
	{
		OOLog(@"debugOXP.load.failed", @"Failed to load DebugOXP.bundle from %@.", bundlePath);
	}
	
	return debugController;
}

#endif

#endif	/* OO_EXCLUDE_DEBUG_SUPPORT */
