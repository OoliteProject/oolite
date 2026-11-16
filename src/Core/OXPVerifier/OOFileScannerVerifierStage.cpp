/*

OOFileScannerVerifierStage.m

C++20 since bead oo-up4b (proposed ADR-0056 Amendment 1 and amendment oo-up4b): OOFileScannerVerifierStage,
OOListUnusedFilesStage (bead oo-cwz) and OOFileHandlingVerifierStage. Method bodies are the
Objective-C ones with message sends turned into calls (ADR-0012). Their Objective-C facades, and the
verifier's -fileScannerStage, were deleted by bead oo-9ht.7. Still
Objective-C++ until Phase 4: the verifier and the resource manager are Objective-C objects.


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

/*	Design notes:
        In order to be able to look files up case-insenstively, but warn about
        case mismatches, the OOFileScannerVerifierStage builds its own
        representation of the file hierarchy. Dictionaries are used heavily: the
        _directoryListings is keyed by folder names mapped to lower case, and its
        entries map lowercase file names to actual case, that is, the case found
        in the file system. The companion dictionary _directoryCases maps
        lowercase directory names to actual case.

        The class design is based on the knowledge that Oolite uses a two-level
        namespace for files. Each file type has an appropriate folder, and files
        may either be in the appropriate folder or "bare". For instance, a texture
        file in an OXP may be either in the Textures subdirectory or in the root
        directory of the OXP. The root directory's contents are listed in
        _directoryListings with the empty string as key. This architecture means
        the OOFileScannerVerifierStage doesn't need to take full file system
        hierarchy into account.
*/

#include "OOFileScannerVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "ResourceManager.h"

#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/String.hpp"

namespace {

const char* const kFileScannerStageName = "Scanning files";
const char* const kUnusedListerStageName = "Checking for unused files";

// The strings of a configuration array (was oo::StringsFrom of -configurationArrayForKey:).
std::vector<std::string> StringsFromArray(const oo::PList& array)
{
    std::vector<std::string> result;
    if (const oo::PList::Array* elements = array.getIf<oo::PList::Array>()) {
        for (const oo::PList& element : *elements) {
            if (const std::string* string = element.getIf<std::string>())
                result.push_back(*string);
        }
    }
    return result;
}

BOOL CheckNameConflict(const std::string& lcName, const std::map<std::string, std::string, std::less<>>& directoryCases, const std::map<std::string, std::string, std::less<>>& rootFiles, std::string* outExisting, std::string* outExistingType);

} // namespace

const char* const OOFileScannerVerifierStage::kName = kFileScannerStageName;

std::optional<std::string> OOFileScannerVerifierStage::name()
{
    return kFileScannerStageName;
}

void OOFileScannerVerifierStage::run()
{

    _usedFiles.clear();
    _caseWarnings.clear();
    _badPLists.clear();

    {
        scanForFiles();
    }

    {
        checkRootFolders();
        checkKnownFiles();
    }
}

// The verifier holds the C++ stages (it held their facades until bead oo-9ht.4).
std::optional<std::string> OOFileScannerVerifierStage::nameForDependencyForVerifier(OOOXPVerifier* verifier)
{
    OOOXPVerifierStage* stage = verifier->stageWithName(kFileScannerStageName);
    if (stage == nullptr) {
        const oo::Ref<OOFileScannerVerifierStage> newStage = oo::makeRef<OOFileScannerVerifierStage>();
        verifier->registerStage(newStage.get());
    }

    return kFileScannerStageName;
}

bool OOFileScannerVerifierStage::fileExists(const std::optional<std::string>& file, const std::optional<std::string>& folder, const std::optional<std::string>& context, bool checkBuiltIn)
{
    return pathForFile(file, folder, context, checkBuiltIn).has_value();
}

