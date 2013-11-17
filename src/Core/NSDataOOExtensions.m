/*

NSDataOOExtensions.m

Extensions to NSData.


Copyright (C) 2008-2013 Jens Ayton and contributors

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

#import "OOCocoa.h"
#import "unzip.h"

#define ZIP_BUFFER_SIZE 8192

@implementation NSData (OOExtensions)

+ (instancetype) oo_dataWithOXZFile:(NSString *)path
{
	unsigned i, cl;
	NSArray *components = [path pathComponents];
	cl = [components count];
	for (i = 0 ; i < cl ; i++)
	{
		NSString *component = [components objectAtIndex:i];
		if ([[[component pathExtension] lowercaseString] isEqualToString:@"oxz"])
		{
			break;
		}
	}
	// if i == cl then the path is entirely uncompressed
	if (i == cl)
	{
/* -initWithContentsOfMappedFile fails quietly under OS X if there's no file,
   but GNUstep complains. */
#if OOLITE_MAC_OS_X
		return [[[NSData alloc] initWithContentsOfMappedFile:path] autorelease];
#else
		NSFileManager	*fmgr = [NSFileManager defaultManager];
		BOOL			dir;
	
		if ([fmgr fileExistsAtPath:path isDirectory:&dir])
		{
			if (!dir)
			{
				if ([[fmgr fileAttributesAtPath:path traverseLink:NO] fileSize] == 0)
				{
					OOLog(kOOLogFileNotFound, @"Expected file but found empty file at %@", path);
				}
				else
				{
					return [[[NSData alloc] initWithContentsOfMappedFile:path] autorelease];
				}
			}
			else
			{
				OOLog(kOOLogFileNotFound, @"Expected file but found directory at %@", path);
			}
		}
		return nil;
#endif	
	}
	// otherwise components 0..i are the OXZ path, and i+1..n are the
	// path inside the OXZ
	NSRange range;
	range.location = 0; range.length = i+1;
	NSString *zipFile = [NSString pathWithComponents:[components subarrayWithRange:range]];
	range.location = i+1; range.length = cl-(i+1);
	NSString *containedFile = [NSString pathWithComponents:[components subarrayWithRange:range]];

	unzFile uf = NULL;
	const char* zipname = [zipFile UTF8String];
	if (zipname != NULL)
	{
		uf = unzOpen64(zipname);
	}
	if (uf == NULL)
	{
		OOLog(kOOLogFileNotFound, @"Could not unzip OXZ at %@", zipFile);
		return nil;
	}
	const char* filename = [containedFile UTF8String];
	// unzLocateFile(*, *, 1) = case-sensitive extract
	if (unzLocateFile(uf, filename, 1) != UNZ_OK)
    {
		unzClose(uf);
		/* Much of the time this function is called with the
		 * expectation that the file may not necessarily exist -
		 * e.g. on plist merges, config scans, etc. So don't add log
		 * entries for this failure mode */
//		OOLog(kOOLogFileNotFound, @"Could not find %@ within OXZ at %@", containedFile, zipFile);
		return nil;
	}
	
	int err = UNZ_OK;
	unz_file_info64 file_info = {0};
	err = unzGetCurrentFileInfo64(uf, &file_info, NULL, 0, NULL, 0, NULL, 0);
    if (err != UNZ_OK)
    {
		unzClose(uf);
		OOLog(kOOLogFileNotFound, @"Could not get properties of %@ within OXZ at %@", containedFile, zipFile);
		return nil;
	}

	err = unzOpenCurrentFile(uf);
	if (err != UNZ_OK)
	{
		unzClose(uf);
		OOLog(kOOLogFileNotFound, @"Could not read %@ within OXZ at %@", containedFile, zipFile);
		return nil;
	}
	
	

	NSMutableData *tmp = [NSMutableData dataWithCapacity:file_info.uncompressed_size];
	void *buf = (void*)malloc(ZIP_BUFFER_SIZE);
	do
	{
		err = unzReadCurrentFile(uf, buf, ZIP_BUFFER_SIZE);
		if (err < 0)
		{
			OOLog(kOOLogFileNotFound, @"Could not read %@ within OXZ at %@ (err %d)", containedFile, zipFile, err);
			break;
		}
		if (err == 0)
		{
			break;
		}
		[tmp appendBytes:buf length:err];
	}
	while (err > 0);
	free(buf);

	err = unzCloseCurrentFile(uf);
	if (err != UNZ_OK)
	{
		unzClose(uf);
		OOLog(kOOLogFileNotFound, @"Could not close %@ within OXZ at %@", containedFile, zipFile);
		return nil;
	}
	
	unzClose(uf);
	return [[tmp retain] autorelease];

}

@end
