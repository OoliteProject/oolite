/*

OOJavaScriptEngineMonitor.h

The JavaScript engine's debugging "monitor": the object the engine gives its errors, warnings and
log messages to (in Oolite, the debug monitor). It was the Objective-C protocol
OOJavaScriptEngineMonitor, adopted by the debug monitor's facade and sent after
-respondsToSelector:; it is a C++ interface since bead oo-9ht.74.1 (proposed ADR-0056, amendment
oo-9ht.74.1), with the same two messages as members. The engine borrows its monitor (the debug
monitor lives as long as the process; a caller keeps its monitor alive while it is set).


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

#ifndef OOJAVASCRIPTENGINEMONITOR_H
#define OOJAVASCRIPTENGINEMONITOR_H

#include "ooscript/JSEngine.hpp"

#include <optional>
#include <string>

class OOJavaScriptEngine;


class OOJavaScriptEngineMonitor
{
public:
	// Sent for JS errors or warnings.
	virtual void jsEngine(::OOJavaScriptEngine *engine,
						  ooscript::Context context,
						  ooscript::ErrorReport *errorReport,
						  unsigned stackSkip,
						  bool showLocation,
						  const std::string &message) = 0;

	// Sent for JS log messages. Note: messageClass is nullopt if Log() is used rather than LogWithClass().
	virtual void jsEngine(::OOJavaScriptEngine *engine,
						  ooscript::Context context,
						  const std::string &message,
						  const std::optional<std::string> &messageClass) = 0;

protected:
	~OOJavaScriptEngineMonitor() = default;	// never deleted through the interface
};

#endif	// OOJAVASCRIPTENGINEMONITOR_H
