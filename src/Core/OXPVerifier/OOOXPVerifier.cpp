/*

OOOXPVerifier.mm

OOOXPVerifier (bead oo-tsa4; proposed ADR-0056). The bodies are the Objective-C methods'
with the message syntax converted: the verifier's own methods are member calls, the stages' are
calls on the C++ stages, and the cache manager is the C++ one. The stages are kept as the C++
stages and described with their description() (they were kept, and handed to OO_LOG, as their
Objective-C objects until bead oo-9ht.4 deleted the stage facade). Global since bead oo-9ht.130
deleted the verifier's own Objective-C facade.


Copyright (C) 2007-2013 Jens Ayton and contributors

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
	see "verifier design.txt".
*/

#include "OOOXPVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#if OOLITE_WINDOWS

#pragma push_macro("interface")
#undef interface
#define interface struct

#include <shlwapi.h>

#pragma pop_macro("interface")

#include <tchar.h>
#endif

#include "OOOXPVerifierStage.h"
#include "OOLoggingExtended.h"
#include "oofnd/Log.hpp"
#include "ResourceManager.h"
#include "GameController.h"
#include "OOCacheManager.h"
#include "OODebugStandards.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Process.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/Date.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/String.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/PListGet.hpp"
#include "OOAIStateMachineVerifierStage.h"
#include "OOCheckJSSyntaxVerifierStage.h"
#include "OOCheckPListSyntaxVerifierStage.h"
#include "OOCheckDemoShipsPListVerifierStage.h"
#include "OOCheckRequiresPListVerifierStage.h"
#include "OOCheckEquipmentPListVerifierStage.h"
#include "OOTextureVerifierStage.h"
#include "OOCheckShipDataPListVerifierStage.h"

namespace {
void SwitchLogFile(const std::string &name);
void NoteVerificationStage(const std::string &displayName, const std::string &stage);
void OpenLogFile();


bool IsPathSeparator(char c)
{
	return c == '/' || c == '\\';
}


/*	-stringByExpandingTildeInPath as gnustep-base 1.31.1 answers it on Windows (probed): a path
	that is "~" or starts with "~" and a separator ('/' or '\') becomes the home directory
	(oo::ResourcePaths, '/' separators) followed by the rest's non-empty components joined with
	'/' ("~/a\\b/" -> "<home>/a/b"); anything else is returned as it is. "~user" is also left as it
	is: GNUstep expanded it only for the current user's own name, which is not looked up here.
*/
std::string ExpandTildeInPath(const std::string &path)
{
	if (path.empty() || path[0] != '~')  return path;
	if (path.size() > 1 && !IsPathSeparator(path[1]))  return path;

	std::string result = oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory());
	std::string component;
	for (size_t i = 1; i <= path.size(); i++)
	{
		if (i == path.size() || IsPathSeparator(path[i]))
		{
			if (!component.empty())  result += "/" + component;
			component.clear();
		}
		else  component += path[i];
	}
	return result;
}


/*	The stages verifyOXP.plist names ("stages") that are C++ (proposed ADR-0056 amendment oo-up4b
	item 5). A converted leaf stage is global and had no Objective-C class, so OOClassFromName found
	nothing (no name is looked up as a class since bead oo-dbz.2); -registerBaseStages looks here first and registers the stage (its facade until bead
	oo-9ht.4). Each bead that converts such a stage adds its line. It is the C++ verifier's since
	oo-tsa4.
*/
struct CxxStage
{
	std::string_view						name;
	oo::Ref<OOOXPVerifierStage>				(*make)();
};

