/*

ResourceManager+FoundationBridge.mm

TRANSITIONAL: see ResourceManager+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts the result exactly as the old method produced it (nil for nil, immutable collections).

*/

#import "OOCacheManager.h"
#import "OOFoundationBridge.h"
#import "ResourceManager.h" // declares the bridge category at its end

/*	The loaders' cache keys (the same text +cxx_dictionaryFromFilesNamed:... and
        +cxx_arrayFromFilesNamed:... build). With cache:YES the old methods returned the object held in
        OOCacheManager, the same object on every call; the bridge returns that object too (for arrays,
        the fresh +arrayWithArray: copy of it the old method made), so a cached load is never rebuilt
        as a Foundation graph per call, and the cache's own clearing drops it.
*/
namespace {

NSString* DictionaryCacheKey(NSString* fileName, NSString* folderName, OOResourceMergeMode mergeMode)
{
    NSString* mergeType = nil;
    switch (mergeMode) {
    case MERGE_NONE:
        mergeType = @"none";
        break;
    case MERGE_BASIC:
        mergeType = @"basic";
        break;
    case MERGE_SMART:
        mergeType = @"smart";
        break;
    }
    if (mergeType == nil)
        return nil;
    if (folderName != nil)
        return [NSString stringWithFormat:@"%@/%@ merge:%@", folderName, fileName, mergeType];
    return [NSString stringWithFormat:@"%@ merge:%@", fileName, mergeType];
}

NSString* ArrayCacheKey(NSString* fileName, NSString* folderName, BOOL mergeFiles)
{
    return [NSString stringWithFormat:@"%@%@ merge:%@", (folderName != nil) ? [folderName stringByAppendingString:@"/"] : (NSString*)@"", fileName, mergeFiles ? @"yes" : @"no"];
}

} // namespace

@implementation ResourceManager (OOFoundationBridge)

// oo-3rb.98: search paths and add-on selection

+ (NSArray*)rootPaths
{
    return oo::NSArrayFromStrings([self cxx_rootPaths]);
}

+ (NSArray*)userRootPaths
{
    return oo::NSArrayFromStrings([self cxx_userRootPaths]);
}

+ (NSString*)builtInPath
{
    return oo::NSStringOrNil([self cxx_builtInPath]);
}

+ (NSArray*)pathsWithAddOns
{
    return oo::NSArrayFromStrings([self cxx_pathsWithAddOns]);
}

+ (NSArray*)paths
{
    return oo::NSArrayFromStrings([self cxx_paths]);
}

+ (NSArray*)maskUserNameInPathArray:(NSArray*)inputPathArray
{
    return oo::NSArrayFromStrings([self cxx_maskUserNameInPathArray:oo::StringsFrom(inputPathArray)]);
}

+ (NSString*)maskUserName:(NSString*)name inPath:(NSString*)path
{
    return oo::NSStringOrNil([self cxx_maskUserName:oo::StdString(name) inPath:oo::StdString(path)]);
}

+ (NSString*)useAddOns
{
    return oo::NSStringOrNil([self cxx_useAddOns]);
}

+ (NSArray*)OXPsWithMessagesFound
{
    const std::vector<std::string> found = [self cxx_OXPsWithMessagesFound];
    if (found.empty())
        return nil; // the array was created by the first message
    return oo::NSArrayFromStrings(found);
}

+ (void)setUseAddOns:(NSString*)useAddOns
{
    [self cxx_setUseAddOns:oo::StdString(useAddOns)];
}

+ (void)addExternalPath:(NSString*)fileName
{
    [self cxx_addExternalPath:oo::StdString(fileName)];
}

+ (NSEnumerator*)pathEnumerator
{
    return [oo::NSArrayFromStrings([self cxx_paths]) objectEnumerator];
}

+ (NSEnumerator*)reversePathEnumerator
{
    return [oo::NSArrayFromStrings([self cxx_paths]) reverseObjectEnumerator];
}

+ (NSString*)errors
{
    return oo::NSStringOrNil([self cxx_errors]);
}

+ (NSString*)diagnosticFileLocation
{
    return oo::NSStringOrNil([self cxx_diagnosticFileLocation]);
}

// oo-3rb.99: OXP manifests and compatibility

+ (NSDictionary*)manifestForIdentifier:(NSString*)identifier
{
    // The manifest as a Foundation graph (nil when there is none); its required_by set is an array.
    return oo::ObjectFromPList([self cxx_manifestForIdentifier:oo::StdString(identifier)]);
}

+ (BOOL)checkVersionCompatibility:(NSDictionary*)manifest forOXP:(NSString*)title
{
    return [self cxx_checkVersionCompatibility:oo::PListFrom(manifest) forOXP:oo::OptionalString(title)];
}

+ (BOOL)manifestHasConflicts:(NSDictionary*)manifest logErrors:(BOOL)logErrors
{
    return [self cxx_manifestHasConflicts:oo::PListFrom(manifest) logErrors:logErrors];
}