std::optional<std::string> OOFileScannerVerifierStage::pathForFile(const std::optional<std::string>& file, const std::optional<std::string>& folder, const std::optional<std::string>& context, bool checkBuiltIn)
{
    std::string lcName,
        lcDirName;
    std::optional<std::string> realDirName,
        realFileName,
        path,
        expectedPath;

    if (!file.has_value())
        return std::nullopt;
    lcName = oo::str::lowercase(*file);

    if (folder.has_value()) {
        lcDirName = oo::str::lowercase(*folder);
        realFileName = realNameOf(lcName, lcDirName);

        if (realFileName.has_value()) {
            const auto dirCase = _directoryCases.find(lcDirName);
            if (dirCase != _directoryCases.end()) {
                realDirName = dirCase->second;
                path = oo::str::appendingPathComponent(*realDirName, *realFileName);
            }
        }
    }

    if (!path.has_value()) {
        realFileName = realNameOf(lcName, "");

        if (realFileName.has_value()) {
            path = realFileName;
        }
    }

    if (path.has_value()) {
        _usedFiles.insert(*path);
        if (realDirName.has_value() && *realDirName != *folder) {
            // Case mismatch for folder name
            if (!_caseWarnings.contains(lcDirName)) {
                _caseWarnings.insert(lcDirName);
                OO_LOG("verifyOXP.files.caseMismatch", "***** ERROR: case mismatch: directory '{}' should be called '{}'.", *realDirName, *folder);
            }
        }

        if (*realFileName != *file) {
            // Case mismatch for file name
            if (!_caseWarnings.contains(lcName)) {
                _caseWarnings.insert(lcName);

                expectedPath = displayNameForFile(file, folder);

                const std::string contextText = context.has_value() ? " referenced in " + *context : std::string();

                OO_LOG("verifyOXP.files.caseMismatch", "***** ERROR: case mismatch: request for file '{}'{} resolved to '{}'.", expectedPath.value_or("(null)"), contextText, *path);
            }
        }

        // One component at a time: realDirName and realFileName are single names from the listing.
        std::string fullPath = _basePath;
        if (realDirName.has_value())
            fullPath = oo::str::appendingPathComponent(fullPath, *realDirName);
        return oo::str::appendingPathComponent(fullPath, *realFileName);
    }

    // If we get here, the file wasn't found in the OXP.
    // FIXME: should check case for built-in files.
    if (checkBuiltIn && file.has_value())
        return ResourceManager::pathForFileNamed(*file, folder); // a nil name found no path

    return std::nullopt;
}

oo::Data OOFileScannerVerifierStage::dataForFile(const std::optional<std::string>& file, const std::optional<std::string>& folder, const std::optional<std::string>& context, bool checkBuiltIn)
{
    const std::optional<std::string> path = pathForFile(file, folder, context, checkBuiltIn);
    if (!path.has_value())
        return oo::Data();

    oo::fs::Result<oo::Data> data = oo::fs::readFile(oo::fs::pathFromUTF8(*path));
    return data ? std::move(*data) : oo::Data();
}

oo::PList OOFileScannerVerifierStage::plistNamed(const std::optional<std::string>& file, const std::optional<std::string>& folder, const std::optional<std::string>& context, bool checkBuiltIn)
{
    oo::PListFormat format = oo::PListFormat::OpenStep;
    oo::PList plist;
    std::optional<std::string> errorString,
        displayName;
    std::string errorKey;

    // Not -dataForFile:, whose empty result also stands for "no file": an empty file is parsed
    // (and reported), as it was.
    const std::optional<std::string> path = pathForFile(file, folder, context, checkBuiltIn);
    if (!path.has_value())
        return oo::PList();
    oo::fs::Result<oo::Data> data = oo::fs::readFile(oo::fs::pathFromUTF8(*path));
    if (!data)
        return oo::PList();

    {
        // +[NSPropertyListSerialization propertyListFromData:...errorDescription:]; the error
        // string it gave is PListError::description().
        oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyListData(data->stringView(), &format);
        if (parsed)
            plist = std::move(*parsed);
        else
            errorString = parsed.error().description();

        if (!plist.isNull()) {
            // PList is readable; check that it's in an official Oolite format.
            checkPListFormat(format, file, folder);
        } else {
            /*	Couldn't parse plist; report problem.
                    This is complicated somewhat by the need to present a possibly
                    multi-line error description while maintaining our indentation.
            */
            displayName = displayNameForFile(file, folder);
            errorKey = oo::str::lowercase(*displayName);
            if (!_badPLists.contains(errorKey)) {
                _badPLists.insert(errorKey);
                OO_LOG("verifyOXP.plist.parseError", "Could not interpret property list {}.", displayName.value_or("(null)"));
                oo::log::indent();
                if (errorString.has_value()) {
                    for (std::string errorLine : oo::str::split(*errorString, "\n")) {
                        while (oo::str::hasPrefix(errorLine, "\t")) {
                            errorLine = "    " + errorLine.substr(1);
                        }
                        OO_LOG("verifyOXP.plist.parseError", "{}", errorLine);
                    }
                }
                oo::log::outdent();
            }
        }
    }

    return plist;
}

