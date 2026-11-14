/*

ResourceManager+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-2wwr, made by chunk oo-3rb.98 and
extended by its later chunks). ResourceManager's Foundation-typed API as it was before its sweep,
with the same selector names and types, forwarding to the cxx_ API in ResourceManager.h. It exists
so that ResourceManager's callers compile unchanged; each caller moves to the cxx_ API in its own
sweep bead. When `git grep` finds no caller of anything declared here, the bridge bead deletes this
file, ResourceManager+FoundationBridge.mm, its line in Core/meson.build and the #import at the end
of ResourceManager.h. Never add to it outside the oo-2wwr chunks; never call it from migrated code.
oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors (ResourceManager.h)

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

// Imported only from the end of ResourceManager.h (which declares everything used here); never
// import it directly, and never import ResourceManager.h from it (a cycle).
#ifndef RESOURCEMANAGER_FOUNDATIONBRIDGE_H
#define RESOURCEMANAGER_FOUNDATIONBRIDGE_H

@interface ResourceManager (OOFoundationBridge)

// oo-3rb.98: search paths and add-on selection
+ (NSArray*)rootPaths; // -> +cxx_rootPaths
+ (NSArray*)userRootPaths; // -> +cxx_userRootPaths
+ (NSString*)builtInPath; // -> +cxx_builtInPath
+ (NSArray*)pathsWithAddOns; // -> +cxx_pathsWithAddOns
+ (NSArray*)paths; // -> +cxx_paths
+ (NSArray*)maskUserNameInPathArray:(NSArray*)inputPathArray; // -> +cxx_maskUserNameInPathArray:
+ (NSString*)maskUserName:(NSString*)name inPath:(NSString*)path; // -> +cxx_maskUserName:inPath:
+ (NSString*)useAddOns; // -> +cxx_useAddOns
+ (NSArray*)OXPsWithMessagesFound; // -> +cxx_OXPsWithMessagesFound
+ (void)setUseAddOns:(NSString*)useAddOns; // -> +cxx_setUseAddOns:
+ (void)addExternalPath:(NSString*)fileName; // -> +cxx_addExternalPath:
+ (NSEnumerator*)pathEnumerator; // no twin: range-for over +cxx_paths
+ (NSEnumerator*)reversePathEnumerator; // no twin: reverse range-for over +cxx_paths
+ (NSString*)errors; // -> +cxx_errors
+ (NSString*)diagnosticFileLocation; // -> +cxx_diagnosticFileLocation

// oo-3rb.99: OXP manifests and compatibility
+ (NSDictionary*)manifestForIdentifier:(NSString*)identifier; // -> +cxx_manifestForIdentifier:
+ (BOOL)checkVersionCompatibility:(NSDictionary*)manifest forOXP:(NSString*)title; // -> +cxx_checkVersionCompatibility:forOXP:
+ (BOOL)manifestHasConflicts:(NSDictionary*)manifest logErrors:(BOOL)logErrors; // -> +cxx_manifestHasConflicts:logErrors:
+ (BOOL)manifestHasMissingDependencies:(NSDictionary*)manifest logErrors:(BOOL)logErrors; // -> +cxx_manifestHasMissingDependencies:logErrors:
+ (BOOL)manifest:(NSDictionary*)manifest HasUnmetDependency:(NSDictionary*)required logErrors:(BOOL)logErrors; // -> +cxx_manifest:HasUnmetDependency:logErrors:
+ (BOOL)matchVersions:(NSDictionary*)rangeDict withVersion:(NSString*)version; // -> +cxx_matchVersions:withVersion:

// oo-3rb.101: merged plist loading
+ (BOOL)corePlist:(NSString*)fileName excludedAt:(NSString*)path; // -> +cxx_corePlist:excludedAt:

+ (NSDictionary*)dictionaryFromFilesNamed:(NSString*)fileName
                                 inFolder:(NSString*)folderName
                                 andMerge:(BOOL)mergeFiles; // -> +cxx_dictionaryFromFilesNamed:inFolder:andMerge:
+ (NSDictionary*)dictionaryFromFilesNamed:(NSString*)fileName
                                 inFolder:(NSString*)folderName
                                mergeMode:(OOResourceMergeMode)mergeMode
                                    cache:(BOOL)useCache; // -> +cxx_dictionaryFromFilesNamed:inFolder:mergeMode:cache:

+ (NSArray*)arrayFromFilesNamed:(NSString*)fileName
                       inFolder:(NSString*)folderName
                       andMerge:(BOOL)mergeFiles; // -> +cxx_arrayFromFilesNamed:inFolder:andMerge:
+ (NSArray*)arrayFromFilesNamed:(NSString*)fileName
                       inFolder:(NSString*)folderName
                       andMerge:(BOOL)mergeFiles
                          cache:(BOOL)useCache; // -> +cxx_arrayFromFilesNamed:inFolder:andMerge:cache:

+ (NSString*)stringFromFilesNamed:(NSString*)fileName inFolder:(NSString*)folderName; // -> +cxx_stringFromFilesNamed:inFolder:
+ (NSString*)stringFromFilesNamed:(NSString*)fileName inFolder:(NSString*)folderName cache:(BOOL)useCache; // -> +cxx_stringFromFilesNamed:inFolder:cache:

// oo-3rb.102: special dictionaries and scripts
+ (NSDictionary*)whitelistDictionary; // -> +cxx_whitelistDictionary
+ (NSDictionary*)shaderBindingTypesDictionary; // -> +cxx_shaderBindingTypesDictionary
+ (NSDictionary*)logControlDictionary; // -> +cxx_logControlDictionary
+ (NSDictionary*)roleCategoriesDictionary; // -> +cxx_roleCategoriesDictionary
+ (NSDictionary*)loadScripts; // -> +cxx_loadScripts
+ (NSDictionary*)materialDefaults; // -> +cxx_materialDefaults

// oo-3rb.103: file lookup, sounds and music, diagnostics
+ (NSString*)pathForFileNamed:(NSString*)fileName inFolder:(NSString*)folderName; // -> +cxx_pathForFileNamed:inFolder:
+ (NSString*)pathForFileNamed:(NSString*)fileName inFolder:(NSString*)folderName cache:(BOOL)useCache; // -> +cxx_pathForFileNamed:inFolder:cache:
+ (OOSound*)ooSoundNamed:(NSString*)fileName inFolder:(NSString*)folderName; // -> +cxx_ooSoundNamed:inFolder:
+ (OOMusic*)ooMusicNamed:(NSString*)fileName inFolder:(NSString*)folderName; // -> +cxx_ooMusicNamed:inFolder:
+ (BOOL)writeDiagnosticData:(NSData*)data toFileNamed:(NSString*)name; // -> +cxx_writeDiagnosticData:toFileNamed:
+ (BOOL)writeDiagnosticString:(NSString*)string toFileNamed:(NSString*)name; // -> +cxx_writeDiagnosticString:toFileNamed:
+ (BOOL)writeDiagnosticPList:(id)plist toFileNamed:(NSString*)name; // -> +cxx_writeDiagnosticPList:toFileNamed:

@end

#endif // RESOURCEMANAGER_FOUNDATIONBRIDGE_H
