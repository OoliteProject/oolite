/*

	Oolite

	OOXMLExtensions.m
	
	Created by Giles Williams on 26/10/2005.


Copyright (c) 2005, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

/*

Currently the windows version exports property lists in a weird format that 
is incompatible with the Mac (at least).

This means that a game saved on a PC could not be loaded elsewhere. 
However the PC version can now load XML property lists, so if we could save 
the game in that format we'd have cross-compatible saved games.

Adding XML export to the windows version wouldn't mean much work  
just extending those classes that can be written to a property list to have a 
method that returns a pointer to an NSString containing their description in 
XML, and a method to writes out a file compatible with Apple's XML property 
lists.

The classes to extend are NSNumber, NSString, NSArray, NSDictionary (and 
optionally, NSData).

The methods to add would be:

- (NSString *) OOXMLdescription

which would be used by:

- (BOOL) writeOOXMLToFile:(NSString *)path atomically:(BOOL)flag

(and optionally:)

- (BOOL) writeOOXMLToURL:(NSURL *)aURL atomically:(BOOL)atomically

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

