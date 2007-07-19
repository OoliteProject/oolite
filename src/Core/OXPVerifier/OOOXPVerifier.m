/*

OOOXPVerifier.m


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

#import "OOOXPVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOOXPVerifierStageInternal.h"
#import "OOLogging.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "GameController.h"
#import "OOCacheManager.h"


#if OOLITE_HAVE_APPKIT
static void SwitchLogFile(NSString *name);
static void NoteVerificationStage(NSString *displayName, NSString *stage);
static void OpenLogFile(NSString *name);
#else
#define SwitchLogFile(name) do {} while (0)
#define NoteVerificationStage(displayName, stage) do {} while (0)
#define OpenLogFile(name) do {} while (0)
#endif


@interface OOOXPVerifier (OOPrivate)

- (id)initWithPath:(NSString *)path;
- (void)run;

- (void)setUpLogOverrides;

- (void)registerBaseStages;
- (void)buildDependencyGraph;
- (void)runStages;
- (void)postRunStages;

- (BOOL)setUpDependenciesForStage:(OOOXPVerifierStage *)stage;

- (void)listStageDependencies;

@end


@implementation OOOXPVerifier

+ (BOOL)runVerificationIfRequested
{
	NSArray				*arguments = nil;
	NSEnumerator		*argEnum = nil;
	NSString			*arg = nil;
	NSString			*foundPath = nil;
	BOOL				exists, isDirectory;
	OOOXPVerifier		*verifier = nil;
	NSAutoreleasePool	*pool = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	arguments = [[NSProcessInfo processInfo] arguments];
	
	// Scan for -verify-oxp or --verify-oxp followed by relative path
	for (argEnum = [arguments objectEnumerator]; (arg = [argEnum nextObject]); )
	{
		if ([arg isEqual:@"-verify-oxp"] || [arg isEqual:@"--verify-oxp"])
		{
			foundPath = [argEnum nextObject];
			if (foundPath == nil)
			{
				OOLog(@"verifyOXP.noPath", @"ERROR: %@ passed without path argument; nothing to verify.");
				[pool release];
				return YES;
			}
			foundPath = [foundPath stringByExpandingTildeInPath];
			break;
		}
	}
	
	if (foundPath == nil)
	{
		[pool release];
		return NO;
	}
	
	// We got a path; does it point to a directory?
	exists = [[NSFileManager defaultManager] fileExistsAtPath:foundPath isDirectory:&isDirectory];
	if (!exists)
	{
		OOLog(@"verifyOXP.badPath", @"ERROR: no OXP exists at path \"%@\"; nothing to verify.", foundPath);
	}
	else if (!isDirectory)
	{
		OOLog(@"verifyOXP.badPath", @"ERROR: path \"%@\" refers to a file, not an OXP directory; nothing to verify.", foundPath);
	}
	else
	{
		verifier = [[OOOXPVerifier alloc] initWithPath:foundPath];
		[pool release];
		pool = [[NSAutoreleasePool alloc] init];
		[verifier run];
		[verifier release];
	}
	[pool release];
	
	// Whether or not we got a valid path, -verify-oxp was passed.
	return YES;
}


- (void)dealloc
{
	[_verifierPList release];
	[_basePath release];
	[_displayName release];
	[_stagesByName release];
	[_waitingStages release];
	
	[super dealloc];
}


- (void)registerStage:(OOOXPVerifierStage *)stage
{
	NSString				*name = nil;
	OOOXPVerifierStage		*existing = nil;
	
	// Sanity checking
	if (stage == nil)  return;
	
	if (!_openForRegistration)
	{
		OOLog(@"verifyOXP.registration.failed", @"Attempt to register verifier stage %@ after registration closed, ignoring.", stage);
		return;
	}
	
	name = [stage name];
	if (name == nil)
	{
		OOLog(@"verifyOXP.registration.failed", @"Attempt to register verifier stage %@ with nil name, ignoring.", stage);
		return;
	}
		
	// We can only have one stage with a given name. Registering the same stage twice is OK, though.
	existing = [_stagesByName objectForKey:name];
	if (existing == stage)  return;
	if (existing != nil)
	{
		OOLog(@"verifyOXP.registration.failed", @"Attempt to register verifier stage %@ with same name as stage %@, ignoring.", stage, existing);
		return;
	}
	
	// Checks passed, store state.
	if (_stagesByName == nil)  _stagesByName = [[NSMutableDictionary alloc] init];
	[_stagesByName setObject:stage forKey:name];
}


- (NSString *)oxpPath
{
	return [[_basePath retain] autorelease];
}


- (NSString *)oxpDisplayName
{
	return [[_displayName retain] autorelease];
}


- (id)stageWithName:(NSString *)name
{
	if (name == nil)  return nil;
	
	return [_stagesByName objectForKey:name];
}


- (id)configurationValueForKey:(NSString *)key
{
	return [_verifierPList objectForKey:key];
}


- (NSArray *)configurationArrayForKey:(NSString *)key
{
	return [_verifierPList arrayForKey:key];
}


- (NSDictionary *)configurationDictionaryForKey:(NSString *)key
{
	return [_verifierPList dictionaryForKey:key];
}


- (NSString *)configurationStringForKey:(NSString *)key
{
	return [_verifierPList stringForKey:key];
}


- (NSSet *)configurationSetForKey:(NSString *)key
{
	NSArray *array = [_verifierPList arrayForKey:key];
	return array != nil ? [NSSet setWithArray:array] : nil;
}

@end


@implementation OOOXPVerifier (OOPrivate)

- (id)initWithPath:(NSString *)path
{
	self = [super init];
	
	_verifierPList = [ResourceManager dictionaryFromFilesNamed:@"verifyOXP.plist"
													  inFolder:@"Config"
													  andMerge:NO];
	[_verifierPList retain];
	
	_basePath = [path copy];
	_displayName = [[NSFileManager defaultManager] displayNameAtPath:_basePath];
	if (_displayName == nil)  _displayName = [_basePath lastPathComponent];
	[_displayName retain];
	
	if (_verifierPList == nil ||
		_basePath == nil)
	{
		OOLog(@"verifyOXP.setup.failed", @"ERROR: failed to set up OXP verifier.");
		[self release];
		return nil;
	}
	
	_openForRegistration = YES;
	
	return self;
}


- (void)run
{
	NoteVerificationStage(_displayName, @"");
	
	[self setUpLogOverrides];
	
	/*	We need to be able to look up internal files, but not other OXP files.
		To do this without clobbering the disk cache, we disable cache writes.
	*/
	[[OOCacheManager sharedCache] flush];
	[[OOCacheManager sharedCache] setAllowCacheWrites:NO];
	[ResourceManager setUseAddOns:NO];
	
	SwitchLogFile(_displayName);
	OOLog(@"verifyOXP.start", @"Running OXP verifier for %@", _displayName);
	
	[self registerBaseStages];
	_openForRegistration = NO;
	
	[self buildDependencyGraph];
	[self runStages];
	[self postRunStages];
	
	NoteVerificationStage(_displayName, @"");
	OOLog(@"verifyOXP.done", @"OXP verification complete.");
	
	OpenLogFile(_displayName);
}


