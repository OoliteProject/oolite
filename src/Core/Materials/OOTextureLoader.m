/*

OOTextureLoader.m

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

#import "OOTextureLoader.h"
#import "OOPNGTextureLoader.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"
#import "Universe.h"
#import "OOTextureScaling.h"
#import "OOCPUInfo.h"


static NSConditionLock		*sQueueLock = nil;
OOTextureLoader				*sQueueHead = nil, *sQueueTail = nil;
static GLint				sGLMaxSize = 0;
static uint32_t				sUserMaxSize;
static BOOL					sReducedDetail;
static BOOL					sHaveNPOTTextures = NO;	// TODO: support "true" non-power-of-two textures.


#if !USE_COMPLETION_LOCK
static NSString * const		kOOAsyncWaitForCompletionRunLoopMode = @"org.aegidian.oolite.asyncWaitForCompletion";
#endif


enum
{
	kConditionNoData = 1,
	kConditionQueuedData
};


@interface OOTextureLoader (OOTextureLoadingThread)

+ (void)queueTask;
- (void)performLoad;
- (void)applySettings;

@end


#if !USE_COMPLETION_LOCK
@interface OOTextureLoader (OOCompletionNotification)

- (void)noteCompletion;
- (void)waitForCompletion;

@end
#endif


@implementation OOTextureLoader

+ (id)loaderWithPath:(NSString *)path options:(uint32_t)options
{
	NSString				*extension = nil;
	id						result = nil;
	
	if (path == nil) return nil;
	
	// Set up loading threads (up to four) and queue lock
	if (EXPECT_NOT(sQueueLock == nil))
	{
		sQueueLock = [[NSConditionLock alloc] initWithCondition:kConditionNoData];
		if (sQueueLock != nil)
		{
			int threadCount = MIN(OOCPUCount() / 2, 4);
			do
			{
				[NSThread detachNewThreadSelector:@selector(queueTask) toTarget:self withObject:nil];
			} while (--threadCount > 0);
		}
	}
	if (EXPECT_NOT(sQueueLock == nil))
	{
		OOLog(@"textureLoader.detachThreads.failed", @"Could not start texture-loader threads.");
		return nil;
	}
	
	// Load two maximum sizes - graphics hardware limit and user-specified limit.
	if (sGLMaxSize == 0)
	{
		glGetIntegerv(GL_MAX_TEXTURE_SIZE, &sGLMaxSize);
		if (sGLMaxSize < 64)  sGLMaxSize = 64;
		
		// Why 0x80000000? Because it's the biggest number OORoundUpToPowerOf2() can handle.
		sUserMaxSize = [[NSUserDefaults standardUserDefaults] unsignedIntForKey:@"max-texture-size" defaultValue:0x80000000];
		sUserMaxSize = OORoundUpToPowerOf2(sUserMaxSize);
		if (sUserMaxSize < 64)  sUserMaxSize = 64;
	}
	
	// Get reduced detail setting (every time, in case it changes; we don't want to call through to Universe on the loading thread in case the implementation becomes non-trivial
	sReducedDetail = [UNIVERSE reducedDetail];
	
	// Get a suitable loader.
	extension = [[path pathExtension] lowercaseString];
	if ([extension isEqualToString:@"png"])
	{
		result = [[OOPNGTextureLoader alloc] initWithPath:path options:options];
	}
	else
	{
		OOLog(@"textureLoader.unknownType", @"Can't use %@ as a texture - extension \"%@\" does not identify a known type.", path, extension);
	}
	
	if (result != nil)
	{
		// Add to queue
		[sQueueLock lock];
		
		[result retain];		// Will be released in +queueTask.
		if (sQueueTail != nil)  sQueueTail->queueNext = result;
		sQueueTail = result;
		if (sQueueHead == nil)  sQueueHead = result;
		
		[sQueueLock unlockWithCondition:kConditionQueuedData];
	}
	
	return [result autorelease];
}


- (id)initWithPath:(NSString *)inPath options:(uint32_t)options
{
	self = [super init];
	if (self == nil)  return nil;
	
	path = [inPath copy];
	if (EXPECT_NOT(path == nil))
	{
		[self release];
		return nil;
	}
	
#if USE_COMPLETION_LOCK
	completionLock = [[NSLock alloc] init];
	
	if (EXPECT_NOT(completionLock == nil))
	{
		[self release];
		return nil;
	}
	
	[completionLock lock];	// Will be unlocked when loading is done.
#endif
	
	generateMipMaps = (options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap;
	avoidShrinking = (options & kOOTextureNoShrink) != 0;
	
	return self;
}


- (void)dealloc
{
	// If we're still in the queue, we've been overreleased and the game will crash.
	assert(queueNext == nil);
	
	[path release];
#if USE_COMPLETION_LOCK
	[completionLock release];
#endif
	if (data != NULL)  free(data);
	
	[super dealloc];
}


- (NSString *)description
{
	NSString			*state = nil;
	
	if (ready)
	{
		if (data != NULL)  state = @"ready";
		else  state = @"failed";
	}
	else  state = @"loading";
	
	return [NSString stringWithFormat:@"<%@ %p>{%@ -- %@}", [self class], self, path, state];
}


- (BOOL)isReady
{
	return ready;
}


- (BOOL)getResult:(void **)outData
		   format:(OOTextureDataFormat *)outFormat
			width:(uint32_t *)outWidth
		   height:(uint32_t *)outHeight
{
#if USE_COMPLETION_LOCK
	if (completionLock != NULL)
	{
		/*	If the lock exists, we must block on it until it is unlocked by
			the loader thread, _even if the ready flag is set_, because of
			potential write reordering issues. A read barrier here and a write
			barrier at the end of loading (before setting the ready flag)
			would probably be OK, too, if we had cross-platform barriers.
			
			If you don't understand the previous paragraph, you don't know
			enough about threading to optimize out this unlock. If you do, and
			you're sure it can be bypassed safely, you may be right. :-)
			-- Ahruman
			
			Additional note: since it's not meaningful to call getResult...
			more than once, the lock will probably be there every time.
		*/
		
		priority = YES;
		BOOL block = !ready;
		if (block)  OOLog(@"textureLoader.block", @"Blocking for completion of loading of %@", [path lastPathComponent]);
		[completionLock lock];
		[completionLock unlock];
		[completionLock release];
		completionLock = nil;
		if (block)  OOLog(@"textureLoader.block.done", @"Finished waiting around.");
	}