std::optional<std::string> OOFileScannerVerifierStage::displayNameForFile(const std::optional<std::string>& file, const std::optional<std::string>& folder)
{
    if (file.has_value() && folder.has_value())
        return oo::str::appendingPathComponent(*folder, *file);
    return file;
}

std::optional<std::vector<std::string>> OOFileScannerVerifierStage::filesInFolder(const std::optional<std::string>& folder)
{
    if (!folder.has_value())
        return std::nullopt;
    const auto listing = _directoryListings.find(oo::str::lowercase(*folder));
    if (listing == _directoryListings.end())
        return std::nullopt;

    std::vector<std::string> result;
    for (const auto& [lcName, realName] : listing->second)
        result.push_back(realName);
    return result;
}

// Private (was the OOPrivate category).

std::optional<std::string> OOFileScannerVerifierStage::realNameOf(const std::string& lcName, const std::string& lcDirName)
{
    const auto listing = _directoryListings.find(lcDirName);
    if (listing == _directoryListings.end())
        return std::nullopt;
    const auto entry = listing->second.find(lcName);
    if (entry == listing->second.end())
        return std::nullopt;
    return entry->second;
}

void OOFileScannerVerifierStage::scanForFiles()
{
    std::string path,
        lcName,
        existing,
        existingType;
    std::map<std::string, std::map<std::string, std::string, std::less<>>, std::less<>> directoryListings;
    std::map<std::string, std::string, std::less<>> directoryCases,
        rootFiles;
    std::set<std::string> readMeNames;

    _basePath = verifier()->oxpPath().value_or("");

    for (const std::string& junk : verifier()->configurationSetForKey("junkFiles").value_or(std::vector<std::string>()))
        _junkFileNames.insert(junk);
    for (const std::string& skip : verifier()->configurationSetForKey("skipDirectories").value_or(std::vector<std::string>()))
        _skipDirectoryNames.insert(skip);

    for (const std::string& readMe : constructReadMeNames())
        readMeNames.insert(readMe);

    oo::fs::RecursiveDirectoryEnumerator dirEnum(oo::fs::pathFromUTF8(_basePath));
    for (;;) {
        const std::optional<std::string> nextName = dirEnum.next();
        if (!nextName.has_value())
            break;
        const std::string& name = *nextName;

        path = oo::str::appendingPathComponent(_basePath, name);
        const oo::fs::FileType type = dirEnum.entryType();
        lcName = oo::str::lowercase(name);

        if (type == oo::fs::FileType::directory) {
            dirEnum.skipDescendents();

            if (_skipDirectoryNames.contains(name)) {
                // Silently skip .svn and CVS
                OO_LOG("verifyOXP.verbose.listFiles", "- Skipping {}/", name);
            } else if (!CheckNameConflict(lcName, directoryCases, rootFiles, &existing, &existingType)) {
                OO_LOG("verifyOXP.verbose.listFiles", "- {}/", name);
                oo::log::indentIf("verifyOXP.verbose.listFiles");
                directoryListings[lcName] = *scanDirectory(path);
                directoryCases[lcName] = name;
                oo::log::outdentIf("verifyOXP.verbose.listFiles");
            } else {
                OO_LOG("verifyOXP.scanFiles.overloadedName", "***** ERROR: {} '{}' conflicts with {} named '{}', ignoring. (OXPs must work on case-insensitive file systems!)", "directory", name, existingType, existing);
            }
        } else if (type == oo::fs::FileType::regular) {
            if (_junkFileNames.contains(name)) {
                OO_LOG("verifyOXP.scanFiles.skipJunk", "NOTE: skipping junk file {}.", name);
            } else if (readMeNames.contains(lcName)) {
                OO_LOG("verifyOXP.scanFiles.readMe", "----- WARNING: apparent Read Me file (\"{}\") inside OXP. This is the wrong place for a Read Me file, because it will not be read.", name);
            } else if (!CheckNameConflict(lcName, directoryCases, rootFiles, &existing, &existingType)) {
                OO_LOG("verifyOXP.verbose.listFiles", "- {}", name);
                rootFiles[lcName] = name;
            } else {
                OO_LOG("verifyOXP.scanFiles.overloadedName", "***** ERROR: {} '{}' conflicts with {} named '{}', ignoring. (OXPs must work on case-insensitive file systems!)", "file", name, existingType, existing);
            }
        } else if (type == oo::fs::FileType::symbolic_link) {
            OO_LOG("verifyOXP.scanFiles.symLink", "----- WARNING: \"{}\" is a symbolic link, ignoring.", name);
        } else {
            OO_LOG("verifyOXP.scanFiles.nonStandardFile", "----- WARNING: \"{}\" is a non-standard file, ignoring.", name);
        }
    }

    _junkFileNames.clear();
    _skipDirectoryNames.clear();

    directoryListings[""] = rootFiles;
    _directoryListings = std::move(directoryListings);
    _directoryCases = std::move(directoryCases);
}

