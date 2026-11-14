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

#include "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOFileScannerVerifierStage.h"
#include "OOMaths.h"
#include "OOTexture.h"
#include "OOTextureLoader.h"
#include "oofnd/Log.hpp"

static const char* const kStageName = "Testing textures and images";

std::string OOTextureVerifierStage::nameForReverseDependencyForVerifier(OOOXPVerifier*)
{
    return kStageName;
}

std::optional<std::string> OOTextureVerifierStage::name()
{
    return kStageName;
}

bool OOTextureVerifierStage::shouldRun()
{
    OOFileScannerVerifierStage* fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    return !_usedTextures.empty() || (fileScanner != nullptr && fileScanner->filesInFolder("Images").has_value());
}

void OOTextureVerifierStage::run()
{
    for (const std::string& name : _usedTextures) {
        {
            checkTextureNamed(name, "Textures");
        }
    }
    _usedTextures.clear();

    // All "images" are considered used, since we don't have a reasonable way to look for images referenced in JavaScript scripts.
    OOFileScannerVerifierStage* fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    if (fileScanner == nullptr)
        return; // a nil scanner listed no images
    for (const std::string& name : fileScanner->filesInFolder("Images").value_or(std::vector<std::string> { })) {
        checkTextureNamed(name, "Images");
    }
}

void OOTextureVerifierStage::textureNamed(const std::string& name, const std::string& context)
{
    OOFileScannerVerifierStage* fileScanner = nullptr;

    if (name.empty())
        return;
    const auto where = std::lower_bound(_usedTextures.begin(), _usedTextures.end(), name);
    if (where != _usedTextures.end() && *where == name)
        return;
    _usedTextures.insert(where, name);

    fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    if (fileScanner == nullptr || !fileScanner->fileExists(name, "Textures", context, true)) {
        OO_LOG("verifyOXP.texture.notFound", "----- WARNING: texture \"{}\" referenced in {} could not be found in {} or in Oolite.", name, context, verifier()->oxpDisplayName().value_or("(null)"));
    }
}

void OOTextureVerifierStage::checkTextureNamed(const std::string& name, const std::string& folder)
{
    oo::Ref<OOTextureLoader> loader;
    std::optional<std::string> path;
    OOFileScannerVerifierStage* fileScanner = nullptr;
    std::optional<std::string> displayName;
    OOPixMapDimension rWidth, rHeight;
    bool success;
    OOPixMap pixmap;
    OOTextureDataFormat format;

    fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    if (fileScanner != nullptr)
        path = fileScanner->pathForFile(name, folder, std::nullopt, false);

    if (!path.has_value())
        return;

    loader = OOTextureLoader::loaderWithPath(path,
        kOOTextureMinFilterNearest | kOOTextureMinFilterNearest | kOOTextureNoShrink | kOOTextureNoFNFMessage | kOOTextureNeverScale);

    displayName = fileScanner->displayNameForFile(name, folder);
    if (loader == nullptr) {
        OO_LOG("verifyOXP.texture.failed", "***** ERROR: image {} could not be read.", displayName.value_or("(null)"));
    } else {
        success = loader->getResult(&pixmap, &format, NULL, NULL);

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

// OOTextureHandlingStage: C++ since bead oo-tuq8; global since bead oo-9ht.45 deleted its facade.

std::optional<std::vector<std::string>> OOTextureHandlingStage::dependents()
{
    std::vector<std::string> result = OOFileHandlingVerifierStage::dependents().value_or(std::vector<std::string>());
    const std::string reverse = OOTextureVerifierStage::nameForReverseDependencyForVerifier(verifier());
    if (std::find(result.begin(), result.end(), reverse) == result.end())
        result.push_back(reverse);
    return result;
}

#endif
