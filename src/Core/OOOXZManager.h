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

#import "GuiDisplayGen.h"
#import "NSFileManagerOOExtensions.h"
#import "OOFoundation.h"
#import "OOOpenGL.h"
#import "OOTypes.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"

#include <cstdio>
#include <optional>
#include <string>
#include <vector>

namespace oo::http {
class Download;
}

typedef enum {
    OXZ_DOWNLOAD_NONE = 0,
    OXZ_DOWNLOAD_STARTED = 1,
    OXZ_DOWNLOAD_RECEIVING = 2,
    OXZ_DOWNLOAD_COMPLETE = 10,
    OXZ_DOWNLOAD_ERROR = 99
} OXZDownloadStatus;

typedef enum {
    OXZ_STATE_NODATA,
    OXZ_STATE_MAIN,
    OXZ_STATE_UPDATING,
    OXZ_STATE_PICK_INSTALL,
    OXZ_STATE_PICK_INSTALLED,
    OXZ_STATE_PICK_REMOVE,
    OXZ_STATE_INSTALLING,
    OXZ_STATE_DEPENDENCIES,
    OXZ_STATE_REMOVING,
    OXZ_STATE_TASKDONE,
    OXZ_STATE_RESTARTING,
    OXZ_STATE_SETFILTER,
    OXZ_STATE_EXTRACT,
    OXZ_STATE_EXTRACTDONE
} OXZInterfaceState;

@interface OOOXZManager : OOObject {
@private
    oo::PList _oxzList; // Array of manifests, sorted; null until a list is loaded
    oo::PList _managedList; // Array of the managed OXZs' manifests; null: to be rebuilt
    oo::PList _filteredList; // Array of the manifests on show
    std::string _currentFilter; // lowercase; "*" initially
    NSString* _currentOXPURL;

    OXZInterfaceState _interfaceState;
    BOOL _interfaceShowingOXZDetail;
    BOOL _changesMade;

    oo::http::Download* _currentDownload; // oofnd/Http.hpp; owned
    std::string _currentDownloadName;

    OXZDownloadStatus _downloadStatus;
    NSUInteger _downloadProgress;
    NSUInteger _downloadExpected;
    FILE* _fileWriter;
    NSUInteger _item;

    BOOL _downloadAllDependencies;

    NSUInteger _offset;

    std::string _progressStatus; // "" when there is none
    // Unique by oo::PList::operator==; "any" is front() (order-sensitive: named in commit).
    std::vector<oo::PList> _dependencyStack;
}

+ (OOOXZManager*)sharedManager;

- (std::optional<std::string>)installPath; // oo::ResourcePaths::managedAddOnsDirectory()
- (std::optional<std::string>)extractAddOnsPath; // oo::ResourcePaths::extractAddOnsDirectory()
- (std::vector<std::string>)additionalAddOnsPaths; // oo::ResourcePaths::additionalAddOnsDirectories()

- (BOOL)updateManifests;
- (BOOL)cancelUpdate;

/*	Deliver the current download's callbacks (response, data, finish, failure), in order,
        on the main thread: GameController's frame loop calls this where it pumps the run loop,
        which is where the old URL-connection callbacks were delivered. Proposed ADR-0044.
*/
- (void)processDownloadEvents;

- (oo::PList)manifests; // an Array, or null before a list is loaded
- (oo::PList)managedOXZs; // an Array

- (void)gui;
- (BOOL)isRestarting;
- (BOOL)isAcceptingTextInput;
- (BOOL)isAcceptingGUIInput;

- (void)processSelection;
- (void)processTextInput:(const std::string&)input;
- (void)refreshTextInput:(const std::string&)input;
- (void)processFilterKey;
- (void)processShowInfoKey;
- (void)processCopyUrlKey;
- (void)processExtractKey;
- (OOGUIRow)showInstallOptions;
- (OOGUIRow)showRemoveOptions;
- (void)showOptionsUpdate;
- (void)showOptionsPrev;
- (void)showOptionsNext;
- (void)processOptionsPrev;
- (void)processOptionsNext;

@end
