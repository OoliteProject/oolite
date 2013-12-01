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
	kOOExpandForJavaScript		= 0x00000001,
	kOOExpandBackslashN			= 0x00000002,
	kOOExpandGoodRNG			= 0x00000004,	

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
	  * %H is replaced with <planetName>. If systemName is nil, a planet name
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
	OOExpandWithSeed(string, seed, systemName)
	
	Expand string with a specified system seed.
	
	Equivalent to OOExpandDescriptionString(<string>, <seed>, nil, nil, <systemName>, kOOExpandNoOptions);
*/
NSString *OOExpandWithSeed(NSString *string, Random_Seed seed, NSString *systemName);


/*
	OOExpand(string)
	
	Expand a string with default options.
	
	Equivalent to OOExpandWithSeed(string, [UNIVERSE systemSeed], nil);
*/
NSString *OOExpand(NSString *string);


/*
	OOExpandKeyWithSeed(key, seed, systemName)
 
	Expand a string as though it was surrounded by brackets.
	OOExpandKeyWithSeed(@"foo", ...) is equivalent to
	OOExpandWithSeed(@"[foo]", ...).
*/
NSString *OOExpandKeyWithSeed(NSString *key, Random_Seed seed, NSString *systemName);


/*
	OOExpandKey(string)
	
	Expand a string as though it was surrounded by brackets; OOExpandKey(@"foo")
	is equivalent to OOExpand(@"[foo]").
*/
NSString *OOExpandKey(NSString *key);


/*
	OOExpandKeyRandomized(key)
	
	Like OOExpandKey(), but uses a random-er random seed to avoid repeatability.
*/
NSString *OOExpandKeyRandomized(NSString *key);


/*
	OOGenerateSystemDescription(seed, name)
	
	Generates the default system description for the specified system seed.
	Equivalent to OOExpand(@"[system-description-string]"), except that it
	uses a special PRNG setting to tie the description to the seed.
	
	NOTE: this does not apply planetinfo overrides. To get the actual system
	description, use [UNIVERSE generateSystemData:].
*/
NSString *OOGenerateSystemDescription(Random_Seed seed, NSString *name);
