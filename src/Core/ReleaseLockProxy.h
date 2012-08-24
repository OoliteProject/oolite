/*	ReleaseLockProxy.h
	By Jens Ayton
	This code is hereby placed in the public domain.
	
	Hacky debug utility.
	A ReleaseLockProxy proxies an object, and stops the proxied object from
	being released until -rlpAllowRelease is called. All releases are logged,
	and one that would cause the object to die is stopped. Breakpoints in
	release may be handy.
*/

#import <Foundation/Foundation.h>


@interface ReleaseLockProxy: NSProxy
{
@private
	id<NSObject>		_object;
	NSString			*_name;
	BOOL				_locked;
}

+ (id)proxyWithObject:(id<NSObject>)object name:(NSString *)name;
+ (id)proxyWithRetainedObject:(id<NSObject>)object name:(NSString *)name;	// Doesn't retain the object

- (id)initWithObject:(id<NSObject>)object name:(NSString *)name;
- (id)initWithRetainedObject:(id<NSObject>)object name:(NSString *)name;	// Doesn't retain the object

- (void)rlpAllowRelease;
- (NSString *)rlpObjectDescription;	// name if not nil, otherwise object description.

@end