void OOFileScannerVerifierStage::checkRootFolders()
{
    std::string lcName;

    for (const std::string& name : StringsFromArray(verifier()->configurationArrayForKey("knownRootDirectories"))) {
        lcName = oo::str::lowercase(name);
        const auto actual = _directoryCases.find(lcName);
        if (actual == _directoryCases.end())
            continue;

        if (actual->second != name) {
            OO_LOG("verifyOXP.files.caseMismatch", "***** ERROR: case mismatch: directory '{}' should be called '{}'.", actual->second, name);
        }
        _caseWarnings.insert(lcName);
    }
}

void OOFileScannerVerifierStage::checkConfigFiles()
{
    std::string lcName;
    std::optional<std::string> realFileName;
    BOOL inConfigDir;

    for (const std::string& name : StringsFromArray(verifier()->configurationArrayForKey("knownConfigFiles"))) {
        /*	In theory, we could use -fileExists:inFolder:referencedFrom:checkBuiltIn:
        here, but we want a different error message.
        */

        lcName = oo::str::lowercase(name);
        realFileName = realNameOf(lcName, "config");
        inConfigDir = realFileName.has_value();
        if (!inConfigDir)
            realFileName = realNameOf(lcName, "");
        if (!realFileName.has_value())
            continue;

        if (*realFileName != name) {
            if (inConfigDir)
                realFileName = oo::str::appendingPathComponent("Config", *realFileName);
            OO_LOG("verifyOXP.files.caseMismatch", "***** ERROR: case mismatch: configuration file '{}' should be called '{}'.", *realFileName, name);
        }
    }
}

void OOFileScannerVerifierStage::checkKnownFiles()
{
    std::string lcDirectory,
        lcName;
    std::optional<std::string> realFileName;
    BOOL inDirectory;

    // Folders in byte order of their names (they were in dictionary order).
    const oo::PList directories = verifier()->configurationDictionaryForKey("knownFiles");
    const oo::PList::Dict* directoryDict = directories.getIf<oo::PList::Dict>();
    if (directoryDict == nullptr)
        return;
    for (const auto& [directory, fileList] : *directoryDict) {
        lcDirectory = oo::str::lowercase(directory);
        const oo::PList::Array* files = fileList.getIf<oo::PList::Array>();
        if (files == nullptr)
            continue;
        for (const oo::PList& entry : *files) {
            const std::string* name = entry.getIf<std::string>();
            if (name == nullptr)
                continue;

            /*	In theory, we could use -fileExists:inFolder:referencedFrom:checkBuiltIn:
                    here, but we want a different error message.
            */

            lcName = oo::str::lowercase(*name);
            realFileName = realNameOf(lcName, lcDirectory);
            inDirectory = realFileName.has_value();
            if (!inDirectory) {
                // Allow for files in root directory of OXP
                realFileName = realNameOf(lcName, "");
            }
            if (!realFileName.has_value())
                continue;

            if (*realFileName != *name) {
                if (inDirectory)
                    realFileName = oo::str::appendingPathComponent(directory, *realFileName);
                OO_LOG("verifyOXP.files.caseMismatch", "***** ERROR: case mismatch: file '{}' should be called '{}'.", *realFileName, *name);
            }
        }
    }
}

