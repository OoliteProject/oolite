/*

OOCheckJSSyntaxVerifierStage.m


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

#import "OOCheckJSSyntaxVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOFoundationBridge.h"
#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "OOScript.h"
#import "OOStringParsing.h"

#include "oofnd/String.hpp"

static const char* const kStageName = "Checking JS Script file syntax";

namespace {

bool Contains(const std::vector<std::string>& strings, std::string_view string)
{
    return std::find(strings.begin(), strings.end(), string) != strings.end();
}

} // namespace

@implementation OOCheckJSSyntaxVerifierStage

- (id)name // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom(kStageName);
}

- (BOOL)shouldRun
{
    OOFileScannerVerifierStage* fileScanner = nil;

    fileScanner = [[self verifier] fileScannerStage];
    return (!oo::StringsFrom([fileScanner filesInFolder:@"Scripts"]).empty() || Contains(oo::StringsFrom([fileScanner filesInFolder:@"Config"]), "script.js"));
}

- (void)run
{
    OOFileScannerVerifierStage* fileScanner = nil;
    std::vector<std::string> scriptFiles;
    BOOL scriptsFolder = NO;
    BOOL configScript = NO;

    fileScanner = [[self verifier] fileScannerStage];
    scriptsFolder = [fileScanner filesInFolder:@"Scripts"] != nil;
    scriptFiles = oo::StringsFrom([fileScanner filesInFolder:@"Scripts"]);
    configScript = Contains(oo::StringsFrom([fileScanner filesInFolder:@"Config"]), "script.js");

    if (scriptsFolder == NO && configScript == NO)
        return;

    [[OOJavaScriptEngine sharedEngine] setShowErrorLocations:YES];

    for (const std::string& scriptFile : scriptFiles) {
        const std::string fileExt = oo::str::lowercase(oo::str::pathExtension(scriptFile));
        if (fileExt == "js" || fileExt == "es") {
            OOScript* script = [OOJSScript scriptWithPath:oo::OptionalString([fileScanner pathForFile:oo::NSStringFrom(scriptFile) inFolder:@"Scripts" referencedFrom:nil checkBuiltIn:NO]) properties:oo::PList()];
            (void)script;
        }
    }
    if (configScript == YES) {
        OOScript* script = [OOJSScript scriptWithPath:oo::OptionalString([fileScanner pathForFile:@"script.js" inFolder:@"Config" referencedFrom:nil checkBuiltIn:NO]) properties:oo::PList()];
        (void)script;
    }
}

@end

#endif
