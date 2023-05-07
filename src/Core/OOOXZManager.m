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
#import "OOStringParsing.h"
#import "ResourceManager.h"
#import "OOCacheManager.h"
#import "Universe.h"
#import "GuiDisplayGen.h"
#import "PlayerEntity.h"
#import "PlayerEntitySound.h"
#import "OOCollectionExtractors.h"
#import "NSFileManagerOOExtensions.h"
#import "NSDataOOExtensions.h"
#import "OOColor.h"
#import "OOStringExpander.h"
#import "MyOpenGLView.h"

#import "unzip.h"

#import "OOManifestProperties.h"

/* The URL for the manifest.plist array. */
/* switching (temporarily maybe) to oolite.space - Nikos 20230507 */
/*static NSString * const kOOOXZDataURL = @"http://addons.oolite.org/api/1.0/overview";*/
static NSString * const kOOOXZDataURL = @"http://addons.oolite.space/api/1.0/overview";
/* The config parameter to use a non-default URL at runtime */
static NSString * const kOOOXZDataConfig = @"oxz-index-url";
/* The filename to store the downloaded manifest.plist array */
static NSString * const kOOOXZManifestCache = @"Oolite-manifests.plist";
/* The filename to temporarily store the downloaded OXZ. Has an OXZ extension since we might want to read its manifest.plist out of it;  */
static NSString * const kOOOXZTmpPath = @"Oolite-download.oxz";
/* The filename to temporarily store the downloaded plists. */
static NSString * const kOOOXZTmpPlistPath = @"Oolite-download.plist";

/* Log file record types */
static NSString * const kOOOXZErrorLog = @"oxz.manager.error";
static NSString * const kOOOXZDebugLog = @"oxz.manager.debug";


/* Filter components */
static NSString * const kOOOXZFilterAll = @"*";
static NSString * const kOOOXZFilterUpdates = @"u";
static NSString * const kOOOXZFilterInstallable = @"i";
static NSString * const kOOOXZFilterKeyword = @"k:";
static NSString * const kOOOXZFilterAuthor = @"a:";
static NSString * const kOOOXZFilterDays = @"d:";
static NSString * const kOOOXZFilterTag = @"t:";


typedef enum {
	OXZ_INSTALLABLE_OKAY,
	OXZ_INSTALLABLE_UPDATE,
	OXZ_INSTALLABLE_DEPENDENCIES,
	OXZ_INSTALLABLE_CONFLICTS,
	// for things to work, _ALREADY must be the first UNINSTALLABLE state
	// and all the INSTALLABLE ones must be before all the UNINSTALLABLE ones
	OXZ_UNINSTALLABLE_ALREADY,
	OXZ_UNINSTALLABLE_NOREMOTE,
	OXZ_UNINSTALLABLE_VERSION,
	OXZ_UNINSTALLABLE_MANUAL
} OXZInstallableState;


enum {
	OXZ_GUI_ROW_LISTHEAD	= 0,
	OXZ_GUI_ROW_FIRSTRUN	= 1,
	OXZ_GUI_ROW_PROGRESS	= 1,
	OXZ_GUI_ROW_FILTERHELP	= 1,
	OXZ_GUI_ROW_LISTPREV	= 1,
	OXZ_GUI_ROW_LISTSTART	= 2,
	OXZ_GUI_NUM_LISTROWS	= 10,
	OXZ_GUI_ROW_LISTNEXT	= 12,
	OXZ_GUI_ROW_LISTSTATUS	= 14,
	OXZ_GUI_ROW_LISTDESC	= 16,
	OXZ_GUI_ROW_LISTINFO1	= 19,
	OXZ_GUI_ROW_LISTINFO2	= 20,
	OXZ_GUI_ROW_LISTFILTER	= 21,
	OXZ_GUI_ROW_INSTALL		= 22,
	OXZ_GUI_ROW_INSTALLED	= 23,
	OXZ_GUI_ROW_UPDATE_ALL	= 24,
	OXZ_GUI_ROW_REMOVE		= 25,
	OXZ_GUI_ROW_PROCEED		= 25,
	OXZ_GUI_ROW_UPDATE		= 26,
	OXZ_GUI_ROW_CANCEL		= 26,
	OXZ_GUI_ROW_FILTERCURRENT = 26,
	OXZ_GUI_ROW_INPUT		= 27,
	OXZ_GUI_ROW_EXIT		= 27
};


NSComparisonResult oxzSort(id m1, id m2, void *context);

static OOOXZManager *sSingleton = nil;

// protocol was only formalised in 10.7
#if OOLITE_MAC_OS_X_10_7 
@interface OOOXZManager (OOPrivate) <NSURLConnectionDataDelegate> 
#else
@interface OOOXZManager (NSURLConnectionDataDelegate) 
#endif

- (NSString *) manifestPath;
- (NSString *) downloadPath;
- (NSString *) extractionBasePathForIdentifier:(NSString *)identifier andVersion:(NSString *)version;
- (NSString *) dataURL;
- (NSString *) humanSize:(NSUInteger)bytes;

- (BOOL) ensureInstallPath;

- (BOOL) beginDownload:(NSMutableURLRequest *)request;
- (BOOL) processDownloadedManifests;
- (BOOL) processDownloadedOXZ;

- (OXZInstallableState) installableState:(NSDictionary *)manifest;
- (OOColor *) colorForManifest:(NSDictionary *)manifest;
- (NSString *) installStatusForManifest:(NSDictionary *)manifest;

- (BOOL) validateFilter:(NSString *)input;

- (void) setOXZList:(NSArray *)list;
- (void) setFilteredList:(NSArray *)list;
- (NSArray *) applyCurrentFilter:(NSArray *)list;

- (void) setCurrentDownload:(NSURLConnection *)download withLabel:(NSString *)label;
- (void) setProgressStatus:(NSString *)newStatus;

- (BOOL) installOXZ:(NSUInteger)item;
- (BOOL) updateAllOXZ;
- (BOOL) removeOXZ:(NSUInteger)item;
- (NSArray *) installOptions;
- (NSArray *) removeOptions;

- (NSString *) extractOXZ:(NSUInteger)item;

/* Delegates for URL downloader */
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;

@end

@interface OOOXZManager (OOFilterRules)
- (BOOL) applyFilterByNoFilter:(NSDictionary *)manifest;
- (BOOL) applyFilterByUpdateRequired:(NSDictionary *)manifest;
- (BOOL) applyFilterByInstallable:(NSDictionary *)manifest;
- (BOOL) applyFilterByKeyword:(NSDictionary *)manifest keyword:(NSString *)keyword;
- (BOOL) applyFilterByAuthor:(NSDictionary *)manifest author:(NSString *)author;
- (BOOL) applyFilterByDays:(NSDictionary *)manifest days:(NSString *)days;
- (BOOL) applyFilterByTag:(NSDictionary *)manifest tag:(NSString *)tag;

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
		_downloadStatus = OXZ_DOWNLOAD_NONE;
		// if the file has not been downloaded, this will be nil
		[self setOXZList:OOArrayFromFile([self manifestPath])];
		OOLog(kOOOXZDebugLog,@"Initialised with %@",_oxzList);
		_interfaceState = OXZ_STATE_NODATA;
		_currentFilter = @"*";
		
		_interfaceShowingOXZDetail = NO;
		_changesMade = NO;
		_downloadAllDependencies = NO;
		_dependencyStack = [[NSMutableSet alloc] initWithCapacity:8];
		[self setProgressStatus:@""];
	}
	return self;
}


- (void)dealloc
{
	if (sSingleton == self)  sSingleton = nil;

	[self setCurrentDownload:nil withLabel:nil];
	DESTROY(_oxzList);
	DESTROY(_managedList);
	DESTROY(_filteredList);

	[super dealloc];
}


/* The install path for OXZs downloaded by
 * Oolite. Library/ApplicationSupport seems to be the most appropriate
 * location. */
- (NSString *) installPath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES);
	NSString *appPath = [paths objectAtIndex:0];
	if (appPath != nil)
	{
		appPath = [appPath stringByAppendingPathComponent:@"Oolite"];
#if OOLITE_MAC_OS_X
		appPath = [appPath stringByAppendingPathComponent:@"Managed AddOns"];
#else
		/* GNUStep uses "ApplicationSupport" rather than "Application
		 * Support" so match convention by not putting a space in the
		 * path either */
		appPath = [appPath stringByAppendingPathComponent:@"ManagedAddOns"];
#endif
		return appPath;
	}
	return nil;
}


- (NSString *) extractionBasePathForIdentifier:(NSString *)identifier andVersion:(NSString *)version
{
	NSString *basePath = [[ResourceManager userRootPaths] lastObject];
	NSString *rawMainDir = [NSString stringWithFormat:@"%@-%@.off",identifier,version];
	
	NSCharacterSet *blacklist = [NSCharacterSet characterSetWithCharactersInString:@"'#%^&{}[]/~|\\?<,:\" "];
	return [[[basePath stringByAppendingPathComponent:[[rawMainDir componentsSeparatedByCharactersInSet:blacklist] componentsJoinedByString:@""]] retain] autorelease];
}


- (BOOL) ensureInstallPath
{
	BOOL				exists, directory;
	NSFileManager		*fmgr = [NSFileManager defaultManager];
	NSString			*path = [self installPath];

	exists = [fmgr fileExistsAtPath:path isDirectory:&directory];
	
	if (exists && !directory)
	{
		OOLog(kOOOXZErrorLog, @"Expected %@ to be a folder, but it is a file.", path);
		return NO;
	}
	if (!exists)
	{
		if (![fmgr oo_createDirectoryAtPath:path attributes:nil])
		{
			OOLog(kOOOXZErrorLog, @"Could not create folder %@.", path);
			return NO;
		}
	}
	
	return YES;
}


- (NSString *) manifestPath
{
	return [[[OOCacheManager sharedCache] cacheDirectoryPathCreatingIfNecessary:YES] stringByAppendingPathComponent:kOOOXZManifestCache];
}


/* Download mechanism could destroy a correct file if it failed
 * half-way and was downloaded on top of the old one. So this loads it
 * off to the side a bit */
- (NSString *) downloadPath
{
	if (_interfaceState == OXZ_STATE_UPDATING)
	{
		return [[[OOCacheManager sharedCache] cacheDirectoryPathCreatingIfNecessary:YES] stringByAppendingPathComponent:kOOOXZTmpPlistPath];
	}
	else
	{
		return [[[OOCacheManager sharedCache] cacheDirectoryPathCreatingIfNecessary:YES] stringByAppendingPathComponent:kOOOXZTmpPath];
	}
}


- (NSString *) dataURL
{
	/* Not expected to be set in general, but might be useful for some users */
	NSString *url = [[NSUserDefaults standardUserDefaults] stringForKey:kOOOXZDataConfig];
	if (url != nil)
	{
		return url;
	}
	return kOOOXZDataURL;
}


- (NSString *) humanSize:(NSUInteger)bytes
{
	if (bytes == 0)
	{
		return DESC(@"oolite-oxzmanager-missing-field");
	}
	else if (bytes < 1024)
	{
		return @"<1 kB";
	}
	else if (bytes < 1024*1024)
	{
		return [NSString stringWithFormat:@"%lu kB",bytes>>10];
	}
	else 
	{
		return [NSString stringWithFormat:@"%.2f MB",((float)(bytes>>10))/1024];
	}
}