- (void)setUpLogOverrides
{
	NSDictionary			*overrides = nil;
	NSEnumerator			*messageClassEnum = nil;
	NSString				*messageClass = nil;
	
	overrides = [_verifierPList dictionaryForKey:@"logControlOverride"];
	OOLogSetShowMessageClass(NO);
	
	for (messageClassEnum = [overrides keyEnumerator]; (messageClass = [messageClassEnum nextObject]); )
	{
		OOLogSetDisplayMessagesInClass(messageClass, [overrides boolForKey:messageClass defaultValue:NO]);
	}
}


- (void)registerBaseStages
{
	NSAutoreleasePool		*pool = nil;
	NSArray					*stages = nil;
	NSEnumerator			*stageEnum = nil;
	NSString				*stageName = nil;
	Class					stageClass = Nil;
	OOOXPVerifierStage		*stage = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	// Load stages specified as array of class names in verifyOXP.plist
	stages = [self configurationArrayForKey:@"stages"];
	for (stageEnum = [stages objectEnumerator]; (stageName = [stageEnum nextObject]); )
	{
		if ([stageName isKindOfClass:[NSString class]])
		{
			stageClass = NSClassFromString(stageName);
			stage = [[stageClass alloc] init];
			[stage setVerifier:self];
			[self registerStage:stage];
			[stage release];
		}
	}
	
	[pool release];
}


