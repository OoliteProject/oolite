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

#import <Foundation/Foundation.h>
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

#ifdef GNUSTEP_BASE_LIBRARY
#define OOLITE_GNUSTEP 1

#if (GNUSTEP_BASE_MAJOR_VERSION == 1 && GNUSTEP_BASE_MINOR_VERSION < 28)
#error Oolite cannot be built using GNUstep earlier than 1.28.
#endif
#else
#define OOLITE_MAC_OS_X 1

/*	Useful macro copied from GNUstep.
 */
#ifndef DESTROY
#define DESTROY(x)    \
    do {              \
        id x_ = x;    \
        x = nil;      \
        [x_ release]; \
    } while (0)
#endif
#endif

#ifdef __clang__
#define OOLITE_HAVE_CLANG 1
#else
#define OOLITE_HAVE_CLANG 0
#endif

#if defined(__GNUC__) && !OOLITE_HAVE_CLANG
// GCC version; for instance, 40300 for 4.3.0. Deliberately undefined in Clang (which defines fake __GNUC__ macros for compatibility).
#define OOLITE_GCC_VERSION (__GNUC__ * 10000 + __GNUC_MINOR__ * 100 + __GNUC_PATCHLEVEL__)
#endif

#if OOLITE_MAC_OS_X && defined(OOLITE_SDL_MAC)
/*	macOS build using Apple Foundation with the SDL front end (the Cocoa
        front end no longer exists). OOLITE_MAC_OS_X selects Apple Foundation and
        OS-level behaviour; UI-level code takes the OOLITE_SDL path.
 */
#define OOLITE_SDL 1
#endif