- (void) setOXZList:(NSArray *)list
{
	DESTROY(_oxzList);
	if (list != nil)
	{
		_oxzList = [[list sortedArrayUsingFunction:oxzSort context:NULL] retain];
		// needed for update to available versions
		DESTROY(_managedList);
	}
}


- (void) setFilteredList:(NSArray *)list
{
	DESTROY(_filteredList);
	_filteredList = [list copy]; // copy retains
}


- (void) setFilter:(NSString *)filter
{
	DESTROY(_currentFilter);
	_currentFilter = [[filter lowercaseString] copy]; // copy retains
}


- (NSArray *) applyCurrentFilter:(NSArray *)list
{
	SEL filterSelector = @selector(applyFilterByNoFilter:);
	NSString *parameter  = nil;
	if ([_currentFilter isEqualToString:kOOOXZFilterUpdates])
	{
		filterSelector = @selector(applyFilterByUpdateRequired:);
	}
	else if ([_currentFilter isEqualToString:kOOOXZFilterInstallable])
	{
		filterSelector = @selector(applyFilterByInstallable:);
	}
	else if ([_currentFilter hasPrefix:kOOOXZFilterKeyword])
	{
		filterSelector = @selector(applyFilterByKeyword:keyword:);
		parameter = [_currentFilter substringFromIndex:[kOOOXZFilterKeyword length]];
	}
	else if ([_currentFilter hasPrefix:kOOOXZFilterAuthor])
	{
		filterSelector = @selector(applyFilterByAuthor:author:);
		parameter = [_currentFilter substringFromIndex:[kOOOXZFilterAuthor length]];
	}
	else if ([_currentFilter hasPrefix:kOOOXZFilterDays])
	{
		filterSelector = @selector(applyFilterByDays:days:);
		parameter = [_currentFilter substringFromIndex:[kOOOXZFilterDays length]];
	}
	else if ([_currentFilter hasPrefix:kOOOXZFilterTag])
	{
		filterSelector = @selector(applyFilterByTag:tag:);
		parameter = [_currentFilter substringFromIndex:[kOOOXZFilterTag length]];
	}

	NSMutableArray *filteredList = [NSMutableArray arrayWithCapacity:[list count]];
	NSDictionary *manifest       = nil;
	NSInvocation *invocation     = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:filterSelector]];
	[invocation setSelector:filterSelector];
	[invocation setTarget:self];
	if (parameter != nil)
	{
		[invocation setArgument:&parameter atIndex:3];
	}

	foreach(manifest, list)
	{
		[invocation setArgument:&manifest atIndex:2];
		[invocation invoke];
		BOOL filterAccepted = NO;
		[invocation getReturnValue:&filterAccepted];
		if (filterAccepted)
		{
			[filteredList addObject:manifest];
		}
	}
	// any bad filter that gets this far is also treated as '*'
	// so don't need to explicitly test for '*' or ''
	return [[filteredList copy] autorelease];
}


/*** Start filters ***/
- (BOOL) applyFilterByNoFilter:(NSDictionary *)manifest
{
	return YES;
}


- (BOOL) applyFilterByUpdateRequired:(NSDictionary *)manifest
{
	return ([self installableState:manifest] == OXZ_INSTALLABLE_UPDATE);
}


- (BOOL) applyFilterByInstallable:(NSDictionary *)manifest
{
	return ([self installableState:manifest] < OXZ_UNINSTALLABLE_ALREADY);
}


- (BOOL) applyFilterByKeyword:(NSDictionary *)manifest keyword:(NSString *)keyword
{
	NSString *parameter = nil;
	NSArray *parameters = [NSArray arrayWithObjects:kOOManifestTitle,kOOManifestDescription,kOOManifestCategory,nil];
	foreach (parameter,parameters)
	{
		if ([[manifest oo_stringForKey:parameter] rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound)
		{
			return YES;
		}
	}
	// tags are slightly different
	parameters = [manifest oo_arrayForKey:kOOManifestTags];
	foreach (parameter,parameters)
	{
		if ([parameter rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound)
		{
			return YES;
		}
	}
	
	return NO;
}


- (BOOL) applyFilterByAuthor:(NSDictionary *)manifest author:(NSString *)author
{
	NSString *mAuth = [manifest oo_stringForKey:kOOManifestAuthor];
	return ([mAuth rangeOfString:author options:NSCaseInsensitiveSearch].location != NSNotFound);
}


- (BOOL) applyFilterByDays:(NSDictionary *)manifest days:(NSString *)days
{
	NSInteger i = [days integerValue];
	if (i < 1)
	{
		return NO;
	}
	else
	{
		NSUInteger updated = [manifest oo_unsignedIntegerForKey:kOOManifestUploadDate];
		NSUInteger now = (NSUInteger)[[NSDate date] timeIntervalSince1970];
		return (updated + (86400 * i) > now);
	}
}


- (BOOL) applyFilterByTag:(NSDictionary *)manifest tag:(NSString *)tag
{
	NSString *parameter = nil;
	NSArray *parameters = [manifest oo_arrayForKey:kOOManifestTags];
	foreach (parameter,parameters)
	{
		if ([parameter rangeOfString:tag options:NSCaseInsensitiveSearch].location != NSNotFound)
		{
			return YES;
		}
	}
	
	return NO;
}

/*** End filters ***/

- (BOOL) validateFilter:(NSString *)input
{
	NSString *filter = [input lowercaseString];
	if (([filter length] == 0) // empty is valid
		|| ([filter isEqualToString:kOOOXZFilterAll])
		|| ([filter isEqualToString:kOOOXZFilterUpdates])
		|| ([filter isEqualToString:kOOOXZFilterInstallable])
		|| ([filter hasPrefix:kOOOXZFilterKeyword] && [filter length] > [kOOOXZFilterKeyword length])
		|| ([filter hasPrefix:kOOOXZFilterAuthor] && [filter length] > [kOOOXZFilterAuthor length])
		|| ([filter hasPrefix:kOOOXZFilterDays] && [[filter substringFromIndex:[kOOOXZFilterDays length]] intValue] > 0)
		|| ([filter hasPrefix:kOOOXZFilterTag] && [filter length] > [kOOOXZFilterTag length])
		)
	{
		return YES;
	}

	return NO;
}


- (void) setCurrentDownload:(NSURLConnection *)download withLabel:(NSString *)label
{
	if (_currentDownload != nil)
	{
		[_currentDownload cancel]; // releases via delegate
	}
	_currentDownload = [download retain];
	DESTROY(_currentDownloadName);
	_currentDownloadName = [label copy];
}


- (void) setProgressStatus:(NSString *)new
{
	DESTROY(_progressStatus);
	_progressStatus = [new copy];
}

- (BOOL) updateManifests
{
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self dataURL]]];
	if (_downloadStatus != OXZ_DOWNLOAD_NONE)
	{
		return NO;
	}
	_downloadStatus = OXZ_DOWNLOAD_STARTED;
	_interfaceState = OXZ_STATE_UPDATING;
	[self setProgressStatus:@""];

	return [self beginDownload:request];
}