#else
	if (!ready)  [self waitForCompletion];
#endif
	
	if (data != NULL)
	{
		if (outData != NULL)  *outData = data;
		if (outFormat != NULL)  *outFormat = format;
		if (outWidth != NULL)  *outWidth = width;
		if (outHeight != NULL)  *outHeight = height;
		
		data = NULL;
		return YES;
	}
	else
	{
		if (outData != NULL)  *outData = NULL;
		if (outFormat != NULL)  *outFormat = kOOTextureDataInvalid;
		if (outWidth != NULL)  *outWidth = 0;
		if (outHeight != NULL)  *outHeight = 0;
		
		return NO;
	}
}


- (void)loadTexture
{
	OOLog(kOOLogSubclassResponsibility, @"%s is a subclass responsibility!", __PRETTY_FUNCTION__);
}


@end


/*** Methods performed on the loader thread. ***/

@implementation OOTextureLoader (OOTextureLoadingThread)

+ (void)queueTask
{
	NSAutoreleasePool			*pool = nil;
	OOTextureLoader				*loader = nil, *curr = nil;
	
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
	
	for (;;)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		[sQueueLock lockWhenCondition:kConditionQueuedData];
		if (EXPECT(sQueueHead != nil))
		{
			loader = nil;
			if (!sQueueHead->priority)
			{
				// Search queue for a loader with the priority flag.
				for (curr = sQueueHead; curr->queueNext != nil; curr = curr->queueNext)
				{
					if (curr->queueNext->priority)
					{
						loader = curr->queueNext;
						curr->queueNext = loader->queueNext;
						if (loader == sQueueTail)  sQueueTail = curr->queueNext;
						break;
					}
				}
			}
			if (loader == nil)
			{
				// Grab first object
				loader = sQueueHead;
				sQueueHead = loader->queueNext;
				if (sQueueTail == loader)  sQueueTail = nil;
			}
			loader->queueNext = nil;
			
			[sQueueLock unlockWithCondition:(sQueueHead != nil) ? kConditionQueuedData : kConditionNoData];
			
			[loader performLoad];
			[loader release];	// Was retained in -queue.
		}
		else
		{
			OOLog(@"textureLoader.queueTask.inconsistency", @"***** Texture loader queue state was data-available when queue was empty!");
			[sQueueLock unlockWithCondition:kConditionNoData];
		}
		
		[pool release];
	}
}


