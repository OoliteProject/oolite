/*

OOStringExpander.h

Functions for expanding escape codes and key references in strings.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the impllied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/


#import "OOCocoa.h"
#import "OOMaths.h"


// Option flags for OOExpandDescriptionString().
enum
{
	kOOExpandForJavaScript		= 0x00000001,	/// Report warnings through JavaScript runtime system instead of normal logging.
	kOOExpandBackslashN			= 0x00000002,	/// Convert literal "\\n"s to line breaks (used for missiontext.plist for historical reasons).
	kOOExpandGoodRNG			= 0x00000004,	/// Use RANDROT for selecting from description arrays and for %N expansion.
	kOOExpandReseedRNG			= 0x00000008,	/// Set "really random" seeds while expanding.
	kOOExpandKey				= 0x00000010,	/// Treat string as a key. Expand(@"foo", kOOExpandKey) == Expand(@"[foo]", kOOExpandNoOptions).

	kOOExpandNoOptions			= 0
};
typedef NSUInteger OOExpandOptions;


/*
	OOExpandDescriptionString(string, seed, overrides, locals, systemName, recurse, options)
	
	Apply the following transformations to a string:
	  * [commander_name] is replaced with the player character's name.
	  * [commander_shipname] is replaced with the player ship's name.
	  * [commander_shipdisplayname] is replaced with the player ship's display
	    name.
	  * [commander_rank] is replaced with the descriptive name of the player's
	    kill rank.
	  * [commander_legal_status] is replaced with the descriptive name for the
	    player's bounty ("Clean" etc)
	  * [commander_bounty] is replaced with the player's numerical bounty.
	  * [credits_number] is replaced with the player's formatted credit balance.
	  * [_oo_legacy_credits_number] is replaced with the player's credit balance
	    in simple #.0 format (this is substituted for [credits_number] by the
		legacy script engine).
	  * [N], where N is an integer, is looked up in system_description in
	    descriptions.plist. This is an array of arrays of five strings each.
	    Each [N] lookup selects entry N of the outer array, then selects a
	    string from the Nth inner array at pseudo-random. The result is then
	    expanded recursively.
	  * [key], where key is any string not specified above, is handled as
	    follows:
	      - If it is found in <overrides>, use the corresponding value.
	      - Otherwise, look it up in descriptions.plist. If a string or number
	        is found, use that; if an array is found, select an item from it
	        at random.
	      - Otherwise, if it is a mission variable name (prefixed with
	        mission_), use the value of the mission variable.
		  - Otherwise, if it is found in <legacyLocals>, use the corresponding
			value.
		  - Otherwise, if it is a whitelisted legacy script property, look it
		    up and insert the value.
		  The resulting string is then recursively expanded.
	  * %H is replaced with <planetName>. If planetName is nil, a planet name
		is retrieved through -[Universe getSystemName:], treating <seed> as a
	    system seed.
	  * %I is equivalent to "%H[planetname-derivative-suffix]".
	  * %N is replaced with a random "alien" name using the planet name
	    digraphs. If used more than once in the same string, it will produce
	    the same name on each occurence.
	  * %R is like %N but, due to a bug, misses some possibilities. Deprecated.
	  * %JNNN, where NNN is a three-digit integer, is replaced with the name
	    of system ID NNN in the current galaxy.
	  * %% is replaced with %.
	  * %[ is replaced with [.
	  * %] is replaced with ].
	
	Syntax errors and, in non-Deployment builds, warnings may be generated. If
	<options & kOOExpandForJavaScript>, warnings are sent through
	OOJSReportWarning, otherwise they are logged.
	
	If <options & kOOExpandBackslashN>, literal \n in strings (i.e., "\\n") are
	converted to line breaks. This is used for expanding missiontext.plist
	entries, which may have literal \n especially in XML format.
*/
NSString *OOExpandDescriptionString(NSString *string, Random_Seed seed, NSDictionary *overrides, NSDictionary *legacyLocals, NSString *systemName, OOExpandOptions options);