- (BOOL) beginDownload:(NSMutableURLRequest *)request
{
	NSString *userAgent = [NSString stringWithFormat:@"Oolite/%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
	[request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
	NSURLConnection *download = [[NSURLConnection alloc] initWithRequest:request delegate:self];
	if (download)
	{
		_downloadProgress = 0;
		_downloadExpected = 0;
		NSString *label = DESC(@"oolite-oxzmanager-download-label-list");
		if (_interfaceState != OXZ_STATE_UPDATING)
		{
			NSDictionary *expectedManifest = nil;
			expectedManifest = [_filteredList objectAtIndex:_item];

			label = [expectedManifest oo_stringForKey:kOOManifestTitle defaultValue:DESC(@"oolite-oxzmanager-download-label-oxz")];
		}

		[self setCurrentDownload:download withLabel:label]; // retains it
		[download release];
		OOLog(kOOOXZDebugLog,@"Download request received, using %@ and downloading to %@",[request URL],[self downloadPath]);
		return YES;
	}
	else
	{
		OOLog(kOOOXZErrorLog,@"Unable to start downloading file at %@",[request URL]);
		_downloadStatus = OXZ_DOWNLOAD_ERROR;
		return NO;
	}
}


- (BOOL) cancelUpdate
{
	if (!(_interfaceState == OXZ_STATE_UPDATING || _interfaceState == OXZ_STATE_INSTALLING) || _downloadStatus == OXZ_DOWNLOAD_NONE)
	{
		return NO;
	}
	OOLog(kOOOXZDebugLog, @"%@", @"Trying to cancel file download");
	if (_currentDownload != nil)
	{
		[_currentDownload cancel];
	}
	else if (_downloadStatus == OXZ_DOWNLOAD_COMPLETE)
	{
		NSString *path = [self downloadPath];
		[[NSFileManager defaultManager] oo_removeItemAtPath:path];
	}
	_downloadStatus = OXZ_DOWNLOAD_NONE;
	if (_interfaceState == OXZ_STATE_INSTALLING)
	{
		_interfaceState = OXZ_STATE_PICK_INSTALL;
	}
	else
	{
		_interfaceState = OXZ_STATE_MAIN;
	}
	[self gui];
	return YES;
}


- (NSArray *) manifests
{
	return _oxzList;
}


- (NSArray *) managedOXZs
{
	if (_managedList == nil)
	{
		// if this list is being reset, also reset the current install list
		[ResourceManager resetManifestKnowledgeForOXZManager];
		NSArray *managedOXZs = [[NSFileManager defaultManager] oo_directoryContentsAtPath:[self installPath]];
		NSMutableArray *manifests = [NSMutableArray arrayWithCapacity:[managedOXZs count]];
		NSString *filename = nil;
		NSString *fullpath = nil;
		NSDictionary *manifest = nil;
		foreach (filename, managedOXZs)
		{
			fullpath = [[self installPath] stringByAppendingPathComponent:filename];
			manifest = OODictionaryFromFile([fullpath stringByAppendingPathComponent:@"manifest.plist"]);
			if (manifest != nil)
			{
				NSMutableDictionary *adjManifest = [NSMutableDictionary dictionaryWithDictionary:manifest];
				[adjManifest setObject:fullpath forKey:kOOManifestFilePath];

				NSDictionary *stored = nil;
				/* The list is already sorted to put the latest
				 * versions first. This flag means that it stops
				 * checking the list for versions once it finds one
				 * that is plausibly installable */
				BOOL foundInstallable = NO;
				foreach (stored, _oxzList)
				{
					if ([[stored oo_stringForKey:kOOManifestIdentifier] isEqualToString:[manifest oo_stringForKey:kOOManifestIdentifier]])
					{
						if (foundInstallable == NO)
						{
							[adjManifest setObject:[stored oo_stringForKey:kOOManifestVersion] forKey:kOOManifestAvailableVersion];
							[adjManifest setObject:[stored oo_stringForKey:kOOManifestDownloadURL] forKey:kOOManifestDownloadURL];
							if ([ResourceManager checkVersionCompatibility:manifest forOXP:nil])
							{
								foundInstallable = YES;
							}
						}
					}
				}

				[manifests addObject:adjManifest];
			}
		}
		[manifests sortUsingFunction:oxzSort context:NULL];

		_managedList = [manifests copy];
	}
	return _managedList;
}


- (BOOL) processDownloadedManifests
{
	if (_downloadStatus != OXZ_DOWNLOAD_COMPLETE)
	{
		return NO;
	}
	[self setOXZList:OOArrayFromFile([self downloadPath])];
	if (_oxzList != nil)
	{
		[_oxzList writeToFile:[self manifestPath] atomically:YES];
		// and clean up the temp file
		[[NSFileManager defaultManager] oo_removeItemAtPath:[self downloadPath]];
		// invalidate the managed list
		DESTROY(_managedList);
		_interfaceState = OXZ_STATE_TASKDONE;
		[self gui];
		return YES;
	}
	else
	{
		_downloadStatus = OXZ_DOWNLOAD_ERROR;
		OOLog(kOOOXZErrorLog,@"Downloaded manifest was not a valid plist, has been left in %@",[self downloadPath]);
		// revert to the old one
		[self setOXZList:OOArrayFromFile([self manifestPath])];
		_interfaceState = OXZ_STATE_TASKDONE;
		[self gui];
		return NO;
	}
}


- (BOOL) processDownloadedOXZ
{
	if (_downloadStatus != OXZ_DOWNLOAD_COMPLETE)
	{
		return NO;
	}

	NSDictionary *downloadedManifest = OODictionaryFromFile([[self downloadPath] stringByAppendingPathComponent:@"manifest.plist"]);
	if (downloadedManifest == nil)
	{
		_downloadStatus = OXZ_DOWNLOAD_ERROR;
		OOLog(kOOOXZErrorLog,@"Downloaded OXZ does not contain a manifest.plist, has been left in %@",[self downloadPath]);
		_interfaceState = OXZ_STATE_TASKDONE;
		[self gui];
		return NO;
	}
	NSDictionary *expectedManifest = nil;
	expectedManifest = [_filteredList objectAtIndex:_item];

	if (expectedManifest == nil || 
		(![[downloadedManifest oo_stringForKey:kOOManifestIdentifier] isEqualToString:[expectedManifest oo_stringForKey:kOOManifestIdentifier]]) || 
		(![[downloadedManifest oo_stringForKey:kOOManifestVersion] isEqualToString:[expectedManifest oo_stringForKey:kOOManifestAvailableVersion defaultValue:[expectedManifest oo_stringForKey:kOOManifestVersion]]])
		)
	{
		_downloadStatus = OXZ_DOWNLOAD_ERROR;
		OOLog(kOOOXZErrorLog, @"%@", @"Downloaded OXZ does not have the same identifer and version as expected. This might be due to your manifests list being out of date - try updating it.");
		_interfaceState = OXZ_STATE_TASKDONE;
		[self gui];
		return NO;
	}
	// this appears to be the OXZ we expected
	// filename is going to be identifier.oxz
	NSString *filename = [[downloadedManifest oo_stringForKey:kOOManifestIdentifier] stringByAppendingString:@".oxz"];

	if (![self ensureInstallPath])
	{
		_downloadStatus = OXZ_DOWNLOAD_ERROR;
		OOLog(kOOOXZErrorLog, @"%@", @"Unable to create installation folder.");
		_interfaceState = OXZ_STATE_TASKDONE;
		[self gui];
		return NO;
	}

	// delete filename if it exists from OXZ folder
	NSString *destination = [[self installPath] stringByAppendingPathComponent:filename];
	[[NSFileManager defaultManager] oo_removeItemAtPath:destination];

	// move the temp file on to it
	if (![[NSFileManager defaultManager] oo_moveItemAtPath:[self downloadPath] toPath:destination])
	{
		_downloadStatus = OXZ_DOWNLOAD_ERROR;
		OOLog(kOOOXZErrorLog, @"%@", @"Downloaded OXZ could not be installed.");
		_interfaceState = OXZ_STATE_TASKDONE;
		[self gui];
		return NO;
	}
	_changesMade = YES;
	DESTROY(_managedList); // will need updating
	// do this now to cope with circular dependencies on download
	[ResourceManager resetManifestKnowledgeForOXZManager];

	/** 
	 * If downloadedManifest is in _dependencyStack, remove it
	 * Get downloadedManifest requires_oxp list
	 * Add entries ones to _dependencyStack
	 * If _dependencyStack has contents, update _progressStatus
	 * ...and start the download of the 'first' item in _dependencyStack
	 * ...which isn't already installed (_dependencyStack is unordered
	 * ...so 'first' isn't really defined)
	 *
	 * ...if the item in _dependencyStack is not findable (e.g. wrong
	 * ...version) then stop here.
	 */
	NSArray *requires = [downloadedManifest oo_arrayForKey:kOOManifestRequiresOXPs defaultValue:nil];
	if (requires == nil)
	{
		// just in case the requirements are only specified in the online copy
		requires = [expectedManifest oo_arrayForKey:kOOManifestRequiresOXPs defaultValue:nil];
	}
	NSDictionary *requirement = nil;
	NSMutableString *progress = [NSMutableString stringWithCapacity:2048];
	OOLog(kOOOXZDebugLog,@"Dependency stack has %lu elements",[_dependencyStack count]);

	if ([_dependencyStack count] > 0)
	{
		// will remove as iterate, so create a temp copy to iterate over
		NSSet *tempStack = [NSSet setWithSet:_dependencyStack];
		foreach (requirement, tempStack)
		{
			OOLog(kOOOXZDebugLog,@"Dependency stack: checking %@",[requirement oo_stringForKey:kOOManifestRelationIdentifier]);
			if (![ResourceManager manifest:downloadedManifest HasUnmetDependency:requirement logErrors:NO]
			    && requires != nil && [requires containsObject:requirement])
			{
				// it was unmet, but now it's met					
				[progress appendFormat:DESC(@"oolite-oxzmanager-progress-now-has-@"),[requirement oo_stringForKey:kOOManifestRelationDescription defaultValue:[requirement oo_stringForKey:kOOManifestRelationIdentifier]]];
				[_dependencyStack removeObject:requirement];
				OOLog(kOOOXZDebugLog, @"%@", @"Dependency stack: requirement met");
			} else if ([[requirement oo_stringForKey:kOOManifestRelationIdentifier] isEqualToString:[downloadedManifest oo_stringForKey:kOOManifestIdentifier]]) {
				// remove the requirement for the just downloaded OXP
				[_dependencyStack removeObject:requirement];
			}
		}
	}
	if (requires != nil)
	{
		foreach (requirement, requires)
		{
			if ([ResourceManager manifest:downloadedManifest HasUnmetDependency:requirement logErrors:NO])
			{
				OOLog(kOOOXZDebugLog,@"Dependency stack: adding %@",[requirement oo_stringForKey:kOOManifestRelationIdentifier]);
				[_dependencyStack addObject:requirement];
				[progress appendFormat:DESC(@"oolite-oxzmanager-progress-requires-@"),[requirement oo_stringForKey:kOOManifestRelationDescription defaultValue:[requirement oo_stringForKey:kOOManifestRelationIdentifier]]];
			}
		}
	}
	if ([_dependencyStack count] > 0)
	{
		// get an object from the requirements list, and download it
		// if it can be found
		BOOL undownloadedRequirement = NO;
		NSDictionary *availableDownload = nil;
		BOOL foundDownload = NO;
		NSUInteger index = 0;
		NSString *needsIdentifier = nil;

		do
		{
			undownloadedRequirement = YES;
			requirement = [_dependencyStack anyObject];
			OOLog(kOOOXZDebugLog,@"Dependency stack: next is %@",[requirement oo_stringForKey:kOOManifestRelationIdentifier]);

			if (!_downloadAllDependencies)
			{
				[progress appendString:DESC(@"oolite-oxzmanager-progress-get-required")];
			}
			needsIdentifier = [requirement oo_stringForKey:kOOManifestRelationIdentifier];
		
			foreach (availableDownload, _oxzList)
			{
				if ([[availableDownload oo_stringForKey:kOOManifestIdentifier] isEqualToString:needsIdentifier])
				{
					if ([ResourceManager matchVersions:requirement withVersion:[availableDownload oo_stringForKey:kOOManifestVersion]])
					{
						OOLog(kOOOXZDebugLog, @"%@", @"Dependency stack: found download for next item");
						foundDownload = YES;
						index = [_oxzList indexOfObject:availableDownload];
						break;
					}
				}
			}
			
			if (foundDownload)
			{
				if ([self installableState:[_oxzList objectAtIndex:index]] == OXZ_UNINSTALLABLE_ALREADY)
				{
					OOLog(kOOOXZDebugLog,@"Dependency stack: %@ is downloaded but not yet loadable, removing from list.",[requirement oo_stringForKey:kOOManifestRelationIdentifier]);
					// then this has already been downloaded, but
					// can't be configured yet presumably because
					// another dependency is still to be loaded
					[_dependencyStack removeObject:requirement];
					if ([_dependencyStack count] > 0)
					{
						// try again
						undownloadedRequirement = NO;
					}
					else
					{
						// this case should probably never happen
						// is handled below just in case
						foundDownload = NO;
					}
				}
			}
		}
		while (!undownloadedRequirement);

		if (foundDownload)
		{
			// must clear filters entirely at this point
			[self setFilteredList:_oxzList];
			// then download that item
			_downloadStatus = OXZ_DOWNLOAD_NONE;
			if (_downloadAllDependencies)
			{
				OOLog(kOOOXZDebugLog,@"Dependency stack: installing %lu from list",index);
				if (![self installOXZ:index]) {
					// if a required dependency is somehow uninstallable
					// e.g. required+maximum version don't match this Oolite
					[progress appendFormat:DESC(@"oolite-oxzmanager-progress-required-@-not-found"),[requirement oo_stringForKey:kOOManifestRelationDescription defaultValue:[requirement oo_stringForKey:kOOManifestRelationIdentifier]]];
					[self setProgressStatus:progress];
					OOLog(kOOOXZErrorLog,@"OXZ dependency %@ could not be found for automatic download.",needsIdentifier);
					_downloadStatus = OXZ_DOWNLOAD_ERROR;
					OOLog(kOOOXZErrorLog, @"%@", @"Downloaded OXZ could not be installed.");
					_interfaceState = OXZ_STATE_TASKDONE;
					[self gui];
					return NO;
				}
			}
			else
			{
				_interfaceState = OXZ_STATE_DEPENDENCIES;
				_item = index;
			}
			[self setProgressStatus:progress];
			[self gui];
			return YES;
		}
		// this is probably always the case, see above
		else if ([_dependencyStack count] > 0)
		{
			[progress appendFormat:DESC(@"oolite-oxzmanager-progress-required-@-not-found"),[requirement oo_stringForKey:kOOManifestRelationDescription defaultValue:[requirement oo_stringForKey:kOOManifestRelationIdentifier]]];
			[self setProgressStatus:progress];
			OOLog(kOOOXZErrorLog,@"OXZ dependency %@ could not be found for automatic download.",needsIdentifier);
			_downloadStatus = OXZ_DOWNLOAD_ERROR;
			OOLog(kOOOXZErrorLog, @"%@", @"Downloaded OXZ could not be installed.");
			_interfaceState = OXZ_STATE_TASKDONE;
			[self gui];
			return NO;
		}
	}

	[self setProgressStatus:@""];
	_interfaceState = OXZ_STATE_TASKDONE;
	[_dependencyStack removeAllObjects]; // just in case
	_downloadAllDependencies = NO;
	[self gui];
	return YES;
}


- (NSDictionary *) installedManifestForIdentifier:(NSString *)identifier
{
	NSArray *installed = [self managedOXZs];
	NSDictionary *manifest = nil;
	foreach (manifest,installed)
	{
		if ([[manifest oo_stringForKey:kOOManifestIdentifier] isEqualToString:identifier])
		{
			return manifest;
		}
	}
	return nil;
}


- (OXZInstallableState) installableState:(NSDictionary *)manifest
{
	NSString *title = [manifest oo_stringForKey:kOOManifestTitle defaultValue:nil];
	NSString *identifier = [manifest oo_stringForKey:kOOManifestIdentifier defaultValue:nil];
	/* Check Oolite version */
	if (![ResourceManager checkVersionCompatibility:manifest forOXP:title])
	{
		return OXZ_UNINSTALLABLE_VERSION;
	}
	/* Check for current automated install */
	NSDictionary *installed = [self installedManifestForIdentifier:identifier];
	if (installed == nil)
	{
		// check for manual install
		installed = [ResourceManager manifestForIdentifier:identifier];
	}

	if (installed != nil)
	{
		if (![[installed oo_stringForKey:kOOManifestFilePath] hasPrefix:[self installPath]])
		{
			// installed manually
			return OXZ_UNINSTALLABLE_MANUAL;
		}
		if ([[installed oo_stringForKey:kOOManifestVersion] isEqualToString:[manifest oo_stringForKey:kOOManifestAvailableVersion defaultValue:[manifest oo_stringForKey:kOOManifestVersion]]]
			&& [[NSFileManager defaultManager] fileExistsAtPath:[installed oo_stringForKey:kOOManifestFilePath]])
		{
			// installed this exact version already, and haven't
			// uninstalled it since entering the manager, and it's
			// still available
			return OXZ_UNINSTALLABLE_ALREADY;
		}
		else if ([installed oo_stringForKey:kOOManifestAvailableVersion defaultValue:nil] == nil)
		{
			// installed, but no remote copy is indexed any more
			return OXZ_UNINSTALLABLE_NOREMOTE;
		}
	}
	/* Check for dependencies being met */
	if ([ResourceManager manifestHasConflicts:manifest logErrors:NO])
	{
		return OXZ_INSTALLABLE_CONFLICTS;
	}
	if (installed != nil)
	{
		NSString *availableVersion = [manifest oo_stringForKey:kOOManifestAvailableVersion];
		if (availableVersion == nil)
		{
			availableVersion = [manifest oo_stringForKey:kOOManifestVersion];
		}
		NSString *installedVersion = [installed oo_stringForKey:kOOManifestVersion];
		OOLog(@"version.debug",@"%@ mv:%@ mav:%@",identifier,installedVersion,availableVersion);
		if (CompareVersions(ComponentsFromVersionString(installedVersion),ComponentsFromVersionString(availableVersion)) == NSOrderedDescending)
		{
			// the installed copy is more recent than the server copy
			return OXZ_UNINSTALLABLE_NOREMOTE;
		}
		return OXZ_INSTALLABLE_UPDATE;
	}
	if ([ResourceManager manifestHasMissingDependencies:manifest logErrors:NO])
	{
		return OXZ_INSTALLABLE_DEPENDENCIES;
	}
	return OXZ_INSTALLABLE_OKAY;
}


- (OOColor *) colorForManifest:(NSDictionary *)manifest 
{
	switch ([self installableState:manifest])
	{
	case OXZ_INSTALLABLE_OKAY:
		return [OOColor yellowColor];
	case OXZ_INSTALLABLE_UPDATE:
		return [OOColor cyanColor];
	case OXZ_INSTALLABLE_DEPENDENCIES:
		return [OOColor orangeColor];
	case OXZ_INSTALLABLE_CONFLICTS:
		return [OOColor brownColor];
	case OXZ_UNINSTALLABLE_ALREADY:
		return [OOColor whiteColor];
	case OXZ_UNINSTALLABLE_MANUAL:
		return [OOColor redColor];
	case OXZ_UNINSTALLABLE_VERSION:
		return [OOColor grayColor];
	case OXZ_UNINSTALLABLE_NOREMOTE:
		return [OOColor blueColor];
	}
	return [OOColor yellowColor]; // never
}


- (NSString *) installStatusForManifest:(NSDictionary *)manifest 
{
	switch ([self installableState:manifest])
	{
	case OXZ_INSTALLABLE_OKAY:
		return DESC(@"oolite-oxzmanager-installable-okay");
	case OXZ_INSTALLABLE_UPDATE:
		return DESC(@"oolite-oxzmanager-installable-update");
	case OXZ_INSTALLABLE_DEPENDENCIES:
		return DESC(@"oolite-oxzmanager-installable-depend");
	case OXZ_INSTALLABLE_CONFLICTS:
		return DESC(@"oolite-oxzmanager-installable-conflicts");
	case OXZ_UNINSTALLABLE_ALREADY:
		return DESC(@"oolite-oxzmanager-installable-already");
	case OXZ_UNINSTALLABLE_MANUAL:
		return DESC(@"oolite-oxzmanager-installable-manual");
	case OXZ_UNINSTALLABLE_VERSION:
		return DESC(@"oolite-oxzmanager-installable-version");
	case OXZ_UNINSTALLABLE_NOREMOTE:
		return DESC(@"oolite-oxzmanager-installable-noremote");
	}
	return nil; // never
}



- (void) gui
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIRow		startRow = OXZ_GUI_ROW_EXIT;

#if OOLITE_WINDOWS
	/* unlock OXZs ahead of potential changes by making sure sound
	 * files aren't being held open */
	[ResourceManager clearCaches];
	[PLAYER destroySound];
#endif

	[gui clearAndKeepBackground:YES];
	[gui setTitle:DESC(@"oolite-oxzmanager-title")];

	/* This switch will give warnings unless all states are
	 * covered. */
	switch (_interfaceState)
	{
	case OXZ_STATE_SETFILTER:
		[gui setTitle:DESC(@"oolite-oxzmanager-title-setfilter")];
		[gui setText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-currentfilter-is-@"),_currentFilter] forRow:OXZ_GUI_ROW_FILTERCURRENT align:GUI_ALIGN_LEFT];
		[gui addLongText:DESC(@"oolite-oxzmanager-filterhelp") startingAtRow:OXZ_GUI_ROW_FILTERHELP align:GUI_ALIGN_LEFT];

		
		return; // don't do normal row selection stuff
	case OXZ_STATE_NODATA:
		if (_oxzList == nil)
		{
			[gui addLongText:DESC(@"oolite-oxzmanager-firstrun") startingAtRow:OXZ_GUI_ROW_FIRSTRUN align:GUI_ALIGN_LEFT];
			[gui setText:DESC(@"oolite-oxzmanager-download-list") forRow:OXZ_GUI_ROW_UPDATE align:GUI_ALIGN_CENTER];
			[gui setKey:@"_UPDATE" forRow:OXZ_GUI_ROW_UPDATE];

			startRow = OXZ_GUI_ROW_UPDATE;
		}
		else
		{
			// update data	
			[gui addLongText:DESC(@"oolite-oxzmanager-secondrun") startingAtRow:OXZ_GUI_ROW_FIRSTRUN align:GUI_ALIGN_LEFT];
			[gui setText:DESC(@"oolite-oxzmanager-download-noupdate") forRow:OXZ_GUI_ROW_PROCEED align:GUI_ALIGN_CENTER];
			[gui setKey:@"_MAIN" forRow:OXZ_GUI_ROW_PROCEED];

			[gui setText:DESC(@"oolite-oxzmanager-update-list") forRow:OXZ_GUI_ROW_UPDATE align:GUI_ALIGN_CENTER];
			[gui setKey:@"_UPDATE" forRow:OXZ_GUI_ROW_UPDATE];

			startRow = OXZ_GUI_ROW_PROCEED;
		}
		break;
	case OXZ_STATE_RESTARTING:
		[gui addLongText:DESC(@"oolite-oxzmanager-restart") startingAtRow:OXZ_GUI_ROW_FIRSTRUN align:GUI_ALIGN_LEFT];
		return; // yes, return, not break: controls are pointless here
	case OXZ_STATE_MAIN:
		[gui addLongText:DESC(@"oolite-oxzmanager-intro") startingAtRow:OXZ_GUI_ROW_FIRSTRUN align:GUI_ALIGN_LEFT];
		// fall through
	case OXZ_STATE_PICK_INSTALL:
	case OXZ_STATE_PICK_INSTALLED:
	case OXZ_STATE_PICK_REMOVE:
		if (_interfaceState != OXZ_STATE_MAIN)
		{
			[gui setText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-currentfilter-is-@-@"),OOExpand(@"[oolite_key_oxzmanager_setfilter]"),_currentFilter] forRow:OXZ_GUI_ROW_LISTFILTER align:GUI_ALIGN_LEFT];
			[gui setColor:[OOColor greenColor] forRow:OXZ_GUI_ROW_LISTFILTER];
		}

		[gui setText:DESC(@"oolite-oxzmanager-install") forRow:OXZ_GUI_ROW_INSTALL align:GUI_ALIGN_CENTER];
		[gui setKey:@"_INSTALL" forRow:OXZ_GUI_ROW_INSTALL];
		[gui setText:DESC(@"oolite-oxzmanager-installed") forRow:OXZ_GUI_ROW_INSTALLED align:GUI_ALIGN_CENTER];
		[gui setKey:@"_INSTALLED" forRow:OXZ_GUI_ROW_INSTALLED];
		[gui setText:DESC(@"oolite-oxzmanager-remove") forRow:OXZ_GUI_ROW_REMOVE align:GUI_ALIGN_CENTER];
		[gui setKey:@"_REMOVE" forRow:OXZ_GUI_ROW_REMOVE];
		[gui setText:DESC(@"oolite-oxzmanager-update-list") forRow:OXZ_GUI_ROW_UPDATE align:GUI_ALIGN_CENTER];
		[gui setKey:@"_UPDATE" forRow:OXZ_GUI_ROW_UPDATE];
		[gui setText:DESC(@"oolite-oxzmanager-update-all") forRow:OXZ_GUI_ROW_UPDATE_ALL align:GUI_ALIGN_CENTER];
		[gui setKey:@"_UPDATE_ALL" forRow:OXZ_GUI_ROW_UPDATE_ALL];

		startRow = OXZ_GUI_ROW_INSTALL;
		break;
	case OXZ_STATE_UPDATING:
	case OXZ_STATE_INSTALLING:
		[gui setTitle:DESC(@"oolite-oxzmanager-title-downloading")];

		[gui addLongText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-progress-@-is-@-of-@"),_currentDownloadName,[self humanSize:_downloadProgress],[self humanSize:_downloadExpected]] startingAtRow:OXZ_GUI_ROW_PROGRESS align:GUI_ALIGN_LEFT];

		[gui addLongText:_progressStatus startingAtRow:OXZ_GUI_ROW_PROGRESS+2 align:GUI_ALIGN_LEFT];

		[gui setText:DESC(@"oolite-oxzmanager-cancel") forRow:OXZ_GUI_ROW_CANCEL align:GUI_ALIGN_CENTER];
		[gui setKey:@"_CANCEL" forRow:OXZ_GUI_ROW_CANCEL];
		startRow = OXZ_GUI_ROW_UPDATE;
		break;
	case OXZ_STATE_DEPENDENCIES:
		[gui setTitle:DESC(@"oolite-oxzmanager-title-dependencies")];

		[gui setText:DESC(@"oolite-oxzmanager-dependencies-decision") forRow:OXZ_GUI_ROW_PROGRESS align:GUI_ALIGN_LEFT];

		[gui addLongText:_progressStatus startingAtRow:OXZ_GUI_ROW_PROGRESS+2 align:GUI_ALIGN_LEFT];

		startRow = OXZ_GUI_ROW_INSTALLED;
		[gui setText:DESC(@"oolite-oxzmanager-dependencies-yes-all") forRow:OXZ_GUI_ROW_INSTALLED align:GUI_ALIGN_CENTER];
		[gui setKey:@"_PROCEED_ALL" forRow:OXZ_GUI_ROW_INSTALLED];

		[gui setText:DESC(@"oolite-oxzmanager-dependencies-yes") forRow:OXZ_GUI_ROW_PROCEED align:GUI_ALIGN_CENTER];
		[gui setKey:@"_PROCEED" forRow:OXZ_GUI_ROW_PROCEED];

		[gui setText:DESC(@"oolite-oxzmanager-dependencies-no") forRow:OXZ_GUI_ROW_CANCEL align:GUI_ALIGN_CENTER];
		[gui setKey:@"_CANCEL" forRow:OXZ_GUI_ROW_CANCEL];
		break;

	case OXZ_STATE_REMOVING:
		[gui addLongText:DESC(@"oolite-oxzmanager-removal-done") startingAtRow:OXZ_GUI_ROW_PROGRESS align:GUI_ALIGN_LEFT];
		[gui setText:DESC(@"oolite-oxzmanager-acknowledge") forRow:OXZ_GUI_ROW_UPDATE align:GUI_ALIGN_CENTER];
		[gui setKey:@"_ACK" forRow:OXZ_GUI_ROW_UPDATE];
		startRow = OXZ_GUI_ROW_UPDATE;
		break;
	case OXZ_STATE_TASKDONE:
		if (_downloadStatus == OXZ_DOWNLOAD_COMPLETE)
		{
			[gui addLongText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-progress-done-%u-%u"),[_oxzList count],[[self managedOXZs] count]] startingAtRow:OXZ_GUI_ROW_PROGRESS align:GUI_ALIGN_LEFT];
		}
		else
		{
			[gui addLongText:OOExpandKey(@"oolite-oxzmanager-progress-error") startingAtRow:OXZ_GUI_ROW_PROGRESS align:GUI_ALIGN_LEFT];
		}
		[gui addLongText:_progressStatus startingAtRow:OXZ_GUI_ROW_PROGRESS+4 align:GUI_ALIGN_LEFT];

		[gui setText:DESC(@"oolite-oxzmanager-acknowledge") forRow:OXZ_GUI_ROW_UPDATE align:GUI_ALIGN_CENTER];
		[gui setKey:@"_ACK" forRow:OXZ_GUI_ROW_UPDATE];
		startRow = OXZ_GUI_ROW_UPDATE;
		break;
	case OXZ_STATE_EXTRACT:
		{
			NSDictionary *manifest = [_filteredList oo_dictionaryAtIndex:_item];
			NSString *title = [manifest oo_stringForKey:kOOManifestTitle];
			NSString *version = [manifest oo_stringForKey:kOOManifestVersion];
			NSString *identifier = [manifest oo_stringForKey:kOOManifestIdentifier];
			[gui setTitle:DESC(@"oolite-oxzmanager-title-extract")];
			[gui setText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-infopage-title-@-version-@"),
								   title,
								   version]
				  forRow:0 align:GUI_ALIGN_LEFT];
			[gui addLongText:DESC(@"oolite-oxzmanager-extract-info") startingAtRow:2 align:GUI_ALIGN_LEFT];
#ifdef NDEBUG
			[gui addLongText:DESC(@"oolite-oxzmanager-extract-releasebuild") startingAtRow:7 align:GUI_ALIGN_LEFT];
			[gui setColor:[OOColor orangeColor] forRow:7];
			[gui setColor:[OOColor orangeColor] forRow:8];
#endif
			NSString *path = [self extractionBasePathForIdentifier:identifier andVersion:version];
			if ([[NSFileManager defaultManager] fileExistsAtPath:path])
			{
				[gui addLongText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-extract-@-already-exists"), path]
				  startingAtRow:10 align:GUI_ALIGN_LEFT];
				startRow = OXZ_GUI_ROW_CANCEL;
				[gui setText:DESC(@"oolite-oxzmanager-extract-unavailable") forRow:OXZ_GUI_ROW_PROCEED align:GUI_ALIGN_CENTER];
				[gui setColor:[OOColor grayColor] forRow:OXZ_GUI_ROW_PROCEED];
			}
			else
			{
				[gui addLongText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-extract-to-@"), path]
				  startingAtRow:10 align:GUI_ALIGN_LEFT];
				startRow = OXZ_GUI_ROW_PROCEED;
				[gui setText:DESC(@"oolite-oxzmanager-extract-proceed") forRow:OXZ_GUI_ROW_PROCEED align:GUI_ALIGN_CENTER];
				[gui setKey:@"_PROCEED" forRow:OXZ_GUI_ROW_PROCEED];

			}
			[gui setText:DESC(@"oolite-oxzmanager-extract-cancel") forRow:OXZ_GUI_ROW_CANCEL align:GUI_ALIGN_CENTER];
			[gui setKey:@"_CANCEL" forRow:OXZ_GUI_ROW_CANCEL];

		}	
		break;
	case OXZ_STATE_EXTRACTDONE:
		[gui addLongText:_progressStatus startingAtRow:1 align:GUI_ALIGN_LEFT];
		[gui setText:DESC(@"oolite-oxzmanager-acknowledge") forRow:OXZ_GUI_ROW_UPDATE align:GUI_ALIGN_CENTER];
		[gui setKey:@"_ACK" forRow:OXZ_GUI_ROW_UPDATE];
		startRow = OXZ_GUI_ROW_UPDATE;
		break;

	}

	if (_interfaceState == OXZ_STATE_PICK_INSTALL)
	{
		[gui setTitle:DESC(@"oolite-oxzmanager-title-install")];
		[self setFilteredList:[self applyCurrentFilter:_oxzList]];
		startRow = [self showInstallOptions];
	}
	else if (_interfaceState == OXZ_STATE_PICK_INSTALLED)
	{
		[gui setTitle:DESC(@"oolite-oxzmanager-title-installed")];
		[self setFilteredList:[self applyCurrentFilter:[self managedOXZs]]];
		startRow = [self showInstallOptions];
	}
	else if (_interfaceState == OXZ_STATE_PICK_REMOVE)
	{
		[gui setTitle:DESC(@"oolite-oxzmanager-title-remove")];
		[self setFilteredList:[self applyCurrentFilter:[self managedOXZs]]];
		startRow = [self showRemoveOptions];
	}


	if (_changesMade)
	{
		[gui setText:DESC(@"oolite-oxzmanager-exit-restart") forRow:OXZ_GUI_ROW_EXIT align:GUI_ALIGN_CENTER];
	}
	else
	{
		[gui setText:DESC(@"oolite-oxzmanager-exit") forRow:OXZ_GUI_ROW_EXIT align:GUI_ALIGN_CENTER];
	}
	[gui setKey:@"_EXIT" forRow:OXZ_GUI_ROW_EXIT];
	[gui setSelectableRange:NSMakeRange(startRow,2+(OXZ_GUI_ROW_EXIT-startRow))];
	if (startRow < OXZ_GUI_ROW_INSTALL)
	{
		[gui setSelectedRow:OXZ_GUI_ROW_INSTALL];
	}
	else if (_interfaceState == OXZ_STATE_NODATA)
	{
		[gui setSelectedRow:OXZ_GUI_ROW_UPDATE];
	}
	else
	{
		[gui setSelectedRow:startRow];
	}
	
}


- (BOOL) isRestarting
{
	// for the restart
	if (EXPECT_NOT(_interfaceState == OXZ_STATE_RESTARTING))
	{
		// Rebuilds OXP search
		[ResourceManager reset];
		[UNIVERSE reinitAndShowDemo:YES];
		_changesMade = NO;
		_interfaceState = OXZ_STATE_MAIN;
		_downloadStatus = OXZ_DOWNLOAD_NONE; // clear error state
		return YES;
	}
	else
	{
		return NO;
	}
}


- (void) processSelection
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIRow selection = [gui selectedRow];

	if (selection == OXZ_GUI_ROW_EXIT)
	{
		[self cancelUpdate]; // doesn't hurt if no update in progress
		[_dependencyStack removeAllObjects]; // cleanup
		_downloadAllDependencies = NO;
		_downloadStatus = OXZ_DOWNLOAD_NONE; // clear error state
		if (_changesMade)
		{
			_interfaceState = OXZ_STATE_RESTARTING;
		}
		else
		{
			[PLAYER setGuiToIntroFirstGo:YES];
			if (_oxzList != nil)
			{
				_interfaceState = OXZ_STATE_MAIN;
			}
			else
			{
				_interfaceState = OXZ_STATE_NODATA;
			}
			return;
		}
	}
	else if (selection == OXZ_GUI_ROW_UPDATE) // also == _CANCEL
	{
		if (_interfaceState == OXZ_STATE_REMOVING)
		{
			_interfaceState = OXZ_STATE_PICK_REMOVE;
			_downloadStatus = OXZ_DOWNLOAD_NONE;
		}
		else if (_interfaceState == OXZ_STATE_TASKDONE || _interfaceState == OXZ_STATE_DEPENDENCIES)
		{
			[_dependencyStack removeAllObjects];
			_downloadAllDependencies = NO;
			_interfaceState = OXZ_STATE_PICK_INSTALL;
			_downloadStatus = OXZ_DOWNLOAD_NONE;
		}
		else if (_interfaceState == OXZ_STATE_EXTRACTDONE)
		{
			[_dependencyStack removeAllObjects];
			_downloadAllDependencies = NO;
			_interfaceState = OXZ_STATE_PICK_INSTALLED;
			_downloadStatus = OXZ_DOWNLOAD_NONE;
		}
		else if (_interfaceState == OXZ_STATE_INSTALLING || _interfaceState == OXZ_STATE_UPDATING)
		{
			[self cancelUpdate]; // sets interface state and download status
		}
		else if (_interfaceState == OXZ_STATE_EXTRACT)
		{
			_interfaceState = OXZ_STATE_MAIN;
		}
		else
		{
			[self updateManifests];
		}
	}
	else if (selection == OXZ_GUI_ROW_INSTALL)
	{
		_interfaceState = OXZ_STATE_PICK_INSTALL;
	}
	else if (selection == OXZ_GUI_ROW_INSTALLED)
	{
		if (_interfaceState == OXZ_STATE_DEPENDENCIES) // also == _PROCEED_ALL
		{
			_downloadAllDependencies = YES;
			[self installOXZ:_item];
		}
		else 
		{
			_interfaceState = OXZ_STATE_PICK_INSTALLED;
		}
	}
	else if (selection == OXZ_GUI_ROW_REMOVE) // also == _PROCEED
	{
		if (_interfaceState == OXZ_STATE_DEPENDENCIES)
		{
			[self installOXZ:_item];
		}
		else if (_interfaceState == OXZ_STATE_NODATA)
		{
			_interfaceState = OXZ_STATE_MAIN;
		}
		else if (_interfaceState == OXZ_STATE_EXTRACT)
		{
			[self setProgressStatus:[self extractOXZ:_item]];
			_interfaceState = OXZ_STATE_EXTRACTDONE;
		}
		else
		{
			_interfaceState = OXZ_STATE_PICK_REMOVE;
		}
	}
	else if (selection == OXZ_GUI_ROW_UPDATE_ALL)
	{
		OOLog(kOOOXZDebugLog, @"%@", @"Trying to update all managed OXPs");
		[self updateAllOXZ];
	}
	else if (selection == OXZ_GUI_ROW_LISTPREV)
	{
		[self processOptionsPrev];
		return;
	}
	else if (selection == OXZ_GUI_ROW_LISTNEXT)
	{
		[self processOptionsNext];
		return;
	}
	else
	{
		NSUInteger item = _offset + selection - OXZ_GUI_ROW_LISTSTART;
		if (_interfaceState == OXZ_STATE_PICK_REMOVE)
		{
			[self removeOXZ:item];
		}
		else if (_interfaceState == OXZ_STATE_PICK_INSTALL)
		{
			OOLog(kOOOXZDebugLog, @"Trying to install index %lu", (unsigned long)item);
			[self installOXZ:item];
		}
		else if (_interfaceState == OXZ_STATE_PICK_INSTALLED)
		{
			OOLog(kOOOXZDebugLog, @"Trying to install index %lu", (unsigned long)item);
			[self installOXZ:item];
		}

	}

	[self gui]; // update GUI
}


- (BOOL) isAcceptingTextInput
{
	return (_interfaceState == OXZ_STATE_SETFILTER);
}


- (BOOL) isAcceptingGUIInput
{
	return !_interfaceShowingOXZDetail;
}


- (void) processTextInput:(NSString *)input
{
	if ([self validateFilter:input])
	{
		if ([input length] > 0)
		{
			[self setFilter:input];
		} // else keep previous filter
		_interfaceState = OXZ_STATE_PICK_INSTALL;
		[self gui];
	}
	// else nothing
}


- (void) refreshTextInput:(NSString *)input
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	[gui setText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-text-prompt-@"), input] forRow:OXZ_GUI_ROW_INPUT align:GUI_ALIGN_LEFT];
	if ([self validateFilter:input])
	{
		[gui setColor:[OOColor cyanColor] forRow:OXZ_GUI_ROW_INPUT];
	}
	else
	{
		[gui setColor:[OOColor orangeColor] forRow:OXZ_GUI_ROW_INPUT];
	}
}


- (void) processFilterKey
{
	if (_interfaceShowingOXZDetail)
	{
		_interfaceShowingOXZDetail = NO;
	}
	if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_INSTALLED || _interfaceState == OXZ_STATE_PICK_REMOVE || _interfaceState == OXZ_STATE_MAIN)
	{
		_interfaceState = OXZ_STATE_SETFILTER;
		[[UNIVERSE gameView] resetTypedString];
		[self gui];
	}
	// else this key does nothing
}


- (void) processShowInfoKey
{
	if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_INSTALLED || _interfaceState == OXZ_STATE_PICK_REMOVE)
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];

		if (_interfaceShowingOXZDetail)
		{
			_interfaceShowingOXZDetail = NO;
			[self gui]; // restore screen
			// reset list selection position
			[gui setSelectedRow:(_item - _offset + OXZ_GUI_ROW_LISTSTART)];
			// and do the GUI again with the correct positions
			[self showOptionsUpdate]; // restore screen
		}
		else
		{
			OOGUIRow selection = [gui selectedRow];
			
			if (selection < OXZ_GUI_ROW_LISTSTART || selection >= OXZ_GUI_ROW_LISTSTART + OXZ_GUI_NUM_LISTROWS)
			{
				// not on an OXZ
				return;
			}


			_item = _offset + selection - OXZ_GUI_ROW_LISTSTART;

			NSDictionary *manifest = [_filteredList oo_dictionaryAtIndex:_item];
			_interfaceShowingOXZDetail = YES;

			[gui clearAndKeepBackground:YES];
			[gui setTitle:DESC(@"oolite-oxzmanager-title-infopage")];

// title, version			
			[gui setText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-infopage-title-@-version-@"),
								   [manifest oo_stringForKey:kOOManifestTitle],
								   [manifest oo_stringForKey:kOOManifestVersion]]
				  forRow:0 align:GUI_ALIGN_LEFT];

// author
			[gui setText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-infopage-author-@"),
								   [manifest oo_stringForKey:kOOManifestAuthor]]
				  forRow:1 align:GUI_ALIGN_LEFT];

