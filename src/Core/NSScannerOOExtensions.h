/*

NSScannerOOExtensions.h

Additions to NSScanner to work around bugs.

FIXME: does this work around bugs that actually exist in any system we're
targetting? It's a conundrum.


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

#import "OOFoundation.h"

#include "oofnd/StdLib.hpp"

@interface NSScanner (OOExtensions)

/*	Foundation sweep (proposed ADR-0043, bead oo-g7rw): the scanned text comes back as UTF-8 in
 *value (value may be NULL), which is set only when something was scanned, as before.
 */
- (BOOL)ooliteScanCharactersFromSet:(NSCharacterSet*)set intoString:(std::string*)value;
- (BOOL)ooliteScanUpToCharactersFromSet:(NSCharacterSet*)set intoString:(std::string*)value;

@end
