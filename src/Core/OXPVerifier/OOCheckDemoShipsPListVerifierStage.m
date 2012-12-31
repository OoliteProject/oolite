/*

OOCheckDemoShipsPListVerifierStage.m


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

#import "OOCheckDemoShipsPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"

static NSString * const kStageName	= @"Checking demoships.plist";


@interface OOCheckDemoShipsPListVerifierStage (OOPrivate)

- (void)runCheckWithDemoShips:(NSArray *)demoshipsPList shipData:(NSDictionary *)shipdataPList;

@end


@implementation OOCheckDemoShipsPListVerifierStage

- (NSString *)name
{
	return kStageName;
}


- (BOOL)shouldRun
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	return [fileScanner fileExists:@"demoships.plist"
						  inFolder:@"Config"
					referencedFrom:nil
					  checkBuiltIn:NO];
}


- (void)run
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	NSArray						*demoshipsPList = nil;
	NSDictionary				*shipdataPList = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	
	demoshipsPList = [fileScanner plistNamed:@"demoships.plist"
									inFolder:@"Config"
							  referencedFrom:nil
								checkBuiltIn:NO];
	
	if (demoshipsPList == nil)  return;
	
	// Check that it's an array
	if (![demoshipsPList isKindOfClass:[NSArray class]])
	{
		OOLog(@"verifyOXP.demoshipsPList.notArray", @"***** ERROR: demoships.plist is not an array.");
		return;
	}
	
	
	shipdataPList = [fileScanner plistNamed:@"shipdata.plist"
								   inFolder:@"Config"
							 referencedFrom:nil
							   checkBuiltIn:NO];
	
	if (shipdataPList == nil)  return;
	
	// Check that it's a dictionary
	if (![shipdataPList isKindOfClass:[NSDictionary class]])
	{
		OOLog(@"verifyOXP.demoshipsPList.notDict", @"***** ERROR: shipdata.plist is not a dictionary.");
		return;
	}
	
	[self runCheckWithDemoShips:demoshipsPList shipData:shipdataPList];
}

@end


@implementation OOCheckDemoShipsPListVerifierStage (OOPrivate)

- (void)runCheckWithDemoShips:(NSArray *)demoshipsPList shipData:(NSDictionary *)shipdataPList
{
	NSEnumerator				*nameEnum = nil;
	NSString					*name = nil;
	
	for (nameEnum = [demoshipsPList objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		if ([shipdataPList objectForKey:name] == nil)
		{
			OOLog(@"verifyOXP.demoshipsPList.unknownShip", @"----- WARNING: demoships.plist entry \"%@\" not found in shipdata.plist.", name);
		}
	}
}

@end

#endif
