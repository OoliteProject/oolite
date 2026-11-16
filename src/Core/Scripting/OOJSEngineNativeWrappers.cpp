/*

OOJSEngineNativeWrappers.cpp

The handler behind OOJS_NATIVE_EXIT (OOJSEngineNativeWrappers.h). The macro is
a C++ catch (...); this file is the one place that tells the game's exception
from a C++ one, so the binding files need neither.


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

#include <exception>

#include "OOJavaScriptEngine.h"
#include "oofnd/objc/OOException.h"

/*	The game's exception (oo::Exception) is reported by its reason. Any
        other object is "Unidentified native exception", as anything else
        still is. A C++ exception is reported from its what() in the same words,
   so a raise site that is a C++ throw reads the same in JS.
*/
void OOJSReportCurrentException(JSContext* context) {
  try {
    throw;
  } catch (const oo::Exception& exception) {
    if (!JS_HasException(context))
      OOJSReportError(context, "Native exception: %s", exception.reason());
    // Else, let the pending exception propagate.
  } catch (const std::exception& exception) {
    if (!JS_HasException(context))
      OOJSReportError(context, "Native exception: %s", exception.what());
  } catch (...) {
    if (!JS_HasException(context))
      OOJSReportError(context, "Unidentified native exception");
  }
}
