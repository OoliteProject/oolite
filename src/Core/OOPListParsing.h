/*

OOPListParsing.h

Property list parser. Tries to use native Foundation property list parsing,
then falls back on Oolite ad-hoc parser for backwards-compatibility (Oolite's
XML plist parser is more lenient than Foundation on OS X).

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

#import <Foundation/Foundation.h>


// whereFrom is an optional description of the data source, for error reporting.
id OOPropertyListFromData(NSData *data, NSString *whereFrom);
id OOPropertyListFromFile(NSString *path);

// Wrappers which ensure that the plist contains the right type of object.
NSDictionary *OODictionaryFromData(NSData *data, NSString *whereFrom);
NSDictionary *OODictionaryFromFile(NSString *path);

NSArray *OOArrayFromData(NSData *data, NSString *whereFrom);
NSArray *OOArrayFromFile(NSString *path);
