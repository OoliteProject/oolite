/*

OOModelVerifierStage.m


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

#include "OOModelVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOFileScannerVerifierStage.h"

#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

static const char* const kStageName = "Testing models";

const char* const OOModelVerifierStage::kName = kStageName;

std::string OOModelVerifierStage::nameForReverseDependencyForVerifier(OOOXPVerifier* verifier)
{
    OOOXPVerifierStage* stage = verifier->stageWithName(kStageName);
    if (stage == nullptr) {
        const oo::Ref<OOModelVerifierStage> newStage = oo::makeRef<OOModelVerifierStage>();
        verifier->registerStage(newStage.get());
    }

    return kStageName;
}

std::optional<std::string> OOModelVerifierStage::name()
{
    return kStageName;
}

bool OOModelVerifierStage::shouldRun()
{
    return !_modelsToCheck.empty();
}

void OOModelVerifierStage::run()
{
    OO_LOG("verifyOXP.models.unimplemented", "{}", "TODO: implement model verifier.");

    for (const OOModelVerifierEntry& info : _modelsToCheck) {
        {
            checkModel(info.name,
                info.context,
                info.materials,
                info.shaders);
        }
    }
    _modelsToCheck.clear();
}

bool OOModelVerifierStage::modelNamed(const std::string& name,
    const std::optional<std::string>& entryName,
    const std::string& fileName,
    const oo::PList& materials,
    const oo::PList& shaders)
{
    OOFileScannerVerifierStage* fileScanner = nullptr;
    std::string context;

    if (name.empty())
        return false;

    if (entryName.has_value())
        context = oo::str::format("entry \"%s\" of %s", entryName->c_str(), fileName.c_str());
    else
        context = fileName;

    fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    if (fileScanner == nullptr || !fileScanner->fileExists(name, "Models", context, true)) {
        return false;
    }

    OOModelVerifierEntry info { name, context, materials, shaders };
    if (std::find(_modelsToCheck.begin(), _modelsToCheck.end(), info) == _modelsToCheck.end()) {
        _modelsToCheck.push_back(std::move(info));
    }

    return true;
}

void OOModelVerifierStage::checkModel(const std::string& name,
    const std::string& context,
    const oo::PList&,
    const oo::PList&)
{
    OO_LOG("verifyOXP.verbose.model.unimp", "- Pretending to verify model {} referenced in {}.", name, context);
    // FIXME: this should check DAT files.
}

#endif
