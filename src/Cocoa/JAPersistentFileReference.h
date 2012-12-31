/*

JAPersistentFileReference.h

Store file references in a property list format. For file URLs, uses bookmark
data (when available) and aliases to track files even if they're moved or
renamed.


Copyright (C) 2010-2013 Jens Ayton

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
