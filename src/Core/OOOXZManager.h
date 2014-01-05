/*

OOOXZManager.h

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

#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "NSFileManagerOOExtensions.h"

typedef enum {
	OXZ_DOWNLOAD_NONE = 0,
	OXZ_DOWNLOAD_STARTED = 1,
	OXZ_DOWNLOAD_RECEIVING = 2,
	OXZ_DOWNLOAD_COMPLETE = 10,
	OXZ_DOWNLOAD_ERROR = 99
} OXZDownloadStatus;

#if 0
// TODO: this should check for Mac OS 10.7 or higher, and possibly later GNUStep
@interface OOOXZManager : NSObject <NSURLDownloadDelegate> 
#else
@interface OOOXZManager : NSObject
#endif
{
@private
	NSArray 			*_oxzList;
	BOOL				_updatingManifests;

	NSURLDownload		*_currentDownload;
	OXZDownloadStatus	_downloadStatus;
	NSUInteger			_downloadProgress;
	NSUInteger			_downloadExpected;
	

}

+ (OOOXZManager *) sharedManager;

- (BOOL) updateManifests;
- (BOOL) cancelUpdateManifests;




@end