/*
	OOGenerateSystemDescription(seed, name)
	
	Generates the default system description for the specified system seed.
	Equivalent to OOExpand(@"[system-description-string]"), except that it
	uses a special PRNG setting to tie the description to the seed.
	
	NOTE: this does not apply planetinfo overrides. To get the actual system
	description, use [UNIVERSE generateSystemData:].
*/
NSString *OOGenerateSystemDescription(Random_Seed seed, NSString *name);


/**
	Expand a string with default options.
*/
#define OOExpand(string, ...) OOExpandFancyWithOptions([UNIVERSE systemSeed], nil, kOOExpandNoOptions, string, __VA_ARGS__)

/**
	Expand a string as though it were surrounded by brackets;
	OOExpandKey(@"foo", ...) is equivalent to OOExpand(@"[foo]", ...).
*/
#define OOExpandKey(key, ...) OOExpandFancyWithOptions([UNIVERSE systemSeed], nil, kOOExpandKey, key, __VA_ARGS__)

/**
	Like OOExpandKey(), but uses a random-er random seed to avoid repeatability.
 */
#define OOExpandKeyRandomized(key, ...) OOExpandFancyWithOptions([UNIVERSE systemSeed], nil, kOOExpandKey | kOOExpandGoodRNG | kOOExpandReseedRNG, key, __VA_ARGS__)

#define OOExpandWithSeed(string, seed, systemName, ...) OOExpandFancyWithOptions(seed, systemName, 0, string, __VA_ARGS__)

#define OOExpandKeyWithSeed(key, seed, systemName, ...) OOExpandFancyWithOptions(seed, systemName, kOOExpandKey, key, __VA_ARGS__)


#define OOExpandFancyWithOptions(seed, systemName, options, string, ...) \
	OOExpandDescriptionString(string, seed, OOEXPAND_ARG_DICTIONARY(__VA_ARGS__), nil, systemName, options)


// MARK: Danger zone! Everything beyond this point is scary.

/*	Given an argument list, return a dictionary whose keys are the literal
	arguments and whose values are objects representing the arguments' values
	(as per OO_CAST_PARAMETER() below).
	
	Note that the argument list will be preprocessor-expanded at this point.
 */
#define OOEXPAND_ARG_DICTIONARY(...) ( \
	(OOEXPAND_ARGUMENT_COUNT(__VA_ARGS__) == 0) ? \
	(NSDictionary *)nil : \
	[NSDictionary dictionaryWithObjects:OOEXPAND_OBJECTS_FROM_ARGS(__VA_ARGS__) \
	                            forKeys:OOEXPAND_NAMES_FROM_ARGS(__VA_ARGS__) \
	                              count:OOEXPAND_ARGUMENT_COUNT(__VA_ARGS__)] )

#define OOEXPAND_NAME_FROM_ARG(ITEM)  @#ITEM
#define OOEXPAND_NAMES_FROM_ARGS(...)  (NSString *[]){ OOEXPAND_MAP(OOEXPAND_NAME_FROM_ARG, __VA_ARGS__) }

#define OOEXPAND_OBJECTS_FROM_ARGS(...) (id[]){ OOEXPAND_MAP(OO_CAST_PARAMETER, __VA_ARGS__) }

/*	Limited boxing mechanism. ITEM may be an NSString *, NSNumber *, any
	integer type or any floating point type; the result is an NSNumber *,
	except if the parameter is an NSString * in which case it is returned
	unmodified.
 */
#define OO_CAST_PARAMETER(ITEM) \
	__builtin_choose_expr( \
		OOEXPAND_IS_OBJECT(ITEM), \
		OOCastParamObject, \
		__builtin_choose_expr( \
			OOEXPAND_IS_SIGNED_INTEGER(ITEM), \
			OOCastParamSignedInteger, \
			__builtin_choose_expr( \
				OOEXPAND_IS_UNSIGNED_INTEGER(ITEM), \
				OOCastParamUnsignedInteger, \
				__builtin_choose_expr( \
					OOEXPAND_IS_FLOAT(ITEM), \
					OOCastParamFloat, \
					__builtin_choose_expr( \
						OOEXPAND_IS_UNSIGNED_INTEGER(ITEM), \
						OOCastParamUnsignedInteger, \
						__builtin_choose_expr( \
							OOEXPAND_IS_DOUBLE(ITEM), \
							OOCastParamDouble, \
							(void)0 \
						) \
					) \
				) \
			) \
		) \
	)(ITEM)

