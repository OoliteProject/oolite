/*

OOJSEngineNativeWrappers.mm

The handler behind OOJS_NATIVE_EXIT (OOJSEngineNativeWrappers.h). Bead oo-ppc, the Phase 3
scripting-bindings pattern (proposed ADR-0056 amendment oo-ppc), made the macro a C++
catch (...); this file is the one place that tells an Objective-C exception from a C++ one, so the
binding files need neither. OOJSReportWrappedException() moved here from OOJavaScriptEngine.mm
unchanged. Objective-C++ until nothing can raise an Objective-C exception (Phase 4).


JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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

#include "OOJavaScriptEngine.h"
#include "oofnd/objc/OOException.h"

#include <exception>


/*	The game's exception (oo::Exception since bead oo-rskgl.1, the Objective-C OOException before)
	is reported as the @catch (id) this replaces reported it, by OOJSReportWrappedException(): its
	reason (the -isKindOfClass:[OOException class] test is the catch clause now). Any other
	Objective-C object was "Unidentified native exception", as anything else still is. A C++ one,
	which that clause could not catch (the process terminated, ADR-0029 measurement 10), is
	reported from its what() in the same words, so a raise site that becomes a C++ throw in
	Phase 3 reads the same in JS.
*/
void OOJSReportCurrentException(ooscript::Context context)
{
	try
	{
		throw;
	}
	catch (const oo::Exception &exception)
	{
		if (!ooscript::isExceptionPending((context)))  cxx_OOJSReportError(context, "Native exception: %s", exception.reason());
		// Else, let the pending exception propagate.
	}
	catch (const std::exception &exception)
	{
		if (!ooscript::isExceptionPending((context)))  cxx_OOJSReportError(context, "Native exception: %s", exception.what());
	}
	catch (...)
	{
		if (!ooscript::isExceptionPending((context)))  cxx_OOJSReportError(context, "Unidentified native exception");
	}
}
