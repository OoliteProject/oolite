/*

OOFileScannerVerifierStage+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056 amendment oo-up4b, bead oo-up4b): the Objective-C facades of the C++
cxx::OOFileScannerVerifierStage and cxx::OOFileHandlingVerifierStage (OOFileScannerVerifierStage.h),
and the verifier's -fileScannerStage, for the stages not converted yet. The interfaces are the
ones OOFileScannerVerifierStage.h declared before the conversion, copied exactly (same selectors,
same types), so those stages compile and behave unchanged. Imported as the last line of
OOFileScannerVerifierStage.h; do not import it directly.

        OOFileScannerVerifierStage   a C++ stage's facade (oo::ToObjC; one live one per stage). Every
                                     method forwards to the C++ member of the same name, cxx_ dropped.
        OOFileHandlingVerifierStage  the superclass of the Objective-C file-handling stages. Its -init
                                     makes their C++ part, an oo::ObjCStage<cxx::OOFileHandlingVerifierStage>,
                                     so -cxx_dependencies and -dependents, and [super dependents],
                                     answer what cxx::OOFileHandlingVerifierStage does.

        a caller that is                       holds / passes                         crosses with
        -------------------------------------  -------------------------------------  -----------------
        still Objective-C (unconverted stages) OOFileScannerVerifierStage *           nothing
        converted (C++)                        cxx::OOFileScannerVerifierStage *      oo::ToCxx([verifier
                                                                                        fileScannerStage])

Never add to this file; converted code does not message the facades. Deleted by its deletion
bead once every stage is C++ and the verifier no longer needs -fileScannerStage.


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

#ifndef OOFILESCANNERVERIFIERSTAGE_OBJCBRIDGE_H
#define OOFILESCANNERVERIFIERSTAGE_OBJCBRIDGE_H

#if OO_OXP_VERIFIER_ENABLED

@interface OOFileScannerVerifierStage : OOOXPVerifierStage

// Returns name to be used in -dependencies by other stages; also registers stage.
+ (std::optional<std::string>)nameForDependencyForVerifier:(OOOXPVerifier*)verifier;

/*	This method does the following:
                A.	Checks whether a file exists.
                B.	Checks whether case matches, and logs a warning otherwise.
                C.	Maintains list of files which are referred to.
                D.	Optionally falls back on Oolite's built-in files.

        For example, to test whether a texture referenced in a shipdata.plist entry
        exists, one would use:
        [fileScanner cxx_fileExists:textureName inFolder:"Textures" referencedFrom:"shipdata.plist" checkBuiltIn:YES];
*/
- (BOOL)cxx_fileExists:(const std::optional<std::string>&)file
              inFolder:(const std::optional<std::string>&)folder
        referencedFrom:(const std::optional<std::string>&)context
          checkBuiltIn:(BOOL)checkBuiltIn;

//	This method performs all the checks the previous one does, but also returns a file path.
- (std::optional<std::string>)cxx_pathForFile:(const std::optional<std::string>&)file
                                     inFolder:(const std::optional<std::string>&)folder
                               referencedFrom:(const std::optional<std::string>&)context
                                 checkBuiltIn:(BOOL)checkBuiltIn;

//	Data getters based on above method. An empty oo::Data: no such file (or an empty one).
- (oo::Data)dataForFile:(const std::optional<std::string>&)file
               inFolder:(const std::optional<std::string>&)folder
         referencedFrom:(const std::optional<std::string>&)context
           checkBuiltIn:(BOOL)checkBuiltIn;

- (oo::PList)cxx_plistNamed:(const std::optional<std::string>&)file // Only uses "real" plist parser, not homebrew. Null: none.
                   inFolder:(const std::optional<std::string>&)folder
             referencedFrom:(const std::optional<std::string>&)context
               checkBuiltIn:(BOOL)checkBuiltIn;

/*	Utility to handle display names of files.
        If a file and folder are provided, returns folder/file, otherwise just file.
*/
- (std::optional<std::string>)cxx_displayNameForFile:(const std::optional<std::string>&)file andFolder:(const std::optional<std::string>&)folder;

/*	Get a list of files in a subfolder of the OXP, in byte order of the lowercase name; nullopt
        if the OXP has no such folder.
*/
- (std::optional<std::vector<std::string>>)cxx_filesInFolder:(const std::optional<std::string>&)folder;

@end

@interface OOOXPVerifier (OOFileScannerVerifierStage)

- (OOFileScannerVerifierStage*)fileScannerStage;

@end

// Convenience base class for stages that require OOFileScannerVerifierStage and OOListUnusedFilesStage.
@interface OOFileHandlingVerifierStage : OOOXPVerifierStage

@end

namespace oo {

// The scanner's facade (autoreleased), nil for null; and the C++ scanner behind it, borrowed, null for nil.
OOFileScannerVerifierStage* ToObjC(cxx::OOFileScannerVerifierStage* stage);
cxx::OOFileScannerVerifierStage* ToCxx(OOFileScannerVerifierStage* stage);

} // namespace oo

#endif // OO_OXP_VERIFIER_ENABLED

#endif // OOFILESCANNERVERIFIERSTAGE_OBJCBRIDGE_H