// license
			[gui addLongText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-infopage-license-@"),
								   [manifest oo_stringForKey:kOOManifestLicense]]
				  startingAtRow:2 align:GUI_ALIGN_LEFT];
// tags
			
			[gui addLongText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-infopage-tags-@"),[[manifest oo_arrayForKey:kOOManifestTags] componentsJoinedByString: @", "]]
				  startingAtRow:4  align:GUI_ALIGN_LEFT];
// description
			[gui addLongText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-infopage-description-@"),[manifest oo_stringForKey:kOOManifestDescription]]
				  startingAtRow:7  align:GUI_ALIGN_LEFT];

// infoURL		
			NSString *infoURLString = [manifest oo_stringForKey:kOOManifestInformationURL];
			[gui setText:[NSString stringWithFormat:DESC(@"oolite-oxzmanager-infopage-infourl-@"),
								   infoURLString]
				  forRow:25 align:GUI_ALIGN_LEFT];
			// copy url info text to clipboard automatically once we are in the oxz info page
			[[UNIVERSE gameView] stringToClipboard:infoURLString];	  
				  
// instructions
			[gui setText:OOExpand(DESC(@"oolite-oxzmanager-infopage-return")) forRow:27 align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor greenColor] forRow:27];

		}
	}
}


- (void) processExtractKey
{
	// TODO: Extraction functionality - converts an installed OXZ to
	// an OXP in the main AddOns folder if it's safe to do so.
	if (!_interfaceShowingOXZDetail && (_interfaceState == OXZ_STATE_PICK_INSTALLED || _interfaceState == OXZ_STATE_PICK_REMOVE))
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		OOGUIRow selection = [gui selectedRow];
		
		if (selection < OXZ_GUI_ROW_LISTSTART || selection >= OXZ_GUI_ROW_LISTSTART + OXZ_GUI_NUM_LISTROWS)
		{
			// not on an OXZ
			return;
		}
		
		_item = _offset + selection - OXZ_GUI_ROW_LISTSTART;
		_interfaceState = OXZ_STATE_EXTRACT;
		[self gui];
	}
}


