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
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "OOStringParsing.h"
#import "OOPListSchemaVerifier.h"

static NSString * const kStageName	= @"Checking shipdata.plist";


@interface OOCheckShipDataPListVerifierStage (OOPrivate)

- (void)verifyShipInfo:(NSDictionary *)info withName:(NSString *)name;

- (void)message:(NSString *)format, ...;
- (void)verboseMessage:(NSString *)format, ...;

- (void)getRoles;
- (void)checkKeys;
- (void)checkSchema;
- (void)checkModel;

- (NSSet *)rolesFromString:(NSString *)string;

@end


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
	NSAutoreleasePool			*pool = nil;
	NSEnumerator				*shipEnum = nil;
	NSString					*shipKey = nil;
	NSDictionary				*shipInfo = nil;
	NSDictionary				*ooliteShipData = nil;
	NSDictionary				*settings = nil;
	NSMutableSet				*mergeSet = nil;
	NSArray						*shipList = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	_shipdataPList = [fileScanner plistNamed:@"shipdata.plist"
									inFolder:@"Config"
							  referencedFrom:nil
								checkBuiltIn:NO];
	
	if (_shipdataPList == nil)  return;
	
	ooliteShipData = [ResourceManager dictionaryFromFilesNamed:@"shipdata.plist"
													  inFolder:@"Config"
													  andMerge:YES];
	
	// Check that it's a dictionary
	if (![_shipdataPList isKindOfClass:[NSDictionary class]])
	{
		OOLog(@"verifyOXP.shipdataPList.notDict", @"ERROR: shipdata.plist is not a dictionary.");
		return;
	}
	
	// Keys that apply to all ships
	_ooliteShipNames = [NSSet setWithArray:[ooliteShipData allKeys]];
	settings = [[self verifier] configurationDictionaryForKey:@"shipdataPListSettings"];
	_basicKeys = [settings setForKey:@"knownShipKeys"];
	
	// Keys that apply to stations/carriers
	mergeSet = [_basicKeys mutableCopy];
	[mergeSet addObjectsFromArray:[settings arrayForKey:@"knownStationKeys"]];
	_stationKeys = mergeSet;
	
	// Keys that apply to player ships
	mergeSet = [_basicKeys mutableCopy];
	[mergeSet addObjectsFromArray:[settings arrayForKey:@"knownPlayerKeys"]];
	_playerKeys = [[mergeSet copy] autorelease];
	
	// Keys that apply to _any_ ship -- union of the above
	[mergeSet unionSet:_stationKeys];
	_allKeys = mergeSet;
	
	_schemaVerifier = [OOPListSchemaVerifier verifierWithSchema:[ResourceManager dictionaryFromFilesNamed:@"shipdataEntrySchema.plist" inFolder:@"Schemata" andMerge:NO]];
	[_schemaVerifier setDelegate:self];
	
	shipList = [[_shipdataPList allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	for (shipEnum = [shipList objectEnumerator]; (shipKey = [shipEnum nextObject]); )
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		shipInfo = [_shipdataPList dictionaryForKey:shipKey];
		if (shipInfo == nil)
		{
			OOLog(@"verifyOXP.shipdata.badType", @"ERROR: shipdata.plist entry for \"%@\" is not a dictionary.", shipKey);
		}
		else
		{
			[self verifyShipInfo:shipInfo withName:shipKey];
		}
		
		[pool release];
	}
	
	_shipdataPList = nil;
	_ooliteShipNames = nil;
	_basicKeys = nil;
	_stationKeys = nil;
	_playerKeys = nil;
}

@end


@implementation OOCheckShipDataPListVerifierStage (OOPrivate)

- (void)verifyShipInfo:(NSDictionary *)info withName:(NSString *)name
{
	_name = name;
	_info = info;
	_havePrintedMessage = NO;
	OOLogPushIndent();
	
	[self getRoles];
	[self checkKeys];
	[self checkSchema];
	[self checkModel];
	
	// Todo: check for pirates with 0 bounty
	
	OOLogPopIndent();
	if (!_havePrintedMessage)
	{
		OOLog(@"verifyOXP.verbose.shipData.OK", @"- ship \"%@\" OK.", _name);
	}
	_name = nil;
	_info = nil;
	_roles = nil;
}


// Custom log method to group messages by ship.
- (void)message:(NSString *)format, ...
{
	va_list						args;
	
	if (!_havePrintedMessage)
	{
		OOLog(@"verifyOXP.shipData.firstMessage", @"Ship \"%@\":", _name);
		OOLogIndent();
		_havePrintedMessage = YES;
	}
	
	va_start(args, format);
	OOLogWithFunctionFileAndLineAndArguments(@"verifyOXP.shipData", NULL, NULL, 0, format, args);
	va_end(args);
}


