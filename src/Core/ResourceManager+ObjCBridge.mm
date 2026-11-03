/*

ResourceManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-jfno): the Objective-C ResourceManager facade. Every class
method of slice 1 forwards to the static member of cxx::ResourceManager in one line; the category
of slices 2-4 is in ResourceManager.mm. See ResourceManager+ObjCBridge.h.

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

#import "OOALMusic.h"
#import "OOScript.h"
#import "OOSystemDescriptionManager.h"
#import "ResourceManager.h"

@implementation ResourceManager

+ (void)reset
{
    cxx::ResourceManager::reset();
}

+ (void)resetManifestKnowledgeForOXZManager
{
    cxx::ResourceManager::resetManifestKnowledgeForOXZManager();
}

+ (std::vector<std::string>)cxx_rootPaths
{
    return cxx::ResourceManager::rootPaths();
}

+ (std::vector<std::string>)cxx_userRootPaths
{
    return cxx::ResourceManager::userRootPaths();
}

+ (std::optional<std::string>)cxx_builtInPath
{
    return cxx::ResourceManager::builtInPath();
}

+ (std::vector<std::string>)cxx_pathsWithAddOns
{
    return cxx::ResourceManager::pathsWithAddOns();
}

+ (std::vector<std::string>)cxx_paths
{
    return cxx::ResourceManager::paths();
}

+ (std::vector<std::string>)cxx_maskUserNameInPathArray:(const std::vector<std::string>&)inputPathArray
{
    return cxx::ResourceManager::maskUserNameInPathArray(inputPathArray);
}

+ (std::optional<std::string>)cxx_maskUserName:(const std::string&)name inPath:(const std::string&)path
{
    return cxx::ResourceManager::maskUserName(name, path);
}

+ (std::optional<std::string>)cxx_useAddOns
{
    return cxx::ResourceManager::useAddOns();
}

+ (std::vector<std::string>)cxx_OXPsWithMessagesFound
{
    return cxx::ResourceManager::OXPsWithMessagesFound();
}

+ (void)cxx_setUseAddOns:(const std::string&)useAddOns
{
    cxx::ResourceManager::setUseAddOns(useAddOns);
}

+ (void)cxx_addExternalPath:(const std::string&)fileName
{
    cxx::ResourceManager::addExternalPath(fileName);
}

+ (oo::PList)cxx_manifestForIdentifier:(const std::string&)identifier
{
    return cxx::ResourceManager::manifestForIdentifier(identifier);
}

+ (std::optional<std::string>)cxx_errors
{
    return cxx::ResourceManager::errors();
}

+ (void)clearCaches
{
    cxx::ResourceManager::clearCaches();
}

+ (BOOL)cxx_checkVersionCompatibility:(const oo::PList&)manifest forOXP:(const std::optional<std::string>&)title
{
    return cxx::ResourceManager::checkVersionCompatibility(manifest, title);
}

+ (BOOL)cxx_manifestHasConflicts:(const oo::PList&)manifest logErrors:(BOOL)logErrors
{
    return cxx::ResourceManager::manifestHasConflicts(manifest, logErrors);
}

+ (BOOL)cxx_manifestHasMissingDependencies:(const oo::PList&)manifest logErrors:(BOOL)logErrors
{
    return cxx::ResourceManager::manifestHasMissingDependencies(manifest, logErrors);
}

+ (BOOL)cxx_manifest:(const oo::PList&)manifest HasUnmetDependency:(const oo::PList&)required logErrors:(BOOL)logErrors
{
    return cxx::ResourceManager::manifest(manifest, required, logErrors);
}

+ (BOOL)cxx_matchVersions:(const oo::PList&)rangeDict withVersion:(const std::string&)version
{
    return cxx::ResourceManager::matchVersions(rangeDict, version);
}

+ (BOOL)cxx_corePlist:(const std::string&)fileName excludedAt:(const std::string&)path
{
    return cxx::ResourceManager::corePlist(fileName, path);
}

+ (oo::PList)cxx_dictionaryFromFilesNamed:(const std::string&)fileName
                                 inFolder:(const std::optional<std::string>&)folderName
                                 andMerge:(BOOL)mergeFiles
{
    return cxx::ResourceManager::dictionaryFromFilesNamed(fileName, folderName, mergeFiles);
}

+ (oo::PList)cxx_dictionaryFromFilesNamed:(const std::string&)fileName
                                 inFolder:(const std::optional<std::string>&)folderName
                                mergeMode:(OOResourceMergeMode)mergeMode
                                    cache:(BOOL)useCache
{
    return cxx::ResourceManager::dictionaryFromFilesNamed(fileName, folderName, mergeMode, useCache);
}

+ (oo::PList)cxx_arrayFromFilesNamed:(const std::string&)fileName
                            inFolder:(const std::optional<std::string>&)folderName
                            andMerge:(BOOL)mergeFiles
{
    return cxx::ResourceManager::arrayFromFilesNamed(fileName, folderName, mergeFiles);
}

+ (oo::PList)cxx_arrayFromFilesNamed:(const std::string&)fileName
                            inFolder:(const std::optional<std::string>&)folderName
                            andMerge:(BOOL)mergeFiles
                               cache:(BOOL)useCache
{
    return cxx::ResourceManager::arrayFromFilesNamed(fileName, folderName, mergeFiles, useCache);
}

+ (void)handleEquipmentListMerging:(oo::PList&)arrayToProcess forLookupIndex:(unsigned)lookupIndex
{
    cxx::ResourceManager::handleEquipmentListMerging(arrayToProcess, lookupIndex);
}

+ (void)handleEquipmentOverrides:(oo::PList&)arrayToProcess
{
    cxx::ResourceManager::handleEquipmentOverrides(arrayToProcess);
}

+ (void)handleStarNebulaListMerging:(oo::PList&)arrayToProcess
{
    cxx::ResourceManager::handleStarNebulaListMerging(arrayToProcess);
}

+ (oo::PList)cxx_whitelistDictionary
{
    return cxx::ResourceManager::whitelistDictionary();
}

+ (oo::PList)cxx_logControlDictionary
{
    return cxx::ResourceManager::logControlDictionary();
}

+ (oo::PList)cxx_roleCategoriesDictionary
{
    return cxx::ResourceManager::roleCategoriesDictionary();
}

+ (oo::Ref<OOSystemDescriptionManager>)systemDescriptionManager
{
    return cxx::ResourceManager::systemDescriptionManager();
}

+ (oo::PList)cxx_shaderBindingTypesDictionary
{
    return cxx::ResourceManager::shaderBindingTypesDictionary();
}

+ (std::optional<std::string>)cxx_pathForFileNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName
{
    return cxx::ResourceManager::pathForFileNamed(fileName, folderName);
}

+ (std::optional<std::string>)cxx_pathForFileNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName cache:(BOOL)useCache
{
    return cxx::ResourceManager::pathForFileNamed(fileName, folderName, useCache);
}

+ (OOSound*)cxx_ooSoundNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName
{
    return cxx::ResourceManager::ooSoundNamed(fileName, folderName);
}

+ (std::optional<std::string>)cxx_stringFromFilesNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName
{
    return cxx::ResourceManager::stringFromFilesNamed(fileName, folderName);
}

+ (std::optional<std::string>)cxx_stringFromFilesNamed:(const std::string&)fileName inFolder:(const std::optional<std::string>&)folderName cache:(BOOL)useCache
{
    return cxx::ResourceManager::stringFromFilesNamed(fileName, folderName, useCache);
}

+ (std::vector<std::pair<std::string, oo::Ref<OOScript>>>)cxx_loadScripts
{
    return cxx::ResourceManager::loadScripts();
}

+ (BOOL)cxx_writeDiagnosticData:(const oo::Data&)data toFileNamed:(const std::string&)name
{
    return cxx::ResourceManager::writeDiagnosticData(data, name);
}

+ (BOOL)cxx_writeDiagnosticString:(const std::string&)string toFileNamed:(const std::string&)name
{
    return cxx::ResourceManager::writeDiagnosticString(string, name);
}

+ (BOOL)cxx_writeDiagnosticPList:(const oo::PList&)plist toFileNamed:(const std::string&)name
{
    return cxx::ResourceManager::writeDiagnosticPList(plist, name);
}

+ (oo::PList)cxx_materialDefaults
{
    return cxx::ResourceManager::materialDefaults();
}

+ (std::optional<std::string>)cxx_diagnosticFileLocation
{
    return cxx::ResourceManager::diagnosticFileLocation();
}

@end
