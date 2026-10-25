/*

OOShipRegistry.m


Copyright (C) 2008-2013 Jens Ayton and contributors

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

#include "OOShipRegistry.h"
#include "OOCacheManager.h"
#include "ResourceManager.h"
#include "OOProbabilitySet.h"
#include "OORoleSet.h"
#include "OOStringParsing.h"
#include "OOMesh.h"
#include "GameController.h"
#include "OOLegacyScriptWhitelist.h"
#include "OOColor.h"
#include "OOStringExpander.h"
#include "OOShipLibraryDescriptions.h"
#include "Universe.h"
#include "OOJSScript.h"

#include "OODebugStandards.h"
#include "oofnd/objc/OOException.h"
#include "OOPListGameTypes.h"
#include "oofnd/String.hpp"

#define PRELOAD 0


namespace {

OOShipRegistry	*sSingleton = nullptr;	// the one +1 is never released (amendment oo-r7m0 item 1)


constexpr const char *kRoleWeightsCacheKey			= "role weights";
constexpr const char *kDefaultDemoShip				= "coriolis-station";

// OOCacheManager caches and keys.
constexpr const char *kShipRegistryCacheName			= "ship registry";
constexpr const char *kShipDataCacheKey				= "ship data";
constexpr const char *kPlayerShipsCacheKey			= "player ships";
constexpr const char *kVisualEffectRegistryCacheName	= "visual effect registry";
constexpr const char *kVisualEffectDataCacheKey		= "visual effect data";


// A dictionary entry as the string extractor (oo_stringForKey:) answered it: nullopt where that
// was nil (no dictionary, no such key, or neither a string nor a number).
std::optional<std::string> StringForKey(const oo::PList *dict, const std::string &key)
{
	const oo::PList *value = dict != nullptr ? dict->find(key) : nullptr;
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dict->get<std::string>(key);
}



// get<Vector> / get<Quaternion>: OOCollectionExtractors' readers (unmigrated) of the value,
// handed back to them as a Foundation object; the defaults of a missing key are theirs.
Vector VectorForKey(const oo::PList &dict, const char *key)
{
	const oo::PList *value = dict.find(key);
	return OOVectorFromPList(value, kZeroVector);
}


Quaternion QuaternionForKey(const oo::PList &dict, const char *key)
{
	const oo::PList *value = dict.find(key);
	return OOQuaternionFromPList(value, kIdentityQuaternion);
}


// oo_setVector: / oo_setQuaternion:: OOPropertyListFromVector / OOPropertyListFromQuaternion's
// dictionaries (float components), as property lists.
oo::PList VectorPList(Vector value)
{
	return OOPListFromVector(value);
}


oo::PList QuaternionPList(Quaternion value)
{
	return OOPListFromQuaternion(value);
}


// The first token of a string, as [ScanTokensFromString(s) objectAtIndex:0] read it: an empty
// token list raised.
std::string FirstToken(const std::vector<std::string> &tokens)
{
	if (tokens.empty())
	{
		OORaiseException(OORangeException, "Index 0 is out of range 0 (in 'objectAtIndex:')");
	}
	return tokens[0];
}


// The tokens joined by single spaces (-componentsJoinedByString:@" ").
std::string JoinTokens(const std::vector<std::string> &tokens)
{
	std::string joined;
	for (std::size_t i = 0; i != tokens.size(); ++i)
	{
		if (i != 0)  joined += ' ';
		joined += tokens[i];
	}
	return joined;
}


// The ship dictionary a load stage works on, and each entry of it, as a dictionary (the loaders'
// results and every entry that survives -makeShipEntriesMutable: are dictionaries).
oo::PList::Dict &Entries(oo::PList &data)
{
	if (!data.isDict())  data = oo::PList(oo::PList::Dict());
	return *data.getIf<oo::PList::Dict>();
}


// -addEntriesFromDictionary:: <from>'s entries join <to>, replacing any with the same key.
void AddEntries(oo::PList::Dict &to, const oo::PList &from)
{
	if (const oo::PList::Dict *entries = from.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *entries)  to.insert_or_assign(key, value);
	}
}


// -sortedArrayUsingSelector: with -caseInsensitiveCompare:, then -componentsJoinedByString:@", "
std::string CaseInsensitiveSortedList(std::vector<std::string> keys)
{
	std::stable_sort(keys.begin(), keys.end(), [](const std::string &a, const std::string &b)
	{
		return oo::str::caseInsensitiveCompare(a, b) < 0;
	});
	std::string list;
	for (std::size_t i = 0; i != keys.size(); ++i)
	{
		if (i != 0)  list += ", ";
		list += keys[i];
	}
	return list;
}


void DumpStringAddrs(const oo::PList &dict, const std::string &context);

}	// namespace


OOShipRegistry *OOShipRegistry::sharedRegistry()
{
	if (sSingleton == nullptr)
	{
		OO_LOG("shipData.load.begin", "{}", "Loading ship data.");	// was +allocWithZone:'s
		sSingleton = oo::makeRef<OOShipRegistry>().leakRef();
		sSingleton->init();
	}

	return sSingleton;
}


void OOShipRegistry::reload()
{
	if (sSingleton != nullptr)
	{
		/* CIM: 'release' doesn't work - the class definition
		 * overrides it, so this leaks memory. Needs a proper reset
		 * method for reloading the ship registry data instead */
		// The singleton's -release did nothing, so the old registry is never freed (leakRef above).
		sSingleton = nullptr;

		(void) sharedRegistry();
	}
}


void OOShipRegistry::init()
{
	{
		OOCacheManager			*cache = OOCacheManager::sharedCache();

		_shipData = cache->pListForKey(kShipDataCacheKey, kShipRegistryCacheName);
		_playerShips.clear();	// the cached array's string elements, in order (anything else skipped, as oo::StringsFrom did)
		const oo::PList cachedPlayerShips = cache->pListForKey(kPlayerShipsCacheKey, kShipRegistryCacheName);
		if (const oo::PList::Array *playerShips = cachedPlayerShips.getIf<oo::PList::Array>())
		{
			for (const oo::PList &element : *playerShips)
			{
				if (const std::string *playerShip = element.getIf<std::string>())  _playerShips.push_back(*playerShip);
			}
		}
		_effectData = cache->pListForKey(kVisualEffectDataCacheKey, kVisualEffectRegistryCacheName);
		if (_shipData.count() == 0)	// Don't accept nil or empty
		{
			loadShipData();
			if (_shipData.count() == 0)
			{
				OORaiseException("OOShipRegistryLoadFailure", "Could not load any ship data.");
			}
			if (_playerShips.empty())
			{
				OORaiseException("OOShipRegistryLoadFailure", "Could not load any player ships.");
			}
		}

		loadDemoShipConditions();
		loadDemoShips(); // testing only
		if (_demoShips.count() == 0)
		{
			OORaiseException("OOShipRegistryLoadFailure", "Could not load or synthesize any demo ships.");
		}

		loadCachedRoleProbabilitySets();
		if (!_probabilitySets.has_value())
		{
			buildRoleProbabilitySets();
			if (_probabilitySets->empty())
			{
				OORaiseException("OOShipRegistryLoadFailure", "Could not load or synthesize role probability sets.");
			}
		}
	}
}


oo::PList OOShipRegistry::shipInfoForKey(const std::string &key)
{
	const oo::PList *entry = _shipData.find(key);
	return entry != nullptr ? *entry : oo::PList();
}


void OOShipRegistry::setShipInfoForKey(const std::string &key, const oo::PList &newShipData)
{
	// A value copy (it was a deep copy into a rebuilt dictionary).
	if (!_shipData.isDict())  _shipData = oo::PList(oo::PList::Dict());
	(*_shipData.getIf<oo::PList::Dict>())[key] = newShipData;
}


oo::PList OOShipRegistry::effectInfoForKey(const std::string &key)
{
	const oo::PList *entry = _effectData.find(key);
	return entry != nullptr ? *entry : oo::PList();
}


