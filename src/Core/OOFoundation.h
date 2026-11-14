/*

OOFoundation.h

Platform and build macros (OOLITE_WINDOWS, OOLITE_LINUX, OOLITE_MACOS,
OOLITE_DEBUG and friends) and the basic types every game file uses.

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

#include <math.h>     // IWYU pragma: export
#include <stdbool.h>  // IWYU pragma: export

#ifdef NDEBUG
#define OOLITE_DEBUG 0
#else
#define OOLITE_DEBUG 1
#endif

#if !OOLITE_DEBUG
#define NS_BLOCK_ASSERTIONS 1
#endif

/*	OO_DEBUG is set by the build system for debug builds (meson.build adds
   -DOO_DEBUG when optimization==0 or debug==true; the deployment/test/dev
   flavours never do).

        Hoisted here from further down the file because the enumeration macros
   below have to test it, and a macro cannot be defined in terms of one the
   preprocessor has not seen yet. Nothing between here and the old site defines
   it, so the meaning is unchanged.
*/
#ifndef OO_DEBUG
// Defined by makefile/Xcode in debug builds.
#define OO_DEBUG 0
#endif

#include <assert.h>  // IWYU pragma: export

#include "oofnd/objc/OOFoundationTypes.h"  // IWYU pragma: export

#ifdef __clang__
#define OOLITE_HAVE_CLANG 1
#else
#define OOLITE_HAVE_CLANG 0
#endif

#if defined(__GNUC__) && !OOLITE_HAVE_CLANG
// GCC version; for instance, 40300 for 4.3.0. Deliberately undefined in Clang
// (which defines fake __GNUC__ macros for compatibility).
#define OOLITE_GCC_VERSION \
  (__GNUC__ * 10000 + __GNUC_MINOR__ * 100 + __GNUC_PATCHLEVEL__)
#endif

#include <limits.h>  // IWYU pragma: export
#include <stdint.h>  // IWYU pragma: export

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

#if !defined(MAX)
#define MAX(A, B)            \
  ({                         \
    __typeof__(A) __a = (A); \
    __typeof__(B) __b = (B); \
    __a > __b ? __a : __b;   \
  })
#endif

#if !defined(MIN)
#define MIN(A, B)            \
  ({                         \
    __typeof__(A) __a = (A); \
    __typeof__(B) __b = (B); \
    __a < __b ? __a : __b;   \
  })
#endif

#ifdef HAVE_LIBESPEAK
#define OOLITE_SPEECH_SYNTH 1
#define OOLITE_ESPEAK 1
#endif

// macOS as a platform (SDL front end, Apple's GL and libc).
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

#ifndef OOLITE_SPEECH_SYNTH
#define OOLITE_SPEECH_SYNTH 0
#endif

#ifndef OOLITE_ESPEAK
#define OOLITE_ESPEAK 0
#endif

#ifndef OOLITE_64_BIT
#define OOLITE_64_BIT 0
#endif

#include "OOLogging.h"            // IWYU pragma: export
#include "oofnd/objc/OOObject.h"  // IWYU pragma: export

/*	The description family (-descriptionComponents & co.,
 * oo::DescriptionOf), Foundation-free.
 */
#include "OODescription.h"  // IWYU pragma: export
#include "OOEnumFlags.h"    // IWYU pragma: export

/*	The ordering type and values: an std::ptrdiff_t enum with Foundation's
   NSComparisonResult values.
*/
enum class OOComparisonResult : std::ptrdiff_t {
  kAscending = -1,
  kSame = 0,
  kDescending = 1,
};
static_assert(static_cast<std::ptrdiff_t>(OOComparisonResult::kAscending) ==
              -1);
static_assert(static_cast<std::ptrdiff_t>(OOComparisonResult::kSame) == 0);
static_assert(static_cast<std::ptrdiff_t>(OOComparisonResult::kDescending) ==
              1);

// OO_DEBUG is defined at the top of this file, where the enumeration macros can
// test it.

#if OOLITE_WINDOWS
#ifndef OO_GAME_DATA_TO_USER_FOLDER
#define OO_GAME_DATA_TO_USER_FOLDER 0
#endif
#endif