- (void)buildDependencyGraph
{
	NSAutoreleasePool		*pool = nil;
	NSArray					*stageKeys = nil;
	NSEnumerator			*stageEnum = nil;
	NSString				*stageKey = nil;
	OOOXPVerifierStage		*stage = nil;
	NSString				*name = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	// Iterate over all stages, and resolve dependencies.
	stageKeys = [_stagesByName allKeys];	// Make a copy because we may need to remove entries from dictionary.
	
	for (stageEnum = [stageKeys objectEnumerator]; (stageKey = [stageEnum nextObject]); )
	{
		stage = [_stagesByName objectForKey:stageKey];
		if (stage == nil)  continue;
		
		// Sanity check
		name = [stage name];
		if (![stageKey isEqualToString:name])
		{
			OOLog(@"verifyOXP.buildDependencyGraph.badName", @"***** Stage name appears to have changed from \"%@\" to \"%@\" for verifier stage %@, removing.", stageKey, name, stage);
			[_stagesByName removeObjectForKey:stageKey];
			continue;
		}
		
		if (![self setUpDependenciesForStage:stage])
		{
			[_stagesByName removeObjectForKey:stageKey];
		}
	}
	
	_waitingStages = [[NSMutableSet alloc] initWithArray:[_stagesByName allValues]];
	[_waitingStages makeObjectsPerformSelector:@selector(dependencyRegistrationComplete)];
	
	if (OOLogWillDisplayMessagesInClass(@"verifyOXP.listStageDependencies"))  [self listStageDependencies];
	
	[pool release];
}


- (void)runStages
{
	NSAutoreleasePool		*pool = nil;
	NSEnumerator			*stageEnum = nil;
	OOOXPVerifierStage		*candidateStage = nil,
							*stageToRun = nil;
	NSString				*stageName = nil;
	
	// Loop while there are still stages to run.
	for (;;)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		// Look through queue for a stage that's ready
		stageToRun = nil;
		for (stageEnum = [_waitingStages objectEnumerator]; (candidateStage = [stageEnum nextObject]); )
		{
			if ([candidateStage canRun])
			{
				stageToRun = candidateStage;
				break;
			}
		}
		if (stageToRun == nil)
		{
			// No more runnable stages
			[pool release];
			break;
		}
		
		stageName = [stageToRun name];
		if ([stageToRun shouldRun])
		{
			NoteVerificationStage(_displayName, stageName);
			OOLog(@"verifyOXP.runStage", @"%@", stageName);
			OOLogPushIndent();
			OOLogIndent();
			[stageToRun performRun];
			OOLogPopIndent();
		}
		else
		{
			OOLog(@"verifyOXP.verbose.skipStage", @"- Skipping stage: %@", stageName);
			[stageToRun noteSkipped];
		}
		
		[_waitingStages removeObject:stageToRun];
		[pool release];
	}
	
	pool = [[NSAutoreleasePool alloc] init];
	
	if ([_waitingStages count] != 0)
	{
		OOLog(@"verifyOXP.incomplete", @"Some verifier stages could not be run:");
		OOLogIndent();
		for (stageEnum = [_waitingStages objectEnumerator]; (candidateStage = [stageEnum nextObject]); )
		{
			OOLog(@"verifyOXP.incomplete.item", @"%@", candidateStage);
		}
		OOLogOutdent();
	}
	[_waitingStages release];
	_waitingStages = nil;
	
	[pool release];
}