// Test whether ITEM is a known object type.
// NOTE: id works here in clang, but not gcc.
#define OOEXPAND_IS_OBJECT(ITEM) ( \
	__builtin_types_compatible_p(typeof(ITEM), NSString *) || \
	__builtin_types_compatible_p(typeof(ITEM), NSNumber *))

// Test whether ITEM is a signed integer type.
// Some redundancy to avoid silliness across platforms; probably not necessary.
#define OOEXPAND_IS_SIGNED_INTEGER(ITEM) ( \
	__builtin_types_compatible_p(typeof(ITEM), char) || \
	__builtin_types_compatible_p(typeof(ITEM), short) || \
	__builtin_types_compatible_p(typeof(ITEM), int) || \
	__builtin_types_compatible_p(typeof(ITEM), long) || \
	__builtin_types_compatible_p(typeof(ITEM), long long) || \
	__builtin_types_compatible_p(typeof(ITEM), NSInteger) || \
	__builtin_types_compatible_p(typeof(ITEM), intptr_t) || \
	__builtin_types_compatible_p(typeof(ITEM), ssize_t) || \
	__builtin_types_compatible_p(typeof(ITEM), off_t))

// Test whether ITEM is an unsigned integer type.
// Some redundancy to avoid silliness across platforms; probably not necessary.
#define OOEXPAND_IS_UNSIGNED_INTEGER(ITEM) ( \
	__builtin_types_compatible_p(typeof(ITEM), unsigned char) || \
	__builtin_types_compatible_p(typeof(ITEM), unsigned short) || \
	__builtin_types_compatible_p(typeof(ITEM), unsigned int) || \
	__builtin_types_compatible_p(typeof(ITEM), unsigned long) || \
	__builtin_types_compatible_p(typeof(ITEM), unsigned long long) || \
	__builtin_types_compatible_p(typeof(ITEM), NSUInteger) || \
	__builtin_types_compatible_p(typeof(ITEM), uintptr_t) || \
	__builtin_types_compatible_p(typeof(ITEM), size_t))

// Test whether ITEM is a float.
// This is distinguished from double to expose optimization opportunities.
#define OOEXPAND_IS_FLOAT(ITEM) ( \
	__builtin_types_compatible_p(typeof(ITEM), float))

// Test whether ITEM is any other floating-point type.
#define OOEXPAND_IS_DOUBLE(ITEM) ( \
	__builtin_types_compatible_p(typeof(ITEM), double) || \
	__builtin_types_compatible_p(typeof(ITEM), long double))

// OO_CAST_PARAMETER() boils down to one of these.
static inline id OOCastParamObject(id object) { return object; }
static inline id OOCastParamSignedInteger(long long value) { return [NSNumber numberWithLongLong:value]; }
static inline id OOCastParamUnsignedInteger(unsigned long long value) { return [NSNumber numberWithUnsignedLongLong:value]; }
static inline id OOCastParamFloat(float value) { return [NSNumber numberWithFloat:value]; }
static inline id OOCastParamDouble(double value) { return [NSNumber numberWithDouble:value]; }


/*
	Evil macro magic.
	
	OOEXPAND_ARGUMENT_COUNT returns the number of elements in a __VA_ARGS__
	list. Trivially modified from code by Laurent Deniau and
	"arpad.goret...@gmail.com" (full name not available). Source:
	https://groups.google.com/forum/?fromgroups=#!topic/comp.std.c/d-6Mj5Lko_s
	
	This version relies on the GCC/Clang ##__VA_ARGS__ extension to handle
	zero-length lists. It supports up to 62 arguments.
	
	OOEXPAND_MAP applies a unary macro or function to each element of a
	parameter or initializer list. For example, "OOEXPAND_MAP(foo, 1, 2, 3)"
	is equivalent to "foo(1), foo(2), foo(3)".
*/

