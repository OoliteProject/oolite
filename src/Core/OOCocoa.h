/*

OOCocoa.h

Import OpenStep main headers and define some Macisms and other compatibility
stuff.

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import <math.h>
#import <Foundation/Foundation.h>

#ifdef GNUSTEP
	#define OOLITE_GNUSTEP			1
	
	#if (GNUSTEP_BASE_MAJOR_VERSION == 1 && GNUSTEP_BASE_MINOR_VERSION >= 20) || (GNUSTEP_BASE_MAJOR_VERSION > 1)
		#define OOLITE_GNUSTEP_1_20	1
	#endif
#else
	#import <AppKit/AppKit.h>
	
	#define OOLITE_MAC_OS_X			1
	#define OOLITE_HAVE_APPKIT		1
	#ifdef OOLITE_SDL_MAC
		#define OOLITE_SDL			1
	#endif
	
	/*	Enforce type-clean use of nil and Nil under OS X. (They are untyped in
		Cocoa, apparently for compatibility with legacy Mac OS code, but typed in
		GNUstep.)
	*/
	#undef nil
	#define nil ((id)0)
	#undef Nil
	#define Nil ((Class)nil)
	
	/*	Useful macro copied from GNUstep.
	*/
	#ifndef DESTROY
		#define DESTROY(x) do { id x_ = x; x = nil; [x_ release]; } while (0)
	#endif
	
	/*	Lots of stuff changed between 10.3.9 SDK used for 32-bit builds and 10.5
		SDK used for 64-bit builds.
	*/
	#if defined MAC_OS_X_VERSION_10_5 && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5
		#define OOLITE_LEOPARD		1
	#endif
#endif


#ifndef OOLITE_GNUSTEP_1_20
	#define OOLITE_GNUSTEP_1_20		0
#endif

#ifndef OOLITE_LEOPARD
	#define OOLITE_LEOPARD			0
#endif


#if OOLITE_GNUSTEP && !defined(OOLITE_SDL_MAC)
#include <stdint.h>
#include <limits.h> // to get UINT_MAX


#define OOLITE_SDL				1

#ifdef WIN32
#define OOLITE_WINDOWS			1
#endif

#ifdef LINUX
#define OOLITE_LINUX			1
#endif


#define Boolean unsigned char
#define Byte unsigned char
#define true 1
#define false 0

#if !defined(MAX)
	#define MAX(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a > __b ? __a : __b; })
#endif

#if !defined(MIN)
	#define MIN(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __a : __b; })
#endif

#define IBOutlet /**/
#define IBAction void

typedef int32_t CGMouseDelta;

#import "Comparison.h"

