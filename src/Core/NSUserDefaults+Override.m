/*

NSUserDefaults+Override.m

Oolite
Copyright (C) 2004-2025 Giles C Williams and contributors

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


#import "NSUserDefaults+Override.h"
#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPropertyList.h>

#if OOLITE_MODERN_BUILD

@implementation NSUserDefaults (Override)

- (BOOL) writeDictionary: (NSDictionary*)dict
                  toFile: (NSString*)file
{
	if ([file length] == 0)
	{
		NSLog(@"Defaults database filename is empty when writing");
	}
	else if (nil == dict)
	{
		NSFileManager	*mgr = [NSFileManager defaultManager];
		
		return [mgr removeFileAtPath: file handler: nil];
	}
	else
	{
		NSData	*data;
		NSString	*err;
		
		err = nil;
		data = [NSPropertyListSerialization dataFromPropertyList: dict
		format: NSPropertyListOpenStepFormat
		errorDescription: &err];
		if (data == nil)
		{
			NSLog(@"Failed to serialize defaults database for writing: %@", err);
		}
		else if ([data writeToFile: file atomically: YES] == NO)
		{
			NSLog(@"Failed to write defaults database to file: %@", file);
		}
		else
		{
			return YES;
		}
	}
	
	return NO;
}

@end

#endif // OOLITE_MODERN_BUILD
