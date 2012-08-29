/*

OONullTexture.m


Copyright (C) 2008-2012 Jens Ayton

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

#import "OONullTexture.h"
#import "OOCocoa.h"
#import "OOTextureInternal.h"


static OONullTexture *sSingleton = nil;


@implementation OONullTexture

+ (OONullTexture *) sharedNullTexture
{
	// NOTE: assumes single-threaded access.
	if (sSingleton == nil)
	{
		sSingleton = [[self alloc] init];
	}
	
	return sSingleton;
}


- (void) apply
{
	[OOTexture applyNone];
}


- (NSSize) dimensions
{
	return NSZeroSize;
}


- (BOOL) isMipMapped
{
	return NO;
}


- (void) forceRebind
{
	
}


#ifndef NDEBUG
- (NSString *) name
{
	return @"<null texture>";
}
#endif

@end


@implementation OONullTexture (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +nullTexture above.
	
	NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id)copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id)retain
{
	return self;
}


- (NSUInteger)retainCount
{
	return UINT_MAX;
}


- (void)release
{}


- (id)autorelease
{
	return self;
}

@end
