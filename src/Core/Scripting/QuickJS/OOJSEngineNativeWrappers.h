/*

OOJSEngineNativeWrappers.h (QuickJS-ng)

Exception safety and profiling macros.

Every JavaScript native callback that could concievably cause an
Objective-C exception should begin with OOJS_NATIVE_ENTER() and end with
OOJS_NATIVE_EXIT. Callbacks which have been carefully audited for potential
exceptions, and support functions called from JavaScript native callbacks,
may start with OOJS_PROFILE_ENTER and end with OOJS_PROFILE_EXIT to be
included in profiling reports.

Functions using either of these pairs _must_ return before
OOJS_NATIVE_EXIT/OOJS_PROFILE_EXIT, or they will crash.

For functions with a non-scalar return type, OOJS_PROFILE_EXIT should be
replaced with OOJS_PROFILE_EXIT_VAL(returnValue). The returnValue is never
used (and should be a constant expression), but is required to placate the
compiler.

For values with void return, use OOJS_PROFILE_EXIT_VOID. It is not
necessary to insert a return statement before OOJS_PROFILE_EXIT_VOID.


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

/*	With QuickJS, the exception safety and profiling macros
        (OOJS_NATIVE_ENTER()/OOJS_NATIVE_EXIT, OOJS_PROFILE_ENTER/OOJS_PROFILE_EXIT,
        OOJS_BEGIN_FULL_NATIVE()/OOJS_END_FULL_NATIVE and friends) are defined in
        OOJavaScriptEngine.h. This header remains so existing imports keep working.
        The profiling hooks are not ported (see OOJSEngineTimeManagement.h).
*/

#import "OOJavaScriptEngine.h"
