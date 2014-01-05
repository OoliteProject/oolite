/*

OOOXZManager.m

Responsible for installing and uninstalling OXZs

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOOXZManager.h"
#import "OOPListParsing.h"
#import "ResourceManager.h"

/* The URL for the manifest.plist array. This one is extremely
 * temporary, of course */
static NSString * const kOOOXZDataURL = @"http://compsoc.dur.ac.uk/~cim/oolite/dev/manifests.plist";
/* The filename to store the downloaded manifest.plist array */
static NSString * const kOOOXZManifestCache = @"manifests.plist";
/* The filename to temporarily store the downloaded manifest.plist array */
static NSString * const kOOOXZManifestTmp = @"manifests.plist.new";


static NSString * const kOOOXZErrorLog = @"oxz.manager.error";
static NSString * const kOOOXZDebugLog = @"oxz.manager.debug";


static OOOXZManager *sSingleton = nil;

@interface OOOXZManager (OOPrivate)
- (NSString *) installPath;
- (NSString *) manifestPath;
- (NSString *) manifestDownloadPath;

- (void) setOXZList:(NSArray *)list;
- (void) setCurrentDownload:(NSURLDownload *)download;

/* Delegates for URL downloader */
- (void) downloadDidBegin:(NSURLDownload *)download;
- (void) download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response;
- (void) download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length;
- (void) downloadDidFinish:(NSURLDownload *)download;
- (void) download:(NSURLDownload *)download didFailWithError:(NSError *)error;

@end


@implementation OOOXZManager

+ (OOOXZManager *)sharedManager
{
	// NOTE: assumes single-threaded first access.
	if (sSingleton == nil)  sSingleton = [[self alloc] init];
	return sSingleton;
}


- (id) init
{
	self = [super init];
	if (self != nil)
	{
		_updatingManifests = NO;
		_downloadStatus = OXZ_DOWNLOAD_NONE;
		// if the file has not been downloaded, this will be nil
		[self setOXZList:OOArrayFromFile([self manifestPath])];
		OOLog(kOOOXZDebugLog,@"Initialised with %@",_oxzList);

	}
	return self;
}


- (void)dealloc
{
	if (sSingleton == self)  sSingleton = nil;

	[self setCurrentDownload:nil];
	DESTROY(_oxzList);

	[super dealloc];
}


/* As currently implemented in ResourceManager the lowest-priority
 * root path is supposed to be in the user's home directory
 * (Mac/Linux) or next to the Oolite install (Windows). This is the
 * safest place to write to. */
- (NSString *) installPath
{
	return [[ResourceManager rootPaths] lastObject];
}


- (NSString *) manifestPath
{
	return [[self installPath] stringByAppendingPathComponent:kOOOXZManifestCache];
}


/* Download mechanism could destroy a correct file if it failed
 * half-way and was downloaded on top of the old one. So this loads it
 * off to the side a bit */
- (NSString *) manifestDownloadPath
{
	return [[self installPath] stringByAppendingPathComponent:kOOOXZManifestTmp];
}


- (void) setOXZList:(NSArray *)list
{
	DESTROY(_oxzList);
	if (list != nil)
	{
		_oxzList = [list retain];
	}
}


- (void) setCurrentDownload:(NSURLDownload *)download
{
	if (_currentDownload != nil)
	{
		[_currentDownload cancel]; // releases via delegate
	}
	_currentDownload = [download retain];
}


- (BOOL) updateManifests
{
/* The download really should be asynchronous (while it's not so bad for the list, it would be terrible for an actual OXZ), but if I do it this way the delegates never get called - and NSURLDownload never actually puts the file anywhere - and I have no idea why. I'm guessing either something to do with the NSRunLoop not working properly under GNUstep or something wrong with the way I'm interacting with it. - CIM*/
#ifndef OXZ_ASYNC_DOWNLOAD
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:kOOOXZDataURL]];
	NSURLResponse *response = nil;
	NSError *error = nil;
	NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	// TODO: check for errors!
	[self setOXZList:OOArrayFromData(data,kOOOXZDataURL)];
	[_oxzList writeToFile:[self manifestPath] atomically:YES];
	OOLog(kOOOXZDebugLog,@"Downloaded %@",_oxzList);
	return YES;
#else
	if (_downloadStatus != OXZ_DOWNLOAD_NONE || _updatingManifests)
	{
		return NO;
	}
	NSURLDownload *download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
	if (download)
	{
		[download setDestination:[self manifestDownloadPath] allowOverwrite:YES];

		_updatingManifests = YES;
		_downloadProgress = 0;
		_downloadExpected = 0;
		[self setCurrentDownload:download]; // retains it
		[download release];
		OOLog(kOOOXZDebugLog,@"Manifest update request received, using %@ and downloading to %@",[request URL],[self manifestDownloadPath]);
		return YES;
	}
	else
	{
		OOLog(kOOOXZErrorLog,@"Unable to start downloading manifests file at %@",[request URL]);
		return NO;
	}
#endif
}


- (BOOL) cancelUpdateManifests
{
	if (!_updatingManifests || _downloadStatus == OXZ_DOWNLOAD_NONE)
	{
		return NO;
	}
	OOLog(kOOOXZDebugLog,@"Trying to cancel manifests file update");
	if (_currentDownload != nil)
	{
		[_currentDownload cancel];
	}
	else if (_downloadStatus == OXZ_DOWNLOAD_COMPLETE)
	{
		// then we should clean up the temp file - TODO!
	}
	_updatingManifests = NO;
	_downloadStatus = OXZ_DOWNLOAD_NONE;
	return YES;
}



- (void) downloadDidBegin:(NSURLDownload *)download
{
	_downloadStatus = OXZ_DOWNLOAD_STARTED;
	OOLog(kOOOXZDebugLog,@"Download started");
}


- (void) download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
	_downloadStatus = OXZ_DOWNLOAD_RECEIVING;
	OOLog(kOOOXZDebugLog,@"Download receiving");
	_downloadExpected = [response expectedContentLength];
	_downloadProgress = 0;
}


- (void) download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
	OOLog(kOOOXZDebugLog,@"Downloaded %lu bytes", (unsigned long)length);
	_downloadProgress += length;
}


- (void) downloadDidFinish:(NSURLDownload *)download
{
	_downloadStatus = OXZ_DOWNLOAD_COMPLETE;
	OOLog(kOOOXZDebugLog,@"Download complete");
	DESTROY(_currentDownload);
}


- (void) download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	_downloadStatus = OXZ_DOWNLOAD_ERROR;
	OOLog(kOOOXZErrorLog,@"Error downloading '%@': %@",[[download request] URL],[error localizedDescription]);
	DESTROY(_currentDownload);
}




@end