oo::PList OOShipRegistry::shipyardInfoForKey(const std::string &key)
{
	const oo::PList *entry = _shipData.find(key);
	const oo::PList *shipyard = entry != nullptr ? entry->find("_oo_shipyard") : nullptr;
	return shipyard != nullptr ? *shipyard : oo::PList();
}


OOProbabilitySet *OOShipRegistry::probabilitySetForRole(const std::string &role)
{
	if (!_probabilitySets.has_value())  return nullptr;
	auto set = _probabilitySets->find(role);
	return set != _probabilitySets->end() ? set->second.get() : nullptr;
}


oo::PList OOShipRegistry::demoShipKeys()
{
	// with condition scripts in use, can't cache this value
	loadDemoShips();

	return _demoShips;
}


std::vector<std::string> OOShipRegistry::playerShipKeys()
{
	return _playerShips;
}


// (OOConveniences)

std::vector<std::string> OOShipRegistry::shipKeys()
{
	std::vector<std::string> keys;
	if (const oo::PList::Dict *ships = _shipData.getIf<oo::PList::Dict>())
	{
		keys.reserve(ships->size());
		for (const auto &[shipKey, shipEntry] : *ships)  keys.push_back(shipKey);
	}
	return keys;
}

std::vector<std::string> OOShipRegistry::shipRoles()
{
	std::vector<std::string> roles;
	if (_probabilitySets.has_value())
	{
		roles.reserve(_probabilitySets->size());
		for (const auto &[role, set] : *_probabilitySets)  roles.push_back(role);
	}
	return roles;
}

std::vector<std::string> OOShipRegistry::shipKeysWithRole(const std::string &role)
{
	// The set's string elements (ship keys), in its order; anything else skipped, as oo::StringsFrom did.
	std::vector<std::string> keys;
	::OOProbabilitySet *set = probabilitySetForRole(role);
	for (const oo::PList &key : (set != nullptr) ? set->allElements() : std::vector<oo::PList>())
	{
		if (const std::string *string = key.getIf<std::string>())  keys.push_back(*string);
	}
	return keys;
}


std::optional<std::string> OOShipRegistry::randomShipKeyForRole(const std::string &role)
{
	// nullopt for no set, or no pick (every weight zero), as nil was.
	::OOProbabilitySet *set = probabilitySetForRole(role);
	if (set == nullptr)  return std::nullopt;
	const oo::PList key = set->randomObject();
	if (const std::string *string = key.getIf<std::string>())  return *string;
	return std::nullopt;
}


/*	-loadShipData
	
	Load the data for all ships. This consists of five stages:
		* Load merges shipdata.plist dictionary.
		* Apply all like_ship entries.
		* Load shipdata-overrides.plist and apply patches.
		* Load shipyard.plist, add shipyard data into ship dictionaries, and
		  create _playerShips array.
		* Build role->ship type probability sets.
*/
void OOShipRegistry::loadShipData()
{
	_shipData = oo::PList();
	_playerShips.clear();

	// Load shipdata.plist.
	oo::PList result = ResourceManager::dictionaryFromFilesNamed("shipdata.plist", "Config", MERGE_BASIC, NO);
	if (result.isNull())  return;

	DumpStringAddrs(result, "shipdata.plist");

	// Make each entry mutable to simplify later stages. Also removes any entries that aren't dictionaries.
	if (!makeShipEntriesMutable(result))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished initial cleanup...");

	// Apply patches.
	if (!loadAndApplyShipDataOverrides(result))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished applying patches...");

	// Strip private keys (anything starting with _oo_).
	if (!stripPrivateKeys(result))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished stripping private keys...");

	// Resolve like_ship entries.
	if (!applyLikeShips(result, "like_ship"))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished resolving like_ships...");

	// Clean up subentity declarations and tag subentities so they won't be pruned.
	if (!canonicalizeAndTagSubentities(result))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished cleaning up subentities...");

	// Clean out templates and invalid entries.
	if (!removeUnusableEntries(result, true))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished removing invalid entries...");

	// Add shipyard entries into shipdata entries.
	if (!loadAndMergeShipyard(result))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished adding shipyard entries...");

	// Sanitize conditions.
	if (!sanitizeConditions(result))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished validating data...");

#if PRELOAD
	// Preload and cache meshes.
	if (!preloadShipMeshes(result))  return;
	OO_LOG("shipData.load.progress", "{}", "Finished loading meshes...");
#endif

	_shipData = std::move(result);
	OOCacheManager::sharedCache()->setPList(_shipData, kShipDataCacheKey, kShipRegistryCacheName);

	OO_LOG("shipData.load.done", "{}", "Ship data loaded.");

	_effectData = oo::PList();

	result = ResourceManager::dictionaryFromFilesNamed("effectdata.plist", "Config", MERGE_BASIC, NO);
	if (result.isNull())  return;

	// Make each entry mutable to simplify later stages. Also removes any entries that aren't dictionaries.
	if (!makeShipEntriesMutable(result))  return;
	OO_LOG("effectData.load.progress", "{}", "Finished initial cleanup...");

	// Strip private keys (anything starting with _oo_).
	if (!stripPrivateKeys(result))  return;
	OO_LOG("effectData.load.progress", "{}", "Finished stripping private keys...");

	// Resolve like_effect entries.
	if (!applyLikeShips(result, "like_effect"))  return;
	OO_LOG("effectData.load.progress", "{}", "Finished resolving like_effects...");

	// Clean up subentity declarations and tag subentities so they won't be pruned.
	if (!canonicalizeAndTagSubentities(result))  return;
	OO_LOG("effectData.load.progress", "{}", "Finished cleaning up subentities...");

	// Clean out templates and invalid entries.
	if (!removeUnusableEntries(result, false))  return;
	OO_LOG("effectData.load.progress", "{}", "Finished removing invalid entries...");

	_effectData = std::move(result);
	OOCacheManager::sharedCache()->setPList(_effectData, kVisualEffectDataCacheKey, kVisualEffectRegistryCacheName);

	OO_LOG("effectData.load.done", "{}", "Effect data loaded.");
}


void OOShipRegistry::loadDemoShipConditions()
{
	std::vector<std::string>	conditionScripts;

	// OOCacheManager is an unmigrated callee: convert at the call.
	const oo::PList initialDemoShips = ResourceManager::arrayFromFilesNamed("shiplibrary.plist", "Config", YES, NO);

	if (const oo::PList::Array *entries = initialDemoShips.getIf<oo::PList::Array>())
	{
		for (const oo::PList &key : *entries)
		{
			std::optional<std::string> conditions = StringForKey(&key, kOODemoShipConditions);
			if (conditions.has_value())
			{
				conditionScripts.push_back(std::move(*conditions));
			}
		}
	}

	oo::PList::Array conditionScriptList;	// an array of strings, as the Objective-C array was
	for (const std::string &conditionScript : conditionScripts)  conditionScriptList.emplace_back(conditionScript);
	OOCacheManager::sharedCache()->setPList(oo::PList(std::move(conditionScriptList)), "demoship conditions", "condition scripts");
}


