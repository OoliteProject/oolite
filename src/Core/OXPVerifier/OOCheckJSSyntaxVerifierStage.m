/*

OOCheckJSSyntaxVerifierStage.m


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

#import "OOCheckJSSyntaxVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOStringParsing.h"
#import "OOScript.h"
#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"

static NSString * const kStageName	= @"Checking JS Script file syntax";


@implementation OOCheckJSSyntaxVerifierStage

- (NSString *)name
{
	return kStageName;
}


- (BOOL)shouldRun
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	return ([[fileScanner filesInFolder:@"Scripts"] count] > 0);
}


- (void)run
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	NSArray						*scriptFiles = nil;
	NSString					*scriptFile = nil;
	NSString					*fileExt = nil;
	NSString					*filePath = nil;

	fileScanner = [[self verifier] fileScannerStage];
	scriptFiles = [fileScanner filesInFolder:@"Scripts"];
	
	if (scriptFiles == nil)  return;

	[[OOJavaScriptEngine sharedEngine] setShowErrorLocations:YES];

	foreach (scriptFile, scriptFiles)
	{
		fileExt = [[scriptFile pathExtension] lowercaseString];
		if ([fileExt isEqualToString:@"js"] || [fileExt isEqualToString:@"es"])
		{
			filePath = [fileScanner pathForFile:scriptFile inFolder:@"Scripts" referencedFrom:nil checkBuiltIn:NO];

			OOScript	*script = [OOJSScript scriptWithPath:filePath properties:nil];
			(void)script;
		}
	}
	
	
}

@end

#endif
