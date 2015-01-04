/*

OOCheckPListSyntaxVerifierStage.m


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

#import "OOCheckPListSyntaxVerifierStage.h"
#import "OOCollectionExtractors.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"

static NSString * const kStageName	= @"Checking plist well-formedness";


@implementation OOCheckPListSyntaxVerifierStage

- (NSString *)name
{
	return kStageName;
}


- (BOOL)shouldRun
{
	return YES;
}


- (void)run
{
	OOFileScannerVerifierStage	*fileScanner = nil;

	
	fileScanner = [[self verifier] fileScannerStage];

	NSArray *plists = [[[self verifier] configurationDictionaryForKey:@"knownFiles"] oo_arrayForKey:@"Config"];
	NSArray *arrayPlists = [[[self verifier] configurationDictionaryForKey:@"knownFiles"] oo_arrayForKey:@"ConfigArrays"];
	NSArray *dictionaryPlists = [[[self verifier] configurationDictionaryForKey:@"knownFiles"] oo_arrayForKey:@"ConfigDictionaries"];

	NSString *plistName = nil;
	foreach (plistName, plists)
	{
		if ([fileScanner fileExists:plistName
						   inFolder:@"Config"
					 referencedFrom:nil
					   checkBuiltIn:NO])
		{
			OOLog(@"verifyOXP.syntaxCheck",@"Checking %@",plistName);
			id retrieve = [fileScanner plistNamed:plistName
										 inFolder:@"Config"
								   referencedFrom:nil
									 checkBuiltIn:NO];
			if (retrieve != nil)
			{
				if ([retrieve isKindOfClass:[NSArray class]])
				{
					if (![arrayPlists containsObject:plistName])
					{
						OOLog(@"verifyOXP.syntaxCheck.error",@"%@ should be an array but isn't.",plistName);
					}
				}
				else if ([retrieve isKindOfClass:[NSDictionary class]])
				{
					if (![dictionaryPlists containsObject:plistName])
					{
						OOLog(@"verifyOXP.syntaxCheck.error",@"%@ should be an array but isn't.",plistName);
					}
				}
				else
				{
					OOLog(@"verifyOXP.syntaxCheck.error",@"%@ is neither an array nor a dictionary.",plistName);
				}
			}
		}
	}
	
}

@end



#endif
