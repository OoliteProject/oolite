/*
 * NSBundle+Override.m
 *
 * Oolite Core Framework Override
 * Bypasses standard plist loading to manually locate and parse info-gnustep.plist
 * across Windows and Linux environments safely at boot.
 */

#import "NSBundle+Override.h"
#import "OOFoundationBridge.h"

#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"

#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#endif
@implementation NSBundle (Override)

- (id)infoDictionary
{ // shared selector (proposed ADR-0043)
    // <cwd>/Resources, else <cwd>/../share/oolite/Resources (Standard Linux system layout): the
    // same resolution oo::ResourcePaths makes for the built-in resources (and oo::Defaults for
    // this very file).
    const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";

    // Load the target configuration file: any plist format; missing, unreadable or not a
    // dictionary is no dictionary, as -dictionaryWithContentsOfFile: returned nil for them.
    oo::PList gnustepPlist;
    if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty()) {
        oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
        if (parsed && parsed->isDict())
            gnustepPlist = std::move(*parsed);
    }

    if (gnustepPlist.isNull()) {
        // Fallback block prevents runtime crashes if files are missing during dev/build refactors
        gnustepPlist = oo::PList(oo::PList::Dict { });
        NSLog(@"[Oolite-Core] Warning: Failed to find info-gnustep.plist at calculated path: %@", oo::NSStringFrom(oo::fs::utf8String(plistPath)));
    }

    // A mutable copy, as before, returned autoreleased.
    return [[oo::ObjectFromPList(gnustepPlist) mutableCopy] autorelease];
}

@end
#ifdef __clang__
#pragma clang diagnostic pop
#endif
