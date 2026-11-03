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

#import "OOModelVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"

#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

static const char* const kStageName = "Testing models";

@interface OOModelVerifierStage (OOPrivate)

- (void)checkModel:(const std::string&)name
           context:(const std::string&)context
         materials:(const oo::PList&)materials
           shaders:(const oo::PList&)shaders;

@end

@implementation OOModelVerifierStage

+ (std::string)nameForReverseDependencyForVerifier:(OOOXPVerifier*)verifier
{
    OOModelVerifierStage* stage = [verifier cxx_stageWithName:kStageName];
    if (stage == nil) {
        stage = [[OOModelVerifierStage alloc] init];
        [verifier registerStage:stage];
        [stage release];
    }

    return kStageName;
}

- (std::optional<std::string>)cxx_name
{
    return kStageName;
}

- (BOOL)shouldRun
{
    return !_modelsToCheck.empty();
}

- (void)run
{
    OO_LOG("verifyOXP.models.unimplemented", "{}", "TODO: implement model verifier.");

    for (const OOModelVerifierEntry& info : _modelsToCheck) {
        @autoreleasepool {
            [self checkModel:info.name
                     context:info.context
                   materials:info.materials
                     shaders:info.shaders];
        }
    }
    _modelsToCheck.clear();
}

- (BOOL)modelNamed:(const std::string&)name
      usedForEntry:(const std::optional<std::string>&)entryName
            inFile:(const std::string&)fileName
     withMaterials:(const oo::PList&)materials
        andShaders:(const oo::PList&)shaders
{
    OOFileScannerVerifierStage* fileScanner = nil;
    std::string context;

    if (name.empty())
        return NO;

    if (entryName.has_value())
        context = oo::str::format("entry \"%s\" of %s", entryName->c_str(), fileName.c_str());
    else
        context = fileName;

    fileScanner = [[self verifier] fileScannerStage];
    if (![fileScanner cxx_fileExists:name inFolder:"Models" referencedFrom:context checkBuiltIn:YES]) {
        return NO;
    }

    OOModelVerifierEntry info { name, context, materials, shaders };
    if (std::find(_modelsToCheck.begin(), _modelsToCheck.end(), info) == _modelsToCheck.end()) {
        _modelsToCheck.push_back(std::move(info));
    }

    return YES;
}

@end

@implementation OOModelVerifierStage (OOPrivate)

- (void)checkModel:(const std::string&)name
           context:(const std::string&)context
         materials:(const oo::PList&)materials
           shaders:(const oo::PList&)shaders
{
    OO_LOG("verifyOXP.verbose.model.unimp", "- Pretending to verify model {} referenced in {}.", name, context);
    // FIXME: this should check DAT files.
}

@end

@implementation OOOXPVerifier (OOModelVerifierStage)

- (OOModelVerifierStage*)modelVerifierStage
{
    return [self cxx_stageWithName:kStageName];
}

@end

#endif