- (BOOL) installOXZ:(NSUInteger)item 
{
	NSArray *picklist = _filteredList;

	if ([picklist count] <= item)
	{
		return NO;
	}
	NSDictionary *manifest = [picklist objectAtIndex:item];
	_item = item;

	if ([self installableState:manifest] >= OXZ_UNINSTALLABLE_ALREADY)
	{
		OOLog(kOOOXZDebugLog,@"Cannot install %@",manifest);
		// can't be installed on this version of Oolite, or already is installed
		return NO;
	}
	NSString *url = [manifest objectForKey:kOOManifestDownloadURL];
	if (url == nil)
	{
		OOLog(kOOOXZErrorLog, @"%@", @"Manifest does not have a download URL - cannot install");
		return NO;
	}
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
	if (_downloadStatus != OXZ_DOWNLOAD_NONE)
	{
		return NO;
	}
	_downloadStatus = OXZ_DOWNLOAD_STARTED;
	_interfaceState = OXZ_STATE_INSTALLING;
	
	[self setProgressStatus:@""];
	return [self beginDownload:request];
}


- (BOOL) updateAllOXZ
{
	[_dependencyStack removeAllObjects];
	_downloadAllDependencies = YES;
	[self setFilteredList:_oxzList];
	NSDictionary *manifest = nil;

	foreach (manifest,_oxzList)
	{
		if ([self installableState:manifest] == OXZ_INSTALLABLE_UPDATE)
		{
			OOLog(kOOOXZDebugLog, @"Queuing in for update: %@", manifest);
			[_dependencyStack addObject:manifest];
		}
	}
	NSDictionary *first = [_dependencyStack anyObject];
	NSString* identifier = [first oo_stringForKey:kOOManifestRelationIdentifier];
	NSUInteger item = NSUIntegerMax;
	NSDictionary *availableDownload = nil;
	foreach (availableDownload, _oxzList)
	{
		if ([[availableDownload oo_stringForKey:kOOManifestIdentifier] isEqualToString:identifier])
		{
			item = [_oxzList indexOfObject:availableDownload];
			break;
		}
	}
	return [self installOXZ:item];
}


