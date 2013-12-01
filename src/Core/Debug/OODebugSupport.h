/*

OODebugSupport.h

Set up debug support.


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

#ifndef OO_EXCLUDE_DEBUG_SUPPORT

void OOInitDebugSupport(void);

#else

#define OOInitDebugSupport() do {} while (0)

#endif


#if OOLITE_MAC_OS_X
#import <DTPerformanceSession/DTSignalFlag.h>

/**
 * Set a point flag in Instruments.
 *
 * Signal flags are hidden by default. To show them, select "Manage Flags..."
 * from the Window menu, and select "Signal Flags" from the "Displayed Flags"
 * dropdown menu.
 *
 * @param string An NSString identifying the context of the flag. This will be
 *               displayed as "from oolite <string> [point]".
 */
#define OOProfilerPointMarker(string) \
	OODTSendSignalFlag(string, DT_POINT_SIGNAL, NO)

/**
 * Set a start flag in Instruments.
 *
 * A start flag should be balanced with a matching end flag.
 *
 * @param string An NSString identifying the context of the flag. This will be
 *               displayed as "from oolite <string> [point]". The start flag
 *               is matched with the following end flag with the same string.
 */
#define OOProfilerStartMarker(string) \
	OODTSendSignalFlag(string, DT_START_SIGNAL, NO)

/**
 * Set an end flag in Instruments.
 *
 * An end flag should be balanced with a matching start flag.
 *
 * @param string An NSString identifying the context of the flag. This will be
 *               displayed as "from oolite <string> [point]". The end flag
 *               is matched with the previous start flag with the same string.
 */
#define OOProfilerEndMarker(string) \
	OODTSendSignalFlag(string, DT_END_SIGNAL, NO)

#define OODTSendSignalFlag(string, signal, includeBacktrace) \
	do { const char *stringC = [[@"oolite " stringByAppendingString:string] UTF8String]; DTSendSignalFlag(stringC, signal, includeBacktrace); } while (0)

#else

#define OOProfilerPointMarker(string) \
	do {} while (0)

#define OOProfilerStartMarker(string) \
	do {} while (0)

#define OOProfilerEndMarker(string) \
	do {} while (0)
#endif