#if OOLITE_GNUSTEP || OOLITE_SDL
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
/*	Objective-C++ is built as C++20 (ADR-0011; proposed ADR-0028). The true/false macros below
        stay exactly as they were (game code keeps its int-typed true/false), but a C++20 standard
        header parsed after them breaks: <optional> has `bool(__x) <=> false`, i.e. bool <=> int.
        So those headers are parsed here first, with the real keywords; their include guards make
        every later #include of them a no-op. extern "C++" because OOFoundation.h is sometimes reached
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

#import "Comparison.h"

/* Define AppKit constants for events */
enum {
    NSUpArrowFunctionKey = 0xF700,
    NSDownArrowFunctionKey = 0xF701,
    NSLeftArrowFunctionKey = 0xF702,
    NSRightArrowFunctionKey = 0xF703,
    NSF1FunctionKey = 0xF704,
    NSF2FunctionKey = 0xF705,
    NSF3FunctionKey = 0xF706,
    NSF4FunctionKey = 0xF707,
    NSF5FunctionKey = 0xF708,
    NSF6FunctionKey = 0xF709,
    NSF7FunctionKey = 0xF70A,
    NSF8FunctionKey = 0xF70B,
    NSF9FunctionKey = 0xF70C,
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
#define OOLITE_GNUSTEP 0
#endif

#ifndef OOLITE_MAC_OS_X
#define OOLITE_MAC_OS_X 0
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

#import "OOLogging.h"

@interface NSObject (OODescriptionComponents)

/*	In order to allow implementations of -description to inherit description
        components from superclasses, and to allow implementations of -description
        and -oo_jsDescription to share code, both are implemented as wrappers
        around -descriptionComponents. -descriptionComponents should provide
        information about an object without a class name or surrounding
        punctuation. -description will wrap the components like this:
                <ClassName 0xnnnnnnnn>{descriptionComponents}
        and -oo_jsDescription will wrap them like this:
                [oo_jsClassName descriptionComponents]
*/
- (NSString*)descriptionComponents;

/*	A lot of Oolite's -description implementations are rather long, and many
        embed other descriptions. -shortDescription provides a truncated
        alternative, while -shortDescriptionComponents provides a
        -descriptionComponents-like mechanism to simplify implementation.
*/
- (NSString*)shortDescription;
- (NSString*)shortDescriptionComponents;

@end

#if OOLITE_MAC_OS_X
#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 1
#else
#define OOLITE_RELEASE_PLIST_ERROR_STRINGS 0
#endif

/*	For some reason, return types for some comparison callbacks are typed
        NSInteger/int under OS X but (more sensibly) NSComparisonResult under
        GNUstep.
*/
#if OOLITE_MAC_OS_X
typedef NSInteger OOComparisonResult;
#else
typedef NSComparisonResult OOComparisonResult;
#endif

/*	Fast enumeration (for (x in y) syntax) is supported in all Mac compilers
        when targeting 10.5 or later, and in gcc 4.6 with the GNU libobjc runtime.
        At the time of writing, GNUstep stable does not support gcc 4.6, but it
        already has support for the fast enumeration protocol in its collection
        classes.

        All release versions of clang support fast enumeration, assuming libobjc2
        or ObjectiveC2.framework is being used. We shall make that assumption.

        References:
                http://lists.gnu.org/archive/html/discuss-gnustep/2011-02/msg00019.html
                http://wiki.gnustep.org/index.php/ObjC2_FAQ
        -- Ahruman 2011-02-04
*/

/*	Enumeration macros:
        foreach(VAR, COLLECTION) enumerates the members of an array or set, setting
        the variable VAR to a member on each pass.
        foreachkey(VAR, DICT) enumerates the keys of a dictionary the same way.

        Example:
                id element = nil;
                foreach (element, array)
                {
                        OOLog(@"element", @"%@", element);
                }

    These are based on macros by Jens Alfke.

        In a DEBUG build these route through the enumeration-order shuffle
        (OOEnumerationShuffle.h): with OO_SHUFFLE_ENUMERATION set to a seed, dictionaries and
        sets are enumerated in a seeded, reproducible order instead of GNUstep's hash order, so
        code that silently depends on that order fails here rather than after the C++ port.

        The two functions are declared here rather than by including OOEnumerationShuffle.h,
        which includes this file; the documentation lives there.

        In every non-debug flavour (deployment, test, dev) OO_DEBUG is 0 and the macros below
        are character-for-character the upstream ones, so the shuffle is compiled out rather
        than branched around: an unset OO_SHUFFLE_ENUMERATION cannot change behaviour because
        in a shipping build there is no code to change it.
*/
/* OO_ENUMERATION_MACROS_BEGIN - tools/check-enumeration-shuffle.sh extracts between these
   sentinels and preprocesses the block under both settings of OO_DEBUG. Do not remove them
   without updating that script. */
#if OO_DEBUG

id OOShuffledKeys(id dictionary);
id OOShuffledObjects(id collection);

#define foreach(VAR, COLLECTION) for (VAR in OOShuffledObjects(COLLECTION))
#define foreachkey(VAR, DICT) for (VAR in OOShuffledKeys(DICT))

#else

#define foreach(VAR, COLLECTION) for (VAR in COLLECTION)
#define foreachkey(VAR, DICT) for (VAR in DICT)

#endif
/* OO_ENUMERATION_MACROS_END */

/*	Support for foreach() with NSEnumerators in GCC.
        It works without this with for (x in y) support, but we leave it defined
        to reduce differences between different build environments.
*/
@interface NSEnumerator (OOForEachSupport)
- (NSEnumerator*)objectEnumerator;
@end

#define OOLITE_OPTIONAL(protocolName) @optional

/*	instancetype contextual keyword; added in Clang 3.0ish.

        Pseudo-type indicating that the return value of an instance method is an
        instance of the same class as the receiver, or for a class mothod, is an
        instance of that class.

        For example, given:
                @interface Foo: NSObject
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
#if __OBJC__ && !__has_feature(objc_instancetype)
typedef id instancetype;
#endif

// OO_DEBUG is defined at the top of this file, where the enumeration macros can test it.

#if OOLITE_WINDOWS
#ifndef OO_GAME_DATA_TO_USER_FOLDER
#define OO_GAME_DATA_TO_USER_FOLDER 0
#endif
#endif
