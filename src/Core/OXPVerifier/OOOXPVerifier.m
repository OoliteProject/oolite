/*

OOOXPVerifier.m


Copyright (C) 2007-2012 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

/*	Design notes:
	see "verifier design.txt".
*/

#import "OOOXPVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOOXPVerifierStageInternal.h"
#import "OOLoggingExtended.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "GameController.h"
#import "OOCacheManager.h"


static void SwitchLogFile(NSString *name);
static void NoteVerificationStage(NSString *displayName, NSString *stage);
static void OpenLogFile(NSString *name);

@interface OOOXPVerifier (OOPrivate)

- (id)initWithPath:(NSString *)path;
- (void)run;

- (void)setUpLogOverrides;

- (void)registerBaseStages;
- (void)buildDependencyGraph;
- (void)runStages;

- (BOOL)setUpDependencies:(NSSet *)dependencies
				 forStage:(OOOXPVerifierStage *)stage;

- (void)setUpDependents:(NSSet *)dependents
			   forStage:(OOOXPVerifierStage *)stage;

- (void)dumpDebugGraphviz;

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
				OOLog(@"verifyOXP.noPath", @"***** ERROR: %@ passed without path argument; nothing to verify.", arg);
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
		OOLog(@"verifyOXP.badPath", @"***** ERROR: no OXP exists at path \"%@\"; nothing to verify.", foundPath);
	}
	else if (!isDirectory)
	{
		OOLog(@"verifyOXP.badPath", @"***** ERROR: \"%@\" is a file, not an OXP directory; nothing to verify.", foundPath);
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
	
	if (![stage isKindOfClass:[OOOXPVerifierStage class]])
	{
		OOLog(@"verifyOXP.registration.failed", @"Attempt to register class %@ as a verifier stage, but it is not a subclass of OOOXPVerifierStage; ignoring.", [stage class]);
		return;
	}
	
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
	[stage setVerifier:self];
	[_stagesByName setObject:stage forKey:name];
	[_waitingStages addObject:stage];
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
	return [_verifierPList oo_arrayForKey:key];
}


- (NSDictionary *)configurationDictionaryForKey:(NSString *)key
{
	return [_verifierPList oo_dictionaryForKey:key];
}


- (NSString *)configurationStringForKey:(NSString *)key
{
	return [_verifierPList oo_stringForKey:key];
}


- (NSSet *)configurationSetForKey:(NSString *)key
{
	NSArray *array = [_verifierPList oo_arrayForKey:key];
	return array != nil ? [NSSet setWithArray:array] : nil;
}

@end


@implementation OOOXPVerifier (OOPrivate)