- (NSArray *) installOptions
{
	NSUInteger start = _offset;
	if (start >= [_filteredList count])
	{
		start = 0;
		_offset = 0;
	}
	NSUInteger end = start + OXZ_GUI_NUM_LISTROWS;
	if (end > [_filteredList count])
	{
		end = [_filteredList count];
	}
	return [_filteredList subarrayWithRange:NSMakeRange(start,end-start)];
}


- (OOGUIRow) showInstallOptions
{
	// shows the current installation options page
	OOGUIRow startRow = OXZ_GUI_ROW_LISTPREV;
	NSArray *options = [self installOptions];
	NSUInteger optCount = [_filteredList count];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUITabSettings tab_stops;
	tab_stops[0] = 0;
	tab_stops[1] = 100;
	tab_stops[2] = 320;
	tab_stops[3] = 400;
	[gui setTabStops:tab_stops];
	

	[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-oxzmanager-heading-category"),
						   DESC(@"oolite-oxzmanager-heading-title"), 
						   DESC(@"oolite-oxzmanager-heading-installed"), 
						   DESC(@"oolite-oxzmanager-heading-downloadable"), 
								nil] forRow:OXZ_GUI_ROW_LISTHEAD];

	if (_offset > 0)
	{
		[gui setColor:[OOColor greenColor] forRow:OXZ_GUI_ROW_LISTPREV];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @"",@"",@" <-- ", nil] forRow:OXZ_GUI_ROW_LISTPREV];
		[gui setKey:@"_BACK" forRow:OXZ_GUI_ROW_LISTPREV];
	}
	else
	{
		if ([gui selectedRow] == OXZ_GUI_ROW_LISTPREV)
		{
			[gui setSelectedRow:OXZ_GUI_ROW_LISTSTART];
		}
		[gui setText:@"" forRow:OXZ_GUI_ROW_LISTPREV align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:OXZ_GUI_ROW_LISTPREV];
	}
	if (_offset + 10 < optCount)
	{
		[gui setColor:[OOColor greenColor] forRow:OXZ_GUI_ROW_LISTNEXT];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @"",@"",@" --> ", nil] forRow:OXZ_GUI_ROW_LISTNEXT];
		[gui setKey:@"_NEXT" forRow:OXZ_GUI_ROW_LISTNEXT];
	}
	else
	{
		if ([gui selectedRow] == OXZ_GUI_ROW_LISTNEXT)
		{
			[gui setSelectedRow:OXZ_GUI_ROW_LISTSTART];
		}
		[gui setText:@"" forRow:OXZ_GUI_ROW_LISTNEXT align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:OXZ_GUI_ROW_LISTNEXT];
	}

	// clear any previous longtext
	for (NSUInteger i = OXZ_GUI_ROW_LISTSTATUS; i < OXZ_GUI_ROW_INSTALL-1; i++)
	{
		[gui setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:i];
	}
	// and any previous listed entries
	for (NSUInteger i = OXZ_GUI_ROW_LISTSTART; i < OXZ_GUI_ROW_LISTNEXT; i++)
	{
		[gui setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:i];
	}

	OOGUIRow row = OXZ_GUI_ROW_LISTSTART;
	NSDictionary *manifest = nil;
	BOOL oxzLineSelected = NO;

	foreach (manifest, options)
	{
		NSDictionary *installed = [ResourceManager manifestForIdentifier:[manifest oo_stringForKey:kOOManifestIdentifier]];
		NSString *localPath = [[[self installPath] stringByAppendingPathComponent:[manifest oo_stringForKey:kOOManifestIdentifier]] stringByAppendingPathExtension:@"oxz"];
		if (installed == nil)
		{
			// check that there's not one just been downloaded
			installed = OODictionaryFromFile([localPath stringByAppendingPathComponent:@"manifest.plist"]);
		}
		else
		{
			// check for a more recent download
			if ([[NSFileManager defaultManager] fileExistsAtPath:localPath])
			{
				
				installed = OODictionaryFromFile([localPath stringByAppendingPathComponent:@"manifest.plist"]);
			}
			else
			{
				// check if this was a managed OXZ which has been deleted
				if ([[installed oo_stringForKey:kOOManifestFilePath] hasPrefix:[self installPath]])
				{
					installed = nil;
				}
			}
		}

		NSString *installedVersion = DESC(@"oolite-oxzmanager-version-none");
		if (installed != nil)
		{
			installedVersion = [installed oo_stringForKey:kOOManifestVersion defaultValue:DESC(@"oolite-oxzmanager-version-none")];
		}

		/* If the filter is in use, the available_version key will
		 * contain the version which can be downloaded. */
		[gui setArray:[NSArray arrayWithObjects:
			 [manifest oo_stringForKey:kOOManifestCategory defaultValue:DESC(@"oolite-oxzmanager-missing-field")],
			 [manifest oo_stringForKey:kOOManifestTitle defaultValue:DESC(@"oolite-oxzmanager-missing-field")],
			 installedVersion,
		 	 [manifest oo_stringForKey:kOOManifestAvailableVersion defaultValue:[manifest oo_stringForKey:kOOManifestVersion defaultValue:DESC(@"oolite-oxzmanager-version-none")]],
		  nil] forRow:row];

		[gui setKey:[manifest oo_stringForKey:kOOManifestIdentifier] forRow:row];
		/* yellow for installable, orange for dependency issues, grey and unselectable for version issues, white and unselectable for already installed (manually or otherwise) at the current version, red and unselectable for already installed manually at a different version. */
		[gui setColor:[self colorForManifest:manifest] forRow:row];

		if (row == [gui selectedRow])
		{
			oxzLineSelected = YES;
			
			[gui setText:[self installStatusForManifest:manifest] forRow:OXZ_GUI_ROW_LISTSTATUS];
			[gui setColor:[OOColor greenColor] forRow:OXZ_GUI_ROW_LISTSTATUS];

			[gui addLongText:[[[manifest oo_stringForKey:kOOManifestDescription] componentsSeparatedByString:@"\n"] oo_stringAtIndex:0] startingAtRow:OXZ_GUI_ROW_LISTDESC align:GUI_ALIGN_LEFT];
			
			NSString *infoUrl = [manifest oo_stringForKey:kOOManifestInformationURL];
			if (infoUrl != nil)
			{
				[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-oxzmanager-infoline-url"),infoUrl,nil] forRow:OXZ_GUI_ROW_LISTINFO1];
			}
			NSUInteger size = [manifest oo_unsignedIntForKey:kOOManifestFileSize defaultValue:0];
			NSString *updatedDesc = nil;

			NSUInteger timestamp = [manifest oo_unsignedIntegerForKey:kOOManifestUploadDate defaultValue:0];
			if (timestamp > 0)
			{
				// list of installable OXZs
				NSDate *updated = [NSDate dateWithTimeIntervalSince1970:timestamp];
			
				//keep only the first part of the date string description, which should be in YYYY-MM-DD format
				updatedDesc = [[[updated description] componentsSeparatedByString:@" "] oo_stringAtIndex:0];
				
				[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-oxzmanager-infoline-size"),[self humanSize:size],DESC(@"oolite-oxzmanager-infoline-date"),updatedDesc,nil] forRow:OXZ_GUI_ROW_LISTINFO2];
			} 
			else if (size > 0)
			{
				// list of installed/removable OXZs
				[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-oxzmanager-infoline-size"),[self humanSize:size],nil] forRow:OXZ_GUI_ROW_LISTINFO2];
			}
			

		}
		

		row++;
	}

	if (!oxzLineSelected)
	{
		if (_interfaceState == OXZ_STATE_PICK_INSTALLED)
		{
			// installeD
			[gui addLongText:OOExpand(DESC(@"oolite-oxzmanager-installed-nonepicked")) startingAtRow:OXZ_GUI_ROW_LISTDESC align:GUI_ALIGN_LEFT];
		}
		else
		{
			// installeR
			[gui addLongText:OOExpand(DESC(@"oolite-oxzmanager-installer-nonepicked")) startingAtRow:OXZ_GUI_ROW_LISTDESC align:GUI_ALIGN_LEFT];
		}
		
	}


	return startRow;
}


- (BOOL) removeOXZ:(NSUInteger)item
{
	NSArray *remList = _filteredList;
	if ([remList count] <= item)
	{
		OOLog(kOOOXZDebugLog, @"Unable to remove item %lu as only %lu in list", (unsigned long)item, (unsigned long)[remList count]);
		return NO;
	}
	NSString *filename = [[remList objectAtIndex:item] oo_stringForKey:kOOManifestFilePath];
	if (filename == nil)
	{
		OOLog(kOOOXZDebugLog, @"Unable to remove item %lu as filename not found", (unsigned long)item);
		return NO;
	}

	if (![[NSFileManager defaultManager] oo_removeItemAtPath:filename])
	{
		OOLog(kOOOXZErrorLog, @"Unable to remove file %@", filename);
		return NO;
	}
	_changesMade = YES;
	DESTROY(_managedList); // will need updating
	_interfaceState = OXZ_STATE_REMOVING;
	[self gui];
	return YES;
}


- (NSArray *) removeOptions
{
	NSArray *remList = _filteredList;
	if ([remList count] == 0)
	{
		return nil;
	}
	NSUInteger start = _offset;
	if (start >= [remList count])
	{
		start = 0;
		_offset = 0;
	}
	NSUInteger end = start + OXZ_GUI_NUM_LISTROWS;
	if (end > [remList count])
	{
		end = [remList count];
	}
	return [remList subarrayWithRange:NSMakeRange(start,end-start)];
}


- (OOGUIRow) showRemoveOptions
{
	// shows the current installation options page
	OOGUIRow startRow = OXZ_GUI_ROW_LISTPREV;
	NSArray *options = [self removeOptions];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	if (options == nil)
	{
		[gui addLongText:DESC(@"oolite-oxzmanager-nothing-removable") startingAtRow:OXZ_GUI_ROW_PROGRESS align:GUI_ALIGN_LEFT];
		return startRow;
	}

	OOGUITabSettings tab_stops;
	tab_stops[0] = 0;
	tab_stops[1] = 100;
	tab_stops[2] = 400;
	[gui setTabStops:tab_stops];
	
	[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-oxzmanager-heading-category"),
						   DESC(@"oolite-oxzmanager-heading-title"), 
						   DESC(@"oolite-oxzmanager-heading-version"), 
								nil] forRow:OXZ_GUI_ROW_LISTHEAD];
	if (_offset > 0)
	{
		[gui setColor:[OOColor greenColor] forRow:OXZ_GUI_ROW_LISTPREV];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @"",@" <-- ", nil] forRow:OXZ_GUI_ROW_LISTPREV];
		[gui setKey:@"_BACK" forRow:OXZ_GUI_ROW_LISTPREV];
	}
	else
	{
		if ([gui selectedRow] == OXZ_GUI_ROW_LISTPREV)
		{
			[gui setSelectedRow:OXZ_GUI_ROW_LISTSTART];
		}
		[gui setText:@"" forRow:OXZ_GUI_ROW_LISTPREV align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:OXZ_GUI_ROW_LISTPREV];
	}
	if (_offset + OXZ_GUI_NUM_LISTROWS < [[self managedOXZs] count])
	{
		[gui setColor:[OOColor greenColor] forRow:OXZ_GUI_ROW_LISTNEXT];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @"",@" --> ", nil] forRow:OXZ_GUI_ROW_LISTNEXT];
		[gui setKey:@"_NEXT" forRow:OXZ_GUI_ROW_LISTNEXT];
	}
	else
	{
		if ([gui selectedRow] == OXZ_GUI_ROW_LISTNEXT)
		{
			[gui setSelectedRow:OXZ_GUI_ROW_LISTSTART];
		}
		[gui setText:@"" forRow:OXZ_GUI_ROW_LISTNEXT align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:OXZ_GUI_ROW_LISTNEXT];
	}

	// clear any previous longtext
	for (NSUInteger i = OXZ_GUI_ROW_LISTDESC; i < OXZ_GUI_ROW_INSTALL-1; i++)
	{
		[gui setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:i];
	}
	// and any previous listed entries
	for (NSUInteger i = OXZ_GUI_ROW_LISTSTART; i < OXZ_GUI_ROW_LISTNEXT; i++)
	{
		[gui setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[gui setKey:GUI_KEY_SKIP forRow:i];
	}


	OOGUIRow row = OXZ_GUI_ROW_LISTSTART;
	NSDictionary *manifest = nil;
	BOOL oxzSelected = NO;

	foreach (manifest, options)
	{

		[gui setArray:[NSArray arrayWithObjects:
								   [manifest oo_stringForKey:kOOManifestCategory defaultValue:DESC(@"oolite-oxzmanager-missing-field")],
							   [manifest oo_stringForKey:kOOManifestTitle defaultValue:DESC(@"oolite-oxzmanager-missing-field")],
							   [manifest oo_stringForKey:kOOManifestVersion defaultValue:DESC(@"oolite-oxzmanager-missing-field")],
									nil] forRow:row];
		NSString *identifier = [manifest oo_stringForKey:kOOManifestIdentifier];
		[gui setKey:identifier forRow:row];
		
		[gui setColor:[self colorForManifest:manifest] forRow:row];
		
		if (row == [gui selectedRow])
		{
			[gui setText:[self installStatusForManifest:manifest] forRow:OXZ_GUI_ROW_LISTSTATUS];
			[gui setColor:[OOColor greenColor] forRow:OXZ_GUI_ROW_LISTSTATUS];

			[gui addLongText:[[[manifest oo_stringForKey:kOOManifestDescription] componentsSeparatedByString:@"\n"] oo_stringAtIndex:0] startingAtRow:OXZ_GUI_ROW_LISTDESC align:GUI_ALIGN_LEFT];
			
			oxzSelected = YES;
		}
		row++;
	}

	if (!oxzSelected)
	{
		[gui addLongText:DESC(@"oolite-oxzmanager-remover-nonepicked") startingAtRow:OXZ_GUI_ROW_LISTDESC align:GUI_ALIGN_LEFT];
	}

	return startRow;	
}