- (void)postRunStages
{
	NSAutoreleasePool		*pool = nil;
	NSEnumerator			*stageEnum = nil;
	OOOXPVerifierStage		*candidateStage = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	for (stageEnum = [_waitingStages objectEnumerator]; (candidateStage = [stageEnum nextObject]); )
	{
		if ([candidateStage completed] && [candidateStage needsPostRun])
		{
			[candidateStage postRun];
		}
	}
	
	[pool release];
}


- (BOOL)setUpDependenciesForStage:(OOOXPVerifierStage *)stage
{
	NSSet					*depNames = nil;
	NSEnumerator			*depEnum = nil;
	NSString				*depName = nil;
	OOOXPVerifierStage		*dependency = nil;
	
	// Iterate over dependencies, connecting them up.
	depNames = [stage requiredStages];
	for (depEnum = [depNames objectEnumerator]; (depName = [depEnum nextObject]); )
	{
		dependency = [_stagesByName objectForKey:depName];
		if (dependency == nil)
		{
			OOLog(@"verifyOXP.buildDependencyGraph.unresolved", @"Verifier stage %@ has unresolved depdency \"%@\", skipping.", stage, depName);
			return NO;
		}
		
		if ([dependency isDependentOf:stage])
		{
			OOLog(@"verifyOXP.buildDependencyGraph.circularReference", @"Verifier stages %@ and %@ have a dependency loop, skipping.", stage, dependency);
			[_stagesByName removeObjectForKey:depName];
			return NO;
		}
		
		[stage registerDependency:dependency];
	}
	
	return YES;
}


- (void)listStageDependencies
{
	NSEnumerator				*stageEnum = nil;
	OOOXPVerifierStage			*stage = nil;
	NSSet						*deps = nil;
	NSEnumerator				*depEnum = nil;
	OOOXPVerifierStage			*dep = nil;
	
	OOLog(@"verifyOXP.listStageDependencies", @"Verifier stage dependencies:");
	OOLogIndent();
	
	for (stageEnum = [_stagesByName objectEnumerator]; (stage = [stageEnum nextObject]); )
	{
		OOLog(@"verifyOXP.listStageDependencies", @"%@", stage);
		OOLogIndent();
		
		deps = [stage dependencies];
		if (deps == nil)
		{
			OOLog(@"verifyOXP.listStageDependencies", @"Requires: none.");
		}
		else
		{
			OOLog(@"verifyOXP.listStageDependencies", @"Requires:");
			OOLogIndent();
			
			for (depEnum = [deps objectEnumerator]; (dep = [depEnum nextObject]); )
			{
				OOLog(@"verifyOXP.listStageDependencies", @"* %@", dep);
			}
			
			OOLogOutdent();
		}
		
		deps = [stage dependents];
		if (deps == nil)
		{
			OOLog(@"verifyOXP.listStageDependencies", @"Required by: none.");
		}
		else
		{
			OOLog(@"verifyOXP.listStageDependencies", @"Required by:");
			OOLogIndent();
			
			for (depEnum = [deps objectEnumerator]; (dep = [depEnum nextObject]); )
			{
				OOLog(@"verifyOXP.listStageDependencies", @"* %@", dep);
			}
			
			OOLogOutdent();
		}
		
		OOLogOutdent();
	}
	
	OOLogOutdent();
}

@end


#if OOLITE_HAVE_APPKIT

#import "OOLogOutputHandler.h"

static void SwitchLogFile(NSString *name)
{
	name = [name stringByAppendingPathExtension:@"log"];
	OOLog(@"verifyOXP.switchingLog", @"Switching log files -- logging to \"%@\".", name);
	OOLogOutputHandlerChangeLogFile(name);}


static void NoteVerificationStage(NSString *displayName, NSString *stage)
{
	[[GameController sharedController] logProgress:[NSString stringWithFormat:@"Verifying %@\n%@", displayName, stage]];
}


static void OpenLogFile(NSString *name)
{
	//	Open log file in appropriate application.
	
	[[NSWorkspace sharedWorkspace] openFile:OOLogHandlerGetLogPath()];
}

#endif	// OOLITE_HAVE_APPKIT

#endif	// OO_OXP_VERIFIER_ENABLED
