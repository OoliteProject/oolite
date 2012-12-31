/*

OOXMLExtensions.m

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

#import "OOXMLExtensions.h"


@implementation NSDictionary (OOXMLExtensions)

- (BOOL) writeOOXMLToFile:(NSString *)path atomically:(BOOL)flag errorDescription:(NSString **)outErrorDesc
{
	NSData		*data = nil;
	NSString	*errorDesc = nil;
	
	data = [NSPropertyListSerialization dataFromPropertyList:self format:NSPropertyListXMLFormat_v1_0 errorDescription:outErrorDesc];
	if (data == nil)
	{
		if (outErrorDesc != NULL)
		{
			*outErrorDesc = [NSString stringWithFormat:@"could not convert property list to XML: %@", errorDesc];
		}
#if OOLITE_RELEASE_PLIST_ERROR_STRINGS
		[errorDesc release];
#endif
		return NO;
	}
	
	if (![data writeToFile:path atomically:YES])
	{
		if (outErrorDesc != NULL)
		{
			*outErrorDesc = [NSString stringWithFormat:@"could not write data to %@.", path];
		}
		return NO;
	}
	
	return YES;
}

@end
