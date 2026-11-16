/*

OODebuggerInterface.h

Protocols for communication between OODebugMonitor and OODebuggerInterface.


Oolite Debug Support

Copyright (C) 2007-2013 Jens Ayton

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

#pragma once

#import "OOFoundation.h"

@class OODebugMonitor;

// Interface for debugger.

@protocol OODebuggerInterface <NSObject>

// The string and dictionary parameters are typed id: these selectors are shared with the one
// implementer, OODebugTCPConsoleClient (proposed ADR-0043).

// Sent to establish connection. *message: a string.
- (BOOL)connectDebugMonitor:(in OODebugMonitor*)debugMonitor
               errorMessage:(out id*)message;

// Sent to close connection. message: a string or nil.
- (void)disconnectDebugMonitor:(in OODebugMonitor*)debugMonitor
                       message:(in id)message;

// Sent to print to the JavaScript console.
// colorKey is intended to be used to look up a foreground/background colour pair
// in the configuration. EmphasisRange is to specify a bold section of text.
- (oneway void)debugMonitor:(in OODebugMonitor*)debugMonitor
            jsConsoleOutput:(in id)output
                   colorKey:(in id)colorKey
              emphasisRange:(in NSRange)emphasisRange;

// Sent to clear the JavaScript console.
- (oneway void)debugMonitorClearConsole:(in OODebugMonitor*)debugMonitor;

// Sent to show the console, for instance in response to a warning or error message.
- (oneway void)debugMonitorShowConsole:(in OODebugMonitor*)debugMonitor;

// Sent once when the debugger is connected.
- (oneway void)debugMonitor:(in OODebugMonitor*)debugMonitor
          noteConfiguration:(in id)configuration; // a dictionary

// Sent when configuration changes. newValue may be nil.
- (oneway void)debugMonitor:(in OODebugMonitor*)debugMonitor
    noteChangedConfigrationValue:(in id)newValue
                          forKey:(in id)key;

@end