/* Define AppKit constants for events */
enum {
  NSUpArrowFunctionKey = 0xF700,
  NSDownArrowFunctionKey = 0xF701,
  NSLeftArrowFunctionKey = 0xF702,
  NSRightArrowFunctionKey = 0xF703,
  NSF1FunctionKey  = 0xF704,
  NSF2FunctionKey  = 0xF705,
  NSF3FunctionKey  = 0xF706,
  NSF4FunctionKey  = 0xF707,
  NSF5FunctionKey  = 0xF708,
  NSF6FunctionKey  = 0xF709,
  NSF7FunctionKey  = 0xF70A,
  NSF8FunctionKey  = 0xF70B,
  NSF9FunctionKey  = 0xF70C,
  NSF10FunctionKey = 0xF70D,
  NSF11FunctionKey = 0xF70E,
  NSF12FunctionKey = 0xF70F,
  NSF13FunctionKey = 0xF710,
  NSF14FunctionKey = 0xF711,
  NSF15FunctionKey = 0xF712,
  NSF16FunctionKey = 0xF713,
  NSF17FunctionKey = 0xF714,
  NSF18FunctionKey = 0xF715,
  NSF19FunctionKey = 0xF716,
  NSF20FunctionKey = 0xF717,
  NSF21FunctionKey = 0xF718,
  NSF22FunctionKey = 0xF719,
  NSF23FunctionKey = 0xF71A,
  NSF24FunctionKey = 0xF71B,
  NSF25FunctionKey = 0xF71C,
  NSF26FunctionKey = 0xF71D,
  NSF27FunctionKey = 0xF71E,
  NSF28FunctionKey = 0xF71F,
  NSF29FunctionKey = 0xF720,
  NSF30FunctionKey = 0xF721,
  NSF31FunctionKey = 0xF722,
  NSF32FunctionKey = 0xF723,
  NSF33FunctionKey = 0xF724,
  NSF34FunctionKey = 0xF725,
  NSF35FunctionKey = 0xF726,
  NSInsertFunctionKey = 0xF727,
  NSDeleteFunctionKey = 0xF728,
  NSHomeFunctionKey = 0xF729,
  NSBeginFunctionKey = 0xF72A,
  NSEndFunctionKey = 0xF72B,
  NSPageUpFunctionKey = 0xF72C,
  NSPageDownFunctionKey = 0xF72D,
  NSPrintScreenFunctionKey = 0xF72E,
  NSScrollLockFunctionKey = 0xF72F,
  NSPauseFunctionKey = 0xF730,
  NSSysReqFunctionKey = 0xF731,
  NSBreakFunctionKey = 0xF732,
  NSResetFunctionKey = 0xF733,
  NSStopFunctionKey = 0xF734,
  NSMenuFunctionKey = 0xF735,
  NSUserFunctionKey = 0xF736,
  NSSystemFunctionKey = 0xF737,
  NSPrintFunctionKey = 0xF738,
  NSClearLineFunctionKey = 0xF739,
  NSClearDisplayFunctionKey = 0xF73A,
  NSInsertLineFunctionKey = 0xF73B,
  NSDeleteLineFunctionKey = 0xF73C,
  NSInsertCharFunctionKey = 0xF73D,
  NSDeleteCharFunctionKey = 0xF73E,
  NSPrevFunctionKey = 0xF73F,
  NSNextFunctionKey = 0xF740,
  NSSelectFunctionKey = 0xF741,
  NSExecuteFunctionKey = 0xF742,
  NSUndoFunctionKey = 0xF743,
  NSRedoFunctionKey = 0xF744,
  NSFindFunctionKey = 0xF745,
  NSHelpFunctionKey = 0xF746,
  NSModeSwitchFunctionKey = 0xF747
};

#endif


#ifndef OOLITE_GNUSTEP
#define OOLITE_GNUSTEP			0
#endif

#ifndef OOLITE_MAC_OS_X
#define OOLITE_MAC_OS_X			0
#endif

#ifndef OOLITE_WINDOWS
#define OOLITE_WINDOWS			0
#endif

#ifndef OOLITE_LINUX
#define OOLITE_LINUX			0
#endif

#ifndef OOLITE_SDL
#define OOLITE_SDL				0
#endif

#ifndef OOLITE_HAVE_APPKIT
#define OOLITE_HAVE_APPKIT		0
#endif

#define OOLITE_HAVE_JOYSTICK	1


// When Oolite-Linux used AppKit, the load/save dialogs didn't work well with the SDL window, so we use a separate macro for this.
#define OOLITE_USE_APPKIT_LOAD_SAVE	OOLITE_MAC_OS_X


#import "OOLogging.h"


@interface NSObject (OODescriptionComponents)

/*	In order to allow implementations of -description to inherit description
	components from superclasses, and to allow implementations of -description
	and -javaScriptDescription to share code, both are implemented as wrappers
	around -descriptionComponents. -descriptionComponents should provide
	information about an object without a class name or surrounding
	punctuation. -description will wrap the components like this:
		<ClassName 0xnnnnnnnn>{descriptionComponents}
	and -javaScriptDescription will wrap them like this:
		[JSClassName descriptionComponents]
*/
- (NSString *)descriptionComponents;


/*	A lot of Oolite's -description implementations are rather long, and many
	embed other descriptions. -shortDescription provides a truncated
	alternative, while -shortDescriptionComponents provides a
	-descriptionComponents-like mechanism to simplify implementation.
*/
- (NSString *) shortDescription;
- (NSString *) shortDescriptionComponents;

@end


/*	Under Mac OS X 10.4 and earlier, but not GNUstep, the error string
	parameters for the property list parsing primitive methods in
	NSPropertyListSerialization would contain unreleased strings. To avoid
	leaking, it is necessary to release them. This does not affect programs
	linked against the Mac OS X 10.5 SDK.
*/
#if OOLITE_MAC_OS_X
	#if defined OOLITE_LEOPARD
		#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 0
	#else
		#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 1
	#endif
#else
	#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 0
#endif