/*	-loadDemoShips
	
	Load demoships.plist, and filter out non-existent ships. If no existing
	ships remain, try adding coriolis; if this fails, add any ship in
	shipdata.
*/
void OOShipRegistry::loadDemoShips()
{
	_demoShips = oo::PList();

	const oo::PList initialDemoShips = ResourceManager::arrayFromFilesNamed("shiplibrary.plist", "Config", YES, NO);
	const oo::PList::Array noShips;
	const oo::PList::Array *initialArray = initialDemoShips.getIf<oo::PList::Array>();	// null unless isArray()
	const oo::PList::Array &initialEntries = initialArray != nullptr ? *initialArray : noShips;
	oo::PList::Array demoShips = initialEntries;
	// -removeObject: took every equal entry out
	auto removeEntry = [&demoShips](const oo::PList &entry)
	{
		demoShips.erase(std::remove(demoShips.begin(), demoShips.end(), entry), demoShips.end());
	};

	// Note: iterate over initialDemoShips to avoid mutating the collection being enu,erated.
	for (const oo::PList &key : initialEntries)
	{
		const std::optional<std::string> shipKey = StringForKey(&key, kOODemoShipKey);
		if (!key.isDict() || !shipKey.has_value() || _shipData.find(*shipKey) == nullptr)
		{
			removeEntry(key);
		}
		else
		{
			const std::optional<std::string> conditions = StringForKey(&key, kOODemoShipConditions);
			if (conditions.has_value())
			{
				if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_START_GAME)
				{
					// conditions always false here
					removeEntry(key);
				}
				else
				{
					::OOScript *condScript = (UNIVERSE != nullptr ? UNIVERSE->getConditionScript(*conditions) : nullptr);
					if (condScript != nil) // should always be non-nil, but just in case
					{
						ooscript::Context context = OOJSAcquireContext();
						BOOL OK;
						bool allow_use;
						ooscript::Value result;
						ooscript::Value args[] = { OOJSValueFromPList(context, oo::PList(*shipKey)) };

						OK = (condScript != nullptr ? condScript->callMethod(OOJSID("allowShowLibraryShip"), context, args, sizeof args / sizeof *args, &result) : false);

						if (OK) OK = ooscript::valueToBoolean(context, result, &allow_use);

						OOJSRelinquishContext(context);
						if (OK && !allow_use)
						{
							/* if the script exists, the function exists, the function
							 * returns a bool, and that bool is false, hide the
							 * ship. Otherwise allow it as default */
							removeEntry(key);
						}
					}
				}
			}
		}
	}

	if (demoShips.empty())
	{
		std::string shipKey;
		if (_shipData.find(kDefaultDemoShip) != nullptr)
		{
			shipKey = kDefaultDemoShip;
		}
		else
		{
			shipKey = _shipData.getIf<oo::PList::Dict>()->begin()->first;	// the first key in key order (was hash order)
		}
		oo::PList::Dict entry;
		entry.emplace(kOODemoShipKey, shipKey);
		demoShips.emplace_back(std::move(entry));
	}

	// now separate out the demoships by class, and add some extra keys
	std::map<std::string, oo::PList::Array, std::less<>> demoList;
	for (const oo::PList &key : demoShips)
	{
		std::string klass = key.get<std::string>(kOODemoShipClass, "ship");
		if (OOShipLibraryCategoryPlural(klass).empty())
		{
			OO_LOG("shipdata.load.warning", "Unexpected class '{}' in shiplibrary.plist for '{}'", klass, StringForKey(&key, kOODemoShipKey).value_or("(null)"));
			klass = "ship";
		}
		oo::PList::Array &demoClass = demoList[klass];
		oo::PList demoEntry = key;
		oo::PList::Dict &demoEntryValues = *demoEntry.getIf<oo::PList::Dict>();
		// add "name" object to dictionary from ship definition
		const std::optional<std::string> name = StringForKey(_shipData.find(demoEntry.get<std::string>("ship")), kOODemoShipName);
		if (!name.has_value())
		{
			// -setObject:nil forKey: raised
			OORaiseException(OOInvalidArgumentException, "Tried to add nil value for key '%s' to dictionary", kOODemoShipName);
		}
		demoEntryValues[kOODemoShipName] = *name;
		// set "class" object to standard ship if not otherwise set
		if (StringForKey(&demoEntry, kOODemoShipClass) != klass)
		{
			demoEntryValues[kOODemoShipClass] = klass;
		}
		demoClass.push_back(std::move(demoEntry));
	}
	// sort each ship list by name (-compare:)
	oo::PList::Array categories;
	categories.reserve(demoList.size());
	for (auto &[demoClassName, demoClass] : demoList)
	{
		std::stable_sort(demoClass.begin(), demoClass.end(), [](const oo::PList &a, const oo::PList &b)
		{
			return oo::str::compare(a.get<std::string>("name"), b.get<std::string>("name")) < 0;
		});
		categories.emplace_back(std::move(demoClass));
	}

	// and then sort the ship list list by class name (the plural category name, -compare:)
	std::stable_sort(categories.begin(), categories.end(), [](const oo::PList &a, const oo::PList &b)
	{
		return oo::str::compare(OOShipLibraryCategoryPlural(a.at(0)->get<std::string>("class")), OOShipLibraryCategoryPlural(b.at(0)->get<std::string>("class"))) < 0;
	});
	_demoShips = oo::PList(std::move(categories));
}


void OOShipRegistry::loadCachedRoleProbabilitySets()
{
	const oo::PList cachedSets = OOCacheManager::sharedCache()->pListForKey(kRoleWeightsCacheKey, kShipRegistryCacheName);
	if (cachedSets.isNull())  return;

	std::map<std::string, oo::Ref<OOProbabilitySet>, std::less<>> restoredSets;
	if (const oo::PList::Dict *sets = cachedSets.getIf<oo::PList::Dict>())
	{
		for (const auto &[role, representation] : *sets)
		{
			restoredSets[role] = OOProbabilitySet::probabilitySetWithPropertyListRepresentation(representation);
		}
	}

	_probabilitySets = std::move(restoredSets);
}


void OOShipRegistry::buildRoleProbabilitySets()
{
	std::map<std::string, oo::Ref<OOMutableProbabilitySet>, std::less<>>	probabilitySets;

	// Build role sets (ships in key order; was hash order)
	if (const oo::PList::Dict *ships = _shipData.getIf<oo::PList::Dict>())
	{
		for (const auto &[shipKey, shipEntry] : *ships)
		{
			mergeShipRoles(StringForKey(&shipEntry, "roles").value_or(""), shipKey, probabilitySets);
		}
	}

	// Convert role sets to immutable form, and build cache entry.
	std::map<std::string, oo::Ref<OOProbabilitySet>, std::less<>>	sets;
	oo::PList::Dict		cacheEntry;
	for (const auto &[role, mutableSet] : probabilitySets)
	{
		oo::Ref<OOProbabilitySet> pset = mutableSet->copy();
		sets[role] = pset;
		// OOProbabilitySet is an unmigrated callee (its weights are floats: single reals, written to disk)
		cacheEntry[role] = pset->propertyListRepresentation();
	}

	_probabilitySets = std::move(sets);
	OOCacheManager::sharedCache()->setPList(oo::PList(std::move(cacheEntry)), kRoleWeightsCacheKey, kShipRegistryCacheName);
}