+ (BOOL)manifestHasMissingDependencies:(NSDictionary*)manifest logErrors:(BOOL)logErrors
{
    return [self cxx_manifestHasMissingDependencies:oo::PListFrom(manifest) logErrors:logErrors];
}

+ (BOOL)manifest:(NSDictionary*)manifest HasUnmetDependency:(NSDictionary*)required logErrors:(BOOL)logErrors
{
    return [self cxx_manifest:oo::PListFrom(manifest) HasUnmetDependency:oo::PListFrom(required) logErrors:logErrors];
}

+ (BOOL)matchVersions:(NSDictionary*)rangeDict withVersion:(NSString*)version
{
    return [self cxx_matchVersions:oo::PListFrom(rangeDict) withVersion:oo::StdString(version)];
}

// oo-3rb.101: merged plist loading

+ (BOOL)corePlist:(NSString*)fileName excludedAt:(NSString*)path
{
    if (path == nil || fileName == nil)
        return NO; // messaging nil answered NO: not excluded
    return [self cxx_corePlist:oo::StdString(fileName) excludedAt:oo::StdString(path)];
}

+ (NSDictionary*)dictionaryFromFilesNamed:(NSString*)fileName
                                 inFolder:(NSString*)folderName
                                 andMerge:(BOOL)mergeFiles
{
    return [self dictionaryFromFilesNamed:fileName inFolder:folderName mergeMode:mergeFiles ? MERGE_BASIC : MERGE_NONE cache:YES];
}

+ (NSDictionary*)dictionaryFromFilesNamed:(NSString*)fileName
                                 inFolder:(NSString*)folderName
                                mergeMode:(OOResourceMergeMode)mergeMode
                                    cache:(BOOL)useCache
{
    if (fileName == nil)
        return nil;

    NSString* cacheKey = useCache ? DictionaryCacheKey(fileName, folderName, mergeMode) : nil;
    OOCacheManager* cacheMgr = [OOCacheManager sharedCache];
    if (cacheKey != nil) {
        id cached = [cacheMgr objectForKey:cacheKey inCache:@"dictionaries"];
        if (cached != nil)
            return cached;
    }

    const oo::PList result = [self cxx_dictionaryFromFilesNamed:oo::StdString(fileName) inFolder:oo::OptionalString(folderName) mergeMode:mergeMode cache:useCache];
    if (cacheKey != nil) {
        id cached = [cacheMgr objectForKey:cacheKey inCache:@"dictionaries"]; // what the load just cached
        if (cached != nil)
            return cached;
    }
    return oo::ObjectFromPList(result);
}

+ (NSArray*)arrayFromFilesNamed:(NSString*)fileName
                       inFolder:(NSString*)folderName
                       andMerge:(BOOL)mergeFiles
{
    return [self arrayFromFilesNamed:fileName inFolder:folderName andMerge:mergeFiles cache:YES];
}

+ (NSArray*)arrayFromFilesNamed:(NSString*)fileName
                       inFolder:(NSString*)folderName
                       andMerge:(BOOL)mergeFiles
                          cache:(BOOL)useCache
{
    if (fileName == nil)
        return nil;

    NSString* cacheKey = useCache ? ArrayCacheKey(fileName, folderName, mergeFiles) : nil;
    OOCacheManager* cacheMgr = [OOCacheManager sharedCache];
    if (cacheKey != nil) {
        id cached = [cacheMgr objectForKey:cacheKey inCache:@"arrays"];
        if (cached != nil)
            return [NSArray arrayWithArray:cached];
    }

    const oo::PList result = [self cxx_arrayFromFilesNamed:oo::StdString(fileName) inFolder:oo::OptionalString(folderName) andMerge:mergeFiles cache:useCache];
    if (cacheKey != nil) {
        id cached = [cacheMgr objectForKey:cacheKey inCache:@"arrays"]; // what the load just cached
        if (cached != nil)
            return [NSArray arrayWithArray:cached];
    }
    // No file to merge was nil; a missing unmerged array went through +arrayWithArray: of nil, an empty array.
    if (result.isNull() && mergeFiles)
        return nil;
    return [NSArray arrayWithArray:oo::ObjectFromPList(result)];
}

+ (NSString*)stringFromFilesNamed:(NSString*)fileName inFolder:(NSString*)folderName
{
    return [self stringFromFilesNamed:fileName inFolder:folderName cache:YES];
}

+ (NSString*)stringFromFilesNamed:(NSString*)fileName inFolder:(NSString*)folderName cache:(BOOL)useCache
{
    if (fileName == nil)
        return nil; // no path was found for a nil name
    return oo::NSStringOrNil([self cxx_stringFromFilesNamed:oo::StdString(fileName) inFolder:oo::OptionalString(folderName) cache:useCache]);
}

// oo-3rb.102: special dictionaries and scripts
// The whitelist and shader binding types were loaded once and returned as the same object on
// every call: the bridge converts them once and keeps that object (they are never reloaded).

+ (NSDictionary*)whitelistDictionary
{
    static NSDictionary* whitelistDictionary = nil;
    static BOOL converted = NO;
    if (!converted) {
        whitelistDictionary = [oo::ObjectFromPList([self cxx_whitelistDictionary]) retain];
        converted = YES;
    }
    return whitelistDictionary;
}

