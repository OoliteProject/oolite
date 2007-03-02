/*

OOXMLExtensions.h

Extensions to Foundation property list classes to export property lists in
XML format, which both Cocoa and GNUstep can read. This is done because
GNUstep defaults to writing a version of OpenStep text-based property lists
that Cocoa can't understand. The XML format is understood by both
implementations, although GNUstep complains about not being able to find the
DTD.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import <Foundation/NSString.h>

/* interfaces */

@interface NSString (OOXMLExtensions)

- (NSString *) OOXMLencodedString;
- (NSString *) OOXMLdescription;

@end

@interface NSNumber (OOXMLExtensions)

- (NSString *) OOXMLdescription;

@end

@interface NSArray (OOXMLExtensions)

- (NSString *) OOXMLdescription;

@end

@interface NSDictionary (OOXMLExtensions)

- (NSString *) OOXMLdescription;
- (BOOL) writeOOXMLToFile:(NSString *)path atomically:(BOOL)flag;
- (BOOL) writeOOXMLToURL:(NSURL *)aURL atomically:(BOOL)atomically;

@end