/*	OOInteger and OOUInteger: int (32-bit) on 32-bit platforms, long (64-bit)
	on 64-bit platforms. This is equivalent to NSInteger/NSUInteger in OS X
	10.5 and GNUstep 1.16.
	
	Why not long in 32-bit? Because we want to avoid "multiple methods"
	warnings when using SDKs using int.
	
	Similarly, CGFloat is 64-bit in 64-bit and 32-bit in 32-bit under OS X.
	There is no need to make this distinction in GNUStep.
*/

#if OOLITE_MAC_OS_X
	#if OOLITE_LEOPARD && NSINTEGER_DEFINED
		// If OS X 10.5 SDK, use system definitions.
		typedef NSInteger		OOInteger;
		typedef NSUInteger		OOUInteger;
		typedef CGFloat			OOCGFloat;
		#if __LP64__
			#define OOLITE_64_BIT			1
		#endif
	#else
		// Older SDK, 32-bit only.
		typedef int				OOInteger;
		typedef unsigned int	OOUInteger;
		typedef float			OOCGFloat;
	#endif
#elif OOLITE_GNUSTEP
	/* MKW 20090414 - GNUStep 1.19 still has the NSInteger bug, so let's revert
	 * to the older definitions for OOInteger */
	#if GNUSTEP_BASE_MAJOR_VERSION > 1 || GNUSTEP_BASE_MINOR_VERSION >= 20
		typedef NSInteger OOInteger;
		typedef NSUInteger OOUInteger;
	#else
		// Older versions of GNUstep used int on all systems.
		typedef int				OOInteger;
		typedef unsigned int	OOUInteger;
	#endif
	typedef float			OOCGFloat;
#endif

#ifndef OOLITE_64_BIT
	#define OOLITE_64_BIT				0
#endif


#if OOLITE_MAC_OS_X
	#define OOLITE_NATIVE_EXCEPTIONS	1
	
	#undef NS_DURING
	#undef NS_HANDLER
	#undef NS_ENDHANDLER
	#undef NS_VALUERETURN
	#undef NS_VOIDRETURN
	
	#define NS_DURING					@try {
	#define NS_HANDLER					} @catch (NSException *localException) {
	#define NS_ENDHANDLER				}
	#define NS_VALUERETURN(v,t)			return (v)
	#define NS_VOIDRETURN				return
#elif OOLITE_GNUSTEP
	#define OOLITE_NATIVE_EXCEPTIONS	defined(_NATIVE_OBJC_EXCEPTIONS)
#endif


/*	For some reason, return types for some comparison callbacks are typed
	NSInteger/int under OS X but (more sensibly) NSComparisonResult under
	GNUstep.
*/
#if OOLITE_MAC_OS_X
	typedef OOInteger OOComparisonResult;
#else
	typedef NSComparisonResult OOComparisonResult;
#endif


#if OOLITE_MAC_OS_X && OOLITE_LEOPARD
	#define OOLITE_FAST_ENUMERATION		1
#else
	#define OOLITE_FAST_ENUMERATION		0
#endif


/*	Speech synthesis
*/
#if OOLITE_MAC_OS_X || defined(HAVE_LIBESPEAK)
	#define OOLITE_SPEECH_SYNTH			1
	#if defined(HAVE_LIBESPEAK)
		#define OOLITE_ESPEAK			1
	#else
		#define OOLITE_ESPEAK			0
	#endif
#else
	#define OOLITE_SPEECH_SYNTH			0
#endif


/*	@optional directive for protocols: added in Objective-C 2.0.
	
	As a nasty, nasty hack, the OOLITE_OPTIONAL(foo) macro allows an optional
	section with or without @optional. If @optional is not available, it
	actually ends the protocol and starts an appropriately-named informal
	protocol, i.e. a category on NSObject. Since it ends the protocol, there
	can only be one and there's no way to switch back to @required.
*/
#ifndef OOLITE_HAVE_PROTOCOL_OPTIONAL
#define OOLITE_HAVE_PROTOCOL_OPTIONAL OOLITE_LEOPARD
#endif

#if OOLITE_HAVE_PROTOCOL_OPTIONAL
#define OOLITE_OPTIONAL(protocolName) @optional
#else
#define OOLITE_OPTIONAL(protocolName) @end @interface NSObject (protocolName ## Optional)
#endif


#ifndef OO_DEBUG
#define OO_DEBUG 0
#endif
