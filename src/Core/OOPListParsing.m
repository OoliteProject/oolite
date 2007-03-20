/*

OOPListParsing.m

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


#import "OOPListParsing.h"
#import "OOLogging.h"


static NSString * const kOOLogPListFoundationParseError		= @"plist.parse.foundation.failed";
static NSString * const kOOLogPListWrongType				= @"plist.wrongType";


static id ValueIfClass(id value, Class class);


id OOPropertyListFromData(NSData *data, NSString *whereFrom)
{
	id			result = nil;
	NSString	*error = nil;
	
	
	if (data != nil)
	{
		result = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&error];
		if (result == nil)	// Foundation parser failed
		{
			// Ensure we can say something sensible...
			if (error == nil) error = @"<no error message>";
			if (whereFrom == nil) whereFrom = @"<data in memory>";
			
			// Complain
			OOLog(kOOLogPListFoundationParseError, @"Failed to parse %@ as a property list using Foundation. Retrying using home-grown parser. WARNING: the home-grown parser is deprecated and will be removed in a future version of Oolite.\n%@", whereFrom, error);
			OOLogIndentIf(kOOLogPListFoundationParseError);
			
			// TODO: use homebrew parser here
			
			OOLogOutdentIf(kOOLogPListFoundationParseError);
		}
	}
	
	return result;
}


id OOPropertyListFromFile(NSString *path)
{
	id			result = nil;
	NSData		*data = nil;
	
	if (path != nil)
	{
		// Load file, if it exists...
		data = [[NSData alloc] initWithContentsOfMappedFile:path];
		if (data != nil)
		{
			// ...and parse it
			result = OOPropertyListFromData(data, path);
			[data release];
		}
		// Non-existent file is not an error.
	}
	
	return result;
}


// Wrappers which ensure that the plist contains the right type of object.
NSDictionary *OODictionaryFromData(NSData *data, NSString *whereFrom)
{
	id result = OOPropertyListFromData(data, whereFrom);
	return ValueIfClass(result, [NSDictionary class]);
}


NSDictionary *OODictionaryFromFile(NSString *path)
{
	id result = OOPropertyListFromFile(path);
	return ValueIfClass(result, [NSDictionary class]);
}


NSArray *OOArrayFromData(NSData *data, NSString *whereFrom)
{
	id result = OOPropertyListFromData(data, whereFrom);
	return ValueIfClass(result, [NSArray class]);
}


NSArray *OOArrayFromFile(NSString *path)
{
	id result = OOPropertyListFromFile(path);
	return ValueIfClass(result, [NSArray class]);
}


// Ensure that object is of desired class.
static id ValueIfClass(id value, Class class)
{
	if (value != nil && ![value isKindOfClass:class])
	{
		OOLog(kOOLogPListWrongType, @"Property list is wrong type - expected %@, got %@.", class, [value class]);
		value = nil;
	}
	return value;
}


#if 0
// Old XML parsing code (was part of ResourceManager)


+ (NSMutableArray *) scanTokensFromString:(NSString*) values
{
	NSMutableArray* result = [NSMutableArray arrayWithCapacity:8];
	NSScanner* scanner = [NSScanner scannerWithString:values];
	NSCharacterSet* space_set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString* token;
	while (![scanner isAtEnd])
	{
		[scanner ooliteScanCharactersFromSet:space_set intoString:(NSString * *)nil];
		if ([scanner ooliteScanUpToCharactersFromSet:space_set intoString:&token])
			[result addObject:[NSString stringWithString:token]];
	}
	return result;
}


+ (NSString *) decodeString:(NSString*) encodedString
{
	if ([encodedString rangeOfString:@"&"].location == NSNotFound)
		return encodedString;
	//
	NSMutableString* result = [NSMutableString stringWithString:encodedString];
	//
	[result replaceOccurrencesOfString:@"&amp;"		withString:@"&"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&lt;"		withString:@"<"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&gt;"		withString:@">"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&apos;"	withString:@"'"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&quot;"	withString:@"\""	options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	//
	return result;
}

+ (OOXMLElement) parseOOXMLElement:(NSScanner*) scanner upTo:(NSString*)closingTag
{
	OOXMLElement	result, element;
	element.tag = nil;
	element.content = nil;
	result.tag = nil;
	result.content = nil;
	NSMutableArray* elements = [NSMutableArray arrayWithCapacity:4];	// arbitrarily choose 4
	BOOL done = NO;
	while ((!done)&&(![scanner isAtEnd]))
	{
		NSString* preamble;
		BOOL foundPreamble = [scanner scanUpToString:@"<" intoString:&preamble];
		BOOL foundOpenBracket = [scanner scanString:@"<" intoString:(NSString * *)nil];
		if (!foundOpenBracket)
		{
//			NSLog(@"XML >>>>> no '<' found.");
			//
			// no openbracket found
			if (foundPreamble)
			{
//				NSLog(@"XML >>>>> Returning preamble=\"%@\"", preamble);
				// return the text we got instead
				element.tag = nil;
				element.content = [ResourceManager decodeString:preamble];
			}
			else
			{
//				NSLog(@"XML >>>>> Returning \"\"");
				// no preamble, return an empty string
				element.tag = nil;
				element.content = @"";
			}
		}
		else
		{
//			NSLog(@"XML >>>>> '<' found.");
			//
			NSString* tag;
			// look for closing '>'
			int openBracketLocation = [scanner scanLocation];
			BOOL foundTag = [scanner scanUpToString:@">" intoString:&tag];
			BOOL foundCloseBracket = [scanner scanString:@">" intoString:(NSString * *)nil];
			if (!foundCloseBracket)
			{
				// ERROR no closing bracket for tag
				NSException* myException = [NSException
					exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
					reason: [NSString stringWithFormat:@"Tag without closing bracket: \"%@\"", tag]
					userInfo: nil];
				[myException raise];
				result.tag = nil;
				result.content = nil;
				return result;
			}
			if (!foundTag)
			{
				// ERROR empty tag
				NSException* myException = [NSException
					exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
					reason: [NSString stringWithFormat:@"Empty tag \"<>\" encountered.", tag]
					userInfo: nil];
				[myException raise];
				result.tag = nil;
				result.content = nil;
				return result;
			}
			//
//			NSLog(@"XML >>>>> '>' found. tag = <%@>", tag);
			//
			// okay we have a < tag >
			//
			if ([tag hasPrefix:@"!"]||[tag hasPrefix:@"?"]||[tag hasSuffix:@"/"])
			{
				if ([tag hasPrefix:@"!--"])
				{
					// it's a comment
					[scanner setScanLocation:openBracketLocation + 3];
					NSString* comment;
//					BOOL foundComment = [scanner scanUpToString:@"-->" intoString:&comment];
					[scanner scanUpToString:@"-->" intoString:&comment];
					BOOL foundEndComment = [scanner scanString:@"-->" intoString:(NSString * *)nil];
					if (!foundEndComment)
					{
						// ERROR comment without closing -->
						NSException* myException = [NSException
							exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
							reason: [NSString stringWithFormat:@"No closing --> for comment", tag]
							userInfo: nil];
						[myException raise];
						result.tag = nil;
						result.content = nil;
						return result;
					}
					else
					{
						// got a well formed comment so...
//						if (foundComment)
//							NSLog(@"XML >>>>> Comment \"%@\"", comment);
						element.tag = nil;
						element.content = nil;	// ignore the comment
					}
				}
				else
				{
					// it's a singleton
					NSArray* tagbits = ScanTokensFromString(tag);
					// lowercase first 'word' of the tag - with entities decoded
					tag = [ResourceManager decodeString:[(NSString*)[tagbits objectAtIndex:0] lowercaseString]];
					element.tag = tag;
					element.content = tagbits;
				}
			}
			else
			{
				if ([tag hasPrefix:@"/"])
				{
					// it's a closing tag
					if ([tag hasSuffix:closingTag])
					{
						element.tag = nil;
						if (foundPreamble)
							element.content = [ResourceManager decodeString:preamble];
						else
							element.content = @"";
						done = YES;
					}
					else
					{
						// ERROR closing tag without opening tag
						NSException* myException = [NSException
							exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
							reason: [NSString stringWithFormat:@"Closing tag \"<%@>\" without opening tag.", tag]
							userInfo: nil];
						[myException raise];
						result.tag = nil;
						result.content = nil;
						return result;
					}
				}
				else
				{
					// at this point we have an opening tag for some content
					// so we'll recursively parse the rest of the text
					NSArray* tagbits = ScanTokensFromString(tag);
					if (![tagbits count])
					{
						// ERROR empty opening tag
						NSException* myException = [NSException
							exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
							reason: [NSString stringWithFormat:@"Empty tag encountered.", tag]
							userInfo: nil];
						[myException raise];
						result.tag = nil;
						result.content = nil;
						return result;
					}
					// lowercase first 'word' of the tag - with entities decoded
					tag = [ResourceManager decodeString:[(NSString*)[tagbits objectAtIndex:0] lowercaseString]];
					//
					OOXMLElement inner_element = [ResourceManager parseOOXMLElement:scanner upTo:tag];
					element.tag = inner_element.tag;
//					if ([inner_element.content isKindOfClass:[NSArray class]])
//					{
//						NSArray* inner_element_array = (NSArray*)inner_element.content;
//						if ([inner_element_array count] == 1)
//							inner_element.content = [inner_element_array objectAtIndex:0];
//					}
					element.content = inner_element.content;
				}
			}
		}
		// we reach here with element set so we need to add it in to the elements array
		if ((element.tag)&&(element.content))
		{
			[elements addObject:[NSArray arrayWithObjects: element.tag, element.content, nil]];
		}
	}
	
	// all done!
	result.tag = closingTag;
	if ([elements count])
		result.content = elements;
	else
		result.content = element.content;
		
//	NSLog(@"DEBUG XML found '%@' = '%@'", result.tag, result.content);
	
	return result;
}

+ (id) parseXMLPropertyList:(NSString*)xmlString
{
	NSScanner* scanner = [NSScanner scannerWithString:xmlString];
	OOXMLElement xml = { nil, nil };
	NS_DURING
		xml = [ResourceManager parseOOXMLElement:scanner upTo:@"ROOT"];
	NS_HANDLER
		if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
		{
			NSLog(@"***** [ResourceManager parseXMLPropertyList:] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
		}
		[localException raise];
	NS_ENDHANDLER
	if (!xml.content)
		return nil;
	if (![xml.content isKindOfClass:[NSArray class]])
		return nil;
	NSArray* elements = (NSArray*)xml.content;
	int n_elements = [elements count];
	int i;
	for (i = 0; i < n_elements; i++)
	{
		NSArray* element = (NSArray*)[elements objectAtIndex:i];
		NSString* tag = (NSString*)[element objectAtIndex:0];
		NSObject* content = [element objectAtIndex:1];
//		NSLog(@"DEBUG XML found '%@' = %@", tag, content);
		if ([tag isEqual:@"plist"])
		{
			if ([content isKindOfClass:[NSArray class]])
			{
				NSArray* plist = (NSArray*)[(NSArray*)content objectAtIndex:0];
//				NSString* plistTag = (NSString*)[plist objectAtIndex:0];
//				NSLog(@"DEBUG XML found plist containing '%@'", plistTag);
				return [ResourceManager objectFromXMLElement:plist];
			}
		}
	}
	// with a well formed plist we should not reach here!
	return nil;
}

+ (id) objectFromXMLElement:(NSArray*) xmlElement
{
//	NSLog(@"XML DEBUG trying to get an NSObject out of %@", xmlElement);
	//
	if ([xmlElement count] != 2)
	{
		// bad xml element
		NSException* myException = [NSException
			exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
			reason: [NSString stringWithFormat:@"Bad XMLElement %@ passed to objectFromXMLElement:", xmlElement]
			userInfo: nil];
		[myException raise];
		return nil;
	}
	NSString* tag = (NSString*)[xmlElement objectAtIndex:0];
	NSObject* content = [xmlElement objectAtIndex:1];
	//
	if ([tag isEqual:@"true/"])
		return [ResourceManager trueFromXMLContent:content];
	if ([tag isEqual:@"false/"])
		return [ResourceManager falseFromXMLContent:content];
	//
	if ([tag isEqual:@"real"])
		return [ResourceManager realFromXMLContent:content];
	//
	if ([tag isEqual:@"integer"])
		return [ResourceManager integerFromXMLContent:content];
	//
	if ([tag isEqual:@"string"])
		return [ResourceManager stringFromXMLContent:content];
	if ([tag isEqual:@"string/"])
		return @"";
	//
	if ([tag isEqual:@"date"])
		return [ResourceManager dateFromXMLContent:content];
	//
	if ([tag isEqual:@"data"])
		return [ResourceManager dataFromXMLContent:content];
	//
	if ([tag isEqual:@"array"])
		return [ResourceManager arrayFromXMLContent:content];
	if ([tag isEqual:@"array/"])
		return [NSArray arrayWithObjects:nil];
	//
	if ([tag isEqual:@"dict"])
		return [ResourceManager dictionaryFromXMLContent:content];
	if ([tag isEqual:@"dict/"])
		return [NSDictionary dictionaryWithObjectsAndKeys:nil];
	//
	if ([tag isEqual:@"key"])
		return [ResourceManager stringFromXMLContent:content];
	//
	return nil;
}

+ (NSNumber*) trueFromXMLContent:(NSObject*) xmlContent
{
	return [NSNumber numberWithBool:YES];
}

+ (NSNumber*) falseFromXMLContent:(NSObject*) xmlContent
{
	return [NSNumber numberWithBool:NO];
}

+ (NSNumber*) realFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return [NSNumber numberWithDouble:[(NSString*)xmlContent doubleValue]];
	}
	return nil;
}

+ (NSNumber*) integerFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return [NSNumber numberWithInt:[(NSString*)xmlContent intValue]];
	}
	return nil;
}

+ (NSString*) stringFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return (NSString*)xmlContent;
	}
	return nil;
}

+ (NSDate*) dateFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return [NSDate dateWithString:(NSString*)xmlContent];
	}
	return nil;
}

+ (NSData*) dataFromXMLContent:(NSObject*) xmlContent
{
	// we don't use this for Oolite
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		// we're going to decode the string from base64
		NSString* base64String = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
		NSMutableData* resultingData = [NSMutableData dataWithLength:0];
		NSString* dataString = (NSString *)xmlContent;
		char bytes3[3];
		int n_64Chars;
		int tripletValue;
		int n_chars = [dataString length];
		int i = 0;
		while (i < n_chars)
		{
			n_64Chars = 0;
			tripletValue = 0;
			while ((n_64Chars < 4)&(i < n_chars))
			{
				int b64 = [base64String rangeOfString:[dataString substringWithRange:NSMakeRange(i,1)]].location;
				if (b64 != NSNotFound)
				{
					tripletValue *= 64;
					tripletValue += (b64 & 63);
					n_64Chars++;
				}
				i++;
			}
			while (n_64Chars < 4)	//shouldn't need to pad, but we do just in case
			{
				tripletValue *= 64;
				n_64Chars++;
			}
			bytes3[0] = (tripletValue & 0xff0000) >> 16; 
			bytes3[1] = (tripletValue & 0xff00) >> 8; 
			bytes3[2] = (tripletValue & 0xff);
			[resultingData appendBytes:(const void *)bytes3 length:3];
		}
		return [NSData dataWithData:resultingData];
	}
	return nil;
}

+ (NSArray*) arrayFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSArray class]])
	{
		NSArray* xmlElementArray = (NSArray*)xmlContent;
		int n_objects = [xmlElementArray count];
		NSMutableArray* result = [NSMutableArray arrayWithCapacity:n_objects];
		int i;
		for (i = 0; i < n_objects; i++)
		{
			NSArray* xmlElement = [xmlElementArray objectAtIndex:i];
			NSObject* object = [ResourceManager objectFromXMLElement:xmlElement];
			if (object)
				[result addObject:object];
			else
				return nil;
		}
		return [NSArray arrayWithArray:result];
	}
	return nil;
}

+ (NSDictionary*) dictionaryFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSArray class]])
	{
		NSArray* xmlElementArray = (NSArray*)xmlContent;
		int n_objects = [xmlElementArray count];
		if (n_objects & 1)
			return nil;	// must be an even number of objects in the array
		NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: n_objects / 2];
		int i;
		for (i = 0; i < n_objects; i += 2)
		{
			NSArray* keyXmlElement = [xmlElementArray objectAtIndex:i];
			NSObject* key = [ResourceManager objectFromXMLElement:keyXmlElement];
			NSArray* objectXmlElement = [xmlElementArray objectAtIndex:i + 1];
			NSObject* object = [ResourceManager objectFromXMLElement:objectXmlElement];
			if (key && object)
			{
				[result setObject:object forKey:key];
			}
			else
				return nil;
		}
		return [NSDictionary dictionaryWithDictionary:result];
	}
	return nil;
}

+ (NSString*) stringFromGLFloats: (GLfloat*) float_array : (int) n_floats
{
	NSMutableString* result = [NSMutableString stringWithCapacity:256];
	int i;
	for ( i = 0; i < n_floats ; i++)
		[result appendFormat:@"%f ", float_array[i]];
	return result;
}

+ (void) GLFloatsFromString: (NSString*) float_string: (GLfloat*) float_array
{
	NSArray* tokens = ScanTokensFromString(float_string);
	int i;
	int n_tokens = [tokens count];
	for (i = 0; i < n_tokens; i++)
		float_array[i] = [[tokens objectAtIndex:i] floatValue];
}

+ (NSString*) stringFromNSPoint: (NSPoint) point
{
	return [NSString stringWithFormat:@"%f %f", point.x, point.y];
}

+ (NSPoint) NSPointFromString: (NSString*) point_string
{
	NSArray* tokens = ScanTokensFromString(point_string);
	int n_tokens = [tokens count];
	if (n_tokens != 2)
		return NSMakePoint( 0.0, 0.0);
	return NSMakePoint( [[tokens objectAtIndex:0] floatValue], [[tokens objectAtIndex:1] floatValue]);
}


#endif
