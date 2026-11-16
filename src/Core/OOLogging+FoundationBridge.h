/*

OOLogging+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-lskf, made by chunk oo-3rb.136).
OOLogging's Foundation-string API as it was before its sweep, with the same names, types,
attributes and linkage: the functions the OOLog / OOLogERR / OOLogWARN / OOLogIndentIf macros of
OOLogging.h expand to (they take an NSString message class and an NSString format with %@), the
configuration functions of OOLoggingExtended.h that take or give NSStrings, and the kOOLog*
message classes as NSString constants. It exists so that every OOLog caller compiles unchanged;
each caller moves to OO_LOG (oofnd/Log.hpp) with a cxx_kOOLog* constant or a literal class in its
own sweep bead. When `git grep` finds no use of anything declared here (nor of the macros that
expand to it), the bridge bead deletes this file, OOLogging+FoundationBridge.mm, its line in
Core/meson.build and the #import at the end of OOLogging.h; it is the last bridge deleted. Never
add to it; never call it from migrated code. oo-qps (the removal of gnustep-base) cannot compile
while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2013 Jens Ayton and contributors (OOLogging.h, OOLoggingExtended.h)

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

// Imported only from the end of OOLogging.h (which declares everything used here); never import
// it directly, and never import OOLogging.h from it (a cycle).
#ifndef OOLOGGING_FOUNDATIONBRIDGE_H
#define OOLOGGING_FOUNDATIONBRIDGE_H

// From OOLogging.h

#ifdef __cplusplus
extern "C" {
#endif

BOOL OOLogWillDisplayMessagesInClass(NSString* inMessageClass);

#ifdef __cplusplus
}
#endif

#if !OOLOG_SHORT_CIRCUIT
#ifdef __cplusplus
extern "C" {
#endif
void OOLogIndentIf(NSString* inMessageClass);
void OOLogOutdentIf(NSString* inMessageClass);
#ifdef __cplusplus
}
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

void OOLogWithPrefix(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inPrefix, NSString* inFormat, ...) OO_TAKES_FORMAT_STRING(6, 7);
void OOLogWithFunctionFileAndLine(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inFormat, ...) OO_TAKES_FORMAT_STRING(5, 6);
void OOLogWithFunctionFileAndLineAndArguments(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inFormat, va_list inArguments) OO_TAKES_FORMAT_STRING(5, 0);

#ifdef __cplusplus
}
#endif

extern NSString* const kOOLogSubclassResponsibility; // @"general.error.subclassResponsibility"
extern NSString* const kOOLogParameterError; // @"general.error.parameterError"
extern NSString* const kOOLogDeprecatedMethod; // @"general.error.deprecatedMethod"
extern NSString* const kOOLogAllocationFailure; // @"general.error.allocationFailure"
extern NSString* const kOOLogInconsistentState; // @"general.error.inconsistentState"
extern NSString* const kOOLogException; // @"exception"

extern NSString* const kOOLogFileNotFound; // @"files.notFound"
extern NSString* const kOOLogFileNotLoaded; // @"files.notLoaded"

extern NSString* const kOOLogOpenGLError; // @"rendering.opengl.error"

// Don't use. However, #defining it as @"unclassified.module" can be used as a stepping stone to OOLog support.
extern NSString* const kOOLogUnconvertedNSLog; // @"unclassified"

// From OOLoggingExtended.h

void OOLogSetDisplayMessagesInClass(NSString* inClass, BOOL inFlag);
NSString* OOLogGetParentMessageClass(NSString* inClass);

// Utility function to strip path components from __FILE__ strings.
#ifdef __cplusplus
extern "C" {
#endif

NSString* OOLogAbbreviatedFileName(const char* inName);

#ifdef __cplusplus
}
#endif

#endif // OOLOGGING_FOUNDATIONBRIDGE_H