- (void) showOptionsUpdate
{

	if (_interfaceState == OXZ_STATE_PICK_INSTALL)
	{
		[self setFilteredList:[self applyCurrentFilter:_oxzList]];
		[self showInstallOptions];
	}
	else if (_interfaceState == OXZ_STATE_PICK_INSTALLED)
	{
		[self setFilteredList:[self applyCurrentFilter:[self managedOXZs]]];
		[self showInstallOptions];
	}
	else if (_interfaceState == OXZ_STATE_PICK_REMOVE)
	{
		[self setFilteredList:[self applyCurrentFilter:[self managedOXZs]]];
		[self showRemoveOptions];
	}
	// else nothing necessary
}


- (void) showOptionsPrev
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_REMOVE || _interfaceState == OXZ_STATE_PICK_INSTALLED)
	{
		if ([gui selectedRow] == OXZ_GUI_ROW_LISTPREV)
		{
			[self processSelection];
		}
	}
}


- (void) processOptionsPrev
{
	if (_offset < OXZ_GUI_NUM_LISTROWS)  
	{
		_offset = 0;
	}
	else
	{
		_offset -= OXZ_GUI_NUM_LISTROWS;
	}
	[self showOptionsUpdate];
}


- (void) processOptionsNext
{
	if (_offset + OXZ_GUI_NUM_LISTROWS < [_filteredList count])
	{
		_offset += OXZ_GUI_NUM_LISTROWS;
	}
	[self showOptionsUpdate];
	return;
}


