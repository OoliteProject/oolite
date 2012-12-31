/*

OOCheckRequiresPListVerifierStage.m


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

#import "OOCheckRequiresPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOStringParsing.h"

static NSString * const kStageName	= @"Checking requires.plist";


@implementation OOCheckRequiresPListVerifierStage

- (NSString *)name
{
	return kStageName;
}


- (BOOL)shouldRun
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	return [fileScanner fileExists:@"requires.plist"
						  inFolder:@"Config"
					referencedFrom:nil
					  checkBuiltIn:NO];
}


- (void)run
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	NSDictionary				*requiresPList = nil;
	NSSet						*knownKeys = nil;
	NSMutableSet				*actualKeys = nil;
	NSString					*version = nil,
								*maxVersion = nil;
	NSArray						*ooVersionComponents = nil,
								*versionComponents = nil,
								*maxVersionComponents = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	requiresPList = [fileScanner plistNamed:@"requires.plist"
								   inFolder:@"Config"
							 referencedFrom:nil
							   checkBuiltIn:NO];
	
	if (requiresPList == nil)  return;
	
	// Check that it's a dictionary
	if (![requiresPList isKindOfClass:[NSDictionary class]])
	{
		OOLog(@"verifyOXP.requiresPList.notDict", @"***** ERROR: requires.plist is not a dictionary.");
		return;
	}
	
	// Check that all the keys are known.
	knownKeys = [[self verifier] configurationSetForKey:@"requiresPListSupportedKeys"];
	actualKeys = [NSMutableSet setWithArray:[requiresPList allKeys]];
	[actualKeys minusSet:knownKeys];
	
	if ([actualKeys count] != 0)
	{
		
		OOLog(@"verifyOXP.requiresPList.unknownKeys", @"----- WARNING: requires.plist contains unknown keys. This OXP will not be loaded by this version of Oolite. Unknown keys are: %@.", [[actualKeys allObjects] componentsJoinedByString:@", "]);
	}
	
	// Sanity check the known keys.
	version = [requiresPList objectForKey:@"version"];
	if (version != nil)
	{
		if (![version isKindOfClass:[NSString class]])
		{
			OOLog(@"verifyOXP.requiresPList.badValue", @"***** ERROR: Value for 'version' is not a string.");
			version = nil;
		}
	}
	
	maxVersion = [requiresPList objectForKey:@"max_version"];
	if (maxVersion != nil)
	{
		if (![maxVersion isKindOfClass:[NSString class]])
		{
			OOLog(@"verifyOXP.requiresPList.badValue", @"***** ERROR: Value for 'max_version' is not a string.");
			maxVersion = nil;
		}
	}
	
	if (version != nil || maxVersion != nil)
	{
		ooVersionComponents = ComponentsFromVersionString([[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]);
		if (ooVersionComponents == nil)
		{
			OOLog(@"verifyOXP.requiresPList.cantFindOoliteVersion", @"----- WARNING: could not find Oolite's version for requires.plist sanity check.");
		}
		if (version != nil)
		{
			versionComponents = ComponentsFromVersionString(version);
			if (versionComponents == nil)
			{
				OOLog(@"verifyOXP.requiresPList.badValue", @"***** ERROR: could not interpret version string \"%@\" as version number.", version);
			}
			else if (ooVersionComponents != nil)
			{
				if (CompareVersions(ooVersionComponents, versionComponents) == NSOrderedAscending)
				{
					OOLog(@"verifyOXP.requiresPList.oxpRequiresNewerOolite", @"----- WARNING: this OXP requires a newer version of Oolite (%@) to work.", version);
				}
			}
		}
		if (maxVersion != nil)
		{
			maxVersionComponents = ComponentsFromVersionString(maxVersion);
			if (maxVersionComponents == nil)
			{
				OOLog(@"verifyOXP.requiresPList.badValue", @"***** ERROR: could not interpret max_version string \"%@\" as version number.", maxVersion);
			}
			else if (ooVersionComponents != nil)
			{
				if (CompareVersions(ooVersionComponents, maxVersionComponents) == NSOrderedDescending)
				{
					OOLog(@"verifyOXP.requiresPList.oxpRequiresOlderOolite", @"----- WARNING: this OXP requires an older version of Oolite (%@) to work.", maxVersion);
				}
			}
		}
		
		if (versionComponents != nil && maxVersionComponents != nil)
		{
			if (CompareVersions(versionComponents, maxVersionComponents) == NSOrderedDescending)
			{
				OOLog(@"verifyOXP.requiresPList.noVersionsInRange", @"***** ERROR: this OXP's maximum version (%@) is less than its minimum version (%@).", maxVersion, version);
			}
		}
	}
}

@end

#endif
