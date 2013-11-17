/*

OOPListParsing.m

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


#import "OOPListParsing.h"
#import "OOLogging.h"
#import "OOStringParsing.h"
#import "NSDataOOExtensions.h"
#include <ctype.h>
#include <string.h>


#if !OOLITE_GNUSTEP
#define NO_DYNAMIC_PLIST_DTD_CHANGE
#endif


static NSString * const kOOLogPListFoundationParseError		= @"plist.parse.failed";
static NSString * const kOOLogPListWrongType				= @"plist.wrongType";


#ifndef NO_DYNAMIC_PLIST_DTD_CHANGE
static NSData *ChangeDTDIfApplicable(NSData *data);
#endif

static NSData *CopyDataFromFile(NSString *path);
static id ValueIfClass(id value, Class class);


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
			
			OOLog(kOOLogPListFoundationParseError, @"Failed to parse %@ as a property list.\n%@", whereFrom, error);
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
	return [[NSData oo_dataWithOXZFile:path] retain];
#if 0
// without OXZ extension. Code to be deleted once everything is working
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