std::optional<std::map<std::string, std::string, std::less<>>> OOFileScannerVerifierStage::lowercaseMap(const std::vector<std::string>& array)
{
    std::map<std::string, std::string, std::less<>> result;

    for (const std::string& canonical : array) {
        result[oo::str::lowercase(canonical)] = canonical;
    }

    return result;
}

std::optional<std::map<std::string, std::string, std::less<>>> OOFileScannerVerifierStage::scanDirectory(const std::string& path)
{
    std::map<std::string, std::string, std::less<>> result;
    std::string lcName,
        dirName,
        relativeName;

    dirName = oo::str::lastPathComponent(path);

    oo::fs::RecursiveDirectoryEnumerator dirEnum(oo::fs::pathFromUTF8(path));
    for (;;) {
        const std::optional<std::string> nextName = dirEnum.next();
        if (!nextName.has_value())
            break;
        const std::string& name = *nextName;

        const oo::fs::FileType type = dirEnum.entryType();
        relativeName = oo::str::appendingPathComponent(dirName, name);

        if (_junkFileNames.contains(name)) {
            OO_LOG("verifyOXP.scanFiles.skipJunk", "NOTE: skipping junk file {}/{}.", dirName, name);
        } else if (type == oo::fs::FileType::regular) {
            lcName = oo::str::lowercase(name);
            const auto existing = result.find(lcName);

            if (existing == result.end()) {
                OO_LOG("verifyOXP.verbose.listFiles", "- {}", name);
                result[lcName] = name;
            } else {
                OO_LOG("verifyOXP.scanFiles.overloadedName", "***** ERROR: {} '{}' conflicts with {} named '{}', ignoring. (OXPs must work on case-insensitive file systems!)", "file", relativeName, "file", oo::str::appendingPathComponent(dirName, existing->second));
            }
        } else {
            if (type == oo::fs::FileType::directory) {
                dirEnum.skipDescendents();
                if (!_skipDirectoryNames.contains(name)) {
                    OO_LOG("verifyOXP.scanFiles.directory", "----- WARNING: \"{}\" is a nested directory, ignoring.", relativeName);
                } else {
                    OO_LOG("verifyOXP.verbose.listFiles", "- Skipping {}/{}/", dirName, name);
                }
            } else if (type == oo::fs::FileType::symbolic_link) {
                OO_LOG("verifyOXP.scanFiles.symLink", "----- WARNING: \"{}\" is a symbolic link, ignoring.", relativeName);
            } else {
                OO_LOG("verifyOXP.scanFiles.nonStandardFile", "----- WARNING: \"{}\" is a non-standard file, ignoring.", relativeName);
            }
        }
    }

    return result;
}

void OOFileScannerVerifierStage::checkPListFormat(oo::PListFormat format, const std::optional<std::string>& file, const std::optional<std::string>& folder)
{
    std::string weirdnessKey;
    std::string formatDesc;
    std::optional<std::string> displayPath;

    if (format != oo::PListFormat::OpenStep && format != oo::PListFormat::XML) {
        displayPath = displayNameForFile(file, folder);
        weirdnessKey = oo::str::lowercase(*displayPath);

        if (!_badPLists.contains(weirdnessKey)) {
            // Warn about "non-standard" format
            _badPLists.insert(weirdnessKey);

            switch (format) {
            case oo::PListFormat::Binary:
                formatDesc = "Apple binary format";
                break;

#if OOLITE_GNUSTEP
            case oo::PListFormat::GNUstep:
                formatDesc = "GNUstep text format";
                break;

            case oo::PListFormat::GNUstepBinary:
                formatDesc = "GNUstep binary format";
                break;
#endif

            default:
                formatDesc = oo::str::format("unknown format (%i)", (int)format);
            }

            OO_LOG("verifyOXP.plist.weirdFormat", "----- WARNING: Property list {} is in {}; OpenStep text format and XML format are the recommended formats for Oolite.", displayPath.value_or("(null)"), formatDesc);
        }
    }
}

