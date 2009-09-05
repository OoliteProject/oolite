/*

OOTextureLoadDispatcher.h


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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

Copyright (C) 2007-2009 Jens Ayton

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

#import "OOTextureLoadDispatcher.h"
#import "OOAsyncQueue.h"
#import "OOCPUInfo.h"
#import "OOCollectionExtractors.h"
#import "NSThreadOOExtensions.h"
#import "OONSOperation.h"


static OOTextureLoadDispatcher *sSingleton = nil;


@interface OOTextureLoadDispatcher (Internal)

- (void) queueResult:(OOTextureLoader *)loader;

@end


#if !OO_HAVE_NSOPERATION
@interface OOTextureLoadManualDispatcher: OOTextureLoadDispatcher
{
@private
	OOAsyncQueue			*_loadQueue;
	
	BOOL					_haveInited;
}
@end
#endif


@interface OOTextureLoadOperationQueueDispatcher: OOTextureLoadDispatcher
{
	id						_operationQueue;
}

#if !OO_HAVE_NSOPERATION
+ (BOOL) canBeUsed;
#endif

@end


@implementation OOTextureLoadDispatcher

+ (id) sharedTextureLoadDispatcher
{
	if (sSingleton == nil)
	{
#if !OO_HAVE_NSOPERATION
		if ([OOTextureLoadOperationQueueDispatcher canBeUsed])
		{
			sSingleton = [[OOTextureLoadOperationQueueDispatcher alloc] init];
		}
		if (sSingleton == nil)
		{
			sSingleton = [[OOTextureLoadManualDispatcher alloc] init];
		}
#else
		sSingleton = [[OOTextureLoadOperationQueueDispatcher alloc] init];
#endif
		
		if (sSingleton == nil)
		{
			OOLog(@"textureLoader.setUpDispatcher.failed", @"***** FATAL ERROR: could not set up texture load dispatcher!");
			exit(EXIT_FAILURE);
		}
		
		OOLog(@"textureLoader.dispatchMethod", @"Selected texture load dispatcher: %@", [sSingleton class]);
	}
	
	return sSingleton;
}


+ (id) allocWithZone:(NSZone *)zone
{
	if (sSingleton != nil)  return [sSingleton retain];
	return [super allocWithZone:zone];
}


- (id) init
{
	if ((self = [super init]))
	{
		_readyQueue = [[OOAsyncQueue alloc] init];
		
		if (_readyQueue == nil)
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	if (self == sSingleton)  sSingleton = nil;
	[_readyQueue release];
	
	[super dealloc];
}


- (BOOL) dispatchLoader:(OOTextureLoader *)loader
{
	OOLogGenericSubclassResponsibility();
	return NO;
}


/*	In order for a texture loader to be considered loaded, it must be pulled
	off the "ready queue". Since the order of items in the ready queue is not
	necessarily (or generally) the order in which they're used, we keep pulling
	texture loaders off and marking them as loaded until we get the one we're
	looking for. If the loading isn't actually completed, we'll stall on the
	dequeue operation until one of the loader threads pushes a loader.
*/
- (void) waitForLoaderToComplete:(OOTextureLoader *)target
{
	OOTextureLoader				*next = nil;
	
	do
	{
		// Dequeue a loader and mark it as done.
		next = [_readyQueue dequeue];
		[next markAsReady];
		
	}  while (next != target);	// We don't control order, so keep looking until we get the one we care about.
}


- (void) queueResult:(OOTextureLoader *)loader
{
	[_readyQueue enqueue:loader];
}

@end



/******* OOTextureLoadManualDispatcher - manual thread management *******/

enum
{
	kMaxWorkThreads			= 4U
};


@implementation OOTextureLoadManualDispatcher

- (id) init
{
	if (_haveInited)  return self;	// Might reinit if alloc returns existing instance.
	
	if ((self = [super init]))
	{
		// Set up work queues.
		_loadQueue = [[OOAsyncQueue alloc] init];
		
		if (_loadQueue == nil)
		{
			[self release];
			return nil;
		}
		
		// Set up loading threads.
		OOUInteger threadCount, threadNumber = 1;
#if OO_DEBUG
		threadCount = kMaxWorkThreads;
#else
		threadCount = MIN(OOCPUCount(), (unsigned)kMaxWorkThreads);
#endif
		do
		{
			[NSThread detachNewThreadSelector:@selector(queueTask:) toTarget:self withObject:[NSNumber numberWithInt:threadNumber++]];
		}  while (--threadCount > 0);
		
		_haveInited = YES;
	}
	
	return self;
}


- (void) dealloc
{
	[_loadQueue release];
	
	[super dealloc];
}


- (BOOL) dispatchLoader:(OOTextureLoader *)loader
{
	return [_loadQueue enqueue:loader];
}


- (void) queueTask:(NSNumber *)threadNumber
{
	NSAutoreleasePool			*rootPool = nil, *pool = nil;
	OOTextureLoader				*loader = nil;
	
	rootPool = [[NSAutoreleasePool alloc] init];
	[[self retain] autorelease];
	
	/*	Lower thread priority so the loader doesn't go "Hey! This thread's
		just woken up, let's give it exclusive use of the CPU for a second or
		five!", thus stopping graphics from happening, which is somewhat
		against the point.
		
		This leads to priority inversion when the main thread blocks for
		texture load completion. I'm assuming people aren't going to be
		running other CPU-hogging tasks at the same time as Oolite, so it
		won't be a problem.
		-- Ahruman
	*/
	[NSThread setThreadPriority:0.5];
	[NSThread ooSetCurrentThreadName:[NSString stringWithFormat:@"OOTextureLoader loader thread %@", threadNumber]];
	
	for (;;)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		loader = [_loadQueue dequeue];
		NS_DURING
			[loader performLoad];
		NS_HANDLER
		NS_ENDHANDLER
		[self queueResult:loader];
		
		[pool release];
	}
	
	[rootPool release];
}

@end


/******* OOTextureLoadOperationQueueDispatcher - dispatch through NSOperationQueue if available *******/


@implementation OOTextureLoadOperationQueueDispatcher

#if !OO_HAVE_NSOPERATION
+ (BOOL) canBeUsed
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"disable-operation-queue-texture-loader"])  return NO;
	return [OONSInvocationOperationClass() class] != Nil;
}
#endif


- (id) init
{
	if ((self = [super init]))
	{
		_operationQueue = [[OONSOperationQueueClass() alloc] init];
		
		if (_operationQueue == nil)
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	[_operationQueue release];
	
	[super dealloc];
}


- (BOOL) dispatchLoader:(OOTextureLoader *)loader
{
	id operation = [[OONSInvocationOperationClass() alloc] initWithTarget:self selector:@selector(performLoadOperation:) object:loader];
	if (operation == nil)  return NO;
	
	[_operationQueue addOperation:operation];
	[operation release];
	return YES;
}


- (void) performLoadOperation:(OOTextureLoader *) loader
{
	NS_DURING
		[loader performLoad];
	NS_HANDLER
	NS_ENDHANDLER
	[self queueResult:loader];
}

@end
