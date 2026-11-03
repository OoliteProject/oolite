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
#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "OOLogging.h"
#import "OOPListParsing.h"
#import "OOPListScript.h"
#import "ResourceManager.h"
#import "Universe.h"

#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"

namespace {
// The strings in the array a property-list file holds (other elements skipped); nullopt when the
// file holds no array (what OOArrayFromFile answered nil for; its plist.wrongType line, which named
// the Foundation class, is not kept).
static std::optional<std::vector<std::string>> StringsFromArrayFile(const std::string& path)
{
    const oo::PList list = cxx_OOPropertyListFromFile(path);
    const oo::PList::Array* array = list.getIf<oo::PList::Array>();
    if (array == nullptr)
        return std::nullopt;
    std::vector<std::string> result;
    for (const oo::PList& element : *array) {
        if (const std::string* string = element.getIf<std::string>())
            result.push_back(*string);
    }
    return result;
}
} // namespace

@implementation OOScript

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)cxx_worldScriptsAtPath:(const std::string&)path
{
    std::string filePath;
    std::optional<std::vector<oo::ObjCRef<OOScript*>>> result;
    id script = nil;
    BOOL foundScript = NO;

    // First, look for world-scripts.plist.
    filePath = oo::str::appendingPathComponent(path, "world-scripts.plist");
    {
        std::optional<std::vector<std::string>> names = StringsFromArrayFile(filePath);
        if (names.has_value()) {
            foundScript = YES;
            result = [self scriptsFromList:*names];
        }
    }

    // Second, try to load a JavaScript.
    if (!result.has_value()) {
        filePath = oo::str::appendingPathComponent(path, "script.js");
        if (OOOxzFileExistsAtPath(filePath))
            foundScript = YES;
        else {
            filePath = oo::str::appendingPathComponent(path, "script.es");
            if (OOOxzFileExistsAtPath(filePath))
                foundScript = YES;
        }
        if (foundScript) {
            OO_LOG("script.load.javaScript", "Trying to load JavaScript script {}", filePath);
            oo::log::indentIf("script.load.javaScript");

            script = [OOJSScript scriptWithPath:filePath properties:oo::PList()];
            if (script != nil) {
                result = std::vector<oo::ObjCRef<OOScript*>> { oo::ObjCRef<OOScript*>(script) };
                OO_LOG("script.load.parseOK", "Successfully loaded JavaScript script {}", filePath);
            } else
                OO_LOG_ERR("script.load.parseError", "Failed to load JavaScript script {}", filePath);

            oo::log::outdentIf("script.load.javaScript");
        }
    }

    // Third, try to load a plist script.
    if (!result.has_value()) {
        filePath = oo::str::appendingPathComponent(path, "script.plist");
        if (OOOxzFileExistsAtPath(filePath)) {
            cxx_OOStandardsDeprecated(oo::str::format("Legacy script %s is deprecated", filePath.c_str()));
            if (!OOEnforceStandards()) {
                foundScript = YES;
                OO_LOG("script.load.pList", "Trying to load property list script {}", filePath);
                oo::log::indentIf("script.load.pList");

                result = [OOPListScript scriptsInPListFile:filePath];
                if (result.has_value())
                    OO_LOG("script.load.parseOK", "Successfully loaded property list script {}", filePath);
                else
                    OO_LOG_ERR("script.load.parseError", "Failed to load property list script {}", filePath);

                oo::log::outdentIf("script.load.pList");
            }
        }
    }

    if (!result.has_value() && foundScript) {
        OO_LOG("script.load.none", "No script could be loaded from {}", path);
    }

    return result;
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsFromFileNamed:(const std::string&)fileName
{
    std::optional<std::vector<oo::ObjCRef<OOScript*>>> result;
    std::optional<std::string> path = [ResourceManager cxx_pathForFileNamed:fileName inFolder:"Scripts"];
    if (path.has_value()) {
        result = [self scriptsFromFileAtPath:*path];
    }

    if (!result.has_value()) {
        OO_LOG_ERR("script.load.notFound", "Could not find script file {}.", fileName);
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
    // OXZ-aware exists is false for directories
    if (!OOOxzFileExistsAtPath(filePath))
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

    OO_LOG_ERR("script.load.badName", "Don't know how to load a script from {}.", filePath);
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
        path = [ResourceManager cxx_pathForFileNamed:fileName inFolder:"Scripts"];
        if (!path.has_value()) {
            OO_LOG_ERR("script.load.notFound", "Could not find script file {}.", fileName);
            return nil;
        }
        return [OOJSScript scriptWithPath:path properties:properties];
    } else if (extension == "plist") {
        OO_LOG_ERR("script.load.badName", "Can't load script named {} - legacy scripts are not supported in this context.", fileName);
        return nil;
    }

    OO_LOG_ERR("script.load.badName", "Don't know how to load a script from {}.", fileName);
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
        path = [ResourceManager cxx_pathForFileNamed:fileName inFolder:"AIs"];
        if (!path.has_value()) {
            OO_LOG_ERR("script.load.notFound", "Could not find script file {}.", fileName);
            return nil;
        }
        return [OOJSScript scriptWithPath:path properties:properties];
    } else if (extension == "plist") {
        OO_LOG_ERR("script.load.badName", "Can't load script named {} - legacy scripts are not supported in this context.", fileName);
        return nil;
    }

    OO_LOG_ERR("script.load.badName", "Don't know how to load a script from {}.", fileName);
    return nil;
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return oo::str::format("\"%s\" version %s", [self cxx_name].value_or("(null)").c_str(), [self cxx_version].value_or("(null)").c_str());
}

- (std::optional<std::string>)cxx_name
{
    OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
    return std::nullopt;
}

- (std::optional<std::string>)scriptDescription
{
    OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
    return std::nullopt;
}

- (std::optional<std::string>)cxx_version
{
    OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
    return std::nullopt;
}

- (std::optional<std::string>)displayName
{
    const std::optional<std::string> name = [self cxx_name];
    std::optional<std::string> version = [self cxx_version];

    if (version.has_value())
        return oo::str::format("%s %s", name.value_or("(null)").c_str(), version->c_str());
    else
        return name;
}

- (BOOL)requiresTickle
{
    return NO;
}

- (void)runWithTarget:(Entity*)target
{
    OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
}

@end
