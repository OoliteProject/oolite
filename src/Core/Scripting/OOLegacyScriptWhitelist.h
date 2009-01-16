/*

OOLegacyScriptWhitelist.h

Functions to apply method whitelist and basic tokenization to legacy scripts.

Basic tokenization converts an action string to one or two strings (selector
and argument), and a condition string to an array of the form (typeCode, 
leftHandSide, operatorCode, rightHandSide).


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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


NSDictionary *OOSanitizeLegacyScript(NSDictionary *script);

// context is used for error messages.
NSArray *OOSanitizeLegacyScriptConditions(NSArray *conditions, NSString *context);


/*	Quick test of whether a conditions array is sanitized. It is assumed that
	this will only be passed fully-sanitized or fully-unsanitized conditions
	arrays, so the test doesn't need to be exhaustive.
	
	Note that OOLegacyConditionsAreSanitized() is *not* called by
	OOSanitizeLegacyScript(), so that it is not possible to sneak an
	unwhitelisted "pre-compiled" condition past it.
*/
BOOL OOLegacyConditionsAreSanitized(NSArray *conditions);