- (void) showOptionsNext
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_REMOVE || _interfaceState == OXZ_STATE_PICK_INSTALLED)
	{
		if ([gui selectedRow] == OXZ_GUI_ROW_LISTNEXT)
		{
			[self processSelection];
		}
	}
}


- (NSString *) extractOXZ:(NSUInteger)item
{
	NSFileManager *fmgr 			= [NSFileManager defaultManager];
	NSMutableString *extractionLog	= [[NSMutableString alloc] init];
	NSDictionary *manifest 			= [_filteredList oo_dictionaryAtIndex:item];
	NSString *version 				= [manifest oo_stringForKey:kOOManifestVersion];
	NSString *identifier 			= [manifest oo_stringForKey:kOOManifestIdentifier];
	NSString *path 					= [self extractionBasePathForIdentifier:identifier andVersion:version];

	// OXZ errors should really never happen unless someone is messing
	// directly with the managed folder while Oolite is running, but
	// it's possible.

	NSString *oxzfile = [manifest oo_stringForKey:kOOManifestFilePath];
	if (![fmgr fileExistsAtPath:oxzfile])
	{
		OOLog(kOOOXZErrorLog,@"OXZ %@ could not be found",oxzfile);
		[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-no-original")];
		return [extractionLog autorelease];
	}
	const char* zipname = [oxzfile UTF8String];
	unzFile uf = NULL;
	uf = unzOpen64(zipname);
	if (uf == NULL)
	{
		OOLog(kOOOXZErrorLog,@"Could not open .oxz at %@ as zip file",path);
		[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-bad-original")];
		return [extractionLog autorelease];
	}	

	if ([fmgr fileExistsAtPath:path])
	{
		OOLog(kOOOXZErrorLog,@"Path %@ already exists",path);
		[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-main-exists")];
		unzClose(uf);
		return [extractionLog autorelease];
	}
	if (![fmgr oo_createDirectoryAtPath:path attributes:nil])
	{
		OOLog(kOOOXZErrorLog,@"Path %@ could not be created",path);
		[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-main-unmakeable")];
		unzClose(uf);
		return [extractionLog autorelease];
	}
	[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-main-created")];
	NSUInteger counter = 0;
	char rawComponentName[512];
	BOOL error = NO;
	unz_file_info64 file_info = {0};
	if (unzGoToFirstFile(uf) == UNZ_OK)
	{
		do 
		{
			unzGetCurrentFileInfo64(uf, &file_info,
									rawComponentName, 512,
									NULL, 0,
									NULL, 0);
			NSString *componentName = [NSString stringWithUTF8String:rawComponentName];
			if ([componentName hasSuffix:@"/"])
			{
				// folder
				if (![fmgr oo_createDirectoryAtPath:[path stringByAppendingPathComponent:componentName] attributes:nil])
				{
					OOLog(kOOOXZErrorLog,@"Subpath %@ could not be created",componentName);
					[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-sub-failed")];
					error = YES;
					break;
				}
				else
				{
					OOLog(kOOOXZDebugLog,@"Subpath %@ created OK",componentName);
				}
			}
			else
			{
				// file
				// usually folder must now exist, but just in case...
				NSString *folder = [[path stringByAppendingPathComponent:componentName] stringByDeletingLastPathComponent];
				if ([folder length] > 0 && ![fmgr fileExistsAtPath:folder] && ![fmgr oo_createDirectoryAtPath:folder attributes:nil])
				{
					OOLog(kOOOXZErrorLog,@"Subpath %@ could not be created",folder);
					[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-sub-failed")];
					error = YES;
					break;
				}
				

				// This is less efficient in memory use than just
				// streaming out of the ZIP file onto disk
				// but it makes error handling easier
				NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
				NSData *tmp = [NSData oo_dataWithOXZFile:[oxzfile stringByAppendingPathComponent:componentName]];
				if (tmp == nil)
				{
					OOLog(kOOOXZErrorLog,@"Sub file %@ could not be extracted from the OXZ",componentName);
					[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-sub-failed")];
					error = YES;
					[pool release];
					break;
				}
				else
				{
					if (![tmp writeToFile:[path stringByAppendingPathComponent:componentName] atomically:YES])
					{
						OOLog(kOOOXZErrorLog,@"Sub file %@ could not be created",componentName);
						[extractionLog appendString:DESC(@"oolite-oxzmanager-extract-log-sub-failed")];
						error = YES;
						[pool release];
						break;
					}
					else
					{
						++counter;
					}
				}
				[pool release];

			}
		}
		while (unzGoToNextFile(uf) == UNZ_OK);
	}
	unzClose(uf);

	if (!error)
	{
		[extractionLog appendFormat:DESC(@"oolite-oxzmanager-extract-log-num-u-extracted"),counter];
		[extractionLog appendFormat:DESC(@"oolite-oxzmanager-extract-log-extracted-to-@"),path];
	}

	return [extractionLog autorelease];
}




- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	_downloadStatus = OXZ_DOWNLOAD_RECEIVING;
	OOLog(kOOOXZDebugLog, @"%@", @"Download receiving");
	_downloadExpected = [response expectedContentLength];
	_downloadProgress = 0;
	DESTROY(_fileWriter);
	[[NSFileManager defaultManager] createFileAtPath:[self downloadPath] contents:nil attributes:nil];
	_fileWriter = [[NSFileHandle fileHandleForWritingAtPath:[self downloadPath]] retain];
	if (_fileWriter == nil)
	{
		// file system is full or read-only or something
		OOLog(kOOOXZErrorLog, @"%@", @"Unable to create download file");
		[self cancelUpdate];
	}
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	OOLog(kOOOXZDebugLog,@"Downloaded %lu bytes",[data length]);
	[_fileWriter seekToEndOfFile];
	[_fileWriter writeData:data];
	_downloadProgress += [data length];
	[self gui]; // update GUI
#if OOLITE_WINDOWS
	/* Irritating fix to issue https://github.com/OoliteProject/oolite/issues/95
	 *
	 * The problem is that on MINGW, GNUStep makes all socket streams
	 * blocking, which causes problems with the run loop. Calling this
	 * method of the run loop forces it to execute all already
	 * scheduled items with a time in the past, before any more items
	 * are placed on it, which means that the main game update gets a
	 * chance to run.
	 *
	 * This stops the interface freezing - and Oolite appearing to
	 * have stopped responding to the OS - when downloading large
	 * (>20Mb) OXZ files.
	 *
	 * CIM 6 July 2014
	 */
	[[NSRunLoop currentRunLoop] limitDateForMode:NSDefaultRunLoopMode];
#endif
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	_downloadStatus = OXZ_DOWNLOAD_COMPLETE;
	OOLog(kOOOXZDebugLog, @"%@", @"Download complete");
	[_fileWriter synchronizeFile];
	[_fileWriter closeFile];
	DESTROY(_fileWriter);
	DESTROY(_currentDownload);
	if (_interfaceState == OXZ_STATE_UPDATING)
	{
		if (![self processDownloadedManifests])
		{
			_downloadStatus = OXZ_DOWNLOAD_ERROR;
		}
	}
	else if (_interfaceState == OXZ_STATE_INSTALLING)
	{
		if (![self processDownloadedOXZ])
		{
			_downloadStatus = OXZ_DOWNLOAD_ERROR;
		}
	}
	else
	{
		OOLog(kOOOXZErrorLog,@"Error: download completed in unexpected state %d. This is an internal error - please report it.",_interfaceState);
		_downloadStatus = OXZ_DOWNLOAD_ERROR;
	}
}


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	_downloadStatus = OXZ_DOWNLOAD_ERROR;
	OOLog(kOOOXZErrorLog,@"Error downloading file: %@",[error description]);
	[_fileWriter closeFile];
	DESTROY(_fileWriter);
	DESTROY(_currentDownload);
}




@end

/* Sort by category, then title, then version - and that should be unique */
NSComparisonResult oxzSort(id m1, id m2, void *context)
{
	NSComparisonResult result = [[m1 oo_stringForKey:kOOManifestCategory defaultValue:@"zz"] localizedCompare:[m2 oo_stringForKey:kOOManifestCategory defaultValue:@"zz"]];
	if (result == NSOrderedSame)
	{
		result = [[m1 oo_stringForKey:kOOManifestTitle defaultValue:@"zz"] localizedCompare:[m2 oo_stringForKey:kOOManifestTitle defaultValue:@"zz"]];
		if (result == NSOrderedSame)
		{
			result = [[m2 oo_stringForKey:kOOManifestVersion defaultValue:@"0"] localizedCompare:[m1 oo_stringForKey:kOOManifestVersion defaultValue:@"0"]];
		}
	}
	return result;
}