#define OOEXPAND_ARGUMENT_COUNT(...) \
		OOEXPAND_ARGUMENT_COUNT_INNER(_0, ##__VA_ARGS__, OOEXPAND_ARGUMENT_COUNT_63_VALUES())
#define OOEXPAND_ARGUMENT_COUNT_INNER(...) \
		OOEXPAND_ARGUMENT_COUNT_EXTRACT_64TH_ARG(__VA_ARGS__)
#define OOEXPAND_ARGUMENT_COUNT_EXTRACT_64TH_ARG( \
		 _1, _2, _3, _4, _5, _6, _7, _8, _9,_10, \
		_11,_12,_13,_14,_15,_16,_17,_18,_19,_20, \
		_21,_22,_23,_24,_25,_26,_27,_28,_29,_30, \
		_31,_32,_33,_34,_35,_36,_37,_38,_39,_40, \
		_41,_42,_43,_44,_45,_46,_47,_48,_49,_50, \
		_51,_52,_53,_54,_55,_56,_57,_58,_59,_60, \
		_61,_62,_63,N,...) N
#define OOEXPAND_ARGUMENT_COUNT_63_VALUES() \
		62,61,60, \
		59,58,57,56,55,54,53,52,51,50, \
		49,48,47,46,45,44,43,42,41,40, \
		39,38,37,36,35,34,33,32,31,30, \
		29,28,27,26,25,24,23,22,21,20, \
		19,18,17,16,15,14,13,12,11,10, \
		9,8,7,6,5,4,3,2,1,0


#define OOEXPAND_MAP(F, ...) \
		OOEXPAND_MAP_INNER(F, OOEXPAND_ARGUMENT_COUNT(__VA_ARGS__), __VA_ARGS__)
#define OOEXPAND_MAP_INNER(F, COUNTEXPR, ...) \
		OOEXPAND_MAP_INNER2(F, COUNTEXPR, __VA_ARGS__)
#define OOEXPAND_MAP_INNER2(F, COUNT, ...) \
		OOEXPAND_MAP_INNER3(F, OOEXPAND_MAP_IMPL_ ## COUNT, __VA_ARGS__)
#define OOEXPAND_MAP_INNER3(F, IMPL, ...) \
		IMPL(F, __VA_ARGS__)

#define OOEXPAND_MAP_IMPL_0(F, HEAD)
#define OOEXPAND_MAP_IMPL_1(F, HEAD)       F(HEAD)
#define OOEXPAND_MAP_IMPL_2(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_1(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_3(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_2(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_4(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_3(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_5(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_4(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_6(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_5(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_7(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_6(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_8(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_7(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_9(F, HEAD, ...)  F(HEAD), OOEXPAND_MAP_IMPL_8(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_10(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_9(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_11(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_10(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_12(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_11(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_13(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_12(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_14(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_13(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_15(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_14(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_16(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_15(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_17(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_16(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_18(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_17(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_19(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_18(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_20(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_19(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_21(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_20(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_22(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_21(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_23(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_22(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_24(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_23(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_25(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_24(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_26(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_25(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_27(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_26(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_28(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_27(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_29(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_28(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_30(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_29(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_31(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_30(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_32(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_31(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_33(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_32(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_34(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_33(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_35(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_34(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_36(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_35(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_37(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_36(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_38(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_37(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_39(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_38(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_40(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_39(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_41(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_40(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_42(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_41(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_43(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_42(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_44(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_43(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_45(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_44(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_46(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_45(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_47(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_46(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_48(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_47(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_49(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_48(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_50(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_49(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_51(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_50(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_52(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_51(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_53(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_52(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_54(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_53(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_55(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_54(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_56(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_55(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_57(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_56(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_58(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_57(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_59(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_58(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_60(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_59(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_61(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_60(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_62(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_61(F, __VA_ARGS__)
