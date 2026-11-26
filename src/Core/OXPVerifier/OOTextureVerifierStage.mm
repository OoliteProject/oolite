/*

OOTextureVerifierStage.m


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

#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOFoundationBridge.h"
#import "OOMaths.h"
#import "OOTextureLoader.h"
#include "oofnd/Log.hpp"

static const char* const kStageName = "Testing textures and images";

@interface OOTextureVerifierStage (OOPrivate)

- (void)checkTextureNamed:(const std::string&)name inFolder:(const std::string&)folder;

@end

@implementation OOTextureVerifierStage

+ (std::string)nameForReverseDependencyForVerifier:(OOOXPVerifier*)verifier
{
    return kStageName;
}

- (std::optional<std::string>)cxx_name
{
    return kStageName;
}

- (BOOL)shouldRun
{
    return !_usedTextures.empty() || [[[self verifier] fileScannerStage] cxx_filesInFolder:"Images"].has_value();
}

- (void)run
{
    for (const std::string& name : _usedTextures) {
        @autoreleasepool {
            [self checkTextureNamed:name inFolder:"Textures"];
        }
    }
    _usedTextures.clear();

    // All "images" are considered used, since we don't have a reasonable way to look for images referenced in JavaScript scripts.
    for (const std::string& name : [[[self verifier] fileScannerStage] cxx_filesInFolder:"Images"].value_or(std::vector<std::string> { })) {
        [self checkTextureNamed:name inFolder:"Images"];
    }
}

- (void)textureNamed:(const std::string&)name usedInContext:(const std::string&)context
{
    OOFileScannerVerifierStage* fileScanner = nil;

    if (name.empty())
        return;
    const auto where = std::lower_bound(_usedTextures.begin(), _usedTextures.end(), name);
    if (where != _usedTextures.end() && *where == name)
        return;
    _usedTextures.insert(where, name);

    fileScanner = [[self verifier] fileScannerStage];
    if (![fileScanner cxx_fileExists:name inFolder:"Textures" referencedFrom:context checkBuiltIn:YES]) {
        OO_LOG("verifyOXP.texture.notFound", "----- WARNING: texture \"{}\" referenced in {} could not be found in {} or in Oolite.", name, context, [[self verifier] cxx_oxpDisplayName].value_or("(null)"));
    }
}

@end

@implementation OOTextureVerifierStage (OOPrivate)

- (void)checkTextureNamed:(const std::string&)name inFolder:(const std::string&)folder
{
    OOTextureLoader* loader = nil;
    std::optional<std::string> path;
    OOFileScannerVerifierStage* fileScanner = nil;
    std::optional<std::string> displayName;
    OOPixMapDimension rWidth, rHeight;
    BOOL success;
    OOPixMap pixmap;
    OOTextureDataFormat format;

    fileScanner = [[self verifier] fileScannerStage];
    path = [fileScanner cxx_pathForFile:name inFolder:folder referencedFrom:std::nullopt checkBuiltIn:NO];

    if (!path.has_value())
        return;

    loader = [OOTextureLoader cxx_loaderWithPath:path
                                         options:kOOTextureMinFilterNearest | kOOTextureMinFilterNearest | kOOTextureNoShrink | kOOTextureNoFNFMessage |
        kOOTextureNeverScale];

    displayName = [fileScanner cxx_displayNameForFile:name andFolder:folder];
    if (loader == nil) {
        OO_LOG("verifyOXP.texture.failed", "***** ERROR: image {} could not be read.", displayName.value_or("(null)"));
    } else {
        success = [loader getResult:&pixmap format:&format originalWidth:NULL originalHeight:NULL];

        if (success) {
            rWidth = OORoundUpToPowerOf2_PixMap((2 * pixmap.width) / 3);
            rHeight = OORoundUpToPowerOf2_PixMap((2 * pixmap.height) / 3);
            if (pixmap.width != rWidth || pixmap.height != rHeight) {
                OO_LOG("verifyOXP.texture.notPOT", "----- WARNING: image {} has non-power-of-two dimensions; it will have to be rescaled (from {}x{} pixels to {}x{} pixels) at runtime.", displayName.value_or("(null)"), pixmap.width, pixmap.height, rWidth, rHeight);
            } else {
                OO_LOG("verifyOXP.verbose.texture.OK", "- {} ({}x{} px) OK.", displayName.value_or("(null)"), pixmap.width, pixmap.height);
            }

            OOFreePixMap(&pixmap);
        } else {
            OO_LOG("verifyOXP.texture.failed", "***** ERROR: texture loader failed to load {}.", displayName.value_or("(null)"));
        }
    }
}

@end

@implementation OOTextureHandlingStage

- (std::optional<std::vector<std::string>>)dependents
{
    std::vector<std::string> result = [super dependents].value_or(std::vector<std::string>());
    const std::string reverse = [OOTextureVerifierStage nameForReverseDependencyForVerifier:[self verifier]];
    if (std::find(result.begin(), result.end(), reverse) == result.end())
        result.push_back(reverse);
    return result;
}

@end

@implementation OOOXPVerifier (OOTextureVerifierStage)

- (OOTextureVerifierStage*)textureVerifierStage
{
    return [self cxx_stageWithName:kStageName];
}

@end

#endif