- (void)performLoad
{
	NS_DURING
		OOLog(@"textureLoader.asyncLoad", @"Loading texture %@", [path lastPathComponent]);
		
		[self loadTexture];
		if (data != NULL)  [self applySettings];
		
		OOLog(@"textureLoader.asyncLoad.done", @"Loading complete.");
	NS_HANDLER
		OOLog(@"textureLoader.asyncLoad.exception", @"***** Exception loading texture %@: %@ (%@).", path, [localException name], [localException reason]);
		
		// Be sure to signal load failure
		if (data != NULL)
		{
			free(data);
			data = NULL;
		}
	NS_ENDHANDLER
	
#if USE_COMPLETION_LOCK
	ready = YES;
	[completionLock unlock];	// Signal readyness
#else
	static NSArray *modes = nil;
	if (EXPECT_NOT(modes == nil))  modes = [[NSArray alloc] initWithObjects:NSDefaultRunLoopMode, kOOAsyncWaitForCompletionRunLoopMode, nil];
	
	[self performSelectorOnMainThread:@selector(noteCompletion) withObject:nil waitUntilDone:NO modes:modes];
#endif
}


- (void)applySettings
{
	uint32_t			desiredWidth, desiredHeight;
	BOOL				rescale;
	void				*newData = NULL;
	size_t				newSize;
	uint8_t				planes;
	
	planes = OOTexturePlanesForFormat(format);
	
	if (rowBytes == 0)  rowBytes = width * planes;
	
	// Work out appropriate final size for textures.
	if (!sHaveNPOTTextures)
	{
		desiredWidth = OORoundUpToPowerOf2((2 * width) / 3);
		desiredHeight = OORoundUpToPowerOf2((2 * height) / 3);
	}
	else
	{
		desiredWidth = width;
		desiredHeight = height;
	}
	
	desiredWidth = MIN(desiredWidth, sGLMaxSize);
	desiredHeight = MIN(desiredHeight, sGLMaxSize);
	
	if (!avoidShrinking)
	{
		desiredWidth = MIN(desiredWidth, sUserMaxSize);
		desiredHeight = MIN(desiredHeight, sUserMaxSize);
		
		if (sReducedDetail)
		{
			if (512 < desiredWidth)  desiredWidth /= 2;
			if (512 < desiredHeight)  desiredHeight /= 2;
		}
	}
	
	// Rescale if needed.
	rescale = (width != desiredWidth || height != desiredHeight);
	if (rescale)
	{
		data = OOScalePixMap(data, width, height, planes, rowBytes, desiredWidth, desiredHeight, generateMipMaps);
		if (EXPECT_NOT(data == NULL))  return;
		
		width = desiredWidth;
		height = desiredHeight;
	}
	
	// Generate mip maps if needed.
	if (generateMipMaps && !rescale)
	{
		// Make space...
		newSize = desiredWidth * planes * desiredHeight;
		newSize = (newSize * 4) / 3;
		newData = realloc(data, newSize);
		if (newData != nil)  data = newData;
		else  generateMipMaps = NO;
	}
	if (generateMipMaps)
	{
		OOGenerateMipMaps(data, width, height, planes);
	}
	
	// All done.
}

@end


#if !USE_COMPLETION_LOCK
@implementation OOTextureLoader (OOCompletionNotification)

- (void)noteCompletion
{
	ready = YES;
	OOLog(@"textureLoader.noteCompletion", @"Loading completed for texture %@.", [path lastPathComponent]);
}


- (void)waitForCompletion
{
	NSRunLoop				*runLoop = nil;
	
	runLoop = [NSRunLoop currentRunLoop];
	assert(runLoop != nil);
	
	OOLog(@"textureLoader.waitForCompletion", @"Waiting for completion notification for texture %@.", [path lastPathComponent]);
	
	while (!ready)  [runLoop acceptInputForMode:kOOAsyncWaitForCompletionRunLoopMode beforeDate:[NSDate distantFuture]];
}

@end
#endif