- (void)verboseMessage:(NSString *)format, ...
{
	va_list						args;
	
	if (!OOLogWillDisplayMessagesInClass(@"verifyOXP.verbose.shipData"))  return;
	
	if (!_havePrintedMessage)
	{
		OOLog(@"verifyOXP.shipData.firstMessage", @"Ship \"%@\":", _name);
		OOLogIndent();
		_havePrintedMessage = YES;
	}
	
	va_start(args, format);
	OOLogWithFunctionFileAndLineAndArguments(@"verifyOXP.verbose.shipData", NULL, NULL, 0, format, args);
	va_end(args);
}


- (void)getRoles
{
	NSString					*rolesString = nil;
	
	rolesString = [_info objectForKey:@"roles"];
	_roles = [self rolesFromString:rolesString];
	_isPlayer = [_roles member:@"player"] != nil;
	_isStation = [_info boolForKey:@"isCarrier" defaultValue:NO] ||
				 [rolesString rangeOfString:@"station"].location != NSNotFound ||
				 [rolesString rangeOfString:@"carrier"].location != NSNotFound;
	
	if (_isPlayer && _isStation)
	{
		[self message:@"ERROR: ship is both a player ship and a station. Treating as non-station."];
		_isStation = NO;
	}
}


- (void)checkKeys
{
	NSSet						*referenceSet = nil;
	NSEnumerator				*keyEnum = nil;
	NSString					*key = nil;
	
	if (_isPlayer)  referenceSet = _playerKeys;
	else if (_isStation)  referenceSet = _stationKeys;
	else  referenceSet = _basicKeys;
	
	for (keyEnum = [_info keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		if ([referenceSet member:key] == nil)
		{
			if ([_allKeys member:key] != nil)
			{
				[self message:@"WARNING: key \"%@\" does not apply to this category of ship.", key];
			}
			else
			{
				[self message:@"WARNING: unknown key \"%@\".", key];
			}
		}
	}
}


- (void)checkSchema
{
	[_schemaVerifier verifyPropertyList:_info named:_name];
}


- (void)checkModel
{
	id							model = nil,
								materials = nil,
								shaders = nil;
	
	model = [_info stringForKey:@"model"];
	materials = [_info dictionaryForKey:@"materials"];
	shaders = [_info dictionaryForKey:@"shaders"];
	
	if (![[[self verifier] modelVerifierStage] modelNamed:model
											 usedForEntry:_name
												   inFile:@"shipdata.plist"
											withMaterials:materials
											   andShaders:shaders])
	{
		[self message:@"WARNING: model \"%@\" could not be found in %@ or in Oolite.", model, [[self verifier] oxpDisplayName]];
	}
}


// Convert a roles string to a set of role names, discarding probabilities.
- (NSSet *)rolesFromString:(NSString *)string
{
	NSArray						*parts = nil;
	NSMutableSet				*result = nil;
	unsigned					i, count;
	NSString					*role = nil;
	NSRange						parenRange;
	
	if (string == nil)  return [NSSet set];
	
	parts = ScanTokensFromString(string);
	count = [parts count];
	if (count == 0)  return [NSSet set];
	
	result = [NSMutableSet setWithCapacity:count];
	for (i = 0; i != count; ++i)
	{
		role = [parts objectAtIndex:i];
		parenRange = [role rangeOfString:@"("];
		if (parenRange.location != NSNotFound)
		{
			role = [role substringToIndex:parenRange.location];
		}
		[result addObject:role];
	}
	
	return result;
}


- (BOOL)verifier:(OOPListSchemaVerifier *)verifier
withPropertyList:(id)rootPList
		   named:(NSString *)name
	testProperty:(id)subPList
		  atPath:(NSArray *)keyPath
	 againstType:(NSString *)typeKey
		   error:(NSError **)outError
{
	[self verboseMessage:@"- Skipping verification for type %@ at %@.%@.", typeKey, _name, [OOPListSchemaVerifier descriptionForKeyPath:keyPath]];
	return YES;
}


- (BOOL)verifier:(OOPListSchemaVerifier *)verifier
withPropertyList:(id)rootPList
		   named:(NSString *)name
 failedForProperty:(id)subPList
	   withError:(NSError *)error
	expectedType:(NSDictionary *)localSchema
{
	// FIXME: use fancy new error codes to provide useful error descriptions.
	[self message:@"ERROR: verification of ship \"%@\" failed at \"%@\": %@", name, [error plistKeyPathDescription], [error localizedDescription]];
	return YES;
}

@end

#endif
