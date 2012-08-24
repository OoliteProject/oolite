/*

OODebugMonitor.h

Debugging services object for Oolite.
 
The debug controller implements Oolite's part of debugging support. It can
connect to one debugger object, which conforms to the OODebuggerInterface
formal protocol. This can either be (part of) a debugger loaded into Oolite
itself (as in the Mac Debug OXP), or provide communications with an external
debugger (for instance, over Distributed Objects or TCP/IP).


Oolite debug support

Copyright (C) 2007-2012 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCocoa.h"
#import "OOWeakReference.h"
#import "OODebuggerInterface.h"

@class OOJSScript;


@protocol OODebugMonitorInterface

// Note: disconnectDebugger:message: will cause a disconnectDebugMonitor:message: message to be sent to the debugger. The debugger should not send disconnectDebugger:message: in response to disconnectDebugMonitor:message:.
- (void)disconnectDebugger:(in id<OODebuggerInterface>)debugger
				   message:(in NSString *)message;


// *** JavaScript console support.

// Perform a JS command as though entered at the console, including echoing.
- (oneway void)performJSConsoleCommand:(in NSString *)command;

- (id)configurationValueForKey:(in NSString *)key;
- (void)setConfigurationValue:(in id)value forKey:(in NSString *)key;

- (NSString *)sourceCodeForFile:(in NSString *)filePath line:(in unsigned)line;

@end


@interface OODebugMonitor: OOWeakRefObject <OODebugMonitorInterface>
{
	id<OODebuggerInterface>				_debugger;
	
	// JavaScript console support.
	OOJSScript							*_script;
	struct JSObject						*_jsSelf;
	
	NSDictionary						*_configFromOXPs;	// Settings from debugConfig.plist
	NSMutableDictionary					*_configOverrides;	// Settings from preferences, modifiable through JS.
	
	// Caches
	NSMutableDictionary					*_fgColors,
										*_bgColors,
										*_sourceFiles;
	// TCP options
	BOOL								_TCPIgnoresDroppedPackets;
	BOOL								_usingPlugInController;
}

+ (OODebugMonitor *) sharedDebugMonitor;
- (BOOL)setDebugger:(id<OODebuggerInterface>)debugger;

	// *** JavaScript console support.
- (void)appendJSConsoleLine:(id)string
				   colorKey:(NSString *)colorKey
			  emphasisRange:(NSRange)emphasisRange;

- (void)appendJSConsoleLine:(id)string
				   colorKey:(NSString *)colorKey;

- (void)clearJSConsole;
- (void)showJSConsole;

- (id)configurationValueForKey:(NSString *)key class:(Class)class defaultValue:(id)value;
- (long long)configurationIntValueForKey:(NSString *)key defaultValue:(long long)value;

- (NSArray *)configurationKeys;

- (BOOL) debuggerConnected;

- (void) dumpMemoryStatistics;

- (void) setTCPIgnoresDroppedPackets:(BOOL)flag;
- (BOOL) TCPIgnoresDroppedPackets;

- (void) setUsingPlugInController:(BOOL)flag;
- (BOOL) usingPlugInController;

#if OOLITE_GNUSTEP
- (void) applicationWillTerminate;
#endif

@end