std::vector<std::string> OOFileScannerVerifierStage::constructReadMeNames()
{
    std::vector<std::string> result;
    std::size_t i, j, stemCount, extCount;
    std::string stem,
        extension;

    const oo::PList dict = verifier()->configurationDictionaryForKey("readMeNames");
    const oo::PList* stems = dict.get<oo::PList::Array>("stems");
    const oo::PList* extensions = dict.get<oo::PList::Array>("extensions");
    stemCount = stems != nullptr ? stems->count() : 0;
    extCount = extensions != nullptr ? extensions->count() : 0;
    if (stemCount * extCount == 0)
        return result;

    // Construct all stem+extension permutations; a stem or extension that is not a string (or
    // number) was nil, and skipped.
    for (i = 0; i != stemCount; ++i) {
        const oo::PList* stemEntry = stems->at(i);
        if (stemEntry->isString() || stemEntry->isNumber()) {
            stem = oo::str::lowercase(stems->at<std::string>(i));
            for (j = 0; j != extCount; ++j) {
                const oo::PList* extensionEntry = extensions->at(j);
                if (extensionEntry->isString() || extensionEntry->isNumber()) {
                    extension = oo::str::lowercase(extensions->at<std::string>(j));
                    result.push_back(stem + extension);
                }
            }
        }
    }

    return result;
}

// OOListUnusedFilesStage: C++ since bead oo-cwz (proposed ADR-0056 Amendment 1).

std::optional<std::string> OOListUnusedFilesStage::name()
{
    return kUnusedListerStageName;
}

std::optional<std::vector<std::string>> OOListUnusedFilesStage::dependencies()
{
    return std::vector<std::string> { kFileScannerStageName };
}

void OOListUnusedFilesStage::run()
{
    OO_LOG("verifyOXP.unusedFiles.unimplemented", "{}", "TODO: implement unused files check.");
}

// The verifier holds the C++ stages (it held their facades until bead oo-9ht.4).
std::string OOListUnusedFilesStage::nameForReverseDependencyForVerifier(OOOXPVerifier* verifier)
{
    OOOXPVerifierStage* stage = verifier->stageWithName(kUnusedListerStageName);
    if (stage == nullptr) {
        const oo::Ref<OOListUnusedFilesStage> newStage = oo::makeRef<OOListUnusedFilesStage>();
        verifier->registerStage(newStage.get());
    }

    return kUnusedListerStageName;
}

// OOFileHandlingVerifierStage: C++ since bead oo-up4b; global since bead oo-9ht.7 deleted its facade.

std::optional<std::vector<std::string>> OOFileHandlingVerifierStage::dependencies()
{
    return std::vector<std::string> { *OOFileScannerVerifierStage::nameForDependencyForVerifier(verifier()) };
}

std::optional<std::vector<std::string>> OOFileHandlingVerifierStage::dependents()
{
    return std::vector<std::string> { OOListUnusedFilesStage::nameForReverseDependencyForVerifier(verifier()) };
}

namespace {

BOOL CheckNameConflict(const std::string& lcName, const std::map<std::string, std::string, std::less<>>& directoryCases, const std::map<std::string, std::string, std::less<>>& rootFiles, std::string* outExisting, std::string* outExistingType)
{
    const auto directory = directoryCases.find(lcName);
    if (directory != directoryCases.end()) {
        if (outExisting != NULL)
            *outExisting = directory->second;
        if (outExistingType != NULL)
            *outExistingType = "directory";
        return YES;
    }

    const auto file = rootFiles.find(lcName);
    if (file != rootFiles.end()) {
        if (outExisting != NULL)
            *outExisting = file->second;
        if (outExistingType != NULL)
            *outExistingType = "file";
        return YES;
    }

    return NO;
}

} // namespace

#endif
