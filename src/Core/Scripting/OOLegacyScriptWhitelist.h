/*

OOLegacyScriptWhitelist.h

Functions to apply method whitelist and basic tokenization to legacy scripts.


A sanitized script is an array of zero or more sanitized statements.

A sanitized statement is an array whose first element is a boolean indicating
whether it's a conditional statement (true) or an action statement (false).

A conditional statement has three additional elements. The first is an array
of sanitized conditions (see below). The second is a sanitized script to
execute if the condition evaluates to true. The third is a sanitized script to
execute if the condition evaluates to false.

An action statement has one or two additional elements, both strings. The
first is a selector. If the selector ends with a colon (i.e., takes an
argument), the second is the argument.


A sanitized condition is an array of the form:
	(opType, rawString, selector, comparisonType, operandArray).

opType and comparisonType are NSNumbers containing OOOperationType and
OOComparisonType enumerators, respectively.

rawString is the original textual representation of the condition for
display purposes.

selector is a string, either a method selector or a mission/local
variable name.

operandArray is an array of operands. Each operand is itself an array
of two items: a boolean indicating whether it's a method selector
(true) or a string (false), and a string.

The special opType OP_FALSE doesn't require any other elements in the
array. All other valid opTypes require the array to have five elements.


A complete example: given the following script (the Cloaking Device mission
script from Oolite 1.65):
	(
		{
			conditions = (
				"galaxy_number equal 4",
				"status_string equal STATUS_EXITING_WITCHSPACE",
				"mission_cloak undefined"
			);
			do = (
				{
					conditions = ("mission_cloakcounter undefined");
					do = ("set: mission_cloakcounter 0");
				},
				"increment: mission_cloakcounter",
				"checkForShips: asp-cloaked",
				{
					conditions = ("shipsFound_number equal 0", "mission_cloakcounter greaterthan 6");
					do = ("addShips: asp-cloaked 1", "addShips: asp-pirate 2");
				}
			);
		}
	)
the sanitized form (with rawString values replaced with "..." for simplicity) is:
	(
		(
			true,	// This is a conditonal statement
			(		// conditions
				(OP_NUMBER, "...", "galaxy_number", COMPARISON_EQUAL, ((false, "4"))),
				(OP_STRING, "...", "status_string", COMPARISON_EQUAL, ((false, "STATUS_EXITING_WITCHSPACE"))),
				(OP_MISSION_VAR, "...", "mission_cloak", COMPARISON_UNDEFINED, ())
			),
			(		// do
				(
					true,
					( (OP_MISSION_VAR, "...", "mission_cloakcounter", COMPARISON_UNDEFINED, ()) ),
					( (false, "set:", "mission_cloakcounter 0") ),
					()
				),
				(false, "increment:", "mission_cloakcounter"),
				(false, "checkForShips:", "asp-cloaked"),
				(true,
					(
						(OP_NUMBER, "...", "shipsFound_number", COMPARISON_EQUAL, ((false, "0"))),
						(OP_MISSION_VAR, "...", "mission_cloakcounter, COMPARISON_GREATERTHAN, ((false, "6"))),
					),
					(
						(false, "addShips:", "asp-cloaked 1"),
						(false, "addShips:", "asp-pirate 2"),
					),
					()
				)
			),
			()		// else
		)
	)
 

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOCocoa.h"


// context is used for error messages.
NSArray *OOSanitizeLegacyScript(NSArray *script, NSString *context, BOOL allowAIMethods);
NSArray *OOSanitizeLegacyScriptConditions(NSArray *conditions, NSString *context);


/*	Quick test of whether a conditions array is sanitized. It is assumed that
	this will only be passed fully-sanitized or fully-unsanitized conditions
	arrays, so the test doesn't need to be exhaustive.
	
	Note that OOLegacyConditionsAreSanitized() is *not* called by
	OOSanitizeLegacyScript(), so that it is not possible to sneak an
	unwhitelisted "pre-compiled" condition past it.
*/
BOOL OOLegacyConditionsAreSanitized(NSArray *conditions);