+ (NSDictionary*)shaderBindingTypesDictionary
{
    static NSDictionary* shaderBindingTypesDictionary = nil;
    static BOOL converted = NO;
    if (!converted) {
        shaderBindingTypesDictionary = [oo::ObjectFromPList([self cxx_shaderBindingTypesDictionary]) retain];
        converted = YES;
    }
    return shaderBindingTypesDictionary;
}

+ (NSDictionary*)logControlDictionary
{
    // Built afresh on every call, as before (a mutable dictionary).
    return [NSMutableDictionary dictionaryWithDictionary:oo::ObjectFromPList([self cxx_logControlDictionary])];
}

+ (NSDictionary*)roleCategoriesDictionary
{
    // Each category is a mutable set of roles, as the old merge built it.
    NSMutableDictionary* roleCategories = [NSMutableDictionary dictionaryWithCapacity:16];
    const oo::PList categories = [self cxx_roleCategoriesDictionary];
    for (const auto& [category, roles] : *categories.getIf<oo::PList::Dict>()) {
        NSMutableSet* contents = [NSMutableSet setWithCapacity:16];
        for (const oo::PList& role : *roles.getIf<oo::PList::Array>()) {
            id member = oo::ObjectFromPList(role);
            if (member != nil)
                [contents addObject:member];
        }
        [roleCategories setObject:contents forKey:oo::NSStringFrom(category)];
    }
    return [[roleCategories copy] autorelease];
}

+ (NSDictionary*)loadScripts
{
    // The old mutable dictionary, filled in the old insertion order (so it enumerates as before).
    NSMutableDictionary* loadedScripts = [NSMutableDictionary dictionary];
    for (const auto& [name, script] : [self cxx_loadScripts]) {
        [loadedScripts setObject:script.get() forKey:oo::NSStringFrom(name)];
    }
    return loadedScripts;
}

+ (NSDictionary*)materialDefaults
{
    // The loader's cached object, as the old method returned it (see +dictionaryFromFilesNamed:...).
    return [self dictionaryFromFilesNamed:@"material-defaults.plist" inFolder:@"Config" andMerge:YES];
}

// oo-3rb.103: file lookup, sounds and music, diagnostics

+ (NSString*)pathForFileNamed:(NSString*)fileName inFolder:(NSString*)folderName
{
    return [self pathForFileNamed:fileName inFolder:folderName cache:YES];
}

+ (NSString*)pathForFileNamed:(NSString*)fileName inFolder:(NSString*)folderName cache:(BOOL)useCache
{
    if (fileName == nil)
        return nil;

    // A resolved path came back as the string object held in OOCacheManager; the bridge returns
    // that object too (see the loaders above).
    NSString* cacheKey = (folderName != nil) ? [NSString stringWithFormat:@"%@/%@", folderName, fileName] : fileName;
    OOCacheManager* cacheMgr = [OOCacheManager sharedCache];
    id cached = [cacheMgr objectForKey:cacheKey inCache:@"resolved paths"];
    if (cached != nil)
        return cached;

    const std::optional<std::string> result = [self cxx_pathForFileNamed:oo::StdString(fileName) inFolder:oo::OptionalString(folderName) cache:useCache];
    if (useCache && result.has_value()) {
        cached = [cacheMgr objectForKey:cacheKey inCache:@"resolved paths"]; // what the lookup just cached
        if (cached != nil)
            return cached;
    }
    return oo::NSStringOrNil(result);
}

+ (OOSound*)ooSoundNamed:(NSString*)fileName inFolder:(NSString*)folderName
{
    if (fileName == nil)
        return nil; // no path was found for a nil name
    return [self cxx_ooSoundNamed:oo::StdString(fileName) inFolder:oo::OptionalString(folderName)];
}

+ (OOMusic*)ooMusicNamed:(NSString*)fileName inFolder:(NSString*)folderName
{
    if (fileName == nil)
        return nil; // no path was found for a nil name
    return [self cxx_ooMusicNamed:oo::StdString(fileName) inFolder:oo::OptionalString(folderName)];
}

+ (BOOL)writeDiagnosticData:(NSData*)data toFileNamed:(NSString*)name
{
    if (data == nil || name == nil)
        return NO;
    return [self cxx_writeDiagnosticData:oo::Data([data bytes], [data length]) toFileNamed:oo::StdString(name)];
}

+ (BOOL)writeDiagnosticString:(NSString*)string toFileNamed:(NSString*)name
{
    if (string == nil || name == nil)
        return NO; // -dataUsingEncoding: of nil was nil
    return [self cxx_writeDiagnosticString:oo::StdString(string) toFileNamed:oo::StdString(name)];
}

+ (BOOL)writeDiagnosticPList:(id)plist toFileNamed:(NSString*)name
{
    if (name == nil)
        return NO;
    return [self cxx_writeDiagnosticPList:plist toFileNamed:oo::StdString(name)];
}

@end
