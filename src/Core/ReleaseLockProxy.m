/*	ReleaseLockProxy.h
	By Jens Ayton
	This code is hereby placed in the public domain.
*/

#import "ReleaseLockProxy.h"


#define VERBOSE		0

#if VERBOSE
#define VerboseLog NSLog
#else
#define VerboseLog(...) do {} while (0)
#endif


@interface ReleaseLockProxy_SignatureTemplateClass: NSObject

// These exist purely to provide NSMethodSignatures for -[ReleaseLockProxy methodSignatureForSelector:].
+ (id)initWithObject:(id<NSObject>)object name:(NSString *)name;
+ (id)initWithRetainedObject:(id<NSObject>)object name:(NSString *)name;
+ (void)rlpAllowRelease;
+ (NSString *)rlpObjectDescription;

@end


@implementation ReleaseLockProxy

// *** Boilerplate

+ (id)proxyWithObject:(id<NSObject>)object name:(NSString *)name
{
	return [[[self alloc] initWithObject:object name:name] autorelease];
}


+ (id)proxyWithRetainedObject:(id<NSObject>)object name:(NSString *)name
{
	return [[[self alloc] initWithRetainedObject:object name:name] autorelease];
}


- (id)initWithObject:(id<NSObject>)object name:(NSString *)name
{
	return [self initWithRetainedObject:[object retain] name:name];
}


- (id)initWithRetainedObject:(id<NSObject>)object name:(NSString *)name
{
	if (object == nil)
	{
		NSLog(@"** ReleaseLockProxy: passed nil object, returning nil proxy.");
		[self release];
		return nil;
	}
	
	// No super init for proxies.
	
	_object = object;
	_name = [name copy];
	_locked = YES;
	
	return self;
}


- (void)dealloc
{
	if (_locked)
	{
		NSLog(@"** ReleaseLockProxy (%@): deallocated while locked. This shouldn't happen, unless -dealloc is being called directly.", [self rlpObjectDescription]);
	}
	else
	{
		VerboseLog(@"-- ReleaseLockProxy (%@): deallocated while not locked.", [self rlpObjectDescription]);
	}
	
	[_object release];
	[_name release];
	
	[super dealloc];
}


- (void)rlpAllowRelease
{
	_locked = NO;
}


- (NSString *)rlpObjectDescription
{
	return _name ? _name : [_object description];
}


// *** Core functionality

- (void)release
{
	unsigned retainCount = [self retainCount];
	
	if (_locked && retainCount == 1)
	{
		// Breakpoint here to catch what would otherwise be the last release before crashing.
		NSLog(@"** ReleaseLockProxy (%@): released while locked and retain count is one - intercepting retain. Something is broken.", [self rlpObjectDescription]);
		return;
	}
	
	if (_locked)
	{
		VerboseLog(@"-- ReleaseLockProxy (%@): released while locked, but retain count > 1; retain count going from %u to %u.", [self rlpObjectDescription], retainCount, retainCount - 1);
	}
	else
	{
		VerboseLog(@"-- ReleaseLockProxy (%@): released while not locked; retain count going from %u to %u.", [self rlpObjectDescription], retainCount, retainCount - 1);
	}
	
	[super release];
}


- (id)autorelease
{
	VerboseLog(@"-- ReleaseLockProxy (%@): autoreleased while %slocked and retain count at %u.", [self rlpObjectDescription], _locked ? "" : "not ", [self retainCount]);
	return [super autorelease];
}


// *** Proxy stuff.

- (void)forwardInvocation:(NSInvocation *)invocation
{
	[invocation invokeWithTarget:_object];
}


- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
	NSMethodSignature		*result = nil;
	
	if (selector == @selector(initWithObject:name:) ||
		selector == @selector(initWithRetainedObject:name:) || 
		selector == @selector(rlpAllowRelease) ||
		selector == @selector(rlpObjectDescription))
	{
		result = [ReleaseLockProxy_SignatureTemplateClass methodSignatureForSelector:selector];
	}
	else
	{
		result = [(id)_object methodSignatureForSelector:selector];
	}
	
	return result;
}


+ (BOOL)instancesRespondToSelector:(SEL)selector
{
	if (selector == @selector(initWithObject:name:) ||
		selector == @selector(initWithRetainedObject:name:) || 
		selector == @selector(rlpAllowRelease) ||
		selector == @selector(rlpObjectDescription))
	{
		return YES;
	}
	else
	{
		return NO;
	}
}


- (BOOL)respondsToSelector:(SEL)selector
{
	return [ReleaseLockProxy instancesRespondToSelector:selector];
}

@end


@implementation ReleaseLockProxy_SignatureTemplateClass

+ (id)initWithObject:(id<NSObject>)object name:(NSString *)name  { return nil; }
+ (id)initWithRetainedObject:(id<NSObject>)object name:(NSString *)name  { return nil; }
+ (void)rlpAllowRelease  { }
+ (NSString *)rlpObjectDescription  { return nil; }

@end
