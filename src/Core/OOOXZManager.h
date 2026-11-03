/*

OOOXZManager.h

Responsible for installing and uninstalling OXZs

C++20 since bead oo-bwjb, slice 1 of docs/phases/3-slices/OOOXZManager.md (proposed ADR-0056: a
singleton, amendment oo-r7m0; a class-shell slice, amendment oo-pni4); slices 2 to 4 (beads oo-0hyr,
oo-q7r3, oo-qbgo) converted the rest of the file. Its Objective-C facade was deleted by bead
oo-9ht.131: the callers (GameController, PlayerEntity, PlayerEntityControls) call
OOOXZManager::sharedManager(), and the class left namespace cxx.

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

#pragma once

#include "GuiDisplayGen.h"
#include "OOColor.h"
#include "OOFoundation.h"
#include "OOOpenGL.h"
#include "OOTypes.h"
#include "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

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

// What a manifest's OXZ can do here (installableState()). Moved from OOOXZManager.mm by bead oo-0hyr
// (a member's result; ADR-0056 amendment oo-pni4 item 2).
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

class OOOXZManager : public oo::RefCounted {
public:
    // The shared manager, made on first use; borrowed, never released (proposed ADR-0056
    // amendment oo-r7m0).
    static OOOXZManager* sharedManager();

    ~OOOXZManager();

    std::optional<std::string> installPath(); // oo::ResourcePaths::managedAddOnsDirectory()
    std::optional<std::string> extractAddOnsPath(); // oo::ResourcePaths::extractAddOnsDirectory()
    std::vector<std::string> additionalAddOnsPaths(); // oo::ResourcePaths::additionalAddOnsDirectories()

    bool updateManifests();
    bool cancelUpdate();

    /*	Deliver the current download's callbacks (response, data, finish, failure), in order,
            on the main thread: GameController's frame loop calls this where it pumps the run loop,
            which is where the old URL-connection callbacks were delivered. Proposed ADR-0044.
    */
    void processDownloadEvents();

    oo::PList manifests(); // an Array, or null before a list is loaded
    oo::PList managedOXZs(); // an Array

    bool isRestarting();

    void gui();
    bool isAcceptingTextInput();
    bool isAcceptingGUIInput();

    void processSelection();
    void processTextInput(const std::string& input);
    void refreshTextInput(const std::string& input);
    void processFilterKey();
    void processShowInfoKey();
    void processCopyUrlKey();
    void processExtractKey();
    OOGUIRow showInstallOptions();
    OOGUIRow showRemoveOptions();
    void showOptionsUpdate();
    void showOptionsPrev();
    void showOptionsNext();
    void processOptionsPrev();
    void processOptionsNext();

    // Internal (the OOPrivate and OOFilterRules categories): public for the unit test, which calls
    // them and sets the state below, and for the facade's forwards; private once the facade is
    // deleted and the test reaches them otherwise.
    std::optional<std::string> manifestPath(); // nullopt: no cache directory
    std::optional<std::string> downloadPath(); // nullopt: no cache directory
    std::optional<std::string> extractionBasePathForIdentifier(const std::string& identifier, const std::string& version); // nullopt: no user root
    std::optional<std::string> dataURL();
    std::optional<std::string> humanSize(NSUInteger bytes); // nullopt: the missing-field description is missing

    bool ensureInstallPath();

    bool beginDownload(const std::string& url);
    bool processDownloadedManifests();
    bool processDownloadedOXZ();

    oo::PList installedManifestForIdentifier(const std::string& identifier); // null: not installed
    OXZInstallableState installableState(const oo::PList& manifest);
    oo::Ref<OOColor> colorForManifest(const oo::PList& manifest);
    std::optional<std::string> installStatusForManifest(const oo::PList& manifest); // nullopt: its description is missing

    bool installOXZ(NSUInteger item);
    bool updateAllOXZ();
    bool removeOXZ(NSUInteger item);

    std::string extractOXZ(NSUInteger item); // the extraction log

    std::vector<oo::PList> installOptions(); // the manifests on the current page
    std::vector<oo::PList> removeOptions(); // empty: nothing removable (was nil)

    bool validateFilter(const std::string& input);

    void setOXZList(const oo::PList& list); // an Array (sorted here), or null
    void setFilteredList(const oo::PList& list);
    void setFilter(const std::string& filter);
    void setOXPURL(const std::optional<std::string>& url); // lowercased; nullopt: none (was nil)
    oo::PList applyCurrentFilter(const oo::PList& list); // an Array

    void setCurrentDownload(oo::http::Download* download, const std::string& label);
    void setProgressStatus(const std::string& newValue);

    /* The download's callbacks (HTTP client events until proposed ADR-0044) */
    void downloadDidFailWithError(const std::string& error);
    void downloadDidReceiveResponse(long long expectedContentLength);
    void downloadDidReceiveData(const std::string& data);
    void downloadDidFinishLoading();

    // (OOFilterRules)
    bool applyFilterByNoFilter(const oo::PList& manifest);
    bool applyFilterByUpdateRequired(const oo::PList& manifest);
    bool applyFilterByInstallable(const oo::PList& manifest);
    bool applyFilterByKeyword(const oo::PList& manifest, const std::string& keyword);
    bool applyFilterByAuthor(const oo::PList& manifest, const std::string& author);
    bool applyFilterByDays(const oo::PList& manifest, const std::string& days);
    bool applyFilterByTag(const oo::PList& manifest, const std::string& tag);
    bool applyFilterByCategory(const oo::PList& manifest, const std::string& category);

    oo::PList _oxzList; // Array of manifests, sorted; null until a list is loaded
    oo::PList _managedList; // Array of the managed OXZs' manifests; null: to be rebuilt
    oo::PList _filteredList; // Array of the manifests on show
    std::string _currentFilter; // lowercase; "*" initially
    std::optional<std::string> _currentOXPURL; // lowercase; the info page's URL, nullopt: none (was nil)

    OXZInterfaceState _interfaceState = { };
    bool _interfaceShowingOXZDetail = { };
    bool _changesMade = { };

    std::string _currentDownloadName;

    OXZDownloadStatus _downloadStatus = { };
    NSUInteger _downloadProgress = { };
    NSUInteger _downloadExpected = { };
    NSUInteger _item = { };

    bool _downloadAllDependencies = { };

    NSUInteger _offset = { };

    std::string _progressStatus; // "" when there is none
    // Unique by oo::PList::operator==; "any" is front() (order-sensitive: named in commit).
    std::vector<oo::PList> _dependencyStack;

private:
    void init(); // -init's body: run by sharedManager() on the new object

    oo::http::Download* _currentDownload = { }; // oofnd/Http.hpp; owned
    FILE* _fileWriter = { };
};
