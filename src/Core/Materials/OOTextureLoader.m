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

*/

#import "OOTextureLoader.h"
#import "OOPNGTextureLoader.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"
#import "Universe.h"
#import "OOTextureScaling.h"
#import "OOCPUInfo.h"


typedef struct
{
	OOTextureLoader			*head,
							*tail;
} LoaderQueue;


static NSConditionLock		*sQueueLock = nil;
OOTextureLoader				*sQueueHead = nil, *sQueueTail = nil;
static GLint				sGLMaxSize = 0;
static uint32_t				sUserMaxSize;
static BOOL					sReducedDetail;
static BOOL					sHaveNPOTTextures = NO;	// TODO: support "true" non-power-of-two textures.


enum
{
	kConditionNoData = 1,
	kConditionQueuedData
};


@interface OOTextureLoader (OOPrivate)

// Manipulate queue (call without lock acquired)
- (void)queue;
- (void)unqueue;

@end

@interface OOTextureLoader (OOTextureLoadingThread)

+ (void)queueTask;
- (void)performLoad;
- (void)applySettings;

@end


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
		OOLog(@"textureLoader.detachThreads", @"Could not start texture-loader threads.");
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
	
	if (result != nil)  [result queue];
	
	return [result autorelease];
}


- (id)initWithPath:(NSString *)inPath options:(uint32_t)options
{
	self = [super init];
	if (self == nil)  return nil;
	
	path = [inPath copy];
	completionLock = [[NSLock alloc] init];
	
	if (EXPECT_NOT(path == nil || completionLock == nil))
	{
		[self release];
		return nil;
	}
	
	[completionLock lock];	// Will be unlocked when loading is done.
	
	generateMipMaps = (options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap;
	avoidShrinking = (options & kOOTextureNoShrink) != 0;
	
	return self;
}


- (void)dealloc
{
	if (EXPECT_NOT(next != nil || prev != nil))  [self unqueue];
	[path release];
	[completionLock release];
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
	
	return [NSString stringWithFormat:@"<%@ %p>{%@ -- ready:%@}", [self class], self, path, state];
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


@implementation OOTextureLoader (OOPrivate)

- (void)queue
{
	if (EXPECT_NOT(prev != nil || next != nil))
	{
		// Already queued.
		return;
	}
	
	[sQueueLock lock];
	
	[self retain];		// Will be released in +queueTask.
	prev = sQueueTail;
	// Already established that next is nil above.
	
	if (sQueueTail != nil)  sQueueTail->next = self;
	sQueueTail = self;
	
	if (sQueueHead == nil)  sQueueHead = self;
	
	[sQueueLock unlockWithCondition:kConditionQueuedData];
}


- (void)unqueue
{
	if (EXPECT_NOT(prev == nil && next == nil))
	{
		// Not queued.
		return;
	}
	
	[sQueueLock lock];
	
	if (next != nil)  next->prev = prev;
	if (prev != nil)  prev->next = next;
	
	if (sQueueHead == self)  sQueueHead = next;
	if (sQueueTail == self)  sQueueTail = prev;
	
	[sQueueLock unlockWithCondition:(sQueueHead != nil) ? kConditionQueuedData : kConditionNoData];
}

@end


/*** Methods performed on the loader thread. ***/

@implementation OOTextureLoader (OOTextureLoadingThread)

+ (void)queueTask
{
	NSAutoreleasePool			*pool = nil;
	OOTextureLoader				*loader = nil;
	
	/*	Lower thread priority so the loader doesn't go "Hey! This thread's
		just woken up, let's give it exclusive use of the CPU for a second or
		five!", thus stopping graphics from happening, which is somewhat
		against the point.
		
		This leads to priority inversion when the main thread blocks for
		texture load completion. I'm assuming people aren't going to be
		running other CPU-hogging time at the same time as Oolite, so it won't
		be a problem.
		-- Ahruman
	*/
	[NSThread setThreadPriority:0.5];
	
	for (;;)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		[sQueueLock lockWhenCondition:kConditionQueuedData];
		loader = sQueueHead;
		if (EXPECT(loader != nil))
		{
			// TODO: search for first item with priority bit set.
			sQueueHead = loader->next;
			if (sQueueTail == loader)  sQueueTail = nil;
			[sQueueLock unlockWithCondition:(sQueueHead != nil) ? kConditionQueuedData : kConditionNoData];
			
			OOLog(@"textureLoader.asyncLoad", @"Loading texture %@", [loader->path lastPathComponent]);
			[loader performLoad];
			OOLog(@"textureLoader.asyncLoad.done", @"Loading complete.");
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
	next = prev = nil;
	
	NS_DURING
		[self loadTexture];
		if (data != NULL)  [self applySettings];
	NS_HANDLER
		OOLog(kOOLogException, @"***** Exception loading texture %@: %@ (%@).", path, [localException name], [localException reason]);
		
		// Be sure to signal load failure
		if (data != NULL)
		{
			free(data);
			data = NULL;
		}
	NS_ENDHANDLER
	
	ready = YES;
	[completionLock unlock];	// Signal readyness
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
