/*

OOScript.m

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

#import "OOScript.h"
#import "OODebugStandards.h"
#import "OOFoundationBridge.h"
#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "OOLogging.h"
#import "OOPListParsing.h"
#import "OOPListScript.h"
#import "ResourceManager.h"
#import "Universe.h"

namespace {
// The strings in an array a callee still returns as a Foundation array; nullopt for nil.
static std::optional<std::vector<std::string>> StringsOrNil(id array)
{
    if (array == nil)
        return std::nullopt;
    return oo::StringsFrom(array);
}
} // namespace

@implementation OOScript

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)cxx_worldScriptsAtPath:(const std::string&)path
{
    NSFileManager* fmgr = nil;
    std::string filePath;
    std::optional<std::vector<oo::ObjCRef<OOScript*>>> result;
    id script = nil;
    BOOL foundScript = NO;

    fmgr = [NSFileManager defaultManager];

    // First, look for world-scripts.plist.
    filePath = oo::str::appendingPathComponent(path, "world-scripts.plist");
    {
        std::optional<std::vector<std::string>> names = StringsOrNil(OOArrayFromFile(oo::NSStringFrom(filePath)));
        if (names.has_value()) {
            foundScript = YES;
            result = [self scriptsFromList:*names];
        }
    }

    // Second, try to load a JavaScript.
    if (!result.has_value()) {
        filePath = oo::str::appendingPathComponent(path, "script.js");
        if ([fmgr oo_oxzFileExistsAtPath:oo::NSStringFrom(filePath)])
            foundScript = YES;
        else {
            filePath = oo::str::appendingPathComponent(path, "script.es");
            if ([fmgr oo_oxzFileExistsAtPath:oo::NSStringFrom(filePath)])
                foundScript = YES;
        }
        if (foundScript) {
            OOLog(@"script.load.javaScript", @"Trying to load JavaScript script %@", oo::NSStringFrom(filePath));
            OOLogIndentIf(@"script.load.javaScript");

            script = [OOJSScript scriptWithPath:filePath properties:oo::PList()];
            if (script != nil) {
                result = std::vector<oo::ObjCRef<OOScript*>> { oo::ObjCRef<OOScript*>(script) };
                OOLog(@"script.load.parseOK", @"Successfully loaded JavaScript script %@", oo::NSStringFrom(filePath));
            } else
                OOLogERR(@"script.load.parseError", @"Failed to load JavaScript script %@", oo::NSStringFrom(filePath));

            OOLogOutdentIf(@"script.load.javaScript");
        }
    }

    // Third, try to load a plist script.
    if (!result.has_value()) {
        filePath = oo::str::appendingPathComponent(path, "script.plist");
        if ([fmgr oo_oxzFileExistsAtPath:oo::NSStringFrom(filePath)]) {
            cxx_OOStandardsDeprecated(oo::str::format("Legacy script %s is deprecated", filePath.c_str()));
            if (!OOEnforceStandards()) {
                foundScript = YES;
                OOLog(@"script.load.pList", @"Trying to load property list script %@", oo::NSStringFrom(filePath));
                OOLogIndentIf(@"script.load.pList");

                result = [OOPListScript scriptsInPListFile:filePath];
                if (result.has_value())
                    OOLog(@"script.load.parseOK", @"Successfully loaded property list script %@", oo::NSStringFrom(filePath));
                else
                    OOLogERR(@"script.load.parseError", @"Failed to load property list script %@", oo::NSStringFrom(filePath));

                OOLogOutdentIf(@"script.load.pList");
            }
        }
    }

    if (!result.has_value() && foundScript) {
        OOLog(@"script.load.none", @"No script could be loaded from %@", oo::NSStringFrom(path));
    }

    return result;
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsFromFileNamed:(const std::string&)fileName
{
    std::optional<std::vector<oo::ObjCRef<OOScript*>>> result;
    std::optional<std::string> path = oo::OptionalString([ResourceManager pathForFileNamed:oo::NSStringFrom(fileName) inFolder:@"Scripts"]);
    if (path.has_value()) {
        result = [self scriptsFromFileAtPath:*path];
    }

    if (!result.has_value()) {
        OOLogERR(@"script.load.notFound", @"Could not find script file %@.", oo::NSStringFrom(fileName));
    }

    return result;
}

+ (std::vector<oo::ObjCRef<OOScript*>>)scriptsFromList:(const std::vector<std::string>&)fileNames
{
    std::vector<oo::ObjCRef<OOScript*>> result;

    result.reserve(fileNames.size());

    for (const std::string& name : fileNames) {
        std::optional<std::vector<oo::ObjCRef<OOScript*>>> scripts = [self scriptsFromFileNamed:name];
        if (scripts.has_value())
            result.insert(result.end(), scripts->begin(), scripts->end());
    }

    return result;
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsFromFileAtPath:(const std::string&)filePath
{
    // oo_oxzFile always returns false for directories
    if (![[NSFileManager defaultManager] oo_oxzFileExistsAtPath:oo::NSStringFrom(filePath)])
        return std::nullopt;

    std::string extension = oo::str::lowercase(oo::str::pathExtension(filePath));

    if (extension == "js" || extension == "es") {
        std::optional<std::vector<oo::ObjCRef<OOScript*>>> result;
        OOScript* script = [OOJSScript scriptWithPath:filePath properties:oo::PList()];
        if (script != nil)
            result = std::vector<oo::ObjCRef<OOScript*>> { oo::ObjCRef<OOScript*>(script) };
        return result;
    } else if (extension == "plist") {
        cxx_OOStandardsDeprecated(oo::str::format("Legacy script %s is deprecated", filePath.c_str()));
        if (OOEnforceStandards()) {
            return std::nullopt;
        }
        return [OOPListScript scriptsInPListFile:filePath];
    }

    OOLogERR(@"script.load.badName", @"Don't know how to load a script from %@.", oo::NSStringFrom(filePath));
    return std::nullopt;
}

+ (id)cxx_jsScriptFromFileNamed:(const std::string&)fileName properties:(const oo::PList&)properties
{
    std::string extension;
    std::optional<std::string> path;

    if (fileName.empty())
        return nil;

    extension = oo::str::lowercase(oo::str::pathExtension(fileName));
    if (extension == "js" || extension == "es") {
        path = oo::OptionalString([ResourceManager pathForFileNamed:oo::NSStringFrom(fileName) inFolder:@"Scripts"]);
        if (!path.has_value()) {
            OOLogERR(@"script.load.notFound", @"Could not find script file %@.", oo::NSStringFrom(fileName));
            return nil;
        }
        return [OOJSScript scriptWithPath:path properties:properties];
    } else if (extension == "plist") {
        OOLogERR(@"script.load.badName", @"Can't load script named %@ - legacy scripts are not supported in this context.", oo::NSStringFrom(fileName));
        return nil;
    }

    OOLogERR(@"script.load.badName", @"Don't know how to load a script from %@.", oo::NSStringFrom(fileName));
    return nil;
}

+ (id)cxx_jsAIScriptFromFileNamed:(const std::string&)fileName properties:(const oo::PList&)properties
{
    std::string extension;
    std::optional<std::string> path;

    if (fileName.empty())
        return nil;

    extension = oo::str::lowercase(oo::str::pathExtension(fileName));
    if (extension == "js" || extension == "es") {
        path = oo::OptionalString([ResourceManager pathForFileNamed:oo::NSStringFrom(fileName) inFolder:@"AIs"]);
        if (!path.has_value()) {
            OOLogERR(@"script.load.notFound", @"Could not find script file %@.", oo::NSStringFrom(fileName));
            return nil;
        }
        return [OOJSScript scriptWithPath:path properties:properties];
    } else if (extension == "plist") {
        OOLogERR(@"script.load.badName", @"Can't load script named %@ - legacy scripts are not supported in this context.", oo::NSStringFrom(fileName));
        return nil;
    }

    OOLogERR(@"script.load.badName", @"Don't know how to load a script from %@.", oo::NSStringFrom(fileName));
    return nil;
}

- (id)descriptionComponents // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom(oo::str::format("\"%s\" version %s", oo::DescriptionOf([self name]).c_str(), oo::DescriptionOf([self version]).c_str()));
}

- (id)name // shared selector (proposed ADR-0043)
{
    OOLogERR(kOOLogSubclassResponsibility, @"%@", @"OOScript should not be used directly!");
    return nil;
}

- (id)scriptDescription // shared selector (proposed ADR-0043)
{
    OOLogERR(kOOLogSubclassResponsibility, @"%@", @"OOScript should not be used directly!");
    return nil;
}

- (id)version // shared selector (proposed ADR-0043)
{
    OOLogERR(kOOLogSubclassResponsibility, @"%@", @"OOScript should not be used directly!");
    return nil;
}

- (id)displayName // shared selector (proposed ADR-0043)
{
    id name = [self name];
    std::optional<std::string> version = oo::OptionalString([self version]);

    if (version.has_value())
        return oo::NSStringFrom(oo::str::format("%s %s", oo::DescriptionOf(name).c_str(), version->c_str()));
    else if (name != nil)
        return oo::NSStringFrom(oo::DescriptionOf(name));
    else
        return nil;
}

- (BOOL)requiresTickle
{
    return NO;
}

- (void)runWithTarget:(Entity*)target
{
    OOLogERR(kOOLogSubclassResponsibility, @"%@", @"OOScript should not be used directly!");
}

@end
