/*

OOFileScannerVerifierStage+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056 amendment oo-up4b, bead oo-up4b): the Objective-C facades
OOFileScannerVerifierStage and OOFileHandlingVerifierStage, and the verifier's -fileScannerStage
(see OOFileScannerVerifierStage+ObjCBridge.h). Deleted with OOFileScannerVerifierStage+ObjCBridge.h.


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOFileScannerVerifierStage.h"
#import "OOOXPVerifierStageInternal.h"

#if OO_OXP_VERIFIER_ENABLED

// A facade of this class is only ever made for a cxx::OOFileScannerVerifierStage (oo::ToObjC names
// the facade class after the C++ class; -init below makes one), so the cast is exact.
OOFileScannerVerifierStage* oo::ToObjC(cxx::OOFileScannerVerifierStage* stage)
{
    return static_cast<OOFileScannerVerifierStage*>(oo::ToObjC(static_cast<cxx::OOOXPVerifierStage*>(stage)));
}

cxx::OOFileScannerVerifierStage* oo::ToCxx(OOFileScannerVerifierStage* stage)
{
    return static_cast<cxx::OOFileScannerVerifierStage*>(oo::ToCxx(static_cast<OOOXPVerifierStage*>(stage)));
}

@implementation OOFileScannerVerifierStage

// [[OOFileScannerVerifierStage alloc] init] still makes a scanner: a new C++ one, and its facade.
- (id)init
{
    [self release];
    return [oo::ToObjC(oo::makeRef<cxx::OOFileScannerVerifierStage>().get()) retain];
}

+ (std::optional<std::string>)nameForDependencyForVerifier:(OOOXPVerifier*)verifier
{
    return cxx::OOFileScannerVerifierStage::nameForDependencyForVerifier(verifier);
}

- (BOOL)cxx_fileExists:(const std::optional<std::string>&)file
              inFolder:(const std::optional<std::string>&)folder
        referencedFrom:(const std::optional<std::string>&)context
          checkBuiltIn:(BOOL)checkBuiltIn
{
    return oo::ToCxx(self)->fileExists(file, folder, context, checkBuiltIn);
}

- (std::optional<std::string>)cxx_pathForFile:(const std::optional<std::string>&)file
                                     inFolder:(const std::optional<std::string>&)folder
                               referencedFrom:(const std::optional<std::string>&)context
                                 checkBuiltIn:(BOOL)checkBuiltIn
{
    return oo::ToCxx(self)->pathForFile(file, folder, context, checkBuiltIn);
}

- (oo::Data)dataForFile:(const std::optional<std::string>&)file
               inFolder:(const std::optional<std::string>&)folder
         referencedFrom:(const std::optional<std::string>&)context
           checkBuiltIn:(BOOL)checkBuiltIn
{
    return oo::ToCxx(self)->dataForFile(file, folder, context, checkBuiltIn);
}

- (oo::PList)cxx_plistNamed:(const std::optional<std::string>&)file
                   inFolder:(const std::optional<std::string>&)folder
             referencedFrom:(const std::optional<std::string>&)context
               checkBuiltIn:(BOOL)checkBuiltIn
{
    return oo::ToCxx(self)->plistNamed(file, folder, context, checkBuiltIn);
}

- (std::optional<std::string>)cxx_displayNameForFile:(const std::optional<std::string>&)file andFolder:(const std::optional<std::string>&)folder
{
    return oo::ToCxx(self)->displayNameForFile(file, folder);
}

- (std::optional<std::vector<std::string>>)cxx_filesInFolder:(const std::optional<std::string>&)folder
{
    return oo::ToCxx(self)->filesInFolder(folder);
}

@end

@implementation OOOXPVerifier (OOFileScannerVerifierStage)

- (OOFileScannerVerifierStage*)fileScannerStage
{
    return [self cxx_stageWithName:cxx::OOFileScannerVerifierStage::kName];
}

@end

@implementation OOFileHandlingVerifierStage

// An Objective-C file-handling stage ([[X alloc] init] of a subclass): its C++ part derives from
// cxx::OOFileHandlingVerifierStage, so what the subclass does not override answers as that class does.
- (id)init
{
    return [super initWithCxxStage:oo::makeRef<oo::ObjCStage<cxx::OOFileHandlingVerifierStage>>(self).get()];
}

@end

#endif // OO_OXP_VERIFIER_ENABLED
