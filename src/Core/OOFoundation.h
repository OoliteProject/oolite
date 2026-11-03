/*

OOFoundation.h

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

#include <math.h>
#include <stdbool.h>

/*	Apple's -sortedArrayUsingFunction: and friends take NSInteger (*)(id, id, void*). Oolite's
        sort functions return NSComparisonResult, which has the same size and calling convention
        but is a distinct enum type that C++ will not convert implicitly. GNUstep declares them
        with NSComparisonResult, so there the functions are passed as they are.
*/
#ifdef GNUSTEP_BASE_LIBRARY
#define OOSortFunction(function) (function)
#else
#define OOSortFunction(function) ((NSInteger (*)(id, id, void*))(function))
#endif

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
#define OO_DEBUG 0
#endif

#include "oofnd/objc/OOFoundationTypes.h"
#include <assert.h>

#ifdef __clang__
#define OOLITE_HAVE_CLANG 1
#else
#define OOLITE_HAVE_CLANG 0
#endif

#if defined(__GNUC__) && !OOLITE_HAVE_CLANG
// GCC version; for instance, 40300 for 4.3.0. Deliberately undefined in Clang (which defines fake __GNUC__ macros for compatibility).
#define OOLITE_GCC_VERSION (__GNUC__ * 10000 + __GNUC_MINOR__ * 100 + __GNUC_PATCHLEVEL__)
#endif

#include <limits.h> // to get UINT_MAX
#include <stdint.h>

#define OOLITE_SDL 1

#ifdef WIN32
#define OOLITE_WINDOWS 1
#if defined(_WIN64)
#define OOLITE_64_BIT 1
#endif
#endif

#ifdef LINUX
#define OOLITE_LINUX 1
#endif

#if defined(__cplusplus)
/*	The game is built as C++20. The true/false macros below
        stay exactly as they were (game code keeps its int-typed true/false),
   but a C++20 standard header parsed after them breaks: <optional> has
   `bool(__x) <=> false`, i.e. bool <=> int. So those headers are parsed here
   first, with the real keywords; their include guards make every later #include
   of them a no-op. extern "C++" because OOFoundation.h is sometimes reached
        from inside an extern "C" block (OOMaths.h).
*/
extern "C++" {
#include <compare>
#include <optional>
}
#endif

#if OOLITE_GNUSTEP
#define true 1
#define false 0
#endif

#if !defined(MAX)
#define MAX(A, B) ({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a > __b ? __a : __b; })
#endif

#if !defined(MIN)
#define MIN(A, B) ({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __a : __b; })
#endif

#ifdef HAVE_LIBESPEAK
#define OOLITE_SPEECH_SYNTH 1
#define OOLITE_ESPEAK 1
#endif

// Pseudo-keywords used for AppKit UI bindings.
#ifndef IBOutlet
#define IBOutlet /**/
#endif
#ifndef IBAction
#define IBAction void
#endif

#ifndef OOLITE_MAC_OS_X
#define OOLITE_MAC_OS_X 0
#endif

// macOS as a platform (SDL front end, Apple's GL and libc), without Apple
// Foundation. OOLITE_MAC_OS_X above is the legacy Foundation/Cocoa switch and
// stays 0.
#ifdef __APPLE__
#define OOLITE_MACOS 1
#else
#define OOLITE_MACOS 0
#endif

#ifndef OOLITE_WINDOWS
#define OOLITE_WINDOWS 0
#endif

#ifndef OOLITE_LINUX
#define OOLITE_LINUX 0
#endif

#ifndef OOLITE_SDL
#define OOLITE_SDL 0
#endif

// The Cocoa (AppKit) front end, as opposed to Apple Foundation with SDL.
#define OOLITE_MAC_COCOA_UI (OOLITE_MAC_OS_X && !OOLITE_SDL)

#ifndef OOLITE_SPEECH_SYNTH
#define OOLITE_SPEECH_SYNTH 0
#endif

#ifndef OOLITE_ESPEAK
#define OOLITE_ESPEAK 0
#endif

#ifndef OOLITE_64_BIT
#define OOLITE_64_BIT 0
#endif

#define OOLITE_PROPERTY_SYNTAX (OOLITE_MAC_OS_X || OOLITE_HAVE_CLANG)

#include "OOLogging.h"

#include "oofnd/objc/OOObject.h"

/*	The description family (-cxx_descriptionComponents & co.,
 * oo::DescriptionOf), Foundation-free.
 */
#include "OODescription.h"

#if OOLITE_MAC_OS_X
#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 1
#else
#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 0
#endif

/*	The ordering type and values under Oolite's own names: game code spells
        OOComparisonResult / OOOrdered*, never the NS names. It is Oolite's own
   NSInteger enum with Foundation's values; the Mac OS X path keeps AppKit's
   NSInteger callbacks and Foundation's constants.
*/
#if OOLITE_MAC_OS_X
typedef NSInteger OOComparisonResult;
inline constexpr OOComparisonResult OOOrderedAscending = NSOrderedAscending;
inline constexpr OOComparisonResult OOOrderedSame = NSOrderedSame;
inline constexpr OOComparisonResult OOOrderedDescending = NSOrderedDescending;
#else
enum OOComparisonResult : NSInteger {
    OOOrderedAscending = -1,
    OOOrderedSame = 0,
    OOOrderedDescending = 1
};
#endif

#define OOLITE_OPTIONAL(protocolName) @optional

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
#define OO_GAME_DATA_TO_USER_FOLDER 0
#endif
#endif