/*	-applyLikeShips:
	
	Implement like_ship by copying inherited ship and overwriting with child
	ship values. Done iteratively to report recursive references of arbitrary
	depth. Also removes and reports ships whose like_ship entry does not
	resolve, and handles reference loops by removing all ships involved.
 
	We start with a set of keys all ships that have a like_ships entry. In
	each iteration, every ship whose like_ship entry does not refer to a ship
	which itself has a like_ship entry is finalized. If the set of pending
	ships does not shrink in an iteration, the remaining ships cannot be
	resolved (either their like_ships do not exist, or they form reference
	cycles) so we stop looping and report it.
*/
bool OOShipRegistry::applyLikeShips(oo::PList &ioData, const std::string &likeKey)
{
	oo::PList::Dict			&ships = Entries(ioData);
	std::set<std::string>	remainingLikeShips;
	std::size_t				count, lastCount;

	// Build set of ships with like_ship references
	for (const auto &[key, shipEntry] : ships)
	{
		if (StringForKey(&shipEntry, likeKey).has_value())
		{
			remainingLikeShips.insert(key);
		}
	}

	count = lastCount = remainingLikeShips.size();
	while (count != 0)
	{
		const std::set<std::string> pendingShips = remainingLikeShips;
		for (const std::string &key : pendingShips)
		{
			// Look up like_ship entry (a key only when it is a string: anything else named no ship)
			const oo::PList *likeValue = ships[key].find(likeKey);
			const std::string *parentKey = likeValue != nullptr ? likeValue->getIf<std::string>() : nullptr;
			if (parentKey != nullptr && !remainingLikeShips.contains(*parentKey))
			{
				// If parent is fully resolved, we can resolve this child.
				// (-mergeShip:withParent: answered nil for a missing parent)
				auto parentEntry = ships.find(*parentKey);
				if (parentEntry != ships.end())
				{
					oo::PList shipEntry = mergeShip(ships[key], parentEntry->second);
					remainingLikeShips.erase(key);
					ships[key] = std::move(shipEntry);
				}
			}
		}

		count = remainingLikeShips.size();
		if (count == lastCount)
		{
			/*	Fail: we couldn't resolve all like_ship entries.
				Remove unresolved entries, building a list of the ones that
				don't have is_external_dependency set.
			*/
			std::vector<std::string> reportedBadShips;
			for (const std::string &key : remainingLikeShips)
			{
				if (!ships[key].get<bool>("is_external_dependency"))
				{
					reportedBadShips.push_back(key);
				}
				ships.erase(key);
			}

			if (!reportedBadShips.empty())
			{
				OO_LOG_ERR("shipData.merge.failed", "one or more shipdata.plist entries have {} references that cannot be resolved: {}", likeKey, CaseInsensitiveSortedList(std::move(reportedBadShips))); // FIXME: distinguish shipdata and effectdata
				cxx_OOStandardsError("Likely missing a dependency in a manifest.plist");
			}
			break;
		}
		lastCount = count;
	}

	return true;
}


oo::PList OOShipRegistry::mergeShip(const oo::PList &child, const oo::PList &parent)
{
	if (parent.isNull())  return oo::PList();
	oo::PList result = parent;
	oo::PList::Dict &entries = Entries(result);

	AddEntries(entries, child);
	entries.erase("like_ship");

	auto hasString = [](const oo::PList &dict, const char *key) { return StringForKey(&dict, key).has_value(); };

	// Certain properties cannot be inherited.
	if (!hasString(child, "display_name"))  entries.erase("display_name");
	if (!hasString(child, "is_template"))  entries.erase("is_template");

	// Since both 'scanClass' and 'scan_class' are accepted as valid keys for the scanClass property,
	// we may end up with conflicting scanClass and scan_class keys from like_ship relationships getting
	// merged in the result dictionary. We want to always have the child overriding the parent setting
	// and we do that by determining which of the two keys belongs to the child dictionary and removing
	// the other one from the result - Nikos 20100512
	if (hasString(result, "scan_class") && hasString(result, "scanClass"))
	{
		if (hasString(child, "scanClass"))
			entries.erase("scan_class");
		else
			entries.erase("scanClass");
	}
	// TODO: all normalised/non-normalised value name pairs need to be catered for. - Kaks 2010-05-13
	if (hasString(result, "escort_role") && hasString(result, "escort-role"))
	{
		if (hasString(child, "escort-role"))
			entries.erase("escort_role");
		else
			entries.erase("escort-role");
	}
	if (hasString(result, "escort_ship") && hasString(result, "escort-ship"))
	{
		if (hasString(child, "escort-ship"))
			entries.erase("escort_ship");
		else
			entries.erase("escort-ship");
	}
	if (hasString(result, "is_carrier") && hasString(result, "isCarrier"))
	{
		if (hasString(child, "isCarrier"))
			entries.erase("is_carrier");
		else
			entries.erase("isCarrier");
	}
	if (hasString(result, "has_shipyard") && hasString(result, "hasShipyard"))
	{
		if (hasString(child, "hasShipyard"))
			entries.erase("has_shipyard");
		else
			entries.erase("hasShipyard");
	}
	return result;
}


bool OOShipRegistry::makeShipEntriesMutable(oo::PList &ioData)
{
	// Entries are values (so already mutable): this stage only drops the ones that aren't dictionaries.
	oo::PList::Dict &ships = Entries(ioData);
	for (auto ship = ships.begin(); ship != ships.end(); )
	{
		if (!ship->second.isDict())
		{
			OO_LOG_ERR("shipData.load.badEntry", "the shipdata.plist entry \"{}\" is not a dictionary.", ship->first);
			ship = ships.erase(ship);
		}
		else
		{
			++ship;
		}
	}

	return true;
}


bool OOShipRegistry::loadAndApplyShipDataOverrides(oo::PList &ioData)
{
	oo::PList::Dict &ships = Entries(ioData);
	const oo::PList overrides = ResourceManager::dictionaryFromFilesNamed("shipdata-overrides.plist", "Config", MERGE_SMART, NO);

	if (const oo::PList::Dict *overrideEntries = overrides.getIf<oo::PList::Dict>())
	{
		for (const auto &[shipKey, overridesEntry] : *overrideEntries)
		{
			auto shipEntry = ships.find(shipKey);
			if (shipEntry != ships.end())
			{
				if (!overridesEntry.isDict())
				{
					OO_LOG_ERR("shipData.load.error", "the shipdata-overrides.plist entry \"{}\" is not a dictionary.", shipKey);
				}
				else
				{
					AddEntries(Entries(shipEntry->second), overridesEntry);
				}
			}
		}
	}

	return true;
}


bool OOShipRegistry::stripPrivateKeys(oo::PList &ioData)
{
	for (auto &ship : Entries(ioData))
	{
		std::erase_if(Entries(ship.second), [](const auto &attribute)
		{
			return oo::str::hasPrefix(attribute.first, "_oo_");
		});
	}

	return true;
}


/*	-loadAndMergeShipyard:

	Load shipyard.plist, add its entries to appropriate shipyard entries as
	a dictionary under the key "shipyard", and build list of player ships.
	Before that, we strip out any "shipyard" entries already in shipdata, and
	apply any shipyard-overrides.plist stuff to shipyard.
*/
bool OOShipRegistry::loadAndMergeShipyard(oo::PList &ioData)
{
	oo::PList::Dict				&ships = Entries(ioData);
	std::vector<std::string>	playerShips;

	// Strip out any shipyard stuff in shipdata (there shouldn't be any).
	for (auto &ship : ships)
	{
		Entries(ship.second).erase("_oo_shipyard");
	}

	const oo::PList shipyard = ResourceManager::dictionaryFromFilesNamed("shipyard.plist", "Config", MERGE_BASIC, NO);
	const oo::PList shipyardOverrides = ResourceManager::dictionaryFromFilesNamed("shipyard-overrides.plist", "Config", MERGE_SMART, NO);

	playerShips.reserve(shipyard.count());

	// Insert merged shipyard and shipyardOverrides entries (in key order, which is the order of
	// the player ships; was hash order).
	if (const oo::PList::Dict *shipyardEntries = shipyard.getIf<oo::PList::Dict>())
	{
		for (const auto &[shipKey, shipyardEntry] : *shipyardEntries)
		{
			auto shipEntry = ships.find(shipKey);
			if (shipEntry != ships.end())
			{
				// merging dictionary entries
				oo::PList mergedEntry = shipyardEntry;
				const oo::PList *shipyardOverridesEntry = shipyardOverrides.find(shipKey);
				if (shipyardOverridesEntry != nullptr && mergedEntry.isDict())
				{
					AddEntries(Entries(mergedEntry), *shipyardOverridesEntry);
				}

				Entries(shipEntry->second)["_oo_shipyard"] = std::move(mergedEntry);

				playerShips.push_back(shipKey);
			}
			else
			{
				OO_LOG_WARN("shipData.load.shipyard.unknown", "the shipyard.plist entry \"{}\" does not have a corresponding shipdata.plist entry, ignoring.", shipKey);
			}
		}
	}

	_playerShips = std::move(playerShips);
	oo::PList::Array playerShipList;	// an array of strings, as the Objective-C array was
	for (const std::string &playerShip : _playerShips)  playerShipList.emplace_back(playerShip);
	OOCacheManager::sharedCache()->setPList(oo::PList(std::move(playerShipList)), kPlayerShipsCacheKey, kShipRegistryCacheName);

	return true;
}


