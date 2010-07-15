//
//  JAPersistentFileReference.m
//  Oolite
//
//  Created by Jens Ayton on 2010-07-15.
//  Copyright 2010 the Oolite team. All rights reserved.
//

#import "JAPersistentFileReference.h"
#import <CoreServices/CoreServices.h>


#define kURLKey			@"url"
#define kAliasKey		@"alias"
#define kBookmarkKey	@"bookmark"


#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1060
#define BookmarkDataSupported() (YES)
#else
#define BookmarkDataSupported() ([NSURL instancesRespondToSelector:@selector(bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:)])

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
					[result autorelease];
				}
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
