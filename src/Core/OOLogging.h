/*

OOLogging.h
By Jens Ayton

More flexible alternative to NSLog().


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#include "OOFoundation.h"
#include "OOFunctionAttributes.h"
#include <stdarg.h>

// OO_LOG / oo::log (ADR-0035): the Foundation-free logging API. extern "C++" because this header
// is sometimes reached from inside an extern "C" block (OOMaths.h), as OOFoundation.h notes.
#ifdef __cplusplus
extern "C++" {
#include "oofnd/Log.hpp"
}
#endif

#ifndef OOLOG_FUNCTION_NAME
#if defined(__GNUC__) && __GNUC__ >= 2
#define OOLOG_FUNCTION_NAME __FUNCTION__
#elif 199901L <= __STDC_VERSION__
#define OOLOG_FUNCTION_NAME __func__
#else
#define OOLOG_FUNCTION_NAME NULL
#endif
#endif

#ifndef OOLOG_FILE_NAME
#ifdef OOLOG_NO_FILE_NAME
#define OOLOG_FILE_NAME NULL
#else
#define OOLOG_FILE_NAME __FILE__
#endif
#endif

/*	OOLOG_SHORT_CIRCUIT:
        If nonzero, the test of whether to display a message before evaluating the
        other parameters of the call. This saves time, but could cause weird bugs
        if the parameters involve calls with side effects.
*/
#ifndef OOLOG_SHORT_CIRCUIT
#define OOLOG_SHORT_CIRCUIT 1
#endif

#ifdef __cplusplus
extern "C" {
#endif

void OOLogIndent(void);
void OOLogOutdent(void);

#ifdef __cplusplus
}
#endif

// Remember/restore indent levels, for cases where an exception may occur while indented.
#ifdef __cplusplus
extern "C" {
#endif

void OOLogPushIndent(void);
void OOLogPopIndent(void);

// OOLogGenericParameterError(): general parameter error message, "***** $function_name: bad parameters. (This is an internal programming error, please report it.)"
#define OOLogGenericParameterError() OOLogGenericParameterErrorForFunction(OOLOG_FUNCTION_NAME)
void OOLogGenericParameterErrorForFunction(const char* inFunction);

// OOLogGenericSubclassResponsibility(): general subclass responsibility message, "***** $function_name is a subclass responsibility. (This is an internal programming error, please report it.)"
#define OOLogGenericSubclassResponsibility() OOLogGenericSubclassResponsibilityForFunction(OOLOG_FUNCTION_NAME)
void OOLogGenericSubclassResponsibilityForFunction(const char* inFunction);

#ifdef __cplusplus
}
#endif

// *** Predefined message classes.
/*	These are general coding error types. Generally a subclass should be used
        for each instance -- for instance, Entity::warnAboutHostiles() uses
        @"general.error.subclassResponsibility.Entity-warnAboutHostiles".
*/

#ifdef __cplusplus
extern const char* const cxx_kOOLogSubclassResponsibility; // "general.error.subclassResponsibility"
extern const char* const cxx_kOOLogParameterError; // "general.error.parameterError"
extern const char* const cxx_kOOLogDeprecatedMethod; // "general.error.deprecatedMethod"
extern const char* const cxx_kOOLogAllocationFailure; // "general.error.allocationFailure"
extern const char* const cxx_kOOLogInconsistentState; // "general.error.inconsistentState"
extern const char* const cxx_kOOLogException; // "exception"

extern const char* const cxx_kOOLogFileNotFound; // "files.notFound"
extern const char* const cxx_kOOLogFileNotLoaded; // "files.notLoaded"

extern const char* const cxx_kOOLogOpenGLError; // "rendering.opengl.error"

// Don't use.
extern const char* const cxx_kOOLogUnconvertedNSLog; // "unclassified"
#endif
