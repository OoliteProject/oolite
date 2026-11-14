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

#pragma once

#include "OOOXPVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/Data.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-56tr / oo-cjel): file and folder names are UTF-8
        std::strings; a name that could be nil is std::optional.

        C++20 since bead oo-up4b (proposed ADR-0056 Amendment 1 and amendment oo-up4b). Bead oo-9ht.7
        deleted the Objective-C facades of OOFileScannerVerifierStage and OOFileHandlingVerifierStage,
        and the verifier's -fileScannerStage, once every stage was C++ (ADR-0056 amendment "deleting a
        facade"): both classes are global, as OOListUnusedFilesStage (bead oo-cwz) always was. A stage
        finds the scanner by its name through the verifier's stage lookup, which answers the C++
        stage (it answered the root facade, an id, until bead oo-9ht.4 deleted that facade).
*/

class OOFileScannerVerifierStage : public OOOXPVerifierStage {
public:
    // The stage's name, as name() returns it (the stages look the scanner up by it).
    static const char* const kName;

    // Returns name to be used in dependencies() by other stages; also registers stage.
    static std::optional<std::string> nameForDependencyForVerifier(OOOXPVerifier* verifier);

    std::optional<std::string> name() override;
    void run() override;

    /*	This method does the following:
                    A.	Checks whether a file exists.
                    B.	Checks whether case matches, and logs a warning otherwise.
                    C.	Maintains list of files which are referred to.
                    D.	Optionally falls back on Oolite's built-in files.

            For example, to test whether a texture referenced in a shipdata.plist entry
            exists, one would use:
            fileScanner->fileExists(textureName, "Textures", "shipdata.plist", true);
    */
    bool fileExists(const std::optional<std::string>& file,
        const std::optional<std::string>& folder,
        const std::optional<std::string>& context,
        bool checkBuiltIn);

    //	This method performs all the checks the previous one does, but also returns a file path.
    std::optional<std::string> pathForFile(const std::optional<std::string>& file,
        const std::optional<std::string>& folder,
        const std::optional<std::string>& context,
        bool checkBuiltIn);

    //	Data getters based on above method. An empty oo::Data: no such file (or an empty one).
    oo::Data dataForFile(const std::optional<std::string>& file,
        const std::optional<std::string>& folder,
        const std::optional<std::string>& context,
        bool checkBuiltIn);

    oo::PList plistNamed(const std::optional<std::string>& file, // Only uses "real" plist parser, not homebrew. Null: none.
        const std::optional<std::string>& folder,
        const std::optional<std::string>& context,
        bool checkBuiltIn);

    /*	Utility to handle display names of files.
            If a file and folder are provided, returns folder/file, otherwise just file.
    */
    std::optional<std::string> displayNameForFile(const std::optional<std::string>& file, const std::optional<std::string>& folder);

    /*	Get a list of files in a subfolder of the OXP, in byte order of the lowercase name; nullopt
            if the OXP has no such folder.
    */
    std::optional<std::vector<std::string>> filesInFolder(const std::optional<std::string>& folder);

private:
    void scanForFiles();

    void checkRootFolders();
    void checkConfigFiles();
    void checkKnownFiles();

    /*	Given an array of strings, return a dictionary mapping lowercase strings
            to the canonicial case given in the array. For instance, given
                    (Foo, BAR)

            it will return
                    { foo = Foo; bar = BAR }
    */
    std::optional<std::map<std::string, std::string, std::less<>>> lowercaseMap(const std::vector<std::string>& array);

    std::optional<std::map<std::string, std::string, std::less<>>> scanDirectory(const std::string& path);
    void checkPListFormat(oo::PListFormat format, const std::optional<std::string>& file, const std::optional<std::string>& folder);
    std::vector<std::string> constructReadMeNames();

    // The file name in a folder's listing (the root's is ""), in the case found on disk.
    std::optional<std::string> realNameOf(const std::string& lcName, const std::string& lcDirName);

    std::string _basePath = { };
    std::set<std::string> _usedFiles = { };
    std::set<std::string> _caseWarnings = { };
    // lowercase folder name ("" for the root) -> lowercase file name -> file name as on disk
    std::map<std::string, std::map<std::string, std::string, std::less<>>, std::less<>> _directoryListings = { };
    std::map<std::string, std::string, std::less<>> _directoryCases = { }; // lowercase -> as on disk
    std::set<std::string> _badPLists = { };
    std::set<std::string> _junkFileNames = { };
    std::set<std::string> _skipDirectoryNames = { };
};

/*	C++20 since bead oo-cwz, the converted stage of the Phase 3 class-hierarchy exemplar (proposed
        ADR-0056 Amendment 1). A C++ subclass of OOOXPVerifierStage that overrides its virtual
        members. It has no facade of its own: nothing outside this file names it, and the verifier
        holds it (as its OOOXPVerifierStage facade until bead oo-9ht.4).
*/
class OOListUnusedFilesStage : public OOOXPVerifierStage {
public:
    // Returns name to be used in dependents() by other stages; also registers stage.
    static std::string nameForReverseDependencyForVerifier(OOOXPVerifier* verifier); // flipped with its family (bead oo-3rb.274.2)

    std::optional<std::string> name() override;
    std::optional<std::vector<std::string>> dependencies() override;
    void run() override;
};

// Convenience base class for stages that require OOFileScannerVerifierStage and OOListUnusedFilesStage.
class OOFileHandlingVerifierStage : public OOOXPVerifierStage {
public:
    std::optional<std::vector<std::string>> dependencies() override;
    std::optional<std::vector<std::string>> dependents() override;
};

#endif
