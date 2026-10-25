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

#include "OOScript.h"
#include "OOJSScript.h"
#include "OOPListScript.h"
#include "OOLogging.h"
#include "Universe.h"
#include "OOJavaScriptEngine.h"
#include "OOPListParsing.h"
#include "ResourceManager.h"
#include "OODebugStandards.h"

#include "oofnd/objc/OOObject.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>
#include "oofnd/Ref.hpp"	// oo::autorelease (beads oo-pvhrh, oo-31u.7)


namespace {
// The strings in the array a property-list file holds (other elements skipped); nullopt when the
// file holds no array (what OOArrayFromFile answered nil for; its plist.wrongType line, which named
// the Foundation class, is not kept).
static std::optional<std::vector<std::string>> StringsFromArrayFile(const std::string &path)
{
	const oo::PList list = cxx_OOPropertyListFromFile(path);
	const oo::PList::Array *array = list.getIf<oo::PList::Array>();
	if (array == nullptr)  return std::nullopt;
	std::vector<std::string> result;
	for (const oo::PList &element : *array)
	{
		if (const std::string *string = element.getIf<std::string>())  result.push_back(*string);
	}
	return result;
}


// The C++ class's name, as [self class] named an Objective-C script's class (the deleted facade's
// -description named it so; bead oo-9ht.133 moved it here).
static std::string ClassName(const OOScript &script)
{
	int status = 0;
	char *demangled = abi::__cxa_demangle(typeid(script).name(), nullptr, nullptr, &status);
	std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(script).name();
	std::free(demangled);
	if (result.starts_with("cxx::"))  result.erase(0, 5);
	return result;
}
} // namespace


std::optional<std::vector<oo::Ref<OOScript>>> OOScript::worldScriptsAtPath(const std::string &path)
{
	std::string			filePath;
	std::optional<std::vector<oo::Ref<OOScript>>>	result;
	oo::Ref<OOScript>	script;
	bool				foundScript = false;
	
	// First, look for world-scripts.plist.
	filePath = oo::str::appendingPathComponent(path, "world-scripts.plist");
	{
		std::optional<std::vector<std::string>> names = StringsFromArrayFile(filePath);
		if (names.has_value())
		{
			foundScript = true;
			result = scriptsFromList(*names);
		}
	}
	
	// Second, try to load a JavaScript.
	if (!result.has_value())
	{
		filePath = oo::str::appendingPathComponent(path, "script.js");
		if (OOOxzFileExistsAtPath(filePath)) foundScript = true;
		else
		{
			filePath = oo::str::appendingPathComponent(path, "script.es");
			if (OOOxzFileExistsAtPath(filePath)) foundScript = true;
		}
		if (foundScript)
		{
			OO_LOG("script.load.javaScript", "Trying to load JavaScript script {}", filePath);
			oo::log::indentIf("script.load.javaScript");
			
			script = OOJSScript::scriptWithPath(filePath, oo::PList());
			if (script != nullptr)
			{
				result = std::vector<oo::Ref<OOScript>>{ script };
				OO_LOG("script.load.parseOK", "Successfully loaded JavaScript script {}", filePath);
			}
			else  OO_LOG_ERR("script.load.parseError", "Failed to load JavaScript script {}", filePath);
			
			oo::log::outdentIf("script.load.javaScript");
		}
	}
	
	// Third, try to load a plist script.
	if (!result.has_value())
	{
		filePath = oo::str::appendingPathComponent(path, "script.plist");
		if (OOOxzFileExistsAtPath(filePath))
		{
			cxx_OOStandardsDeprecated(oo::str::format("Legacy script %s is deprecated", filePath.c_str()));
			if (!OOEnforceStandards())
			{
				foundScript = true;
				OO_LOG("script.load.pList", "Trying to load property list script {}", filePath);
				oo::log::indentIf("script.load.pList");
				
				result = ::OOPListScript::scriptsInPListFile(filePath);
				if (result.has_value())  OO_LOG("script.load.parseOK", "Successfully loaded property list script {}", filePath);
				else  OO_LOG_ERR("script.load.parseError", "Failed to load property list script {}", filePath);
			
				oo::log::outdentIf("script.load.pList");
			}
		}
	}
	
	if (!result.has_value() && foundScript)
	{
		OO_LOG("script.load.none", "No script could be loaded from {}", path);
	}
	
	return result;
}


std::optional<std::vector<oo::Ref<OOScript>>> OOScript::scriptsFromFileNamed(const std::string &fileName)
{
	std::optional<std::vector<oo::Ref<OOScript>>> result;
	std::optional<std::string> path = ResourceManager::pathForFileNamed(fileName, "Scripts");
	if (path.has_value())
	{
		result = scriptsFromFileAtPath(*path);
	}
	
	if (!result.has_value())
	{
		OO_LOG_ERR("script.load.notFound", "Could not find script file {}.", fileName);
	}
	
	return result;
}


std::vector<oo::Ref<OOScript>> OOScript::scriptsFromList(const std::vector<std::string> &fileNames)
{
	std::vector<oo::Ref<OOScript>>	result;
	
	result.reserve(fileNames.size());
	
	for (const std::string &name : fileNames)
	{
		std::optional<std::vector<oo::Ref<OOScript>>> scripts = scriptsFromFileNamed(name);
		if (scripts.has_value())  result.insert(result.end(), scripts->begin(), scripts->end());
	}
	
	return result;
}