constexpr CxxStage kCxxStages[] =
{
	{ "OOAIStateMachineVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOAIStateMachineVerifierStage>()); } },
	{ "OOCheckJSSyntaxVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOCheckJSSyntaxVerifierStage>()); } },
	{ "OOCheckPListSyntaxVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOCheckPListSyntaxVerifierStage>()); } },
	{ "OOCheckDemoShipsPListVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOCheckDemoShipsPListVerifierStage>()); } },
	{ "OOCheckRequiresPListVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOCheckRequiresPListVerifierStage>()); } },
	{ "OOCheckEquipmentPListVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOCheckEquipmentPListVerifierStage>()); } },
	{ "OOTextureVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOTextureVerifierStage>()); } },
	{ "OOCheckShipDataPListVerifierStage", [] { return oo::Ref<OOOXPVerifierStage>(oo::makeRef<OOCheckShipDataPListVerifierStage>()); } },
};


}



oo::Ref<::OOOXPVerifierStage> (*OOOXPVerifier::sTestStageMaker)(const std::string &name) = nullptr;


/**
 * \ingroup cli
 * Scans the command line for -verify-oxp or --verify-oxp, followed by a
 * path to the oxp to verify.
 *
 * @return true or false
 */
bool OOOXPVerifier::runVerificationIfRequested()
{
	std::optional<std::string>	foundPath;
	bool				exists, isDirectory;
	oo::Ref<OOOXPVerifier>	verifier;
	
	const std::vector<std::string> &arguments = oo::process::arguments();

	// Scan for -verify-oxp or --verify-oxp followed by relative path
	for (size_t argIndex = 0; argIndex < arguments.size(); argIndex++)
	{
		const std::string &arg = arguments[argIndex];
		if (arg == "-verify-oxp" || arg == "--verify-oxp")
		{
			if (argIndex + 1 < arguments.size())  foundPath = arguments[argIndex + 1];
			if (!foundPath.has_value())
			{
				OO_LOG("verifyOXP.noPath", "***** ERROR: {} passed without path argument; nothing to verify.", arg.c_str());
				return true;
			}
			foundPath = ExpandTildeInPath(*foundPath);
			break;
		}
	}
	
	if (!foundPath.has_value())
	{
		return false;
	}
	
	// We got a path; does it point to a directory?
	oo::fs::FileType foundType = oo::fs::fileType(oo::fs::pathFromUTF8(*foundPath));
	exists = (foundType != oo::fs::FileType::none);
	isDirectory = (foundType == oo::fs::FileType::directory);
	if (!exists)
	{
		OO_LOG("verifyOXP.badPath", "***** ERROR: no OXP exists at path \"{}\"; nothing to verify.", *foundPath);
	}
	else if (!isDirectory)
	{
		OO_LOG("verifyOXP.badPath", "***** ERROR: \"{}\" is a file, not an OXP directory; nothing to verify.", *foundPath);
	}
	else
	{
		verifier = createWithPath(foundPath);
		if (verifier != nullptr)  verifier->run();	// -run sent to nil did nothing
		verifier = nullptr;
	}
	
	// Whether or not we got a valid path, -verify-oxp was passed.
	return true;
}


void OOOXPVerifier::registerStage(::OOOXPVerifierStage *stage)
{
	std::optional<std::string>	name;
	::OOOXPVerifierStage		*existing = nullptr;

	// Sanity checking
	if (stage == nullptr)  return;

	// A stage is a C++ OOOXPVerifierStage (since bead oo-9ht.4), so the check that it was a
	// subclass of OOOXPVerifierStage is in registerBaseStages(), for a class found by its name.

	if (!_openForRegistration)
	{
		OO_LOG("verifyOXP.registration.failed", "Attempt to register verifier stage {} after registration closed, ignoring.", stage->description());
		return;
	}

	name = stage->name();
	if (!name.has_value())
	{
		OO_LOG("verifyOXP.registration.failed", "Attempt to register verifier stage {} with nil name, ignoring.", stage->description());
		return;
	}

	// We can only have one stage with a given name. Registering the same stage twice is OK, though.
	const auto found = _stagesByName.find(*name);
	existing = found != _stagesByName.end() ? found->second.get() : nullptr;
	if (existing == stage)  return;
	if (existing != nullptr)
	{
		OO_LOG("verifyOXP.registration.failed", "Attempt to register verifier stage {} with same name as stage {}, ignoring.", stage->description(), existing->description());
		return;
	}

	// Checks passed, store state.
	// The stage keeps the verifier, unretained (it kept the Objective-C facade until bead oo-qg71f).
	stage->setVerifier(this);
	_stagesByName[*name] = oo::Ref<::OOOXPVerifierStage>(stage);
	_waitingStages.push_back(oo::Ref<::OOOXPVerifierStage>(stage));
}


std::optional<std::string> OOOXPVerifier::oxpPath()
{
	return _basePath;
}


std::optional<std::string> OOOXPVerifier::oxpDisplayName()
{
	return _displayName;
}


::OOOXPVerifierStage *OOOXPVerifier::stageWithName(const std::string &name)
{
	const auto found = _stagesByName.find(name);
	return found != _stagesByName.end() ? found->second.get() : nullptr;
}


oo::PList OOOXPVerifier::configurationValueForKey(const std::string &key)
{
	const oo::PList *value = _verifierPList.find(key);
	return value != nullptr ? *value : oo::PList();
}


oo::PList OOOXPVerifier::configurationArrayForKey(const std::string &key)
{
	const oo::PList *array = _verifierPList.get<oo::PList::Array>(key);
	return array != nullptr ? *array : oo::PList();
}


oo::PList OOOXPVerifier::configurationDictionaryForKey(const std::string &key)
{
	const oo::PList *dictionary = _verifierPList.get<oo::PList::Dict>(key);
	return dictionary != nullptr ? *dictionary : oo::PList();
}


std::optional<std::string> OOOXPVerifier::configurationStringForKey(const std::string &key)
{
	const oo::PList *value = _verifierPList.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return _verifierPList.get<std::string>(key);
}


std::optional<std::vector<std::string>> OOOXPVerifier::configurationSetForKey(const std::string &key)
{
	const oo::PList *array = _verifierPList.get<oo::PList::Array>(key);
	if (array == nullptr)  return std::nullopt;
	
	std::set<std::string> strings;
	for (const oo::PList &element : *array->getIf<oo::PList::Array>())
	{
		if (const std::string *string = element.getIf<std::string>())  strings.insert(*string);
	}
	return std::vector<std::string>(strings.begin(), strings.end());
}

// Private

oo::Ref<OOOXPVerifier> OOOXPVerifier::createWithPath(const std::optional<std::string> &path)
{
	oo::Ref<OOOXPVerifier> verifier = oo::adopt(new OOOXPVerifier);
	if (!verifier->initWithPath(path))  return nullptr;
	return verifier;
}


bool OOOXPVerifier::initWithPath(const std::optional<std::string> &path)
{
	OOSetStandardsForOXPVerifierMode();

	// Any plist format; missing, unreadable or not a dictionary is no configuration, as
	// -dictionaryWithContentsOfFile: returned nil for them.
	const std::optional<std::string> builtInPath = ResourceManager::builtInPath();
	if (builtInPath.has_value())
	{
		const std::string verifierPListPath = oo::str::appendingPathComponent(oo::str::appendingPathComponent(*builtInPath, "Config"), "verifyOXP.plist");
		if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(oo::fs::pathFromUTF8(verifierPListPath)); bytes && !bytes->empty())
		{
			oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
			if (parsed && parsed->isDict())  _verifierPList = std::move(*parsed);
		}
	}

	_basePath = path.value_or(std::string());	// never nullopt: the path always came from the command line
	_displayName = oo::str::lastPathComponent(_basePath);	// what GNUstep's -displayNameAtPath: returns

	if (_verifierPList.isNull())
	{
		OO_LOG("verifyOXP.setup.failed", "{}", "***** ERROR: failed to set up OXP verifier.");
		return false;
	}

	_openForRegistration = true;

	return true;
}


void OOOXPVerifier::run()
{
	NoteVerificationStage(_displayName, "");

	setUpLogOverrides();
	
	/*	We need to be able to look up internal files, but not other OXP files.
		To do this without clobbering the disk cache, we disable cache writes.
	*/
	OOCacheManager::sharedCache()->flush();
	OOCacheManager::sharedCache()->setAllowCacheWrites(false);
	/* FIXME: the OXP verifier should load files from OXPs which have
	 * been explicitly listed as required_oxps in the
	 * manifest. Reading the manifest from the OXP being verified and
	 * setting 'id:<its identifier>' below will do this. */
	ResourceManager::setUseAddOns(std::string(SCENARIO_OXP_DEFINITION_NONE));
	
	SwitchLogFile(_displayName);
	OO_LOG("verifyOXP.start", "Running OXP verifier for {}", _basePath);//_displayName);
	
	registerBaseStages();
	buildDependencyGraph();
	runStages();
	
	NoteVerificationStage(_displayName, "");
	OO_LOG("verifyOXP.done", "{}", "OXP verification complete.");
	
	OpenLogFile();
}


void OOOXPVerifier::setUpLogOverrides()
{
	OOLogSetShowMessageClassTemporary(_verifierPList.get<bool>("logShowMessageClassOverride", false));

	const oo::PList *overrides = _verifierPList.get<oo::PList::Dict>("logControlOverride");
	if (overrides != nullptr)
	{
		for (const auto &override : *overrides->getIf<oo::PList::Dict>())
		{
			oo::log::logger().setDisplay(override.first, overrides->get<bool>(override.first, false));
		}
	}
	
	/*	Since actually editing logControlOverride is a pain, we also allow
		overriding verifyOXP.verbose through user defaults. This is at least
		as much a pain under GNUstep, but very convenient under OS X.
	*/
	{
		const oo::PList verbose = oo::Defaults::standard().object("oxp-verifier-verbose-logging");
		if (!verbose.isNull())  oo::log::logger().setDisplay("verifyOXP.verbose", oo::PListGet<bool>::from(&verbose, false));
	}
}


void OOOXPVerifier::registerBaseStages()
{
	{
		// Load stages specified as array of class names in verifyOXP.plist
		std::vector<std::string> stages = configurationSetForKey("stages").value_or(std::vector<std::string>());
		const std::vector<std::string> excludeStages = configurationSetForKey("excludeStages").value_or(std::vector<std::string>());
		if (!excludeStages.empty())
		{
			std::erase_if(stages, [&excludeStages](const std::string &stageName) { return std::binary_search(excludeStages.begin(), excludeStages.end(), stageName); });
		}
		for (const std::string &stageName : stages)
		{
			const auto cxxStage = std::find_if(std::begin(kCxxStages), std::end(kCxxStages), [&stageName](const CxxStage &entry) { return entry.name == stageName; });
			if (cxxStage != std::end(kCxxStages))
			{
				registerStage(cxxStage->make().get());
				continue;
			}

			if (sTestStageMaker != nullptr)
			{
				const oo::Ref<::OOOXPVerifierStage> testStage = sTestStageMaker(stageName);
				if (testStage.get() != nullptr)
				{
					registerStage(testStage.get());
					continue;
				}
			}

			/*	No class has the name: every stage is C++ since bead oo-9ht.4, and since bead oo-dbz.2 there
				is no Objective-C runtime to find one in (the only classes a name could still find there
				were libobjc2's own, logged as "not a subclass of OOOXPVerifierStage").
			*/
			OO_LOG("verifyOXP.registration.failed", "Attempt to register unknown class {} as a verifier stage, ignoring.", stageName);
		}
	}
}


void OOOXPVerifier::buildDependencyGraph()
{
	::OOOXPVerifierStage	*stage = nullptr;
	std::optional<std::string>	name;
	std::map<::OOOXPVerifierStage *, std::vector<std::string>>	dependenciesByStage,
															dependentsByStage;

	{
		/*	Iterate over all stages, getting dependency and dependent sets.
			This is done in advance so that -dependencies and -dependents may
			register stages.
		*/
		for (;;)
		{
			/*	Loop while there are stages whose dependency lists haven't been
				checked. This is an indeterminate loop since new ones can be
				added.
			*/
			if (_waitingStages.empty())  break;
			const oo::Ref<::OOOXPVerifierStage> waiting = _waitingStages.front();
			_waitingStages.erase(_waitingStages.begin());
			stage = waiting.get();

			std::optional<std::vector<std::string>> dependencies = stage->dependencies();
			if (dependencies.has_value())
			{
				dependenciesByStage[stage] = std::move(*dependencies);
			}

			const std::optional<std::vector<std::string>> dependents = stage->dependents();
			if (dependents.has_value())
			{
				// -setUpDependents: registers them in this order (-dependents has no duplicates).
				dependentsByStage[stage] = *dependents;
			}
		}
		_waitingStages.clear();
		_openForRegistration = false;

		// Iterate over all stages, resolving dependencies.
		std::vector<std::string> stageKeys;	// Get the keys up front because we may need to remove entries from the map.
		for (const auto &entry : _stagesByName)  stageKeys.push_back(entry.first);

		for (const std::string &stageKey : stageKeys)
		{
			const auto found = _stagesByName.find(stageKey);
			if (found == _stagesByName.end())  continue;
			stage = found->second.get();

			// Sanity check
			name = stage->name();
			if (!name.has_value() || *name != stageKey)
			{
				OO_LOG("verifyOXP.buildDependencyGraph.badName", "***** Stage name appears to have changed from \"{}\" to \"{}\" for verifier stage {}, removing.", stageKey, name.value_or("(null)"), stage->description());
				_stagesByName.erase(stageKey);
				continue;
			}

			// Get dependency set
			const auto stageDependencies = dependenciesByStage.find(stage);

			if (stageDependencies != dependenciesByStage.end() && !setUpDependencies(stageDependencies->second, stage))
			{
				_stagesByName.erase(stageKey);
			}
		}

		/*	Iterate over all stages again, resolving reverse dependencies.
			This is done in a separate pass because reverse dependencies are "weak"
			while forward dependencies are "strong".
		*/
		stageKeys.clear();
		for (const auto &entry : _stagesByName)  stageKeys.push_back(entry.first);

		for (const std::string &stageKey : stageKeys)
		{
			const auto found = _stagesByName.find(stageKey);
			if (found == _stagesByName.end())  continue;
			stage = found->second.get();

			// Get dependent set
			const auto stageDependents = dependentsByStage.find(stage);

			if (stageDependents != dependentsByStage.end())
			{
				setUpDependents(stageDependents->second, stage);
			}
		}

		for (const auto &entry : _stagesByName)  _waitingStages.push_back(entry.second);
		for (const auto &waiting : _waitingStages)  waiting->dependencyRegistrationComplete();

		if (oo::Defaults::standard().boolForKey("oxp-verifier-dump-debug-graphviz"))
		{
			dumpDebugGraphviz();
		}
	}
}


void OOOXPVerifier::runStages()
{
	::OOOXPVerifierStage	*stageToRun = nullptr;
	std::optional<std::string>	stageName;
	
	// Loop while there are still stages to run.
	for (;;)
	{
		
		// Look through queue for a stage that's ready
		stageToRun = nullptr;
		for (const auto &candidateStage : _waitingStages)
		{
			if (candidateStage->canRun())
			{
				stageToRun = candidateStage.get();
				break;
			}
		}
		if (stageToRun == nullptr)
		{
			// No more runnable stages
			break;
		}
		
		stageName.reset();
		oo::log::pushIndent();
		try
		{
			stageName = stageToRun->name();
			if (stageToRun->shouldRun())
			{
				NoteVerificationStage(_displayName, stageName.value_or("(null)"));	// "%@" text, as the old format printed it
				OO_LOG("verifyOXP.runStage", "{}", stageName.value_or("(null)"));
				oo::log::indent();
				stageToRun->performRun();
			}
			else
			{
				OO_LOG("verifyOXP.verbose.skipStage", "- Skipping stage: {} (nothing to do).", stageName.value_or("(null)"));
				stageToRun->noteSkipped();
			}
		}
		catch (...)
		{
			const auto exception = oo::CurrentOOException();
			if (!exception)  throw;	// not an OOException: it goes on up, as before
			if (!stageName.has_value())  stageName = stageToRun->className();	// was [stageToRun class]
			OO_LOG("verifyOXP.exception", "***** Exception occurred when running OXP verifier stage \"{}\": {}: {}", *stageName, exception->name(), exception->reason());
		}
		oo::log::popIndent();
		
		std::erase(_waitingStages, stageToRun);
	}
	
	
	if (!_waitingStages.empty())
	{
		OO_LOG("verifyOXP.incomplete", "{}", "Some verifier stages could not be run:");
		oo::log::indent();
		for (const auto &candidateStage : _waitingStages)
		{
			OO_LOG("verifyOXP.incomplete.item", "{}", candidateStage->description());
		}
		oo::log::outdent();
	}
	_waitingStages.clear();
	
}


bool OOOXPVerifier::setUpDependencies(const std::vector<std::string> &dependencies, ::OOOXPVerifierStage *stage)
{
	::OOOXPVerifierStage	*depStage = nullptr;

	// Iterate over dependencies, connecting them up.
	for (const std::string &depName : dependencies)
	{
		depStage = stageWithName(depName);
		if (depStage == nullptr)
		{
			OO_LOG("verifyOXP.buildDependencyGraph.unresolved", "Verifier stage {} has unresolved dependency \"{}\", skipping.", stage->description(), depName);
			return false;
		}
		
		if (depStage->isDependentOf(stage))
		{
			OO_LOG("verifyOXP.buildDependencyGraph.circularReference", "Verifier stages {} and {} have a dependency loop, skipping.", stage->description(), depStage->description());
			_stagesByName.erase(depName);
			return false;
		}
		
		stage->registerDependency(depStage);
	}
	
	return true;
}


void OOOXPVerifier::setUpDependents(const std::vector<std::string> &dependents, ::OOOXPVerifierStage *stage)
{
	::OOOXPVerifierStage	*depStage = nullptr;

	// Iterate over dependents, connecting them up.
	for (const std::string &depName : dependents)
	{
		depStage = stageWithName(depName);
		if (depStage == nullptr)
		{
			OO_LOG("verifyOXP.buildDependencyGraph.unresolved", "Verifier stage {} has unresolved dependent \"{}\".", stage->description(), depName);
			continue;	// Unresolved/conflicting dependents are non-fatal
		}
		
		if (stage->isDependentOf(depStage))
		{
			OO_LOG("verifyOXP.buildDependencyGraph.circularReference", "Verifier stage {} lists {} as both dependent and dependency (possibly indirectly); will execute {} after {}.", stage->description(), depStage->description(), stage->description(), depStage->description());
			continue;
		}
		
		depStage->registerDependency(stage);
	}
}


void OOOXPVerifier::dumpDebugGraphviz()
{
	using oo::str::FormatArg;

	// The templates are data (verifyOXP.plist), so they are formatted at run time (ADR-0043 item 19).
	const oo::PList graphVizTemplate = configurationDictionaryForKey("debugGraphvizTempate");
	std::string graphViz = oo::str::formatRuntime(graphVizTemplate.get<std::string>("preamble"), {oo::date::description()});

	/*	Pass 1: enumerate over graph setting node attributes for each stage.
		We use pointers as node names for simplicity of generation.
	*/
	std::string arcTemplate = graphVizTemplate.get<std::string>("node");
	for (const auto &entry : _stagesByName)
	{
		::OOOXPVerifierStage *stage = entry.second.get();
		graphViz += oo::str::formatRuntime(arcTemplate, {FormatArg::pointer(stage), stage->className(), stage->name().value_or("(null)")});	// was [stage class]
	}

	graphViz += graphVizTemplate.get<std::string>("forwardPreamble");

	/*	Pass 2: enumerate over graph setting forward arcs for each dependency.
	*/
	arcTemplate = graphVizTemplate.get<std::string>("forwardArc");
	const std::string startTemplate = graphVizTemplate.get<std::string>("startArc");
	for (const auto &entry : _stagesByName)
	{
		::OOOXPVerifierStage *stage = entry.second.get();
		const std::vector<oo::Ref<OOOXPVerifierStage>> deps = stage->resolvedDependencies();
		if (!deps.empty())
		{
			for (const auto &dep : deps)
			{
				graphViz += oo::str::formatRuntime(arcTemplate, {FormatArg::pointer(dep.get()), FormatArg::pointer(stage)});	// the nodes are the stages (their facades until bead oo-9ht.4)
			}
		}
		else
		{
			graphViz += oo::str::formatRuntime(startTemplate, {FormatArg::pointer(stage)});
		}
	}

	graphViz += graphVizTemplate.get<std::string>("backwardPreamble");

	/*	Pass 3: enumerate over graph setting backward arcs for each dependent.
	*/
	arcTemplate = graphVizTemplate.get<std::string>("backwardArc");
	const std::string endTemplate = graphVizTemplate.get<std::string>("endArc");
	for (const auto &entry : _stagesByName)
	{
		::OOOXPVerifierStage *stage = entry.second.get();
		const std::vector<oo::Ref<OOOXPVerifierStage>> deps = stage->resolvedDependents();
		if (!deps.empty())
		{
			for (const auto &dep : deps)
			{
				graphViz += oo::str::formatRuntime(arcTemplate, {FormatArg::pointer(dep.get()), FormatArg::pointer(stage)});	// the nodes are the stages (their facades until bead oo-9ht.4)
			}
		}
		else
		{
			graphViz += oo::str::formatRuntime(endTemplate, {FormatArg::pointer(stage)});
		}
	}

	graphViz += graphVizTemplate.get<std::string>("postamble");

	// Write file: what +[::ResourceManager writeDiagnosticString:toFileNamed:] did for a name with no
	// directory part (UTF-8, atomically, in the diagnostic directory).
	const std::optional<std::string> directory = ResourceManager::diagnosticFileLocation();
	if (directory.has_value())
	{
		const std::string path = oo::str::appendingPathComponent(*directory, "OXPVerifierStageDependencies.dot");
		(void)oo::fs::writeFile(oo::fs::pathFromUTF8(path), oo::Data::fromString(graphViz));
	}
}



#include "OOLogOutputHandler.h"


namespace {

void SwitchLogFile(const std::string &name)
{
//#ifndef OOLITE_LINUX
	const std::string logName = oo::str::appendingPathExtension(name, "log");
	OO_LOG("verifyOXP.switchingLog", "Switching log files -- logging to \"{}\".", logName);
	cxx_OOLogOutputHandlerChangeLogFile(logName);
//#else
//	OO_LOG("verifyOXP.switchingLog", "Switching logging to <stdout>.");
//	OOLogOutputHandlerStartLoggingToStdout();
//#endif
}


void NoteVerificationStage(const std::string &displayName, const std::string &stage)
{
	::GameController::sharedController()->logProgress(oo::str::format("Verifying %s\n%s", displayName.c_str(), stage.c_str()));
}


void OpenLogFile()
{
	//	Open log file in appropriate application / provide feedback.
	
	{
		const oo::PList openLog = oo::Defaults::standard().object("oxp-verifier-open-log");
		if (oo::PListGet<bool>::from(openLog.isNull() ? nullptr : &openLog, true))
		{
#if OOLITE_MAC_OS_X
		[[NSWorkspace sharedWorkspace] openFile:oo::NSStringOrNil(cxx_OOLogHandlerGetLogPath())];
#elif OOLITE_WINDOWS
		// ShellExecute will automatically use the app associated with .log files
		// A nil path's -UTF8String was NULL.
		const std::optional<std::string> logPath = cxx_OOLogHandlerGetLogPath();
		ShellExecute(NULL, NULL, logPath.has_value() ? logPath->c_str() : NULL, NULL, NULL, SW_SHOWNORMAL);
#elif  OOLITE_LINUX
		// MKW - needed to suppress 'ignoring return value' warning for system() call
		//		int ret;
		// CIM - and now the compiler complains about that too... casting return
		// value to void seems to keep it quiet for now
		// Nothing to do here, since we dump to stdout instead of to a file.
		//OOLogOutputHandlerStopLoggingToStdout();
		(void) system(oo::str::format("cat \"%s\"", cxx_OOLogHandlerGetLogPath().value_or("(null)").c_str()).c_str());
#else 
		do {} while (0);
#endif
		}
	}
}


}	// namespace


#endif	// OO_OXP_VERIFIER_ENABLED