bool OOShipRegistry::removeUnusableEntries(oo::PList &ioData, bool shipMode)
{
	oo::PList::Dict &ships = Entries(ioData);

	// Clean out invalid entries and templates.
	for (auto ship = ships.begin(); ship != ships.end(); )
	{
		const std::string	&shipKey = ship->first;
		const oo::PList		&shipEntry = ship->second;
		BOOL				remove = NO;

		if (shipEntry.get<bool>("is_template") || shipEntry.get<bool>("_oo_deferred_remove"))  remove = YES;
		else if (shipMode && StringForKey(&shipEntry, "roles").value_or("").empty() && !shipEntry.get<bool>("_oo_is_subentity") && !shipEntry.get<bool>("_oo_is_effect"))
		{
			OO_LOG_ERR("shipData.load.error", "the shipdata.plist entry \"{}\" specifies no {}.", shipKey, "roles");
			remove = YES;
			cxx_OOStandardsError("Error in shipdata.plist");
		}
		else
		{
			const std::string modelName = StringForKey(&shipEntry, "model").value_or("");
			if (shipMode && modelName.empty())
			{
				OO_LOG_ERR("shipData.load.error", "the shipdata.plist entry \"{}\" specifies no {}.", shipKey, "model");
				cxx_OOStandardsError("Error in shipdata.plist");
				remove = YES;
			}
			else if (!modelName.empty() && !ResourceManager::pathForFileNamed(modelName, "Models").has_value())
			{
				OO_LOG_ERR("shipData.load.error", "the shipdata.plist entry \"{}\" specifies non-existent model \"{}\".", shipKey, modelName);
				cxx_OOStandardsError("Error in shipdata.plist");
				remove = YES;
			}
		}
		if (remove)  ship = ships.erase(ship);
		else  ++ship;
	}

	return true;
}


/*	Transform conditions, determinant (if conditions array) and
	shipyard.conditions from hasShipyard to sanitized form.
  Also get list of condition_scripts
*/
bool OOShipRegistry::sanitizeConditions(oo::PList &ioData)
{
	std::vector<std::string> conditionScripts;	// each once, in first-seen order
	auto addConditionScript = [&conditionScripts](const std::optional<std::string> &script)
	{
		if (script.has_value() && std::find(conditionScripts.begin(), conditionScripts.end(), *script) == conditionScripts.end())
		{
			conditionScripts.push_back(*script);
		}
	};
	// OOSanitizeLegacyScriptConditions takes and returns oo::PList (bead oo-3rb.205; nil is null).
	auto sanitize = [](const oo::PList &unsanitized, const std::string &context)
	{
		return OOSanitizeLegacyScriptConditions(unsanitized, context);
	};
	auto valueOrNull = [](const oo::PList *value) { return value != nullptr ? *value : oo::PList(); };

	// (ships in key order; was the hash order of -allKeys)
	for (auto &[shipKey, shipEntry] : Entries(ioData))
	{
		oo::PList::Dict	&entry = Entries(shipEntry);
		const char		*key = shipKey.c_str();

		oo::PList conditions = valueOrNull(shipEntry.find("conditions"));
		addConditionScript(StringForKey(&shipEntry, "condition_script"));

		// May also be fuzzy boolean
		oo::PList hasShipyard = valueOrNull(shipEntry.get<oo::PList::Array>("has_shipyard"));
		if (hasShipyard.isNull())
		{
			hasShipyard = valueOrNull(shipEntry.get<oo::PList::Array>("hasShipyard"));
		}
		const oo::PList *shipyard = shipEntry.get<oo::PList::Dict>("_oo_shipyard");
		oo::PList shipyardConditions = valueOrNull(shipyard != nullptr ? shipyard->find("conditions") : nullptr);
		addConditionScript(StringForKey(shipyard, "condition_script"));


		if (conditions.isNull() && !hasShipyard.isNull() && shipyardConditions.isNull())  continue;

		if (!conditions.isNull())
		{
			cxx_OOStandardsDeprecated(oo::str::format("The 'conditions' key is deprecated in shipdata entry %s", key));
			if (!OOEnforceStandards())
			{
				if (conditions.isArray())
				{
					conditions = sanitize(conditions, oo::str::format("<shipdata.plist entry \"%s\">", key));
				}
				else
				{
					OO_LOG_WARN("shipdata.load.warning", "conditions for shipdata.plist entry \"{}\" are not an array, ignoring.", shipKey);
					conditions = oo::PList();
				}

				if (!conditions.isNull())
				{
					entry["conditions"] = std::move(conditions);
				}
				else
				{
					entry.erase("conditions");
				}
			}
		}

		if (!hasShipyard.isNull())
		{
			hasShipyard = sanitize(hasShipyard, oo::str::format("<shipdata.plist entry \"%s\" hasShipyard conditions>", key));
			cxx_OOStandardsDeprecated(oo::str::format("Use of legacy script conditions in the 'has_shipyard' key is deprecated in shipyard entry %s", key));
			if (!OOEnforceStandards())
			{
				if (!hasShipyard.isNull())
				{
					entry["has_shipyard"] = std::move(hasShipyard);
				}
				else
				{
					entry.erase("hasShipyard");
					entry.erase("has_shipyard");
				}
			}
		}

		if (!shipyardConditions.isNull())
		{
			cxx_OOStandardsDeprecated(oo::str::format("The 'conditions' key is deprecated in shipyard entry %s", key));
			if (!OOEnforceStandards())
			{
				oo::PList mutableShipyard = valueOrNull(shipEntry.get<oo::PList::Dict>("_oo_shipyard"));

				if (shipyardConditions.isArray())
				{
					shipyardConditions = sanitize(shipyardConditions, oo::str::format("<shipyard.plist entry \"%s\">", key));
				}
				else
				{
					OO_LOG_WARN("shipdata.load.warning", "conditions for shipyard.plist entry \"{}\" are not an array, ignoring.", shipKey);
					shipyardConditions = oo::PList();
				}

				if (!shipyardConditions.isNull())
				{
					Entries(mutableShipyard)["conditions"] = std::move(shipyardConditions);
				}
				else
				{
					Entries(mutableShipyard).erase("conditions");
				}

				entry["_oo_shipyard"] = std::move(mutableShipyard);
			}
		}
	}

	oo::PList::Array conditionScriptList;	// an array of strings, as the Objective-C array was
	for (const std::string &conditionScript : conditionScripts)  conditionScriptList.emplace_back(conditionScript);
	OOCacheManager::sharedCache()->setPList(oo::PList(std::move(conditionScriptList)), "ship conditions", "condition scripts");

	return true;
}


