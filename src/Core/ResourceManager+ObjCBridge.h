/*

ResourceManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-jfno): the Objective-C ResourceManager, a facade over the
C++ cxx::ResourceManager (ResourceManager.h), for the code that is not converted yet: the game's
many callers, which send it class methods, and the methods of slices 2-4 of
docs/phases/3-slices/ResourceManager.md (OXP manifests, plist loading and merging, single-file
lookups), which are still Objective-C, a category of this facade in ResourceManager.mm (ADR-0056
amendment oo-3bgz). Its interface is the one ResourceManager.h declared before the conversion,
copied exactly (same selectors, same types); the selectors of slices 2-4 are declared in the
category ResourceManager (OOResourceManagerUnconverted) that implements them (proposed amendment
oo-2g51 item 1). Each class method of slice 1 forwards to the static member of the same name.
The class is never made, so there is nothing to cross: no oo::ToObjC / oo::ToCxx. Imported as the
last line of ResourceManager.h; do not import it directly.

        a caller that is                       calls
        -------------------------------------  ----------------------------------------------------
        still Objective-C                      [ResourceManager ...] (this facade), as before
        converted (C++)                        cxx::ResourceManager::...() (slice 1's members), or
                                               [::ResourceManager ...] for slices 2-4 until they convert

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside ResourceManager.* names the Objective-C class.

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

#ifndef RESOURCEMANAGER_OBJCBRIDGE_H
#define RESOURCEMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface ResourceManager : OOObject

+ (void)reset;
+ (void)resetManifestKnowledgeForOXZManager;

+ (std::vector<std::string>)cxx_rootPaths; // Places add-ons are searched for, not including add-on paths.
+ (std::vector<std::string>)cxx_userRootPaths; // Places users are expected to place add-ons, not including built-in data or managed add-ons directory.
+ (std::optional<std::string>)cxx_builtInPath; // Path for built-in data only.
+ (std::vector<std::string>)cxx_pathsWithAddOns; // Root paths + add-on paths.
+ (std::vector<std::string>)cxx_paths; // builtInPath or pathsWithAddOns, depending on useAddOns state.
+ (std::vector<std::string>)cxx_maskUserNameInPathArray:(const std::vector<std::string>&)inputPathArray; // potential privacy concerns
+ (std::optional<std::string>)cxx_maskUserName:(const std::string&)name inPath:(const std::string&)path;
+ (std::optional<std::string>)cxx_useAddOns; // nullopt before the first scan (was nil)
+ (std::vector<std::string>)cxx_OXPsWithMessagesFound;
+ (void)cxx_setUseAddOns:(const std::string&)useAddOns;
+ (void)cxx_addExternalPath:(const std::string&)fileName;

// get manifest data for identifier (a null PList when there is none)
+ (oo::PList)cxx_manifestForIdentifier:(const std::string&)identifier;

+ (std::optional<std::string>)cxx_errors; // Errors which occurred during path scanning - essentially a list of OXPs whose requires.plist is bad. nullopt when there are none.

// Clear ResourceManager-internal caches (not those handled by OOCacheManager)
+ (void)clearCaches;

// compatibility checks (a manifest or relation is a Dict; title is nullopt where nil was passed)
+ (BOOL)cxx_checkVersionCompatibility:(const oo::PList&)manifest forOXP:(const std::optional<std::string>&)title;
+ (BOOL)cxx_manifestHasConflicts:(const oo::PList&)manifest logErrors:(BOOL)logErrors;
+ (BOOL)cxx_manifestHasMissingDependencies:(const oo::PList&)manifest logErrors:(BOOL)logErrors;
+ (BOOL)cxx_manifest:(const oo::PList&)manifest HasUnmetDependency:(const oo::PList&)required logErrors:(BOOL)logErrors;
+ (BOOL)cxx_matchVersions:(const oo::PList&)rangeDict withVersion:(const std::string&)version;

+ (BOOL)cxx_corePlist:(const std::string&)fileName excludedAt:(const std::string&)path;

// A null PList when no file was found; folderName nullopt where nil was passed.
+ (oo::PList)cxx_dictionaryFromFilesNamed:(const std::string&)fileName
                                 inFolder:(const std::optional<std::string>&)folderName
                                 andMerge:(BOOL)mergeFiles;
+ (oo::PList)cxx_dictionaryFromFilesNamed:(const std::string&)fileName
                                 inFolder:(const std::optional<std::string>&)folderName
                                mergeMode:(OOResourceMergeMode)mergeMode
                                    cache:(BOOL)useCache;

+ (oo::PList)cxx_arrayFromFilesNamed:(const std::string&)fileName
                            inFolder:(const std::optional<std::string>&)folderName
                            andMerge:(BOOL)mergeFiles;
+ (oo::PList)cxx_arrayFromFilesNamed:(const std::string&)fileName
                            inFolder:(const std::optional<std::string>&)folderName
                            andMerge:(BOOL)mergeFiles
                               cache:(BOOL)useCache;

// In-out: an array of arrays (the merged files), edited in place.
+ (void)handleEquipmentListMerging:(oo::PList&)arrayToProcess forLookupIndex:(unsigned)lookupIndex;
+ (void)handleEquipmentOverrides:(oo::PList&)arrayToProcess;
+ (void)handleStarNebulaListMerging:(oo::PList&)arrayToProcess;
+ (oo::PList)cxx_whitelistDictionary; // a null PList when the file is missing
+ (oo::PList)cxx_logControlDictionary;
+ (oo::PList)cxx_roleCategoriesDictionary; // category -> array of its roles, each once (a set), in first-seen order

+ (OOSystemDescriptionManager*)systemDescriptionManager;
// These are deliberately not merged like normal plists for security reasons.
+ (oo::PList)cxx_shaderBindingTypesDictionary;
// nullopt when not found (was nil); folderName nullopt where nil was passed.
+ (std::optional<std::string>)cxx_pathForFileNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName;
+ (std::optional<std::string>)cxx_pathForFileNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName cache:(BOOL)useCache;
+ (OOMusic*)cxx_ooMusicNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName;
+ (OOSound*)cxx_ooSoundNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName;
// nullopt when no file was found (was nil); folderName nullopt where nil was passed.
+ (std::optional<std::string>)cxx_stringFromFilesNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName;
+ (std::optional<std::string>)cxx_stringFromFilesNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName cache:(BOOL)useCache;
// World scripts by name, in the order each name was first loaded.
+ (std::vector<std::pair<std::string, oo::ObjCRef<OOScript*>>>)cxx_loadScripts;
/*	+cxx_writeDiagnosticData:toFileNamed:
        +cxx_writeDiagnosticString:toFileNamed:
        +cxx_writeDiagnosticPList:toFileNamed:

        Write data to the specified path within the log directory. Slashes may be
        used as path separators in name.
 */
+ (BOOL)cxx_writeDiagnosticData:(const oo::Data&)data toFileNamed:(const std::string&)name;
+ (BOOL)cxx_writeDiagnosticString:(const std::string&)string toFileNamed:(const std::string&)name;
+ (BOOL)cxx_writeDiagnosticPList:(const oo::PList&)plist toFileNamed:(const std::string&)name;
+ (oo::PList)cxx_materialDefaults;
+ (std::optional<std::string>)cxx_diagnosticFileLocation;

@end

#endif // RESOURCEMANAGER_OBJCBRIDGE_H
