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