bool OOShipRegistry::canonicalizeAndTagSubentities(oo::PList &ioData)
{
	oo::PList::Dict			&ships = Entries(ioData);
	BOOL					remove, fatal;

	// Convert all subentity declarations to dictionaries and add
	// _oo_is_subentity=YES to all entries used as subentities.

	// Iterate over all ships. (Entries change in place; none is added or removed. The declaration
	// helpers read only "frangible" and "setup_actions" of the ship data, which this loop never writes.)
	for (auto &[shipKey, shipEntry] : ships)
	{
		remove = NO;
		std::set<std::string> badSubentities;

		// Iterate over each subentity declaration of each ship
		const oo::PList *declarations = shipEntry.get<oo::PList::Array>("subentities");
		if (declarations != nullptr)
		{
			const oo::PList subentityDeclarations = *declarations;	// a copy: the entry's list is replaced below
			oo::PList::Array okSubentities;
			okSubentities.reserve(subentityDeclarations.count());
			for (const oo::PList &subentityDecl : *subentityDeclarations.getIf<oo::PList::Array>())
			{
				oo::PList subentityDict = canonicalizeSubentityDeclaration(subentityDecl, shipKey, ioData, &fatal);

				// If entry is broken, we need to kill this ship.
				if (fatal)
				{
					cxx_OOStandardsError("Bad subentity definition found");
					remove = YES;
				}
				else if (!subentityDict.isNull())
				{
					// Tag subentities.
					if (StringForKey(&subentityDict, "type") != "flasher")
					{
						const std::optional<std::string> subentityKey = StringForKey(&subentityDict, "subentity_key");
						auto subentityShipEntry = subentityKey.has_value() ? ships.find(*subentityKey) : ships.end();
						if (subentityShipEntry == ships.end())
						{
							// Oops, reference to non-existent subent.
							if (!subentityKey.has_value())
							{
								// -addObject:nil raised
								OORaiseException(OOInvalidArgumentException, "Tried to add nil to set");
							}
							badSubentities.insert(*subentityKey);
						}
						else
						{
							// Subent exists, add _oo_is_subentity so roles aren't required.
							Entries(subentityShipEntry->second)["_oo_is_subentity"] = true;
						}
					}

					okSubentities.push_back(std::move(subentityDict));
				}
			}

			// Set updated subentity list.
			oo::PList::Dict &entry = Entries(shipEntry);
			if (!okSubentities.empty())
			{
				entry["subentities"] = std::move(okSubentities);
			}
			else
			{
				entry.erase("subentities");
			}

			if (!badSubentities.empty())
			{
				if (!shipEntry.get<bool>("is_external_dependency"))
				{
					const std::size_t badCount = badSubentities.size();
					const std::string badSubentitiesList = CaseInsensitiveSortedList(std::vector<std::string>(badSubentities.begin(), badSubentities.end()));
					OO_LOG_ERR("shipData.load.error", "the shipdata.plist entry \"{}\" has unresolved subentit{} {}.", shipKey, (badCount == 1) ? "y" : "ies", badSubentitiesList);
					cxx_OOStandardsError("Bad subentity definition found");
				}
				remove = YES;
			}

			if (remove)
			{
				// Removal is deferred to avoid bogus "entry doesn't exist" errors.
				entry["_oo_deferred_remove"] = true;
			}
		}
	}

	return true;
}


#if PRELOAD
bool OOShipRegistry::preloadShipMeshes(oo::PList &ioData)
{
	oo::PList::Dict			&ships = Entries(ioData);
	OOMesh					*mesh = nil;
	std::size_t				i = 0, count;

	count = ships.size();

	// Preload ship meshes.
	for (auto ship = ships.begin(); ship != ships.end(); )
	{
		const oo::PList &shipEntry = ship->second;
		const std::optional<std::string> modelName = StringForKey(&shipEntry, "model");
		{
			oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
			[[::GameController sharedController] setProgressBarValue:(float)i++ / (float)count];

			// (PRELOAD is 0: this names a -meshWithName: form OOMesh no longer has.)
			const oo::PList *materials = shipEntry.get<oo::PList::Dict>("materials");
			const oo::PList *shaders = shipEntry.get<oo::PList::Dict>("shaders");
			mesh = [OOMesh meshWithName:modelName
					 materialDictionary:(materials != nullptr ? *materials : oo::PList())
					  shadersDictionary:(shaders != nullptr ? *shaders : oo::PList())
								 smooth:shipEntry.get<bool>("smooth")
						   shaderMacros:nil
					shaderBindingTarget:nil];
		}	// NOTE: mesh is now invalid, but pointer nil check is OK.

		if (mesh == nil)
		{
			// FIXME: what if it's a subentity? Need to rearrange things.
			OO_LOG_ERR("shipData.load.error", "model \"{}\" could not be loaded for ship \"{}\", removing.", modelName.value_or("(null)"), ship->first);
			ship = ships.erase(ship);
		}
		else
		{
			++ship;
		}
	}

	[[::GameController sharedController] setProgressBarValue:-1.0f];

	return true;
}
#endif


void OOShipRegistry::mergeShipRoles(const std::string &roles, const std::string &shipKey, std::map<std::string, oo::Ref<OOMutableProbabilitySet>, std::less<>> &probabilitySets)
{
	/*	probabilitySets is a dictionary whose keys are roles and whose values
		are mutable probability sets, whose values are ship keys.

		When creating new ships Oolite looks up this probability map.
		To upgrade all soliton 'thargon' roles to 'EQ_THARGON' we need
		to swap these roles here.
	*/

  // add default [shipKey] role
	std::map<std::string, float, std::less<>> rolesAndWeights;
	for (const auto &[parsedRole, weight] : OOParseRolesFromString(roles))
	{
		rolesAndWeights[parsedRole] = weight;
	}
	rolesAndWeights[oo::str::format("[%s]", shipKey.c_str())] = 1.0f;

	auto thargonValue = rolesAndWeights.find("thargon");
	if (thargonValue != rolesAndWeights.end() && rolesAndWeights.find("EQ_THARGON") == rolesAndWeights.end())
	{
		rolesAndWeights["EQ_THARGON"] = thargonValue->second;
	}

	// (roles in role order; was hash order: each role's set is separate)
	for (const auto &[role, weight] : rolesAndWeights)
	{
		oo::Ref<OOMutableProbabilitySet> &probSet = probabilitySets[role];
		if (probSet == nullptr)
		{
			probSet = OOMutableProbabilitySet::probabilitySet();
		}

		probSet->setWeight(weight, oo::PList(shipKey));
	}
}


oo::PList OOShipRegistry::canonicalizeSubentityDeclaration(const oo::PList &declaration, const std::string &shipKey, const oo::PList &shipData, BOOL *outFatalError)
{
	oo::PList				result;

	assert(outFatalError != NULL);
	*outFatalError = NO;

	if (declaration.isString())
	{
		// Update old-style string-based declaration.
		cxx_OOStandardsDeprecated(oo::str::format("Old style sub-entity declarations are deprecated in %s", shipKey.c_str()));
		if (!OOEnforceStandards())
		{
			result = translateOldStyleSubentityDeclaration(*declaration.getIf<std::string>(), shipKey, shipData, outFatalError);
		}
		if (!result.isNull())
		{
			// Ensure internal translation made sense, and clean up a bit.
			result = validateNewStyleSubentityDeclaration(result, shipKey, outFatalError);
		}
	}
	else if (declaration.isDict())
	{
		// Validate dictionary-based declaration.
		result = validateNewStyleSubentityDeclaration(declaration, shipKey, outFatalError);
	}
	else
	{
		// The declaration's property-list type ("array", "integer", ...; was the class name of the
		// Foundation object it converted to, bead oo-qps.50).
		OO_LOG_ERR("shipData.load.error.badSubentity", "subentity declaration for ship {} should be string or dictionary, found {}.", shipKey, oo::typeName(declaration.type()));
		*outFatalError = YES;
	}

	// For frangible ships, bad subentities are non-fatal.
	const oo::PList *shipEntry = shipData.get<oo::PList::Dict>(shipKey);
	if (*outFatalError && shipEntry != nullptr && shipEntry->get<bool>("frangible"))  *outFatalError = NO;

	return result;
}


oo::PList OOShipRegistry::translateOldStyleSubentityDeclaration(const std::string &declaration, const std::string &shipKey, const oo::PList &shipData, BOOL *outFatalError)
{
	const std::vector<std::string>	tokenStrings = oo::str::tokens(declaration);
	std::string						subentityKey;
	BOOL							isFlasher;

	subentityKey = FirstToken(tokenStrings);
	isFlasher = subentityKey == "*FLASHER*";

	// Sanity check: require eight tokens.
	if (tokenStrings.size() != 8)
	{
		if (!isFlasher)
		{
			OO_LOG_ERR("shipData.load.error.badSubentity", "the shipdata.plist entry \"{}\" has a broken subentity definition \"{}\" (should have 8 tokens, has {}).", shipKey, subentityKey, tokenStrings.size());
			*outFatalError = YES;
		}
		else
		{
			OO_LOG_WARN("shipData.load.warning.badFlasher", "the shipdata.plist entry \"{}\" has a broken flasher definition (should have 8 tokens, has {}). This flasher will be ignored.", shipKey, tokenStrings.size());
		}
		return oo::PList();
	}

	// The tokens as an array of strings, read with at<float> as the string tokens were.
	oo::PList::Array tokenArray;
	tokenArray.reserve(tokenStrings.size());
	for (const std::string &token : tokenStrings)  tokenArray.emplace_back(token);
	const oo::PList tokens(std::move(tokenArray));

	if (isFlasher)
	{
		return translateOldStyleFlasherDeclaration(tokens, shipKey, outFatalError);
	}
	else
	{
		return translateOldStandardBasicSubentityDeclaration(tokens, shipKey, shipData, outFatalError);
	}
}


