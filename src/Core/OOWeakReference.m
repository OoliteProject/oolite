/*

OOWeakReference.m

Written by Jens Ayton in 2007-2013 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OOWeakReference.h"


@interface OOWeakReferenceTemplates: NSObject

+ (void)weakRefDrop;
+ (id)weakRefUnderlyingObject;
+ (id)nilMethod;

@end


@implementation OOWeakReference

// *** Core functionality.

+ (id)weakRefWithObject:(id<OOWeakReferenceSupport>)object
{
	if (object == nil)  return nil;
	
	OOWeakReference	*result = [OOWeakReference alloc];
	// No init for proxies.
	result->_object = object;
	return [result autorelease];
}


- (void)dealloc
{
	[_object weakRefDied:self];
	
	[super dealloc];
}


- (NSString *)description
{
	if (_object != nil)  return [_object description];
	else  return [NSString stringWithFormat:@"<Dead %@ %p>", [self class], self];
}


- (id)weakRefUnderlyingObject
{
	return _object;
}


- (id)weakRetain
{
	return [self retain];
}


- (void)weakRefDrop
{
	_object = nil;
}


// *** Proxy evilness beyond this point.

- (Class) class
{
	return [_object class];
}


- (BOOL) isProxy
{
	return YES;
}


- (void)forwardInvocation:(NSInvocation *)invocation
{
	// Does the right thing even with nil _object.
	[invocation invokeWithTarget:_object];
}


- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
	NSMethodSignature		*result = nil;
	
	if (__builtin_expect(
		selector != @selector(weakRefDrop) &&
		selector != @selector(weakRefUnderlyingObject), 1))
	{
		// Not a proxy method; get signature from _object if it exists, otherwise generic signature for nil calls.
		if (__builtin_expect(_object != nil, 1))  result = [(id)_object methodSignatureForSelector:selector];
		else  result = [OOWeakReferenceTemplates methodSignatureForSelector:@selector(nilMethod)];
	}
	else
	{
		// One of OOWeakReference's own methods.
		result = [OOWeakReferenceTemplates methodSignatureForSelector:selector];
	}
	
	return result;
}


- (BOOL)respondsToSelector:(SEL)selector
{
	if (__builtin_expect(_object != nil &&
		selector != @selector(weakRefDrop) &&
		selector != @selector(weakRefUnderlyingObject), 1))
	{
		// _object exists and it's not one of our methods, ask _object.
		return [_object respondsToSelector:selector];
	}
	else
	{
		// Selector we responds to, or _object is nil and therefore responds to everything.
		return YES;
	}
}


// New fast forwarding mechanism introduced in Mac OS X 10.5.
// Note that -forwardInvocation: is still called if _object is nil.
- (id)forwardingTargetForSelector:(SEL)sel
{
	return _object;
}

@end


@implementation NSObject (OOWeakReference)

- (id)weakRefUnderlyingObject
{
	return self;
}

@end


@implementation OOWeakRefObject

- (id)weakRetain
{
	if (weakSelf == nil)  weakSelf = [OOWeakReference weakRefWithObject:self];
	return [weakSelf retain];	// Each caller releases this, as -weakRetain must be balanced with -release.
}


- (void)weakRefDied:(OOWeakReference *)weakRef
{
	if (weakRef == weakSelf)  weakSelf = nil;
}


- (void)dealloc
{
	[weakSelf weakRefDrop];	// Very important!
	[super dealloc];
}

@end


@implementation OOWeakReferenceTemplates

// These are never called, but an implementation must exist so that -methodSignatureForSelector: works.
+ (void)weakRefDrop  {}
+ (id)weakRefUnderlyingObject  { return nil; }
+ (id)nilMethod { return nil; }

@end
