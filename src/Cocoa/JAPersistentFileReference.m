/*

JAPersistentFileReference.m


Copyright (C) 2010-2012 Jens Ayton

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

#import "JAPersistentFileReference.h"
#import <CoreServices/CoreServices.h>


#define kURLKey			@"url"
#define kAliasKey		@"alias"
#define kBookmarkKey	@"bookmark"


#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1060
#define BookmarkDataSupported() (YES)
#else
#if __ppc__ || __ppc64__
// Bookmark data is only available in Snow Leopard and later, which excludes PPC systems.
#define BookmarkDataSupported() (NO)
#else
#define BookmarkDataSupported() ([NSURL instancesRespondToSelector:@selector(bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:)])
#endif


#if MAC_OS_X_VERSION_10_6 > MAC_OS_X_VERSION_MAX_ALLOWED

@interface NSURL (SnowLeopardMethods)

- (NSData *)bookmarkDataWithOptions:(unsigned long)options includingResourceValuesForKeys:(NSArray *)keys relativeToURL:(NSURL *)relativeURL error:(NSError **)error;
- (NSURL *)fileReferenceURL;
- (NSURL *)filePathURL;
- (BOOL)isFileReferenceURL;
+ (id)URLByResolvingBookmarkData:(NSData *)bookmarkData options:(unsigned long)options relativeToURL:(NSURL *)relativeURL bookmarkDataIsStale:(BOOL *)isStale error:(NSError **)error;

@end


enum
{
    NSURLBookmarkResolutionWithoutUI = ( 1UL << 8 ),
    NSURLBookmarkResolutionWithoutMounting = ( 1UL << 9 ),
};

#endif
#endif


NSDictionary *JAPersistentFileReferenceFromURL(NSURL *url)
{
	if (url == nil)  return nil;
	
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:3];
	[result setObject:[url absoluteString] forKey:kURLKey];
	
	if ([url isFileURL])
	{
		FSRef fsRef;
		if (CFURLGetFSRef((CFURLRef)[url absoluteURL], &fsRef))
		{
			AliasHandle alias = NULL;
			if (FSNewAlias(NULL, &fsRef, &alias) == noErr)
			{
				NSData *aliasData = [NSData dataWithBytes:*alias length:GetAliasSize(alias)];
				if (aliasData != NULL)
				{
					[result setObject:aliasData forKey:kAliasKey];
				}
				DisposeHandle((Handle)alias);
			}
		}
	}
	
	if (BookmarkDataSupported())
	{
		NSURL *refURL = [url fileReferenceURL];
		if (refURL != nil)
		{
			NSData *bookmarkData = [refURL bookmarkDataWithOptions:0
									includingResourceValuesForKeys:nil
													 relativeToURL:nil
															 error:NULL];
			if (bookmarkData != nil)
			{
				[result setObject:bookmarkData forKey:kBookmarkKey];
			}
		}
	}
	
	return result;
}


static inline unsigned long BookmarkOptionsFromFlags(JAPersistentFileReferenceResolveFlags flags)
{
	unsigned long result = 0;
	if (flags & kJAPersistentFileReferenceWithoutUI)  result |= NSURLBookmarkResolutionWithoutUI;
	if (flags & NSURLBookmarkResolutionWithoutMounting)  result |= NSURLBookmarkResolutionWithoutMounting;
	return result;
}


static inline unsigned long AliasMountFlagsFromFlags(JAPersistentFileReferenceResolveFlags flags)
{
	unsigned long result = 0;
	if (flags & kJAPersistentFileReferenceWithoutUI)  result |= kResolveAliasFileNoUI;
	return result;
}


NSURL *JAURLFromPersistentFileReference(NSDictionary *fileRef, JAPersistentFileReferenceResolveFlags flags, BOOL *isStale)
{
	NSURL *result = nil;
	BOOL stale = NO, staleIfFile = NO;
	
	// Try bookmark.
	if (BookmarkDataSupported())
	{
		NSData *bookmarkData = [fileRef objectForKey:kBookmarkKey];
		if ([bookmarkData isKindOfClass:[NSData class]])
		{
			result = [NSURL URLByResolvingBookmarkData:bookmarkData
											   options:BookmarkOptionsFromFlags(flags)
										 relativeToURL:nil
								   bookmarkDataIsStale:&stale
												 error:NULL];
		}
		else  staleIfFile = YES;
	}
	
	// Try alias.
	if (result == nil)
	{
		NSData *aliasData = [fileRef objectForKey:kAliasKey];
		if ([aliasData isKindOfClass:[NSData class]])
		{
			size_t size = [aliasData length];
			AliasHandle alias = (AliasHandle)NewHandle(size);
			if (alias != NULL)
			{
				memcpy(*alias, [aliasData bytes], size);
				FSRef fsRef;
				
				Boolean carbonStale;
				if (FSResolveAliasWithMountFlags(NULL, alias, &fsRef, &carbonStale, AliasMountFlagsFromFlags(flags)) == noErr)
				{
					stale = carbonStale;
					result = (NSURL *)CFURLCreateFromFSRef(kCFAllocatorDefault, &fsRef);
#if 1050 <= MAC_OS_X_VERSION_MAX_ALLOWED
					CFMakeCollectable((CFURLRef)result);
#endif
					[result autorelease];
				}
				DisposeHandle((Handle)alias);
			}
		}
		else  staleIfFile = YES;
	}
	
	// Try URL.
	if (result == nil)
	{
		NSString *urlString = [fileRef objectForKey:kURLKey];
		if ([urlString isKindOfClass:[NSString class]])
		{
			result = [NSURL URLWithString:urlString relativeToURL:nil];
			if ([result isFileURL] && ![[NSFileManager defaultManager] fileExistsAtPath:[result path]])
			{
				result = nil;
			}
		}
	}
	
	// If we got nothing, it's definitely stale.
	if (result == nil)
	{
		stale = YES;
	}
	else
	{
		if ([result isFileURL] && staleIfFile)  stale = YES;
		
		// Convert to/from file reference URL as appropriate.
		if (BookmarkDataSupported())
		{
			if (flags & kJAPersistentFileReferenceReturnReferenceURL)
			{
				if (![result isFileReferenceURL] && [result isFileURL])
				{
					NSURL *refURL = [result fileReferenceURL];
					if (refURL != nil)  result = refURL;
				}
			}
			else
			{
				if ([result isFileReferenceURL])
				{
					NSURL *pathURL = [result filePathURL];
					if (pathURL != nil)  result = pathURL;
				}
			}
		}
	}

	
	if (isStale != NULL)  *isStale = stale;
	return result;
}


NSDictionary *JAPersistentFileReferenceFromPath(NSString *path)
{
	return JAPersistentFileReferenceFromURL([NSURL fileURLWithPath:path]);
}


NSString *JAPathFromPersistentFileReference(NSDictionary *fileRef, JAPersistentFileReferenceResolveFlags flags, BOOL *isStale)
{
	NSURL *url = JAURLFromPersistentFileReference(fileRef, flags & ~kJAPersistentFileReferenceReturnReferenceURL, isStale);
	if ([url isFileURL])  return [url path];
	return nil;
}
