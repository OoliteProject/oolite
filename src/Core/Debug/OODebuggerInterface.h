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

#include "oofnd/PList.hpp"
#import "oofnd/objc/OOObject.h"
#include <optional>
#include <string>

// Interface for debugger.

@protocol OODebuggerInterface <OOObject>

// Configuration and console text use oo::PList / std::string (proposed ADR-0043).

// Sent to establish connection. *message: error text when the connect fails.
- (BOOL)connectDebugMonitor:(OODebugMonitor*)debugMonitor
               errorMessage:(std::optional<std::string>*)message;

// Sent to close connection. message: nullopt when none.
- (void)disconnectDebugMonitor:(OODebugMonitor*)debugMonitor
                       message:(const std::optional<std::string>&)message;

// Sent to print to the JavaScript console.
// colorKey is intended to be used to look up a foreground/background colour pair
// in the configuration. EmphasisRange is to specify a bold section of text.
- (void)debugMonitor:(OODebugMonitor*)debugMonitor
     jsConsoleOutput:(const std::string&)output
            colorKey:(const std::optional<std::string>&)colorKey
       emphasisRange:(NSRange)emphasisRange;

// Sent to clear the JavaScript console.
- (void)debugMonitorClearConsole:(OODebugMonitor*)debugMonitor;

// Sent to show the console, for instance in response to a warning or error message.
- (void)debugMonitorShowConsole:(OODebugMonitor*)debugMonitor;

// Sent once when the debugger is connected.
- (void)debugMonitor:(OODebugMonitor*)debugMonitor
    noteConfiguration:(const oo::PList&)configuration;

// Sent when configuration changes. newValue null = was nil.
- (void)debugMonitor:(OODebugMonitor*)debugMonitor
    noteChangedConfigrationValue:(const oo::PList&)newValue
                          forKey:(const std::string&)key;

@end
