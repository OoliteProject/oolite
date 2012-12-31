/*

OOLoggingExtended.h
By Jens Ayton

Configuration functions for OOLogging.h.


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

#import "OOLogging.h"


void OOLogSetDisplayMessagesInClass(NSString *inClass, BOOL inFlag);
NSString *OOLogGetParentMessageClass(NSString *inClass);


void OOLoggingInit(void);
void OOLoggingTerminate(void);


void OOLogInsertMarker(void);


// Get/set display settings. These are stored in user defaults.
BOOL OOLogShowFunction(void);
void OOLogSetShowFunction(BOOL flag);
BOOL OOLogShowFileAndLine(void);
void OOLogSetShowFileAndLine(BOOL flag);
BOOL OOLogShowTime(void);
void OOLogSetShowTime(BOOL flag);
BOOL OOLogShowMessageClass(void);
void OOLogSetShowMessageClass(BOOL flag);

// Change message class visibility without saving to user defaults.
void OOLogSetShowMessageClassTemporary(BOOL flag);

// Utility function to strip path components from __FILE__ strings.
NSString *OOLogAbbreviatedFileName(const char *inName);
