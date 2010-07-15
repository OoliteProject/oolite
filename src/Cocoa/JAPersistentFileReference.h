//
//  JAPersistentFileReference.h
//  Oolite
//
//  Created by Jens Ayton on 2010-07-15.
//  Copyright 2010 the Oolite team. All rights reserved.
//

#import <Foundation/Foundation.h>


enum
{
	kJAPersistentFileReferenceWithoutUI				= 0x00000001UL,	// Avoid user interaction.
	kJAPersistentFileReferenceWithoutMounting		= 0x00000002UL,	// Avoid mounting volumes.
	kJAPersistentFileReferenceReturnReferenceURL	= 0x00000004UL	// Return a file reference URL if possible.
};

typedef uint32_t JAPersistentFileReferenceResolveFlags;


NSDictionary *JAPersistentFileReferenceFromURL(NSURL *url);
NSURL *JAURLFromPersistentFileReference(NSDictionary *fileRef, JAPersistentFileReferenceResolveFlags flags, BOOL *isStale);

NSDictionary *JAPersistentFileReferenceFromPath(NSString *path);
NSString *JAPathFromPersistentFileReference(NSDictionary *fileRef, JAPersistentFileReferenceResolveFlags flags, BOOL *isStale);
