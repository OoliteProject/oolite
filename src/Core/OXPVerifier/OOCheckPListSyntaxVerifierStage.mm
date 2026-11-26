/*

OOCheckPListSyntaxVerifierStage.m


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

#import "OOCheckPListSyntaxVerifierStage.h"
#import "OOPListView.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOFoundationBridge.h"

static const char* const kStageName = "Checking plist well-formedness";

namespace {

// The strings of <key>'s array in a configuration dictionary, in order (an array of plist names).
std::vector<std::string> StringsForKey(const oo::PList& dictionary, std::string_view key)
{
    std::vector<std::string> result;
    if (const oo::PList* array = dictionary.get<oo::PList::Array>(key)) {
        for (const oo::PList& element : *array->getIf<oo::PList::Array>()) {
            if (const std::string* string = element.getIf<std::string>())
                result.push_back(*string);
        }
    }
    return result;
}

bool Contains(const std::vector<std::string>& strings, const std::string& string)
{
    return std::find(strings.begin(), strings.end(), string) != strings.end();
}

} // namespace

@implementation OOCheckPListSyntaxVerifierStage

- (std::optional<std::string>)cxx_name
{
    return kStageName;
}

- (BOOL)shouldRun
{
    return YES;
}

- (void)run
{
    OOFileScannerVerifierStage* fileScanner = nil;

    fileScanner = [[self verifier] fileScannerStage];

    const oo::PList knownFiles = [[self verifier] cxx_configurationDictionaryForKey:"knownFiles"];
    const std::vector<std::string> plists = StringsForKey(knownFiles, "Config");
    const std::vector<std::string> arrayPlists = StringsForKey(knownFiles, "ConfigArrays");
    const std::vector<std::string> dictionaryPlists = StringsForKey(knownFiles, "ConfigDictionaries");

    for (const std::string& plistName : plists) {
        // don't scan a js file as a plist
        if (plistName == "script.js")
            continue;

        if ([fileScanner cxx_fileExists:plistName inFolder:"Config" referencedFrom:std::nullopt checkBuiltIn:NO]) {
            OO_LOG("verifyOXP.syntaxCheck", "Checking {}", plistName);
            const oo::PList retrieve = [fileScanner cxx_plistNamed:plistName inFolder:"Config" referencedFrom:std::nullopt checkBuiltIn:NO];
            if (!retrieve.isNull()) {
                if (retrieve.isArray()) {
                    if (!Contains(arrayPlists, plistName)) {
                        OO_LOG("verifyOXP.syntaxCheck.error", "{} should be an array but isn't.", plistName);
                    }
                } else if (retrieve.isDict()) {
                    if (!Contains(dictionaryPlists, plistName)) {
                        OO_LOG("verifyOXP.syntaxCheck.error", "{} should be an array but isn't.", plistName);
                    }
                } else {
                    OO_LOG("verifyOXP.syntaxCheck.error", "{} is neither an array nor a dictionary.", plistName);
                }
            }
        }
    }
}

@end

#endif