oo::PList OOShipRegistry::translateOldStyleFlasherDeclaration(const oo::PList &tokens, const std::string &/*shipKey*/, BOOL * /*outFatalError*/)
{
	Vector					position;
	float					size, frequency, phase, hue;

	position.x = tokens.at<float>(1);
	position.y = tokens.at<float>(2);
	position.z = tokens.at<float>(3);

	hue = tokens.at<float>(4);
	frequency = tokens.at<float>(5);
	phase = tokens.at<float>(6);
	size = tokens.at<float>(7);

	// (the +numberWithFloat: values are single reals)
	oo::PList::Dict colorDict;
	colorDict.emplace("hue", oo::PList::singleReal(hue));

	oo::PList::Dict result;
	result.emplace("type", "flasher");
	result.emplace("position", VectorPList(position));
	result.emplace("colors", oo::PList::Array{ oo::PList(std::move(colorDict)) });
	result.emplace("frequency", oo::PList::singleReal(frequency));
	result.emplace("phase", oo::PList::singleReal(phase));
	result.emplace("size", oo::PList::singleReal(size));
	const oo::PList resultPList(std::move(result));

	std::vector<std::string> tokenStrings;
	for (std::size_t i = 0; i != tokens.count(); ++i)  tokenStrings.push_back(tokens.at<std::string>(i));
	OO_LOG("shipData.translateSubentity.flasher", "Translated flasher declaration \"{}\" to {}", JoinTokens(tokenStrings), oo::DescriptionOf(resultPList));

	return resultPList;
}


oo::PList OOShipRegistry::translateOldStandardBasicSubentityDeclaration(const oo::PList &tokens, const std::string &shipKey, const oo::PList &shipData, BOOL * /*outFatalError*/)
{
	std::string				subentityKey;
	Vector					position;
	Quaternion				orientation;
	BOOL					isTurret, isDock = NO;

	subentityKey = tokens.at<std::string>(0);

	isTurret = shipIsBallTurretForKey(subentityKey, shipData);

	position.x = tokens.at<float>(1);
	position.y = tokens.at<float>(2);
	position.z = tokens.at<float>(3);

	orientation.w = tokens.at<float>(4);
	orientation.x = tokens.at<float>(5);
	orientation.y = tokens.at<float>(6);
	orientation.z = tokens.at<float>(7);

	if(orientation.w == 0 && orientation.x == 0 && orientation.y == 0 && orientation.z == 0)
	{
		orientation.w = 1; // avoid dividing by zero.
		OO_LOG_WARN("shipData.load.error", "The ship {} has an undefined orientation for its {} subentity. Setting it now at (1,0,0,0)", shipKey, subentityKey);
	}

	quaternion_normalize(&orientation);

	if (!isTurret)
	{
		isDock = subentityKey.find("dock") != std::string::npos;
	}

	oo::PList::Dict result;
	result.emplace("type", isTurret ? "ball_turret" : "standard");
	result.emplace("subentity_key", subentityKey);
	result.emplace("position", VectorPList(position));
	result.emplace("orientation", QuaternionPList(orientation));
	if (isDock)  result.emplace("is_dock", true);
	const oo::PList resultPList(std::move(result));

	std::vector<std::string> tokenStrings;
	for (std::size_t i = 0; i != tokens.count(); ++i)  tokenStrings.push_back(tokens.at<std::string>(i));
	OO_LOG("shipData.translateSubentity.standard", "Translated subentity declaration \"{}\" to {}", JoinTokens(tokenStrings), oo::DescriptionOf(resultPList));

	return resultPList;
}


oo::PList OOShipRegistry::validateNewStyleSubentityDeclaration(const oo::PList &declaration, const std::string &shipKey, BOOL *outFatalError)
{
	const std::string		type = StringForKey(&declaration, "type").value_or("standard");

	if (type == "flasher")
	{
		return validateNewStyleFlasherDeclaration(declaration, shipKey, outFatalError);
	}
	else if (type == "standard" || type == "ball_turret")
	{
		return validateNewStyleStandardSubentityDeclaration(declaration, shipKey, outFatalError);
	}
	else
	{
		OO_LOG_ERR("shipData.load.error.badSubentity", "subentity declaration for ship {} does not declare a valid type (must be standard, flasher or ball_turret).", shipKey);
		*outFatalError = YES;
		return oo::PList();
	}
}


oo::PList OOShipRegistry::validateNewStyleFlasherDeclaration(const oo::PList &declaration, const std::string &shipKey, BOOL * /*outFatalError*/)
{
	Vector					position = kZeroVector;
	float					size, frequency, phase, brightfraction;
	BOOL					initiallyOn;

#define kDefaultFlasherColor "redColor"

	// "Validate" is really "clean up", since all values have defaults.
	const oo::PList *colorList = declaration.get<oo::PList::Array>("colors");
	oo::PList colors = colorList != nullptr ? *colorList : oo::PList();
	if (colors.count() == 0)
	{
		const oo::PList *color = declaration.find("color");
		const oo::PList colorDesc = color != nullptr ? *color : oo::PList(kDefaultFlasherColor);
		if (colorDesc.isArray())
		{
			// an easy made error is adding an array to "color" instead of "colors"
			OO_LOG_WARN("shipData.load.warning.flasher.badColor", "changing flasher for ship {} from a color to a colors definition.", shipKey);
			colors = colorDesc;
		}
		else
		{
			colors = oo::PList(oo::PList::Array{ colorDesc });
		}
	}

	// Validate colours. (Their components are single reals.)
	oo::PList::Array validColors;
	for (std::size_t i = 0; i != colors.count(); ++i)
	{
		oo::Ref<OOColor> color = OOColor::colorWithDescription(*colors.at(i));
		if (color != nullptr)
		{
			oo::PList::Array components;
			for (float component : color->normalizedArray())  components.push_back(oo::PList::singleReal(component));
			validColors.emplace_back(std::move(components));
		}
		else
		{
			OO_LOG_WARN("shipdata.load.warning.flasher.badColor", "skipping invalid colour specifier for flasher for ship {}.", shipKey);
		}
	}
	// Ensure there's at least one.
	if (validColors.empty())
	{
		validColors.emplace_back(kDefaultFlasherColor);
	}

	position = VectorForKey(declaration, "position");

	size = declaration.get<float>("size", 8.0);

	if (size <= 0)
	{
		OO_LOG_WARN("shipData.load.warning.flasher.badSize", "skipping flasher of invalid size {:g} for ship {}.", size, shipKey);
		return oo::PList();
	}

	brightfraction = declaration.get<float>("bright_fraction", 0.5);
	if (brightfraction < 0.0 || brightfraction > 1.0)
	{
		OO_LOG_WARN("shipData.load.warning.flasher.badFraction", "skipping flasher of invalid bright fraction {:g} for ship {}.", brightfraction, shipKey);
		return oo::PList();
	}

	frequency = declaration.get<float>("frequency", 2.0);
	phase = declaration.get<float>("phase", 0.0);
	initiallyOn = declaration.get<bool>("initially_on", true);

	oo::PList::Dict result;
	result.emplace("type", "flasher");
	result.emplace("colors", std::move(validColors));
	result.emplace("position", VectorPList(position));
	result.emplace("size", oo::PList::singleReal(size));
	result.emplace("frequency", oo::PList::singleReal(frequency));
	if (phase != 0)  result.emplace("phase", oo::PList::singleReal(phase));
	result.emplace("bright_fraction", oo::PList::singleReal(brightfraction));
	result.emplace("initially_on", initiallyOn ? true : false);

	return oo::PList(std::move(result));
}


