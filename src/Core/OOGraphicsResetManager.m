/*

OOGraphicsResetManager.m


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

#import "OOGraphicsResetManager.h"
#import "OOTexture.h"
#import "OOOpenGLExtensionManager.h"


static OOGraphicsResetManager *sSingleton = nil;


@implementation OOGraphicsResetManager

- (void) dealloc
{
	if (sSingleton == self)  sSingleton = nil;
	[clients release];
	
	[super dealloc];
}


+ (OOGraphicsResetManager *) sharedManager
{
	if (sSingleton == nil)  sSingleton = [[self alloc] init];
	return sSingleton;
}


- (void) registerClient:(id<OOGraphicsResetClient>)client
{
	if (client != nil)
	{
		if (clients == nil)  clients = [[NSMutableSet alloc] init];
		[clients addObject:[NSValue valueWithPointer:client]];
	}
}


- (void) unregisterClient:(id<OOGraphicsResetClient>)client
{
	[clients removeObject:[NSValue valueWithPointer:client]];
}


- (void) resetGraphicsState
{
	NSEnumerator			*clientEnum = nil;
	id						client = nil;
	
	OOGL(glFinish());
	
	OOLog(@"rendering.reset.start", @"Resetting graphics state.");
	OOLogIndentIf(@"rendering.reset.start");
	
	[[OOOpenGLExtensionManager sharedManager] reset];
	[OOTexture rebindAllTextures];
	
	for (clientEnum = [clients objectEnumerator]; (client = [[clientEnum nextObject] pointerValue]); )
	{
		NS_DURING
			[client resetGraphicsState];
		NS_HANDLER
			OOLog(kOOLogException, @"***** EXCEPTION -- %@ : %@ -- ignored during graphics reset.", [localException name], [localException reason]);
		NS_ENDHANDLER
	}
	
	OOLogOutdentIf(@"rendering.reset.start");
	OOLog(@"rendering.reset.end", @"End of graphics state reset.");
}

@end


@implementation OOGraphicsResetManager (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedManager above.
	
	// NOTE: assumes single-threaded first access.
*/

+ (id) allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id) copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id) retain
{
	return self;
}


- (OOUInteger) retainCount
{
	return UINT_MAX;
}


- (void) release
{}


- (id) autorelease
{
	return self;
}

@end
