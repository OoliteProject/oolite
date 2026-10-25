/*

OODebuggerInterface.h

Interfaces for communication between OODebugMonitor and its debugger. The debugger's was the
Objective-C protocol OODebuggerInterface; it is a C++ interface since bead oo-9ht.81 (proposed
ADR-0056, amendment oo-9ht.81), with the same messages as members taking the C++ monitor.


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


#ifndef OODEBUGGERINTERFACE_H
#define OODEBUGGERINTERFACE_H

#include "OOCocoa.h"	// NSRange
#include "oofnd/Ref.hpp"
#include "oofnd/PList.hpp"
#include <optional>
#include <string>

class OODebugMonitor;

// Interface for debugger. Reference counted: the monitor keeps its debugger (oo::Ref).

class OODebuggerInterface : public oo::RefCounted
{
public:
	// Configuration and console text use oo::PList / std::string (proposed ADR-0043).

	// Sent to establish connection. *message: error text when the connect fails.
	virtual bool connectDebugMonitor(OODebugMonitor *debugMonitor,
									 std::optional<std::string> *message) = 0;

	// Sent to close connection. message: nullopt when none.
	virtual void disconnectDebugMonitor(OODebugMonitor *debugMonitor,
										const std::optional<std::string> &message) = 0;

	// Sent to print to the JavaScript console.
	// colorKey is intended to be used to look up a foreground/background colour pair
	// in the configuration. EmphasisRange is to specify a bold section of text.
	virtual void debugMonitor(OODebugMonitor *debugMonitor,
							  const std::string &output,
							  const std::optional<std::string> &colorKey,
							  NSRange emphasisRange) = 0;

	// Sent to clear the JavaScript console.
	virtual void debugMonitorClearConsole(OODebugMonitor *debugMonitor) = 0;

	// Sent to show the console, for instance in response to a warning or error message.
	virtual void debugMonitorShowConsole(OODebugMonitor *debugMonitor) = 0;

	// Sent once when the debugger is connected.
	virtual void debugMonitor(OODebugMonitor *debugMonitor,
							  const oo::PList &configuration) = 0;

	// Sent when configuration changes. newValue null = was nil.
	virtual void debugMonitor(OODebugMonitor *debugMonitor,
							  const oo::PList &newValue,
							  const std::string &key) = 0;

	// What the monitor's log lines print for the debugger ("%@" of the Objective-C object was
	// <ClassName 0x...>).
	virtual std::string description() const = 0;
};

#endif	// OODEBUGGERINTERFACE_H
