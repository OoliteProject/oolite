/*

OOCheckDemoShipsPListVerifierStage.m


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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCheckDemoShipsPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOStringParsing.h"

NSString * const kOOCheckDemoShipsPListVerifierStageName	= @"Checking demoships.plist";


@interface OOCheckDemoShipsPListVerifierStage (OOPrivate)

- (void)runCheckWithDemoShips:(NSArray *)demoshipsPList shipData:(NSDictionary *)shipdataPList;

@end


@implementation OOCheckDemoShipsPListVerifierStage

- (NSString *)name
{
	return kOOCheckDemoShipsPListVerifierStageName;
}


- (NSSet *)requiredStages
{
	return [NSSet setWithObjects:kOOFileScannerVerifierStageName, nil];
}


- (BOOL)shouldRun
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	fileScanner = [[self verifier] stageWithName:kOOFileScannerVerifierStageName];
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
	
	fileScanner = [[self verifier] stageWithName:kOOFileScannerVerifierStageName];
	
	demoshipsPList = [fileScanner plistNamed:@"demoships.plist"
									inFolder:@"Config"
							  referencedFrom:nil
								checkBuiltIn:NO];
	
	if (demoshipsPList == nil)  return;
	
	// Check that it's an array
	if (![demoshipsPList isKindOfClass:[NSArray class]])
	{
		OOLog(@"verifyOXP.demoshipsPList.notDict", @"ERROR: demoships.plist is not an array.");
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
		OOLog(@"verifyOXP.demoshipsPList.notDict", @"ERROR: shipdata.plist is not a dictionary.");
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
			OOLog(@"verifyOXP.demoshipsPList.unknownShip", @"WARNING: demoships.plist entry \"%@\" not found in shipdata.plist.", name);
		}
	}
}

@end

#endif
