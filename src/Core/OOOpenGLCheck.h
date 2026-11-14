/*

OOOpenGLCheck.h

OpenGL error checking (cxx_OOCheckOpenGLErrors(), OOGL() and friends),
split out of OOOpenGL.h so that a plain C++ translation unit can use it:
this header includes only OOOpenGLOnly.h and oofnd headers (no Cocoa
compatibility header, no Objective-C).


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

#ifndef INCLUDED_OOOPENGLCHECK_h
#define INCLUDED_OOOPENGLCHECK_h

#include "OOOpenGLOnly.h"

// Whether to use state verifier. Will be changed to equal OO_CHECK_GL_HEAVY in future.
#ifdef NDEBUG
#define OO_GL_STATE_VERIFICATION 0
#else
#define OO_GL_STATE_VERIFICATION 1
#endif

/*	cxx_OOCheckOpenGLErrors()
        Check for and log OpenGL errors, and returns true if an error occurred.
        NOTE: this is controlled by the log message class rendering.opengl.error.
                  If logging is disabled, no error checking will occur. This is done
                  because glGetError() is quite expensive, requiring a full OpenGL
                  state sync.
        The context is built only when an error is found: a printf format and its
        arguments (a null format reads "<unknown>"), or a function giving the text.
        (C++ linkage: this header is sometimes reached from inside an extern "C"
        block, OOMaths.h.)
*/
#ifdef __cplusplus
extern "C++" {
#include "oofnd/PrintfFormat.h"
#include "oofnd/StdLib.hpp"
bool cxx_OOCheckOpenGLErrors(const char* format, ...) OO_PRINTF_FORMAT(1, 2);
bool cxx_OOCheckOpenGLErrors(const std::function<std::string()>& context);
}
#endif

/*	OO_CHECK_GL_HEAVY and error-checking stuff

        If OO_CHECK_GL_HEAVY is non-zero, the following error-checking facilities
        come into play:
        OOGL(foo) checks for GL errors before and after performing the statement foo.
        OOGLBEGIN(mode) checks for GL errors, then calls glBegin(mode).
        OOGLEND() calls glEnd(), then checks for GL errors.
        CheckOpenGLErrorsHeavy() checks for errors exactly like cxx_OOCheckOpenGLErrors().

        If OO_CHECK_GL_HEAVY is zero, these macros don't perform error checking,
        but otherwise continue to work as before, so:
        OOGL(foo) performs the statement foo.
        OOGLBEGIN(mode) calls glBegin(mode);
        OOGLEND() calls glEnd().
        CheckOpenGLErrorsHeavy() does nothing (including not performing any parameter side-effects).
*/
#ifndef OO_CHECK_GL_HEAVY
#define OO_CHECK_GL_HEAVY 0
#endif

#if OO_CHECK_GL_HEAVY

#if OO_GL_STATE_VERIFICATION
#ifdef __cplusplus
extern "C" {
#endif
void OOGLNoteCurrentFunction(const char* func, unsigned line);
#ifdef __cplusplus
}
#endif
#else
#define OOGLNoteCurrentFunction(FUNC, line) \
    do {                                    \
    } while (0)
#endif

#ifdef __cplusplus
extern "C++" {
#include "oofnd/Log.hpp" // oo::log::abbreviatedFileName()
}
#endif
#define OOGL_PERFORM_CHECK(label, code) cxx_OOCheckOpenGLErrors("%s %s:%u (%s)%s", label, oo::log::abbreviatedFileName(__FILE__).c_str(), __LINE__, __PRETTY_FUNCTION__, code)
#define OOGL(statement)                                  \
    do {                                                 \
        OOGLNoteCurrentFunction(__FUNCTION__, __LINE__); \
        OOGL_PERFORM_CHECK("PRE", " -- " #statement);    \
        statement;                                       \
        OOGL_PERFORM_CHECK("POST", " -- " #statement);   \
    } while (0)
#define CheckOpenGLErrorsHeavy cxx_OOCheckOpenGLErrors
#define OOGLBEGIN(mode)                                  \
    do {                                                 \
        OOGLNoteCurrentFunction(__FUNCTION__, __LINE__); \
        OOGL_PERFORM_CHECK("PRE-BEGIN", " -- " #mode);   \
        glBegin(mode);                                   \
    } while (0)
#define OOGLEND()                                        \
    do {                                                 \
        glEnd();                                         \
        OOGLNoteCurrentFunction(__FUNCTION__, __LINE__); \
        OOGL_PERFORM_CHECK("POST-END", "");              \
    } while (0)

#else

#define OOGL(statement) \
    do {                \
        statement;      \
    } while (0)
#define CheckOpenGLErrorsHeavy(...) \
    do {                            \
    } while (0)
#define OOGLBEGIN glBegin
#define OOGLEND glEnd

#endif

#endif // INCLUDED_OOOPENGLCHECK_h
