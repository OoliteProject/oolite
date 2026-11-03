/*

OOFileScannerVerifierStage.h

OOOXPVerifierStage which keeps track of which files are used and ensures file
name capitalization is consistent. It also provides the file lookup service
for other stages.


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

#import "OOOXPVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/Data.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-56tr): file and folder names are UTF-8
        std::strings; a name that could be nil is std::optional. The Foundation-typed API this header
        declared moved to OOFileScannerVerifierStage+FoundationBridge.h (transitional), forwarding to
        the cxx_ methods below.
*/

@interface OOFileScannerVerifierStage : OOOXPVerifierStage {
@private
    std::string _basePath;
    std::set<std::string> _usedFiles;
    std::set<std::string> _caseWarnings;
    // lowercase folder name ("" for the root) -> lowercase file name -> file name as on disk
    std::map<std::string, std::map<std::string, std::string, std::less<>>, std::less<>> _directoryListings;
    std::map<std::string, std::string, std::less<>> _directoryCases; // lowercase -> as on disk
    std::set<std::string> _badPLists;
    std::set<std::string> _junkFileNames;
    std::set<std::string> _skipDirectoryNames;
}

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

@interface OOListUnusedFilesStage : OOOXPVerifierStage

// Returns name to be used in -dependents by other stages; also registers stage.
+ (id)nameForReverseDependencyForVerifier:(OOOXPVerifier*)verifier; // an Objective-C string. Shared selector (proposed ADR-0043).

@end

@interface OOOXPVerifier (OOFileScannerVerifierStage)

- (OOFileScannerVerifierStage*)fileScannerStage;

@end

// Convenience base class for stages that require OOFileScannerVerifierStage and OOListUnusedFilesStage.
@interface OOFileHandlingVerifierStage : OOOXPVerifierStage

@end

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API this header
        declared before bead oo-56tr, forwarding to the cxx_ methods above, so unmigrated callers compile
        unchanged. Callers move to the cxx_ API in their own sweep beads; the bridge goes in its own bead.
*/
#import "OOFileScannerVerifierStage+FoundationBridge.h"

#endif