- (id)initWithPath:(NSString *)path
{
	self = [super init];
	
	NSString *verifierPListPath = [[[ResourceManager builtInPath] stringByAppendingPathComponent:@"Config"] stringByAppendingPathComponent:@"verifyOXP.plist"];
	_verifierPList = [[NSDictionary dictionaryWithContentsOfFile:verifierPListPath] retain];
	
	_basePath = [path copy];
	_displayName = [[NSFileManager defaultManager] displayNameAtPath:_basePath];
	if (_displayName == nil)  _displayName = [_basePath lastPathComponent];
	[_displayName retain];
	
	_stagesByName = [[NSMutableDictionary alloc] init];
	_waitingStages = [[NSMutableSet alloc] init];
	
	if (_verifierPList == nil ||
		_basePath == nil)
	{
		OOLog(@"verifyOXP.setup.failed", @"***** ERROR: failed to set up OXP verifier.");
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
	OOLog(@"verifyOXP.start", @"Running OXP verifier for %@", _basePath);//_displayName);
	
	[self registerBaseStages];
	[self buildDependencyGraph];
	[self runStages];
	
	NoteVerificationStage(_displayName, @"");
	OOLog(@"verifyOXP.done", @"OXP verification complete.");
	
	OpenLogFile(_displayName);
}


- (void)setUpLogOverrides
{
	NSDictionary			*overrides = nil;
	NSEnumerator			*messageClassEnum = nil;
	NSString				*messageClass = nil;
	id						verbose = nil;
	
	OOLogSetShowMessageClassTemporary([_verifierPList oo_boolForKey:@"logShowMessageClassOverride" defaultValue:NO]);
	
	overrides = [_verifierPList oo_dictionaryForKey:@"logControlOverride"];
	for (messageClassEnum = [overrides keyEnumerator]; (messageClass = [messageClassEnum nextObject]); )
	{
		OOLogSetDisplayMessagesInClass(messageClass, [overrides oo_boolForKey:messageClass defaultValue:NO]);
	}
	
	/*	Since actually editing logControlOverride is a pain, we also allow
		overriding verifyOXP.verbose through user defaults. This is at least
		as much a pain under GNUstep, but very convenient under OS X.
	*/
	verbose = [[NSUserDefaults standardUserDefaults] objectForKey:@"oxp-verifier-verbose-logging"];
	if (verbose != nil)  OOLogSetDisplayMessagesInClass(@"verifyOXP.verbose", OOBooleanFromObject(verbose, NO));
}


- (void)registerBaseStages
{
	NSAutoreleasePool		*pool = nil;
	NSSet					*stages = nil;
	NSSet					*excludeStages = nil;
	NSEnumerator			*stageEnum = nil;
	NSString				*stageName = nil;
	Class					stageClass = Nil;
	OOOXPVerifierStage		*stage = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	// Load stages specified as array of class names in verifyOXP.plist
	stages = [self configurationSetForKey:@"stages"];
	excludeStages = [self configurationSetForKey:@"excludeStages"];
	if ([excludeStages count] != 0)
	{
		stages = [[stages mutableCopy] autorelease];
		[(NSMutableSet *)stages minusSet:excludeStages];
	}
	for (stageEnum = [stages objectEnumerator]; (stageName = [stageEnum nextObject]); )
	{
		if ([stageName isKindOfClass:[NSString class]])
		{
			stageClass = NSClassFromString(stageName);
			if (stageClass == Nil)
			{
				OOLog(@"verifyOXP.registration.failed", @"Attempt to register unknown class %@ as a verifier stage, ignoring.", stageName);
				continue;
			}
			stage = [[stageClass alloc] init];
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
	NSMutableDictionary		*dependenciesByStage = nil,
							*dependentsByStage = nil;
	NSSet					*dependencies = nil,
							*dependents = nil;
	NSValue					*key = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	/*	Iterate over all stages, getting dependency and dependent sets.
		This is done in advance so that -dependencies and -dependents may
		register stages.
	*/
	dependenciesByStage = [NSMutableDictionary dictionary];
	dependentsByStage = [NSMutableDictionary dictionary];
	
	for (;;)
	{
		/*	Loop while there are stages whose dependency lists haven't been
			checked. This is an indeterminate loop since new ones can be
			added.
		*/
		stage = [_waitingStages anyObject];
		if (stage == nil)  break;
		[_waitingStages removeObject:stage];
		
		key = [NSValue valueWithNonretainedObject:stage];
		
		dependencies = [stage dependencies];
		if (dependencies != nil)
		{
			[dependenciesByStage setObject:dependencies
									forKey:key];
		}
		
		dependents = [stage dependents];
		if (dependents != nil)
		{
			[dependentsByStage setObject:dependents
								  forKey:key];
		}
	}
	[_waitingStages release];
	_waitingStages = nil;
	_openForRegistration = NO;
	
	// Iterate over all stages, resolving dependencies.
	stageKeys = [_stagesByName allKeys];	// Get the keys up front because we may need to remove entries from dictionary.
	
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
		
		// Get dependency set
		key = [NSValue valueWithNonretainedObject:stage];
		dependencies = [dependenciesByStage objectForKey:key];
		
		if (dependencies != nil && ![self setUpDependencies:dependencies forStage:stage])
		{
			[_stagesByName removeObjectForKey:stageKey];
		}
	}
	
	/*	Iterate over all stages again, resolving reverse dependencies.
		This is done in a separate pass because reverse dependencies are "weak"
		while forward dependencies are "strong". 
	*/
	stageKeys = [_stagesByName allKeys];
	
	for (stageEnum = [stageKeys objectEnumerator]; (stageKey = [stageEnum nextObject]); )
	{
		stage = [_stagesByName objectForKey:stageKey];
		if (stage == nil)  continue;
		
		// Get dependent set
		key = [NSValue valueWithNonretainedObject:stage];
		dependents = [dependentsByStage objectForKey:key];
		
		if (dependents != nil)
		{
			[self setUpDependents:dependents forStage:stage];
		}
	}
	
	_waitingStages = [[NSMutableSet alloc] initWithArray:[_stagesByName allValues]];
	[_waitingStages makeObjectsPerformSelector:@selector(dependencyRegistrationComplete)];
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"oxp-verifier-dump-debug-graphviz"])
	{
		[self dumpDebugGraphviz];
	}
	
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
		
		stageName = nil;
		OOLogPushIndent();
		@try
		{
			stageName = [stageToRun name];
			if ([stageToRun shouldRun])
			{
				NoteVerificationStage(_displayName, stageName);
				OOLog(@"verifyOXP.runStage", @"%@", stageName);
				OOLogIndent();
				[stageToRun performRun];
			}
			else
			{
				OOLog(@"verifyOXP.verbose.skipStage", @"- Skipping stage: %@ (nothing to do).", stageName);
				[stageToRun noteSkipped];
			}
		}
		@catch (NSException *exception)
		{
			if (stageName == nil)  stageName = [[stageToRun class] description];
			OOLog(@"verifyOXP.exception", @"***** Exception occurred when running OXP verifier stage \"%@\": %@: %@", stageName, [exception name], [exception reason]);
		}
		OOLogPopIndent();
		
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


- (BOOL)setUpDependencies:(NSSet *)dependencies
				 forStage:(OOOXPVerifierStage *)stage
{
	NSString				*depName = nil;
	NSEnumerator			*depEnum = nil;
	OOOXPVerifierStage		*depStage = nil;
	
	// Iterate over dependencies, connecting them up.
	for (depEnum = [dependencies objectEnumerator]; (depName = [depEnum nextObject]); )
	{
		depStage = [_stagesByName objectForKey:depName];
		if (depStage == nil)
		{
			OOLog(@"verifyOXP.buildDependencyGraph.unresolved", @"Verifier stage %@ has unresolved dependency \"%@\", skipping.", stage, depName);
			return NO;
		}
		
		if ([depStage isDependentOf:stage])
		{
			OOLog(@"verifyOXP.buildDependencyGraph.circularReference", @"Verifier stages %@ and %@ have a dependency loop, skipping.", stage, depStage);
			[_stagesByName removeObjectForKey:depName];
			return NO;
		}
		
		[stage registerDependency:depStage];
	}
	
	return YES;
}


- (void)setUpDependents:(NSSet *)dependents
			   forStage:(OOOXPVerifierStage *)stage
{
	NSString				*depName = nil;
	NSEnumerator			*depEnum = nil;
	OOOXPVerifierStage		*depStage = nil;
	
	// Iterate over dependents, connecting them up.
	for (depEnum = [dependents objectEnumerator]; (depName = [depEnum nextObject]); )
	{
		depStage = [_stagesByName objectForKey:depName];
		if (depStage == nil)
		{
			OOLog(@"verifyOXP.buildDependencyGraph.unresolved", @"Verifier stage %@ has unresolved dependent \"%@\".", stage, depName);
			continue;	// Unresolved/conflicting dependents are non-fatal
		}
		
		if ([stage isDependentOf:depStage])
		{
			OOLog(@"verifyOXP.buildDependencyGraph.circularReference", @"Verifier stage %@ lists %@ as both dependent and dependency (possibly indirectly); will execute %@ after %@.", stage, depStage, stage, depStage);
			continue;
		}
		
		[depStage registerDependency:stage];
	}
}


- (void)dumpDebugGraphviz
{
	NSMutableString				*graphViz = nil;
	NSDictionary				*graphVizTemplate = nil;
	NSString					*template = nil,
								*startTemplate = nil,
								*endTemplate = nil;
	NSEnumerator				*stageEnum = nil;
	OOOXPVerifierStage			*stage = nil;
	NSSet						*deps = nil;
	NSEnumerator				*depEnum = nil;
	OOOXPVerifierStage			*dep = nil;
	
	graphVizTemplate = [self configurationDictionaryForKey:@"debugGraphvizTempate"];
	graphViz = [NSMutableString stringWithFormat:[graphVizTemplate oo_stringForKey:@"preamble"], [NSDate date]];
	
	/*	Pass 1: enumerate over graph setting node attributes for each stage.
		We use pointers as node names for simplicity of generation.
	*/
	template = [graphVizTemplate oo_stringForKey:@"node"];
	for (stageEnum = [_stagesByName objectEnumerator]; (stage = [stageEnum nextObject]); )
	{
		[graphViz appendFormat:template, stage, [stage class], [stage name]];
	}
	
	[graphViz appendString:[graphVizTemplate oo_stringForKey:@"forwardPreamble"]];
	
	/*	Pass 2: enumerate over graph setting forward arcs for each dependency.
	*/
	template = [graphVizTemplate oo_stringForKey:@"forwardArc"];
	startTemplate = [graphVizTemplate oo_stringForKey:@"startArc"];
	for (stageEnum = [_stagesByName objectEnumerator]; (stage = [stageEnum nextObject]); )
	{
		deps = [stage resolvedDependencies];
		if ([deps count] != 0)
		{
			for (depEnum = [deps objectEnumerator]; (dep = [depEnum nextObject]); )
			{
				[graphViz appendFormat:template, dep, stage];
			}
		}
		else
		{
			[graphViz appendFormat:startTemplate, stage];
		}
	}
	
	[graphViz appendString:[graphVizTemplate oo_stringForKey:@"backwardPreamble"]];
	
	/*	Pass 3: enumerate over graph setting backward arcs for each dependent.
	*/
	template = [graphVizTemplate oo_stringForKey:@"backwardArc"];
	endTemplate = [graphVizTemplate oo_stringForKey:@"endArc"];
	for (stageEnum = [_stagesByName objectEnumerator]; (stage = [stageEnum nextObject]); )
	{
		deps = [stage resolvedDependents];
		if ([deps count] != 0)
		{
			for (depEnum = [deps objectEnumerator]; (dep = [depEnum nextObject]); )
			{
				[graphViz appendFormat:template, dep, stage];
			}
		}
		else
		{
			[graphViz appendFormat:endTemplate, stage];
		}
	}
	
	[graphViz appendString:[graphVizTemplate oo_stringForKey:@"postamble"]];
	
	// Write file
	[ResourceManager writeDiagnosticString:graphViz toFileNamed:@"OXPVerifierStageDependencies.dot"];
}

@end


#import "OOLogOutputHandler.h"


static void SwitchLogFile(NSString *name)
{
//#ifndef OOLITE_LINUX
	name = [name stringByAppendingPathExtension:@"log"];
	OOLog(@"verifyOXP.switchingLog", @"Switching log files -- logging to \"%@\".", name);
	OOLogOutputHandlerChangeLogFile(name);
//#else
//	OOLog(@"verifyOXP.switchingLog", @"Switching logging to <stdout>.");
//	OOLogOutputHandlerStartLoggingToStdout();
//#endif
}


static void NoteVerificationStage(NSString *displayName, NSString *stage)
{
	[[GameController sharedController] logProgress:[NSString stringWithFormat:@"Verifying %@\n%@", displayName, stage]];
}


static void OpenLogFile(NSString *name)
{
	//	Open log file in appropriate application / provide feedback.
	
	if ([[NSUserDefaults standardUserDefaults] oo_boolForKey:@"oxp-verifier-open-log" defaultValue:YES])
	{
#if OOLITE_MAC_OS_X
		[[NSWorkspace sharedWorkspace] openFile:OOLogHandlerGetLogPath()];
#elif OOLITE_WINDOWS
		// start wordpad (for historical reasons wordpad is called write from the command prompt)
		system([[NSString stringWithFormat:@"write \"Logs\\%@.log\"", name] UTF8String]);
#elif  OOLITE_LINUX
		// MKW - needed to suppress 'ignoring return value' warning for system() call
		int ret;
		// Nothing to do here, since we dump to stdout instead of to a file.
		//OOLogOutputHandlerStopLoggingToStdout();
		ret = system([[NSString stringWithFormat:@"cat \"%@\"", OOLogHandlerGetLogPath()] UTF8String]);
#else 
		do {} while (0);
#endif
	}
}


#endif	// OO_OXP_VERIFIER_ENABLED
