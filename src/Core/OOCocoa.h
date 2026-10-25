/*

OOCocoa.h

Import OpenStep main headers and define some Macisms and other compatibility
stuff.

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

/*
 Expressions like #define FOO (1 && !defined(NDEBUG)) are formally invalid,
 causing a warning in Clang. This lets us write #define FOO (1 && OOLITE_DEBUG)
 instead.
 */
#pragma once

#ifdef NDEBUG
#define OOLITE_DEBUG 0
#else
#define OOLITE_DEBUG 1
#endif

#if !OOLITE_DEBUG
#define NS_BLOCK_ASSERTIONS 1
#endif


/*	OO_DEBUG is set by the build system for debug builds (meson.build adds -DOO_DEBUG when
	optimization==0 or debug==true; the deployment/test/dev flavours never do).

	Hoisted here from further down the file because the enumeration macros below have to
	test it, and a macro cannot be defined in terms of one the preprocessor has not seen
	yet. Nothing between here and the old site defines it, so the meaning is unchanged.
*/
#ifndef OO_DEBUG
// Defined by makefile/Xcode in debug builds.
#define OO_DEBUG					0
#endif


#include <math.h>
#include <stdbool.h>

#ifdef GNUSTEP_BASE_LIBRARY
	/*	No Foundation (oo-qps.17, ADR-0055): the C types it gave (NSInteger, NSRange, NSPoint...)
		come from the floor's header, which #errors beside any Foundation header, so nothing on
		this path can reach one. GNUSTEP_BASE_LIBRARY is the build's own define (src/meson).
	*/
	#if defined(_WIN32)
		/*	What gnustep-base's GSConfig.h gave every file through Foundation: the Windows API
			and Winsock, with the Windows BOOL renamed so Objective-C's stays BOOL.
		*/
		#define BOOL WinBOOL
		#define __OBJC_BOOL 1
		#include <winsock2.h>
		#include <windows.h>
		#undef __OBJC_BOOL
		#undef BOOL
	#endif
	#include <assert.h>
	#include "oofnd/objc/OOFoundationTypes.h"
	#define OOLITE_GNUSTEP			1
	
	// gnustep-base's macro; the Mac OS X path below defines the same one.
	
#else
	#import <AppKit/AppKit.h>
	
	#define OOLITE_MAC_OS_X			1
	#define OOLITE_SPEECH_SYNTH		1
	
	#if __LP64__
		#define OOLITE_64_BIT		1
	#endif
	
	/*	Useful macro copied from GNUstep.
	*/
	
	#if defined MAC_OS_X_VERSION_10_7 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7
		#define OOLITE_MAC_OS_X_10_7	1
	#endif
	
	#if defined MAC_OS_X_VERSION_10_8 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_8
		#define OOLITE_MAC_OS_X_10_8	1
	#endif

	#if OOLITE_MAC_OS_X && !defined(MAC_OS_X_VERSION_10_12)
		typedef NSUInteger NSWindowStyleMask;
	#endif
#endif


#ifndef OOLITE_MAC_OS_X_10_7
	#define OOLITE_MAC_OS_X_10_7	0
#endif

#ifndef OOLITE_MAC_OS_X_10_8
	#define OOLITE_MAC_OS_X_10_8	0
#endif


#ifdef __clang__
#define OOLITE_HAVE_CLANG			1
#else
#define OOLITE_HAVE_CLANG			0
#endif


#if defined(__GNUC__) && !OOLITE_HAVE_CLANG
// GCC version; for instance, 40300 for 4.3.0. Deliberately undefined in Clang (which defines fake __GNUC__ macros for compatibility).
#define OOLITE_GCC_VERSION			(__GNUC__ * 10000 + __GNUC_MINOR__ * 100 + __GNUC_PATCHLEVEL__)
#endif


#if OOLITE_GNUSTEP
#include <stdint.h>
#include <limits.h> // to get UINT_MAX


#define OOLITE_SDL					1

#ifdef WIN32
	#define OOLITE_WINDOWS				1
	#if defined(_WIN64)
		#define OOLITE_64_BIT			1
	#endif
#endif

#ifdef LINUX
#define OOLITE_LINUX				1
#endif


#if defined(__cplusplus)
/*	Objective-C++ is built as C++20 (ADR-0011; proposed ADR-0028). The true/false macros below
	stay exactly as they were (game code keeps its int-typed true/false), but a C++20 standard
	header parsed after them breaks: <optional> has `bool(__x) <=> false`, i.e. bool <=> int.
	So those headers are parsed here first, with the real keywords; their include guards make
	every later #include of them a no-op. extern "C++" because OOCocoa.h is sometimes reached
	from inside an extern "C" block (OOMaths.h).
*/
extern "C++" {
#include <compare>
#include <optional>
}
#endif

#define true						1
#define false						0

#if !defined(MAX)
	#define MAX(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a > __b ? __a : __b; })
#endif

#if !defined(MIN)
	#define MIN(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __a : __b; })
#endif

