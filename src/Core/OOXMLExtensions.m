/*

OOXMLExtensions.m

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

#import "OOXMLExtensions.h"

int OOXMLindentation_level = 0;

/* implementations */

@implementation NSString (OOXMLExtensions)

- (NSString *) OOXMLencodedString;
{
	NSMutableString* result = [NSMutableString stringWithString:self];
	//
	[result replaceOccurrencesOfString:@"&"		withString:@"&amp;"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"<"		withString:@"&lt;"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@">"		withString:@"&gt;"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"'"		withString:@"&apos;"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"\""	withString:@"&quot;"	options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	//
	return result;
}

- (NSString *) OOXMLdescription;
{
	NSString* indent = @"";
	indent = [indent stringByPaddingToLength:OOXMLindentation_level withString:@"\t" startingAtIndex:0];
	return [NSString stringWithFormat:@"%@<string>%@</string>", indent, [self OOXMLencodedString]];
}

@end

@implementation NSNumber (OOXMLExtensions)

- (NSString *) OOXMLdescription;
{	
	NSString* indent = @"";
	indent = [indent stringByPaddingToLength:OOXMLindentation_level withString:@"\t" startingAtIndex:0];
	NSString* num_type = [[NSString stringWithFormat:@"%s", [self objCType]] lowercaseString];
	
	if ([num_type isEqual:@"c"])	// bool
	{
		if ([self boolValue] == YES)
			return [NSString stringWithFormat:@"%@<true/>", indent];
		else
			return [NSString stringWithFormat:@"%@<false/>", indent];
	}
	
	if ([num_type isEqual:@"f"])	// float
		return [NSString stringWithFormat:@"%@<real>%f</real>", indent, [self floatValue]];
	
	if ([num_type isEqual:@"d"])	// double
		return [NSString stringWithFormat:@"%@<real>%lf</real>", indent, [self doubleValue]];
	
	if ([num_type isEqual:@"i"]||[num_type isEqual:@"q"]||[num_type isEqual:@"l"])	// integer
		return [NSString stringWithFormat:@"%@<integer>%d</integer>", indent, [self intValue]];
	
	return [NSString stringWithFormat:@"%@<!-- NSNumber --><%@>%@</%@>", indent, num_type, [self description], num_type];
}

@end

@implementation NSArray (OOXMLExtensions)

- (NSString *) OOXMLdescription;
{	
	NSString* indent = @"";
	indent = [indent stringByPaddingToLength:OOXMLindentation_level withString:@"\t" startingAtIndex:0];
	NSMutableString* result = [NSMutableString stringWithFormat: @"%@<array/>", indent];	// empty array
	int n_items = [self count];
		
	if (n_items)
	{
		int i;
		result = [NSMutableString stringWithFormat: @"%@<array>", indent];;
		OOXMLindentation_level++;
		for (i = 0; i < n_items; i++)
		{
			NSObject* item = [self objectAtIndex:i];
						
			if ([item isKindOfClass:[NSString class]])
				[result appendFormat: @"\n%@", [(NSString*)item OOXMLdescription]];
			if ([item isKindOfClass:[NSNumber class]])
				[result appendFormat: @"\n%@", [(NSNumber*)item OOXMLdescription]];
			if ([item isKindOfClass:[NSArray class]])
				[result appendFormat: @"\n%@", [(NSArray*)item OOXMLdescription]];
			if ([item isKindOfClass:[NSDictionary class]])
				[result appendFormat: @"\n%@", [(NSDictionary*)item OOXMLdescription]];
		}
		OOXMLindentation_level--;
		[result appendFormat: @"\n%@</array>", indent];
	}
	return result;
}

@end

@implementation NSDictionary (OOXMLExtensions)

- (NSString *) OOXMLdescription;
{	
	NSString* indent = @"";
	indent = [indent stringByPaddingToLength:OOXMLindentation_level withString:@"\t" startingAtIndex:0];
	NSMutableString* result = [NSMutableString stringWithFormat: @"%@<dict/>", indent];	// empty array
	NSMutableArray* my_keys = [NSMutableArray arrayWithArray:[self allKeys]];
	[my_keys sortUsingSelector:@selector(compare:)];
	int n_items = [my_keys count];
		
	if (n_items)
	{
		int i;
		result = [NSMutableString stringWithFormat: @"%@<dict>", indent];;
		OOXMLindentation_level++;
		for (i = 0; i < n_items; i++)
		{
			NSObject* key = [my_keys objectAtIndex:i];
			NSObject* item = [self objectForKey: key];
						
			[result appendFormat: @"\n\t%@<key>%@</key>", indent, key];
			if ([item isKindOfClass:[NSString class]])
				[result appendFormat: @"\n%@", [(NSString*)item OOXMLdescription]];
			if ([item isKindOfClass:[NSNumber class]])
				[result appendFormat: @"\n%@", [(NSNumber*)item OOXMLdescription]];
			if ([item isKindOfClass:[NSArray class]])
				[result appendFormat: @"\n%@", [(NSArray*)item OOXMLdescription]];
			if ([item isKindOfClass:[NSDictionary class]])
				[result appendFormat: @"\n%@", [(NSDictionary*)item OOXMLdescription]];
		}
		OOXMLindentation_level--;
		[result appendFormat: @"\n%@</dict>", indent];
	}
	return result;
}

- (BOOL) writeOOXMLToFile:(NSString *)path atomically:(BOOL)flag
{
	NSMutableString* result = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"];
	[result appendString:@"\n<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"];
	[result appendString:@"\n<plist version=\"1.0\">"];
	[result appendFormat:@"\n%@", [self OOXMLdescription]];
	[result appendString:@"\n</plist>"];
	
	const char* utf8data = [result UTF8String];
	int bytes = strlen(utf8data);
	
	NSData* resultData = [NSData dataWithBytes:(const void *)utf8data length:bytes];
	
	return [resultData writeToFile:path atomically: flag];
}

- (BOOL) writeOOXMLToURL:(NSURL *)aURL atomically:(BOOL)atomically
{
	NSMutableString* result = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"];
	[result appendString:@"\n<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"];
	[result appendString:@"\n<plist version=\"1.0\">"];
	[result appendFormat:@"\n%@", [self OOXMLdescription]];
	[result appendString:@"\n</plist>"];

	const char* utf8data = [result UTF8String];
	int bytes = strlen(utf8data);
	
	NSData* resultData = [NSData dataWithBytes:(const void *)utf8data length:bytes];
	
	return [resultData writeToURL: aURL atomically: atomically];
}

@end
