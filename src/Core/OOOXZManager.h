/*

OOOXZManager.h

Responsible for installing and uninstalling OXZs

A singleton: the callers (GameController, PlayerEntity, PlayerEntityControls)
call OOOXZManager::sharedManager().

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

#include <cstdio>
#include <optional>
#include <string>
#include <vector>

#include "GuiDisplayGen.h"
#include "OOColor.h"
#include "OOEnumFlags.h"
#include "OOFoundation.h"
#include "OOOpenGL.h"
#include "OOTypes.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObject.h"

namespace oo::http {
class Download;
}

enum class OXZDownloadStatus : std::int32_t {
  kNone = 0,
  kStarted = 1,
  kReceiving = 2,
  kComplete = 10,
  kError = 99,
};
static_assert(static_cast<std::int32_t>(OXZDownloadStatus::kNone) == 0);
static_assert(static_cast<std::int32_t>(OXZDownloadStatus::kStarted) == 1);
static_assert(static_cast<std::int32_t>(OXZDownloadStatus::kReceiving) == 2);
static_assert(static_cast<std::int32_t>(OXZDownloadStatus::kComplete) == 10);
static_assert(static_cast<std::int32_t>(OXZDownloadStatus::kError) == 99);

enum class OXZInterfaceState : std::int32_t {
  kNoData,
  kMain,
  kUpdating,
  kPickInstall,
  kPickInstalled,
  kPickRemove,
  kInstalling,
  kDependencies,
  kRemoving,
  kTaskdone,
  kRestarting,
  kSetfilter,
  kExtract,
  kExtractdone,
};
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kNoData) == 0);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kMain) == 1);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kUpdating) == 2);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kPickInstall) == 3);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kPickInstalled) ==
              4);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kPickRemove) == 5);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kInstalling) == 6);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kDependencies) == 7);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kRemoving) == 8);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kTaskdone) == 9);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kRestarting) == 10);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kSetfilter) == 11);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kExtract) == 12);
static_assert(static_cast<std::int32_t>(OXZInterfaceState::kExtractdone) == 13);

// What a manifest's OXZ can do here (installableState()). (a member's result).
enum class OXZInstallableState : std::int32_t {
  kInstallableOkay,
  kInstallableUpdate,
  kInstallableDependencies,
  kInstallableConflicts,
  // for things to work, _ALREADY must be the first UNINSTALLABLE state
  // and all the INSTALLABLE ones must be before all the UNINSTALLABLE ones
  kUninstallableAlready,
  kUninstallableNoremote,
  kUninstallableVersion,
  kUninstallableManual,
};
static_assert(
    static_cast<std::int32_t>(OXZInstallableState::kInstallableOkay) == 0);
static_assert(
    static_cast<std::int32_t>(OXZInstallableState::kInstallableUpdate) == 1);
static_assert(static_cast<std::int32_t>(
                  OXZInstallableState::kInstallableDependencies) == 2);
static_assert(
    static_cast<std::int32_t>(OXZInstallableState::kInstallableConflicts) == 3);
static_assert(
    static_cast<std::int32_t>(OXZInstallableState::kUninstallableAlready) == 4);
static_assert(static_cast<std::int32_t>(
                  OXZInstallableState::kUninstallableNoremote) == 5);
static_assert(
    static_cast<std::int32_t>(OXZInstallableState::kUninstallableVersion) == 6);
static_assert(
    static_cast<std::int32_t>(OXZInstallableState::kUninstallableManual) == 7);

class OOOXZManager : public oo::RefCounted {
 public:
  // The shared manager, made on first use; borrowed, never released.
  static OOOXZManager* sharedManager();

  ~OOOXZManager();

  std::optional<std::string>
  installPath();  // oo::ResourcePaths::managedAddOnsDirectory()
  std::optional<std::string>
  extractAddOnsPath();  // oo::ResourcePaths::extractAddOnsDirectory()
  std::vector<std::string>
  additionalAddOnsPaths();  // oo::ResourcePaths::additionalAddOnsDirectories()

  bool updateManifests();
  bool cancelUpdate();

  /*	Deliver the current download's callbacks (response, data, finish,
     failure), in order, on the main thread: GameController's frame loop calls
     this where it pumps the run loop, which is where the old URL-connection
     callbacks were delivered.
  */
  void processDownloadEvents();

  oo::PList manifests();    // an Array, or null before a list is loaded
  oo::PList managedOXZs();  // an Array

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

  // Internal: public for the unit test, which calls them and sets the state
  // below.
  std::optional<std::string> manifestPath();  // nullopt: no cache directory
  std::optional<std::string> downloadPath();  // nullopt: no cache directory
  std::optional<std::string> extractionBasePathForIdentifier(
      const std::string& identifier,
      const std::string& version);  // nullopt: no user root
  std::optional<std::string> dataURL();
  std::optional<std::string> humanSize(
      std::size_t bytes);  // nullopt: the missing-field description is missing

  bool ensureInstallPath();

  bool beginDownload(const std::string& url);
  bool processDownloadedManifests();
  bool processDownloadedOXZ();

  oo::PList installedManifestForIdentifier(
      const std::string& identifier);  // null: not installed
  OXZInstallableState installableState(const oo::PList& manifest);
  std::shared_ptr<OOColor> colorForManifest(const oo::PList& manifest);
  std::optional<std::string> installStatusForManifest(
      const oo::PList& manifest);  // nullopt: its description is missing

  bool installOXZ(std::size_t item);
  bool updateAllOXZ();
  bool removeOXZ(std::size_t item);

  std::string extractOXZ(std::size_t item);  // the extraction log

  std::vector<oo::PList> installOptions();  // the manifests on the current page
  std::vector<oo::PList> removeOptions();  // empty: nothing removable (was nil)

  bool validateFilter(const std::string& input);

  void setOXZList(const oo::PList& list);  // an Array (sorted here), or null
  void setFilteredList(const oo::PList& list);
  void setFilter(const std::string& filter);
  void setOXPURL(const std::optional<std::string>&
                     url);  // lowercased; nullopt: none (was nil)
  oo::PList applyCurrentFilter(const oo::PList& list);  // an Array

  void setCurrentDownload(oo::http::Download* download,
                          const std::string& label);
  void setProgressStatus(const std::string& newValue);

  /* The download's callbacks (HTTP client events) */
  void downloadDidFailWithError(const std::string& error);
  void downloadDidReceiveResponse(long long expectedContentLength);
  void downloadDidReceiveData(const std::string& data);
  void downloadDidFinishLoading();

  // (OOFilterRules)
  bool applyFilterByNoFilter(const oo::PList& manifest);
  bool applyFilterByUpdateRequired(const oo::PList& manifest);
  bool applyFilterByInstallable(const oo::PList& manifest);
  bool applyFilterByKeyword(const oo::PList& manifest,
                            const std::string& keyword);
  bool applyFilterByAuthor(const oo::PList& manifest,
                           const std::string& author);
  bool applyFilterByDays(const oo::PList& manifest, const std::string& days);
  bool applyFilterByTag(const oo::PList& manifest, const std::string& tag);
  bool applyFilterByCategory(const oo::PList& manifest,
                             const std::string& category);

  oo::PList
      _oxzList;  // Array of manifests, sorted; null until a list is loaded
  oo::PList _managedList;   // Array of the managed OXZs' manifests; null: to be
                            // rebuilt
  oo::PList _filteredList;  // Array of the manifests on show
  std::string _currentFilter;                 // lowercase; "*" initially
  std::optional<std::string> _currentOXPURL;  // lowercase; the info page's URL,
                                              // nullopt: none (was nil)

  OXZInterfaceState _interfaceState = {};
  bool _interfaceShowingOXZDetail = {};
  bool _changesMade = {};

  std::string _currentDownloadName;

  OXZDownloadStatus _downloadStatus = {};
  std::size_t _downloadProgress = {};
  std::size_t _downloadExpected = {};
  std::size_t _item = {};

  bool _downloadAllDependencies = {};

  std::size_t _offset = {};

  std::string _progressStatus;  // "" when there is none
  // Unique by oo::PList::operator==; "any" is front() (order-sensitive: named
  // in commit).
  std::vector<oo::PList> _dependencyStack;

 private:
  void init();  // -init's body: run by sharedManager() on the new object

  oo::http::Download* _currentDownload = {};  // oofnd/Http.hpp; owned
  FILE* _fileWriter = {};
};
