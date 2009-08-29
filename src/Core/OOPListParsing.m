/*

OOPListParsing.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "OOStringParsing.h"
#import <ctype.h>
#import <string.h>


#if !OOLITE_GNUSTEP
#define NO_DYNAMIC_PLIST_DTD_CHANGE
#endif


static NSString * const kOOLogPListFoundationParseError		= @"plist.parse.foundation.failed";
static NSString * const kOOLogPListWrongType				= @"plist.wrongType";
static NSString * const kOOLogPListHomebrewBadEncoding		= @"plist.homebrew.badEncoding";
static NSString * const kOOLogPListHomebrewException		= @"plist.homebrew.exception";
static NSString * const kOOLogPListHomebrewParseError		= @"plist.homebrew.parseError";
static NSString * const kOOLogPListHomebrewParseWarning		= @"plist.homebrew.parseWarning";
static NSString * const kOOLogPListHomebrewTokenizeTrace	= @"plist.homebrew.tokenize.trace";
static NSString * const kOOLogPListHomebrewInterpretTrace	= @"plist.homebrew.interpret.trace";
static NSString * const kOOLogPListHomebrewSuccess			= @"plist.homebrew.success";


#define OOLITE_EXCEPTION_XML_PARSING_FAILURE	@"OOXMLException"


typedef struct
{
	NSString		*tag;		// name of the tag
	id				content;	// content of tag
} OOXMLElement;


#ifndef NO_DYNAMIC_PLIST_DTD_CHANGE
static NSData *ChangeDTDIfApplicable(NSData *data);
#endif

static NSData *CopyDataFromFile(NSString *path);
static id ValueIfClass(id value, Class class);
static id ParseXMLPropertyList(NSData *data, NSString *whereFrom);

static NSArray *TokensFromXML(NSData *data, NSString *whereFrom);
static id InterpretXMLTokens(NSArray *tokens, NSString *whereFrom);
static OOXMLElement ParseXMLElement(NSScanner *scanner, NSString *closingTag, NSString *whereFrom);
static NSString *ResolveXMLEntities(NSString *string);
static id ObjectFromXMLElement(NSArray *tokens, BOOL expectKey, NSString *whereFrom);
static NSData *DataFromXMLString(NSString *string, NSString *whereFrom);
static NSArray *ArrayFromXMLString(NSArray *tokens, NSString *whereFrom);
static NSDictionary *DictionaryFromXMLString(NSArray *tokens, NSString *whereFrom);

static NSString *ShortDescription(id object);


id OOPropertyListFromData(NSData *data, NSString *whereFrom)
{
	id			result = nil;
	NSString	*error = nil;
	
	if (data != nil)
	{
#ifndef NO_DYNAMIC_PLIST_DTD_CHANGE
		data = ChangeDTDIfApplicable(data);
#endif
		
		result = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&error];
		if (result == nil)	// Foundation parser failed
		{	
#if OOLITE_RELEASE_PLIST_ERROR_STRINGS
			[error autorelease];
#endif
			// Ensure we can say something sensible...
			if (error == nil) error = @"<no error message>";
			if (whereFrom == nil) whereFrom = @"<data in memory>";
			
#ifndef NDEBUG
			// Complain
			OOLog(kOOLogPListFoundationParseError, @"Failed to parse %@ as a property list using Foundation. Retrying using homebrew parser. WARNING: the homebrew parser is deprecated and will be removed in a future version of Oolite.\n%@", whereFrom, error);
			OOLogIndentIf(kOOLogPListFoundationParseError);
#endif
			
			result = ParseXMLPropertyList(data, whereFrom);
			
#ifndef NDEBUG
			OOLogOutdentIf(kOOLogPListFoundationParseError);
#endif
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
		data = CopyDataFromFile(path);
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


#ifndef NO_DYNAMIC_PLIST_DTD_CHANGE
static NSData *ChangeDTDIfApplicable(NSData *data)
{
	const uint8_t		*bytes = NULL;
	uint8_t				*newBytes = NULL;
	size_t				length,
						newLength,
						offset = 0,
						newOffset = 0;
	const char			xmlDeclLine[] = "<\?xml version=\"1.0\" encoding=\"UTF-8\"\?>";
	const char			*appleDTDLines[] = 
						{
							"<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
							"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
							NULL
						};
	const char			gstepDTDLine[] = "<!DOCTYPE plist PUBLIC \"-//GNUstep//DTD plist 0.9//EN\" \"http://www.gnustep.org/plist-0_9.xml\">";
	const char			*srcDTDLine = NULL;
	size_t				srcDTDLineSize = 0;
	unsigned			i;
	
	length = [data length];
	if (length < sizeof xmlDeclLine) return data;
	
	bytes = [data bytes];
	
	// Check if it starts with an XML declaration. Bogus: there are valid XML declarations which don't match xmlDeclLine.
	if (memcmp(bytes, xmlDeclLine, sizeof xmlDeclLine - 1) != 0) return data;
	
	offset += sizeof xmlDeclLine - 1;
	while (offset < length && isspace(bytes[offset]))  ++offset;
	
	// Check if first non-blank stuff after XML declaration is any known Apple plist DTD. Also somewhat bogus.
	for (i = 0; ; i++)
	{
		srcDTDLine = appleDTDLines[i];
		if (srcDTDLine == NULL)  return data;  // No matches
		
		srcDTDLineSize = strlen(appleDTDLines[i]);
		
		if (srcDTDLineSize <= length - offset &&
			memcmp(bytes + offset, srcDTDLine, srcDTDLineSize) == 0)
		{
			// Match
			break;
		}
	}
	
	offset += srcDTDLineSize;
	
	newLength = length - offset + sizeof xmlDeclLine + sizeof gstepDTDLine - 1;
	newBytes = malloc(newLength);
	if (newBytes == NULL) return data;
	
	// Construct modified version with altered DTD line
	memcpy(newBytes, xmlDeclLine, sizeof xmlDeclLine - 1);
	newOffset = sizeof xmlDeclLine - 1;
	newBytes[newOffset++] = '\n';
	memcpy(newBytes + newOffset, gstepDTDLine, sizeof gstepDTDLine - 1);
	newOffset += sizeof gstepDTDLine - 1;
	memcpy(newBytes + newOffset, bytes + offset, length - offset);
	
	return [NSData dataWithBytes:newBytes length:newLength];
}
#endif


/*	Load data from file. Returns a retained pointer.
	-initWithContentsOfMappedFile fails quietly under OS X if there's no file,
	but GNUstep complains.
*/
static NSData *CopyDataFromFile(NSString *path)
{
#if OOLITE_MAC_OS_X
	return [[NSData alloc] initWithContentsOfMappedFile:path];
#else
	NSFileManager	*fmgr = [NSFileManager defaultManager];
	BOOL			dir;
	
	if ([fmgr fileExistsAtPath:path isDirectory:&dir])
	{
		if (!dir)
		{
			return [[NSData alloc] initWithContentsOfMappedFile:path];
		}
		else
		{
			OOLog(kOOLogFileNotFound, @"Expected property list but found directory at %@", path);
		}
	}
	
	return nil;
#endif
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


static id ParseXMLPropertyList(NSData *data, NSString *whereFrom)
{
	id						result = nil;
	NSArray					*tokens = nil;
	NSAutoreleasePool		*pool = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	OOLogPushIndent();
	NS_DURING
		OOLog(kOOLogPListHomebrewTokenizeTrace, @">>>>> Tokenizing property list.");
		OOLogIndentIf(kOOLogPListHomebrewTokenizeTrace);
		tokens = TokensFromXML(data, whereFrom);
		OOLogOutdentIf(kOOLogPListHomebrewTokenizeTrace);
		
		if (tokens != nil)
		{
			OOLog(kOOLogPListHomebrewInterpretTrace, @"Property list tokenization successful, interpreting.");
			OOLogIndentIf(kOOLogPListHomebrewInterpretTrace);
			result = InterpretXMLTokens(tokens, whereFrom);
			OOLogOutdentIf(kOOLogPListHomebrewInterpretTrace);
			if (result != nil) OOLog(kOOLogPListHomebrewSuccess, @"Successfully interpreted property list... for now.");
		}
	NS_HANDLER
		// OOLITE_EXCEPTION_XML_PARSING_FAILURE indicates an error we've already logged.
		if (![[localException name] isEqual:OOLITE_EXCEPTION_XML_PARSING_FAILURE])
		{
			OOLog(kOOLogException, @"Encountered exception while parsing property list %@ (parsing failed). Exception: %@: %@", whereFrom, [localException name], [localException reason]);
		}
	NS_ENDHANDLER
	OOLogPopIndent();
	[result retain];
	[pool release];
	return [result autorelease];
	
}


static NSArray *TokensFromXML(NSData *data, NSString *whereFrom)
{
	NSString				*xmlString = nil;
	NSScanner				*scanner = nil;
	OOXMLElement			xml = { nil, nil };
	
	// Assume UTF-8, UTF-16 or system encoding... not robust.
	xmlString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (xmlString == nil) xmlString = [[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding];
	if (xmlString == nil) xmlString = [[NSString alloc] initWithData:data];
	if (xmlString == nil)
	{
		OOLog(kOOLogPListHomebrewBadEncoding, @"Could not interpret property list %@ as UTF-8 text.", whereFrom);
	}
	else
	{
		scanner = [NSScanner scannerWithString:xmlString];
		[xmlString release];
		
		OOLogPushIndent();
		NS_DURING
			xml = ParseXMLElement(scanner, @"ROOT", whereFrom);
		NS_HANDLER
			// OOLITE_EXCEPTION_XML_PARSING_FAILURE indicates an error we've already logged.
			if (![[localException name] isEqual:OOLITE_EXCEPTION_XML_PARSING_FAILURE])
			{
				OOLog(kOOLogException, @"Encountered exception while parsing property list %@ (parsing failed). Exception: %@: %@", whereFrom, [localException name], [localException reason]);
			}
		NS_ENDHANDLER
		OOLogPopIndent();
	}
	
	if ([xml.content isKindOfClass:[NSArray class]])  return xml.content;
	else if ([xml.content isKindOfClass:[NSString class]])
	{
		OOLog(kOOLogPListHomebrewParseError, @"Property list isn't in XML format, homebrew parser can't help you.");
	}
	else
	{
		OOLog(kOOLogPListHomebrewParseError, @"***** Property list parser error: expected root element tokenization to be NSArray, but got %@.", [xml.content class]);
	}
	return nil;
}


static id InterpretXMLTokens(NSArray *tokens, NSString *whereFrom)
{
	NSEnumerator			*elementEnum = nil;
	id						element = nil;
	NSString				*tag = nil;
	id						content = nil;
	NSArray					*plist = nil;
	
	for (elementEnum = [tokens objectEnumerator]; (element = [elementEnum nextObject]); )
	{
		// Elements are OOXMLElements converted to two-member arrays.
		tag = [element objectAtIndex:0];
		content = [element objectAtIndex:1];
		
		OOLog(kOOLogPListHomebrewInterpretTrace, @"Got element: <%@>", tag);
		
		if ([tag isEqual:@"plist"])
		{
			if ([content isKindOfClass:[NSArray class]])
			{
				plist = [content objectAtIndex:0];
				if ([plist isKindOfClass:[NSArray class]])
				{
					return ObjectFromXMLElement(plist, NO, whereFrom);
				}
			}
			
			OOLog(kOOLogPListHomebrewParseError, @"***** Property list parser error: invalid structure for tokenization of <plist> element.");
		}
		
		if (![tag hasPrefix:@"!"] && ![tag hasPrefix:@"?"])
		{
			// Bad root-level element - not <plist> or directive
			OOLog(kOOLogPListHomebrewParseWarning, @"----- Bad property list: root level element <%@> is not <plist> or directive.", tag);
		}
	}
	
	// If we got here, there was no <plist>
	OOLog(kOOLogPListHomebrewParseError, @"***** Property list parser error: could not find a <plist> element.");
	return nil;
}


static OOXMLElement ParseXMLElement(NSScanner *scanner, NSString *closingTag, NSString *whereFrom)
{
	OOXMLElement		result = {0}, element = {0};
	NSMutableArray		*elements = nil;
	NSString			*preamble = nil;
	NSString			*tag = nil;
	int					openBracketLocation;
	NSArray				*tagbits = nil;
	BOOL				done = NO;
	BOOL				foundPreamble, foundBracket, foundTag;
	
	elements = [NSMutableArray array];
	
	while (!done && ![scanner isAtEnd])
	{
		foundPreamble = [scanner scanUpToString:@"<" intoString:&preamble];
		foundBracket = [scanner scanString:@"<" intoString:NULL];
		if (!foundBracket)
		{
			// No < found
			// These cases appear to be ignored, since tag is nil.
			if (foundPreamble)
			{
				// Is this useful? -- ahruman
				element.tag = nil;
				element.content = ResolveXMLEntities(preamble);
				OOLog(kOOLogPListHomebrewTokenizeTrace, @"Found preamble but no <, using \"%@\"", ShortDescription(element.content));
			}
			else
			{
				// Nothing found.
				element.tag = nil;
				element.content = @"";
				OOLog(kOOLogPListHomebrewTokenizeTrace, @"Found nothing, using empty string");
			}
		}
		else
		{
			// < found
			// Look for closing >
			openBracketLocation = [scanner scanLocation];
			foundTag = [scanner scanUpToString:@">" intoString:&tag];
			foundBracket = [scanner scanString:@">" intoString:NULL];
			if (!foundBracket)
			{
				OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: found tag with no closing bracket (\"<%@\").", tag);
				[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Unclosed tag <%@", tag];
			}
			if (!foundTag || [tag length] == 0)
			{
				OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: found empty tag (\"<>\").");
				[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Empty tag"];
			}
			
			// If we get here, we’ve got a tag.
			OOLog(kOOLogPListHomebrewTokenizeTrace, @"Found tag <%@>", tag);
			if ([tag hasPrefix:@"!"] || [tag hasPrefix:@"?"] || [tag hasSuffix:@"/"])
			{
				// Directive, self-closing tag or comment
				if ([tag hasPrefix:@"!--"])
				{
					// Comment. This comment handling is techincally invalid because it doesn't fail if the comment contains "--". XML Is such fun.
					[scanner setScanLocation:openBracketLocation + 3];
					[scanner scanUpToString:@"-->" intoString:NULL];
					foundBracket = [scanner scanString:@"-->" intoString:NULL];
					if (!foundBracket)
					{
						OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: found unterminated comment (no -->).");
						[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Unterminated comment"];
					}
					else
					{
						element.tag = nil;
						element.content = nil;
					}
				}
				else
				{
					// Directive or self-closing tag
					tagbits = ScanTokensFromString(tag);
					tag = ResolveXMLEntities([[tagbits objectAtIndex:0] lowercaseString]);	// Whut? How can there be entities in a tag name? Also, tags are case-sensetive. -- ahruman
					element.tag = tag;
					element.content = tagbits;
				}
			}
			else
			{
				// Opening or closing tag
				if ([tag hasPrefix:@"/"])
				{
					// Closing tag
					if ([tag hasSuffix:closingTag])		// Not general - will match </foo-bar> when looking for </bar> - but good enough for plists. -- ahruman
					{
						// End of bit we're looking for
						element.tag = nil;
						if (foundPreamble)  element.content = ResolveXMLEntities(preamble);
						else  element.content = nil;
						done = YES;
					}
					else
					{
						OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: closing tag <%@> with no opening tag (expected </%@>).", tag, closingTag);
						[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Wrong closing tag <%@>, should be <%@>", tag, closingTag];
					}
				}
				else
				{
					// It's an opening tag; recurse
					tagbits = ScanTokensFromString(tag);
					if ([tagbits count] == 0)
					{
						OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: empty opening tag (<>).");
						[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Empty opening tag"];
					}
					tag = ResolveXMLEntities([[tagbits objectAtIndex:0] lowercaseString]);	// Se before re "whut?". -- ahruman
					
					OOLog(kOOLogPListHomebrewTokenizeTrace, @"Recursively parsing children of tag %@", tag);
					OOLogIndentIf(kOOLogPListHomebrewTokenizeTrace);
					element = ParseXMLElement(scanner, tag, whereFrom);
					OOLogOutdentIf(kOOLogPListHomebrewTokenizeTrace);
				}
			}
		}
		
		if (element.tag != nil && element.content != nil)
		{
			[elements addObject:[NSArray arrayWithObjects:element.tag, element.content, nil]];
		}
	}
	
	result.tag = closingTag;
	if ([elements count] != 0)  result.content = elements;
	else  result.content = element.content;
	
	return result;
}


static NSString *ResolveXMLEntities(NSString *string)
{
	if ([string rangeOfString:@"&"].location == NSNotFound)  return string;
	
	NSMutableString* result = [[string mutableCopy] autorelease];
	
	// These shouldn't really be case-insensetive, but we're going for bugwards-compatibility here.
	[result replaceOccurrencesOfString:@"&amp;"  withString:@"&"  options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&lt;"   withString:@"<"  options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&gt;"   withString:@">"  options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&apos;" withString:@"\'" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	
	return result;
}


static id ObjectFromXMLElement(NSArray *tokens, BOOL expectKey, NSString *whereFrom)
{
	NSString				*tag = nil;
	id						content = nil;
	id						result = nil;
	
	if ([tokens count] != 2)
	{
		OOLog(kOOLogPListHomebrewParseError, @"***** Property list parser error: invalid token structure.");
		[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Invalid token structure"];
	}
	
	tag = [tokens objectAtIndex:0];
	content = [tokens objectAtIndex:1];
	
	if ([content isKindOfClass:[NSString class]])  OOLog(kOOLogPListHomebrewInterpretTrace, @"Interpreting <%@>: %@", tag, ShortDescription(content));
	else  OOLog(kOOLogPListHomebrewInterpretTrace, @"Interpreting <%@>", tag);
	OOLogIndentIf(kOOLogPListHomebrewInterpretTrace);
	
	
	if ([tag isEqual:@"key"])
	{
		result = [NSString stringWithString:content];
		if (!expectKey) OOLog(kOOLogPListHomebrewParseWarning, @"----- Bad property list: <key> element (%@) found when expecting a value, treating as <string>.", result);
	}
	else
	{
		if ([tag isEqual:@"true/"])			result = [NSNumber numberWithBool:YES];
		else if ([tag isEqual:@"false/"])	result = [NSNumber numberWithBool:NO];
		else if ([tag isEqual:@"real"])		result = [NSNumber numberWithDouble:[content doubleValue]];
		else if ([tag isEqual:@"integer"])	result = [NSNumber numberWithDouble:[content intValue]];
		else if ([tag isEqual:@"string"])	result = [NSString stringWithString:content];
		else if ([tag isEqual:@"string/"])	result = @"";
		else if ([tag isEqual:@"date"])		result = [NSDate dateWithString:content];
		else if ([tag isEqual:@"data"])		result = DataFromXMLString(content, whereFrom);
		else if ([tag isEqual:@"array"])	result = ArrayFromXMLString(content, whereFrom);
		else if ([tag isEqual:@"array/"])	result = [NSArray array];
		else if ([tag isEqual:@"dict"])		result = DictionaryFromXMLString(content, whereFrom);
		else if ([tag isEqual:@"dict/"])	result = [NSDictionary dictionary];
		
		if (result != nil)
		{
			if (expectKey) OOLog(kOOLogPListHomebrewParseWarning, @"----- Bad property list: expected <key>, got <%@>. Allowing for backwards compatibility, but the property list will not function as intended.", tag);
		}
		else
		{
			OOLog(kOOLogPListHomebrewParseWarning, @"----- Bad property list: unknown value class element <%@>, ignoring.", tag);
		}
	}
	
	OOLogOutdentIf(kOOLogPListHomebrewInterpretTrace);
	return result;
}


static NSData *DataFromXMLString(NSString *string, NSString *whereFrom)
{
	if (![string isKindOfClass:[NSString class]])
	{
		OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: expected string inside <data>, found %@.", string);
		[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Bad type"];
	}
	
	// String should be base64 data.
	// we're going to decode the string from base64
	NSString		*base64String = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
	NSMutableData	*resultingData = [NSMutableData data];
	char			bytes3[3];
	OOUInteger		n_64Chars;
	int				tripletValue;
	OOUInteger		n_chars = [string length];
	OOUInteger		i = 0;
	
	while (i < n_chars)
	{
		n_64Chars = 0;
		tripletValue = 0;
		while ((n_64Chars < 4)&(i < n_chars))
		{
			OOUInteger b64 = [base64String rangeOfString:[string substringWithRange:NSMakeRange(i,1)]].location;
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


static NSArray *ArrayFromXMLString(NSArray *tokens, NSString *whereFrom)
{
	NSMutableArray			*result = nil;
	NSEnumerator			*elementEnum = nil;
	id						element = nil;
	
	if (![tokens isKindOfClass:[NSArray class]])
	{
		OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: expected elements inside <array>, found %@.", tokens);
		[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Bad type"];
	}
	
	result = [NSMutableArray arrayWithCapacity:[tokens count]];
	for (elementEnum = [tokens objectEnumerator]; (element = [elementEnum nextObject]); )
	{
		element = ObjectFromXMLElement(element, NO, whereFrom);
		if (element != nil) [result addObject:element];
	}
	
	return result;
}


static NSDictionary *DictionaryFromXMLString(NSArray *tokens, NSString *whereFrom)
{
	NSMutableDictionary		*result = nil;
	NSEnumerator			*elementEnum = nil;
	id						keyElement = nil;
	id						valueElement = nil;
	id						key = nil;
	id						value = nil;
	
	if (![tokens isKindOfClass:[NSArray class]])
	{
		OOLog(kOOLogPListHomebrewParseError, @"***** Property list error: expected elements inside <dict>, found %@.", tokens);
		[NSException raise:OOLITE_EXCEPTION_XML_PARSING_FAILURE format:@"Bad type"];
	}
	
	result = [NSMutableDictionary dictionaryWithCapacity:[tokens count]];
	for (elementEnum = [tokens objectEnumerator]; (keyElement = [elementEnum nextObject]); )
	{
		valueElement = [elementEnum nextObject];
		if (valueElement == nil)
		{
			OOLog(kOOLogPListHomebrewParseWarning, @"----- Bad property list: odd number of elements in <dict>, ignoring trailing <%@>.", [keyElement objectAtIndex:0]);
		}
		
		key = ObjectFromXMLElement(keyElement, YES, whereFrom);
		value = ObjectFromXMLElement(valueElement, NO, whereFrom);
		
		if (key != nil && value != nil)
		{
			[result setObject:value forKey:key];
		}
	}
	
	return result;
}


static NSString *ShortDescription(id object)
{
	NSString			*desc = nil;
	
	if (object == nil) return @"(null)";
	
	desc = [object description];
	if (100 < [desc length])
	{
		desc = [[desc substringToIndex:80] stringByAppendingString:@"..."];
	}
	return desc;
}