#ifdef HAVE_LIBESPEAK
	#define OOLITE_SPEECH_SYNTH		1
	#define OOLITE_ESPEAK			1
#endif


// Pseudo-keywords used for AppKit UI bindings.
#ifndef IBOutlet
#define IBOutlet /**/
#endif
#ifndef IBAction
#define IBAction void
#endif



#endif


#ifndef OOLITE_GNUSTEP
#define OOLITE_GNUSTEP				0
#endif

#ifndef OOLITE_MAC_OS_X
#define OOLITE_MAC_OS_X				0
#endif

#ifndef OOLITE_WINDOWS
#define OOLITE_WINDOWS				0
#endif

#ifndef OOLITE_LINUX
#define OOLITE_LINUX				0
#endif

#ifndef OOLITE_SDL
#define OOLITE_SDL					0
#endif

#ifndef OOLITE_SPEECH_SYNTH
#define OOLITE_SPEECH_SYNTH			0
#endif

#ifndef OOLITE_ESPEAK
#define OOLITE_ESPEAK				0
#endif

#ifndef OOLITE_64_BIT
	#define OOLITE_64_BIT			0
#endif


#define OOLITE_PROPERTY_SYNTAX	(OOLITE_MAC_OS_X || OOLITE_HAVE_CLANG)


#include "OOLogging.h"


#include "oofnd/objc/OOObject.h"

/*	The description family (-cxx_descriptionComponents & co., oo::DescriptionOf), Foundation-free
	(proposed ADR-0055 item 1).
*/
#include "OODescription.h"

#if OOLITE_MAC_OS_X
	#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 1
#else
	#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 0
#endif


/*	The ordering type and values under Oolite's own names (bead oo-3yh0): game code spells
	OOComparisonResult / OOOrdered*, never the NS names. Since oo-qps.17 it is Oolite's own
	NSInteger enum with Foundation's values; the Mac OS X path (Phase 5) keeps AppKit's NSInteger
	callbacks and Foundation's constants.
*/
#if OOLITE_MAC_OS_X
	typedef NSInteger OOComparisonResult;
	#ifdef __cplusplus
	inline constexpr OOComparisonResult OOOrderedAscending = NSOrderedAscending;
	inline constexpr OOComparisonResult OOOrderedSame = NSOrderedSame;
	inline constexpr OOComparisonResult OOOrderedDescending = NSOrderedDescending;
	#endif
#elif defined(__cplusplus)
	enum OOComparisonResult: NSInteger
	{
		OOOrderedAscending = -1,
		OOOrderedSame = 0,
		OOOrderedDescending = 1
	};
#endif


/*	@optional directive for protocols: added in Objective-C 2.0.
	
	As a nasty, nasty hack, the OOLITE_OPTIONAL(foo) macro allows an optional
	section with or without @optional. If @optional is not available, it
	actually ends the protocol and starts an appropriately-named informal
	protocol, i.e. a category on the root class. Since it ends the protocol, there
	can only be one and there's no way to switch back to @required.
*/
#ifndef OOLITE_HAVE_PROTOCOL_OPTIONAL
#define OOLITE_HAVE_PROTOCOL_OPTIONAL  (OOLITE_MAC_OS_X || OOLITE_HAVE_CLANG || OOLITE_GCC_VERSION >= 40700)
#endif

#if OOLITE_HAVE_PROTOCOL_OPTIONAL
#define OOLITE_OPTIONAL(protocolName) @optional
#else
#define OOLITE_OPTIONAL(protocolName) @end @interface OOObject (protocolName ## Optional)
#endif


/*	instancetype contextual keyword; added in Clang 3.0ish.
	
	Pseudo-type indicating that the return value of an instance method is an
	instance of the same class as the receiver, or for a class mothod, is an
	instance of that class.
	
	For example, given:
		@interface Foo: OOObject
		+ (instancetype) fooWithProperty:(id)property;
		@end
		
		@interface Bar: Foo
		@end
	
	the type of [Bar fooWithProperty] is inferred to be Bar *.
	
	Clang treats methods of type id as instancetype when their names begin with
	+alloc, +new, -init, -autorelease, -retain, or -self.
	
	For compilers without instancetype support, id is appropriate but less
	type-safe.
	
	NOTE: it is not appropriate to use instancetype for a factory method which
	chooses which publicly-visible subclass to instantiate based on parameters.
	For instance, calling one of the OOMaterial convenience factory methods on
	OOShaderMaterial might return an OOSingleTextureMaterial, so the correct
	return type is either OOMaterial or id.
	On the other hand, it is appropriate on factory methods which just wrap
	the corresponding -init and/or -init + configuration through properties.
	(Such factory methods should be implemented in terms of [[self alloc]
	init...].)
*/


// OO_DEBUG is defined at the top of this file, where the enumeration macros can test it.

#if OOLITE_WINDOWS
#ifndef OO_GAME_DATA_TO_USER_FOLDER
#define OO_GAME_DATA_TO_USER_FOLDER	0
#endif
#endif