std::optional<std::vector<oo::Ref<OOScript>>> OOScript::scriptsFromFileAtPath(const std::string &filePath)
{
	// OXZ-aware exists is false for directories
	if (!OOOxzFileExistsAtPath(filePath)) return std::nullopt;
	
	std::string extension = oo::str::lowercase(oo::str::pathExtension(filePath));
	
	if (extension == "js" || extension == "es")
	{
		std::optional<std::vector<oo::Ref<OOScript>>>	result;
		oo::Ref<OOScript>	script = OOJSScript::scriptWithPath(filePath, oo::PList());
		if (script != nullptr) result = std::vector<oo::Ref<OOScript>>{ script };
		return result;
	}
	else if (extension == "plist")
	{
		cxx_OOStandardsDeprecated(oo::str::format("Legacy script %s is deprecated", filePath.c_str()));
		if (OOEnforceStandards())
		{
			return std::nullopt;
		}
		return ::OOPListScript::scriptsInPListFile(filePath);
	}
	
	OO_LOG_ERR("script.load.badName", "Don't know how to load a script from {}.", filePath);
	return std::nullopt;
}


oo::Ref<OOScript> OOScript::jsScriptFromFileNamed(const std::string &fileName, const oo::PList &properties)
{
	std::string			extension;
	std::optional<std::string>	path;
	
	if (fileName.empty())  return nullptr;
	
	extension = oo::str::lowercase(oo::str::pathExtension(fileName));
	if (extension == "js" || extension == "es")
	{
		path = ResourceManager::pathForFileNamed(fileName, "Scripts");
		if (!path.has_value())
		{
			OO_LOG_ERR("script.load.notFound", "Could not find script file {}.", fileName);
			return nullptr;
		}
		return OOJSScript::scriptWithPath(path, properties);
	}
	else if (extension == "plist")
	{
		OO_LOG_ERR("script.load.badName", "Can't load script named {} - legacy scripts are not supported in this context.", fileName);
		return nullptr;
	}
	
	OO_LOG_ERR("script.load.badName", "Don't know how to load a script from {}.", fileName);
	return nullptr;
}


oo::Ref<OOScript> OOScript::jsAIScriptFromFileNamed(const std::string &fileName, const oo::PList &properties)
{
	std::string			extension;
	std::optional<std::string>	path;
	
	if (fileName.empty())  return nullptr;
	
	extension = oo::str::lowercase(oo::str::pathExtension(fileName));
	if (extension == "js" || extension == "es")
	{
		path = ResourceManager::pathForFileNamed(fileName, "AIs");
		if (!path.has_value())
		{
			OO_LOG_ERR("script.load.notFound", "Could not find script file {}.", fileName);
			return nullptr;
		}
		return OOJSScript::scriptWithPath(path, properties);
	}
	else if (extension == "plist")
	{
		OO_LOG_ERR("script.load.badName", "Can't load script named {} - legacy scripts are not supported in this context.", fileName);
		return nullptr;
	}
	
	OO_LOG_ERR("script.load.badName", "Don't know how to load a script from {}.", fileName);
	return nullptr;
}


std::optional<std::string> OOScript::descriptionComponents()
{
	return oo::str::format("\"%s\" version %s", name().value_or("(null)").c_str(), version().value_or("(null)").c_str());
}


std::optional<std::string> OOScript::name()
{
	OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
	return std::nullopt;
}


std::optional<std::string> OOScript::scriptDescription()
{
	OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
	return std::nullopt;
}


std::optional<std::string> OOScript::version()
{
	OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
	return std::nullopt;
}


std::optional<std::string> OOScript::displayName()
{
	const std::optional<std::string> name = this->name();
	std::optional<std::string> version = this->version();
	
	if (version.has_value())  return oo::str::format("%s %s", name.value_or("(null)").c_str(), version->c_str());
	else  return name;
}


bool OOScript::requiresTickle()
{
	return false;
}


void OOScript::runWithTarget(Entity *)
{
	OO_LOG_ERR(cxx_kOOLogSubclassResponsibility, "{}", "OOScript should not be used directly!");
}


// OOScript (JavaScriptEvents): NO for every script but a JS one (OOJSScript overrides).
bool OOScript::callMethod(ooscript::PropertyId, ooscript::Context, ooscript::Value *, int, ooscript::Value *)
{
	return false;
}


// The deleted facade's class, which a writer error named.
std::string OOScript::className() const
{
	return "OOScript";
}


// The deleted facade's -description: the C++ class's name and the address (the script's, which is
// its identity now), then the components.
std::string OOScript::description() const
{
	OOScript &script = const_cast<OOScript &>(*this);
	std::string result = oo::str::format("<%s %s>", ClassName(script).c_str(), oo::str::pointerDescription(this).c_str());
	if (const std::optional<std::string> components = script.descriptionComponents())  result += "{" + *components + "}";
	return result;
}


// OOObject's -oo_jsValueInContext: (OOObjectJSValueInContext), which the facade answered for every
// script but a JS one.
ooscript::Value OOScript::jsValueInContext(ooscript::Context)
{
	return ooscript::undefinedValue();
}


// OOObject's -oo_clearJSSelf:, which did nothing.
void OOScript::clearJSSelf(ooscript::Object)
{
}


/*	OOScriptAutorelease(): the script goes to the innermost oo::AutoreleaseScope, whose drain releases it
	where the keeper object that held it was released (beads oo-pvhrh, oo-31u.7).
*/
void OOScriptAutorelease(oo::Ref<OOScript> script)
{
	if (script == nullptr)  return;
	oo::autorelease(std::move(script));
}
