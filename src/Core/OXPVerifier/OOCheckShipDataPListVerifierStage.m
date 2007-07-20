/*

OOCheckShipDataPListVerifierStage.m


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

#import "OOCheckShipDataPListVerifierStage.h"
#import "OOModelVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOStringParsing.h"

static NSString * const kStageName	= @"Checking shipdata.plist";


@implementation OOCheckShipDataPListVerifierStage

- (NSString *)name
{
	return kStageName;
}


- (NSSet *)dependents
{
	NSMutableSet *result = [[super dependents] mutableCopy];
	[result addObject:[OOModelVerifierStage nameForReverseDependencyForVerifier:[self verifier]]];
	return [result autorelease];
}


- (BOOL)shouldRun
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	return [fileScanner fileExists:@"shipdata.plist"
						  inFolder:@"Config"
					referencedFrom:nil
					  checkBuiltIn:NO];
}


- (void)run
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	NSDictionary				*shipdataPList = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	shipdataPList = [fileScanner plistNamed:@"shipdata.plist"
								   inFolder:@"Config"
							 referencedFrom:nil
							   checkBuiltIn:NO];
	
	if (shipdataPList == nil)  return;
	
	// Check that it's a dictionary
	if (![shipdataPList isKindOfClass:[NSDictionary class]])
	{
		OOLog(@"verifyOXP.shipdataPList.notDict", @"ERROR: shipdata.plist is not a dictionary.");
		return;
	}
	
	OOLog(@"verifyOXP.models.unimplemented", @"TODO: implement shipdata.plist verifier.");
}

@end

#endif
