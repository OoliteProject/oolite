/*

OODebuggerInterface.h

Protocols for communication between OODebugMonitor and OODebuggerInterface.


Oolite Debug OXP

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


@class OODebugMonitor;

// Interface for debugger.

@protocol OODebuggerInterface <NSObject>

// Sent to establish connection.
- (BOOL)connectDebugMonitor:(in OODebugMonitor *)debugMonitor
			   errorMessage:(out NSString **)message;

// Sent to close connection.
- (void)disconnectDebugMonitor:(in OODebugMonitor *)debugMonitor
					   message:(in NSString *)message;

// Sent to print to the JavaScript console.
// colorKey is intended to be used to look up a foreground/background colour pair
// in the configuration. EmphasisRange is to specify a bold section of text.
- (oneway void)debugMonitor:(in OODebugMonitor *)debugMonitor
			jsConsoleOutput:(in NSString *)output
				   colorKey:(in NSString *)colorKey
			  emphasisRange:(in NSRange)emphasisRange;

// Sent to clear the JavaScript console.
- (oneway void)debugMonitorClearConsole:(in OODebugMonitor *)debugMonitor;

// Sent to show the console, for instance in response to a warning or error message.
- (oneway void)debugMonitorShowConsole:(in OODebugMonitor *)debugMonitor;

// Sent once when the debugger is connected.
- (oneway void)debugMonitor:(in OODebugMonitor *)debugMonitor
		  noteConfiguration:(in NSDictionary *)configuration;

// Sent when configuration changes. newValue may be nil.
- (oneway void)debugMonitor:(in OODebugMonitor *)debugMonitor
noteChangedConfigrationValue:(in id)newValue
					 forKey:(in NSString *)key;

@end
