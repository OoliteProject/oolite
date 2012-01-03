/*

OOLogOutputHandler.h
By Jens Ayton

Output handler for OOLogging.

This does two things:
1. It writes log output to ~/Logs/Oolite/Latest.log under Mac OS X or
   ~/.Oolite/Logs/Latest.log under Linux, handling thread serialization.
2. It installs a filter to capture NSLogs and convert them to OOLogs. This is
   different to the macro in OOLogging.h, which acts at compile time; the
   filter catches logging in included frameworks.

OOLogOutputHandlerPrint() is thread-safe. Other functions are not.


Copyright (C) 2007-2012 Jens Ayton and contributors

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

#import <Foundation/Foundation.h>


void OOLogOutputHandlerInit(void);
void OOLogOutputHandlerClose(void);
void OOLogOutputHandlerPrint(NSString *string);

// This will attempt to ensure the containing directory exists. If it fails, it will return nil.
NSString *OOLogHandlerGetLogPath(void);
NSString *OOLogHandlerGetLogBasePath(void);
void OOLogOutputHandlerChangeLogFile(NSString *newLogName);

void OOLogOutputHandlerStartLoggingToStdout();
void OOLogOutputHandlerStopLoggingToStdout();