oo::PList OOShipRegistry::validateNewStyleStandardSubentityDeclaration(const oo::PList &declaration, const std::string &shipKey, BOOL *outFatalError)
{
	Vector					position = kZeroVector;
	Quaternion				orientation = kIdentityQuaternion;
	BOOL					isTurret;
	BOOL					isDock = NO;
	float					fireRate = -1.0f; // out of range constants
	float					weaponRange = -1.0f;
	float					weaponEnergy = -1.0f;

	const oo::PList *subentityKey = declaration.find("subentity_key");
	if (subentityKey == nullptr)
	{
		OO_LOG_ERR("shipData.load.error.badSubentity", "subentity declaration for ship {} specifies no subentity_key.", shipKey);
		*outFatalError = YES;
		return oo::PList();
	}

	isTurret = StringForKey(&declaration, "type") == "ball_turret";
	if (isTurret)
	{
		fireRate = declaration.get<float>("fire_rate", -1.0f);
		if (fireRate < 0.25f && fireRate >= 0.0f)
		{
			OO_LOG_WARN("shipData.load.warning.turret.badFireRate", "ball turret fire rate of {:g} for subentity of ship {} is invalid, using 0.25.", fireRate, shipKey);
			fireRate = 0.25f;
		}
		weaponRange = declaration.get<float>("weapon_range", -1.0f);
		if (weaponRange > TURRET_SHOT_RANGE * COMBAT_WEAPON_RANGE_FACTOR)
		{
			OO_LOG_WARN("shipData.load.warning.turret.badWeaponRange", "ball turret weapon range of {:g} for subentity of ship {} is too high, using {:.1f}.", weaponRange, shipKey, TURRET_SHOT_RANGE * COMBAT_WEAPON_RANGE_FACTOR);
			weaponRange = TURRET_SHOT_RANGE * COMBAT_WEAPON_RANGE_FACTOR; // approx. range of primary plasma canon.
		}

		weaponEnergy = declaration.get<float>("weapon_energy", -1.0f);
		if (weaponEnergy > 100.0f)

		{
			OO_LOG_WARN("shipData.load.warning.turret.badWeaponEnergy", "ball turret weapon energy of {:g} for subentity of ship {} is too high, using 100.", weaponEnergy, shipKey);
			weaponEnergy = 100.0f;
		}
	}
	else
	{
		isDock = declaration.get<bool>("is_dock");
	}

	position = VectorForKey(declaration, "position");
	orientation = QuaternionForKey(declaration, "orientation");
	quaternion_normalize(&orientation);

	const oo::PList *scriptInfo = declaration.get<oo::PList::Dict>("script_info");

	oo::PList::Dict result;
	result.emplace("type", isTurret ? "ball_turret" : "standard");
	result.emplace("subentity_key", *subentityKey);
	result.emplace("position", VectorPList(position));
	result.emplace("orientation", QuaternionPList(orientation));
	if (isDock)
	{
		result["is_dock"] = true;

		result["dock_label"] = declaration.get<std::string>("dock_label", "the docking bay");

		BOOL dockable = declaration.get<bool>("allow_docking", true);
		BOOL playerdockable = declaration.get<bool>("disallowed_docking_collides", false);
		BOOL undockable = declaration.get<bool>("allow_launching", true);

		result["allow_docking"] = dockable ? true : false;
		result["disallowed_docking_collides"] = playerdockable ? true : false;
		result["allow_launching"] = undockable ? true : false;

	}

	if (isTurret)
	{
		// default constants are defined and set in shipEntity
		// (oo_setFloat: stored the float as a double number)
		if (fireRate > 0) result["fire_rate"] = static_cast<double>(fireRate);
		if (weaponRange >= 0) result["weapon_range"] = static_cast<double>(weaponRange);
		if (weaponEnergy >= 0) result["weapon_energy"] = static_cast<double>(weaponEnergy);
	}

	if (scriptInfo != nullptr)
	{
		result["script_info"] = *scriptInfo;
	}

	return oo::PList(std::move(result));
}


bool OOShipRegistry::shipIsBallTurretForKey(const std::string &shipKey, const oo::PList &shipData)
{
	// Test for presence of setup_actions containing initialiseTurret.
	const oo::PList *shipEntry = shipData.get<oo::PList::Dict>(shipKey);
	const oo::PList *setupActions = shipEntry != nullptr ? shipEntry->get<oo::PList::Array>("setup_actions") : nullptr;

	for (std::size_t i = 0; setupActions != nullptr && i != setupActions->count(); ++i)
	{
		const std::string *action = setupActions->at(i)->getIf<std::string>();
		if (FirstToken(oo::str::tokens(action != nullptr ? *action : std::string())) == "initialiseTurret")  return true;
	}

	if (shipKey == "ballturret")
	{
		// compatibility for OXPs using old subentity declarations and the
		// core turret entity
		return true;
	}

	return false;
}


namespace {

// A string of a dumped property list: where it lives, where it was found, and its text.
struct StringAddr
{
	const void	*address;
	std::string	context;
	std::string	string;
};


void GatherStringAddrsDict(const oo::PList::Dict &dict, std::vector<StringAddr> &strings, const std::string &context);
void GatherStringAddrsArray(const oo::PList::Array &array, std::vector<StringAddr> &strings, const std::string &context);
void GatherStringAddrs(const oo::PList &object, std::vector<StringAddr> &strings, const std::string &context);


void DumpStringAddrs(const oo::PList &dict, const std::string &context)
{
	return;
	static FILE *dump = NULL;
	if (dump == NULL)  dump = fopen("strings.txt", "w");
	if (dump == NULL)  return;

	std::vector<StringAddr> strings;
	GatherStringAddrs(dict, strings, context);

	for (const StringAddr &entry : strings)
	{
		const std::string string = oo::str::format("%s\t%s:  \"%s\"", oo::str::pointerDescription(entry.address).c_str(), entry.context.c_str(), entry.string.c_str());

		fprintf(dump, "%s\n", string.c_str());
	}

	fprintf(dump, "\n");
	fflush(dump);
}


void GatherStringAddr(const std::string &string, std::vector<StringAddr> &strings, const std::string &context)
{
	strings.push_back(StringAddr{&string, context, string});
}


void GatherStringAddrsDict(const oo::PList::Dict &dict, std::vector<StringAddr> &strings, const std::string &context)
{
	const std::string keyContext = context + " key";
	for (const auto &[key, value] : dict)
	{
		GatherStringAddr(key, strings, keyContext);
		GatherStringAddrs(value, strings, oo::str::format("%s.%s", context.c_str(), key.c_str()));
	}
}


void GatherStringAddrsArray(const oo::PList::Array &array, std::vector<StringAddr> &strings, const std::string &context)
{
	unsigned i = 0;
	for (const oo::PList &v : array)
	{
		GatherStringAddrs(v, strings, oo::str::format("%s[%u]", context.c_str(), i++));
	}
}


void GatherStringAddrs(const oo::PList &object, std::vector<StringAddr> &strings, const std::string &context)
{
	if (const std::string *string = object.getIf<std::string>())
	{
		GatherStringAddr(*string, strings, context);
	}
	else if (const oo::PList::Array *array = object.getIf<oo::PList::Array>())
	{
		GatherStringAddrsArray(*array, strings, context);
	}
	else if (const oo::PList::Dict *dict = object.getIf<oo::PList::Dict>())
	{
		GatherStringAddrsDict(*dict, strings, context);
	}
}

}	// namespace
