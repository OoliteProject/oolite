/*

OOCharacter.m

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

#include "OOCharacter.h"

#include "Universe.h"
#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "OOJSScript.h"
#include "oofnd/String.hpp"
#include "oofnd/Scanner.hpp"
#include "OOObjCPList.h"


namespace {

// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dict.get<std::string>(key);
}


}	// namespace



std::optional<std::string> OOCharacter::descriptionComponents() const
{
	// ("(null)" is what "%@" printed for a missing name or description; the two getters read
	// _legalStatus and _insuranceCredits, which a const member reads directly)
	return oo::str::format("%s, %s. bounty: %i insurance: %zu", _name.value_or("(null)").c_str(), _shortDescription.value_or("(null)").c_str(), _legalStatus, _insuranceCredits);
}


std::optional<std::string> OOCharacter::oo_jsClassName()
{
	return std::string("Character");
}


std::string OOCharacter::className() const
{
	return "OOCharacter";
}


std::string OOCharacter::description() const
{
	std::string result = oo::str::format("<OOCharacter %s>", oo::str::pointerDescription(this).c_str());
	const std::optional<std::string> components = descriptionComponents();
	if (components.has_value())  result += "{" + *components + "}";
	return result;
}


OOCharacter::OOCharacter(Random_Seed characterSeed, OOSystemID system)
{
	// do character set-up
	_genSeed = characterSeed;
	_originSystem = system;

	basicSetUp();
}


namespace {

// -initWithRole:andOriginalSystem:'s seed, made before it called -initWithGenSeed:andOriginalSystem:.
Random_Seed PseudoRandomSeed()
{
	Random_Seed seed;
	make_pseudo_random_seed(&seed);
	return seed;
}

}	// namespace


OOCharacter::OOCharacter(const std::string &role, OOSystemID system)
	: OOCharacter(PseudoRandomSeed(), system)
{
	castInRole(role);
}

oo::Ref<OOCharacter> OOCharacter::characterWithRole(const std::string &role, OOSystemID system)
{
	return oo::makeRef<OOCharacter>(role, system);
}


oo::Ref<OOCharacter> OOCharacter::randomCharacterWithRole(const std::string &role, OOSystemID system)
{
	Random_Seed seed;

	seed.a = (Ranrot() & 0xff);
	seed.b = (Ranrot() & 0xff);
	seed.c = (Ranrot() & 0xff);
	seed.d = (Ranrot() & 0xff);
	seed.e = (Ranrot() & 0xff);
	seed.f = (Ranrot() & 0xff);

	oo::Ref<OOCharacter>	character = oo::adopt(new OOCharacter(seed, system));
	character->castInRole(role);

	return character;
}


oo::Ref<OOCharacter> OOCharacter::characterWithDictionary(const oo::PList &dict)
{
	oo::Ref<OOCharacter>	character = oo::makeRef<OOCharacter>();
	// (an oo::PList, which carries any non-plist values exactly: proposed ADR-0043 Amendment 2)
	character->setCharacterFromDictionary(dict);

	return character;
}


std::optional<std::string> OOCharacter::planetOfOrigin()
{
	// determine the planet of origin
	const oo::PList originInfo = (UNIVERSE != nullptr ? UNIVERSE->generateSystemData(planetIDOfOrigin()) : oo::PList());
	const oo::PList *name = originInfo.find(std::string(KEY_NAME));
	if (name == nullptr || !name->isString())  return std::nullopt;	// (the value was returned as it stood; it is a string)
	return *name->getIf<std::string>();
}


OOSystemID OOCharacter::planetIDOfOrigin()
{
	// determine the planet of origin
	return _originSystem;
}


std::optional<std::string> OOCharacter::species()
{
	// determine the character's species
	int species = genSeed().f & 0x03;	// 0-1 native to home system, 2 human colonial, 3 other
	std::optional<std::string> speciesString;
	if (species == 3)  speciesString = (UNIVERSE != nullptr ? UNIVERSE->getSystemInhabitants(genSeed().e, NO) : std::optional<std::string>());
	else  speciesString = (UNIVERSE != nullptr ? UNIVERSE->getSystemInhabitants(planetIDOfOrigin(), NO) : std::optional<std::string>());

	if (!speciesString.has_value())  return std::nullopt;

	if (!UNIVERSE->descriptions()->get<bool>("lowercase_ignore"))
	{
		speciesString = oo::str::lowercase(*speciesString);
	}

	return oo::str::trim(*speciesString, oo::str::CharacterSet::whitespace());
}


void OOCharacter::basicSetUp()
{
	// save random seeds for restoration later
	RNG_Seed savedRNGSeed = currentRandomSeed();
	RANROTSeed savedRANROTSeed = RANROTGetFullSeed();
	// set RNG to character seed
	Random_Seed genSeed = this->genSeed();
	seed_for_planet_description(genSeed);

	// determine the planet of origin
	const oo::PList originInfo = (UNIVERSE != nullptr ? UNIVERSE->generateSystemData(planetIDOfOrigin()) : oo::PList());
	const std::optional<std::string> planet = OptionalStringForKey(originInfo, std::string(KEY_NAME));
	OOGovernmentID government = originInfo.get<int>(std::string(KEY_GOVERNMENT)); // 0 .. 7 (0 anarchic .. 7 most stable)
	int criminalTendency = government ^ 0x07;

	// determine the character's species
	const std::optional<std::string> species = this->species();

	// determine the character's name (each half expanded in turn, as the format's arguments were)
	seed_RNG_only_for_planet_description(genSeed);
	std::string genName;
	if (species.has_value() && oo::str::hasPrefix(*species, "human"))
	{
		const std::string givenName = cxx_OOExpandWithSeed(genSeed, "%R").value_or("(null)");
		const std::string familyName = cxx_OOExpandKeyWithSeed(genSeed, "nom").value_or("(null)");
		genName = givenName + " " + familyName;
	} else {
		/*	NOTE: we can't use "%R %R" because that will produce the same string
			twice. TODO: is there a reason not to use %N and kOOExpandGoodRNG
			here? Is there some context where we rely on being able to get the
			same name for a given genSeed?
		 */
		const std::string givenName = cxx_OOExpandWithSeed(genSeed, "%R").value_or("(null)");
		const std::string familyName = cxx_OOExpandWithSeed(genSeed, "%R").value_or("(null)");
		genName = givenName + " " + familyName;
	}
	_name = genName;

	_shortDescription = cxx_OOExpandKeyWithSeed(genSeed, "character-generic-description", species, planet);

	// determine _legalStatus for a completely random character
	setLegalStatus(0);	// clean
	// Two draws, named so the order is explicit (left operand first, as clang evaluated it).
	const int legalDraw1 = gen_rnd_number();
	const int legalDraw2 = gen_rnd_number();
	int legalIndex = legalDraw1 & legalDraw2 & 0x03;
	while (((gen_rnd_number() & 0xf) < criminalTendency) && (legalIndex < 3))
	{
		legalIndex++;
	}
	if (legalIndex == 3)
	{
		// criminal
		const int bountyDraw1 = gen_rnd_number();
		const int bountyDraw2 = gen_rnd_number();
		const int bountyDraw3 = gen_rnd_number();
		setLegalStatus(criminalTendency + criminalTendency * (bountyDraw1 & 0x03) + (bountyDraw2 & bountyDraw3 & 0x7f));
	}
	legalIndex = 0;
	if (_legalStatus > 0)  legalIndex = (_legalStatus <= 50) ? 1 : 2;

	// if clean - determine insurance level (if any)
	setInsuranceCredits(0);
	if (legalIndex == 0)
	{
		const int insuranceDraw1 = gen_rnd_number();
		const int insuranceDraw2 = gen_rnd_number();
		int insuranceIndex = insuranceDraw1 & insuranceDraw2 & 0x03;
		switch (insuranceIndex)
		{
			case 1:
				setInsuranceCredits(125);
				break;
			case 2:
				setInsuranceCredits(250);
				break;
			case 3:
				setInsuranceCredits(500);
		}
	}

	// restore random seed
	setRandomSeed( savedRNGSeed);
	RANROTSetFullSeed(savedRANROTSeed);
}


bool OOCharacter::castInRole(const std::string &roleName)
{
	bool specialSetUpDone = false;

	const std::string role = oo::str::lowercase(roleName);
	if (oo::str::hasPrefix(role, "pirate"))
	{
		// determine _legalStatus for a completely random character
		Random_Seed genSeed = this->genSeed();
		int sins = 0x08 | (genSeed.a & genSeed.b);
		setLegalStatus(sins & 0x7f);

		specialSetUpDone = true;
	}
	else if (oo::str::hasPrefix(role, "trader"))
	{
		setLegalStatus(0);	// clean

		int insuranceIndex = gen_rnd_number() & 0x03;
		switch (insuranceIndex)
		{
			case 0:
				setInsuranceCredits(0);
				break;
			case 1:
				setInsuranceCredits(125);
				break;
			case 2:
				setInsuranceCredits(250);
				break;
			case 3:
				setInsuranceCredits(500);
		}
		specialSetUpDone = true;
	}
	else if (oo::str::hasPrefix(role, "hunter"))
	{
		setLegalStatus(0);	// clean
		int insuranceIndex = gen_rnd_number() & 0x03;
		if (insuranceIndex == 3)
			setInsuranceCredits(500);
		specialSetUpDone = true;
	}
	else if (oo::str::hasPrefix(role, "police"))
	{
		setLegalStatus(0);	// clean
		setInsuranceCredits(125);
		specialSetUpDone = true;
	}
	else if (role == "miner")
	{
		setLegalStatus(0);	// clean
		setInsuranceCredits(25);
		specialSetUpDone = true;
	}
	else if (role == "passenger")
	{
		setLegalStatus(0);	// clean
		int insuranceIndex = gen_rnd_number() & 0x03;
		switch (insuranceIndex)
		{
			case 0:
				setInsuranceCredits(25);
				break;
			case 1:
				setInsuranceCredits(125);
				break;
			case 2:
				setInsuranceCredits(250);
				break;
			case 3:
				setInsuranceCredits(500);
		}
		specialSetUpDone = true;
	}
	else if (role == "slave")
	{
		setLegalStatus(0);	// clean
		setInsuranceCredits(0);
		specialSetUpDone = true;
	}
	else if (role == "thargoid")
	{
		setLegalStatus(100);
		setInsuranceCredits(0);
		setName(OO_DESC("character-thargoid-name"));
		setShortDescription(OO_DESC("character-a-thargoid"));
		specialSetUpDone = true;
	}

	// do long description here

	return specialSetUpDone;
}


std::optional<std::string> OOCharacter::name()
{
	return _name;
}


std::optional<std::string> OOCharacter::shortDescription()
{
	return _shortDescription;
}


Random_Seed OOCharacter::genSeed()
{
	return _genSeed;
}


int OOCharacter::legalStatus()
{
	return _legalStatus;
}


OOCreditsQuantity OOCharacter::insuranceCredits()
{
	return _insuranceCredits;
}


oo::PList OOCharacter::legacyScript()
{
	return _scriptActions;
}


oo::PList OOCharacter::infoForScripting()
{
	// Every value is worked out first, as the list's arguments were; the list ended at the first
	// nil (a missing name, description or species).
	const std::optional<std::string> species = this->species();
	oo::PList::Dict result;
	if (_name.has_value())
	{
		result.emplace("name", oo::PList(*_name));
		if (_shortDescription.has_value())
		{
			result.emplace("description", oo::PList(*_shortDescription));
			if (species.has_value())
			{
				result.emplace("species", oo::PList(*species));
				result.emplace("legalStatus", oo::PList::signedInteger(legalStatus()));
				result.emplace("insuranceCredits", oo::PList::unsignedInteger(insuranceCredits()));
				result.emplace("homeSystem", oo::PList::signedInteger(planetIDOfOrigin()));
			}
		}
	}
	return oo::PList(std::move(result));
}


void OOCharacter::setName(const std::optional<std::string> &value)
{
	_name = value;
}


void OOCharacter::setShortDescription(const std::optional<std::string> &value)
{
	_shortDescription = value;
}


void OOCharacter::setOriginSystem(OOSystemID value)
{
	_originSystem = value;
}


void OOCharacter::setGenSeed(Random_Seed value)
{
	_genSeed = value;
}


void OOCharacter::setLegalStatus(int value)
{
	_legalStatus = value;
}


void OOCharacter::setInsuranceCredits(OOCreditsQuantity value)
{
	_insuranceCredits = value;
}


void OOCharacter::setLegacyScript(const oo::PList &some_actions)
{
	_scriptActions = some_actions;
}


::OOScript *OOCharacter::script()
{
	return _script.get();
}


void OOCharacter::setCharacterScript(const std::string &scriptName)
{
	// (the script's "character" is this character, an Object node, as it was self; it reaches
	// JavaScript as undefined, as the facade did)
	_script = OOScript::jsScriptFromFileNamed(scriptName,
											  oo::PList(oo::PList::Dict{ { "character", oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(this))) } }));
}


void OOCharacter::doScriptEvent(ooscript::PropertyId message)
{
	ooscript::Context context = OOJSAcquireContext();
	if (_script != nullptr)  _script->callMethod(message, context, NULL, 0, NULL);
	OOJSRelinquishContext(context);
}


void OOCharacter::setCharacterFromDictionary(const oo::PList &dict)
{
	const oo::PList		*origin = nullptr;
	Random_Seed			seed;

	origin = dict.find("origin");
	// (a string or a number; another object that answered -intValue, in an Object node, went with
	// bead oo-4aq6a.5: no game object is one)
	const std::string	*originName = (origin != nullptr) ? origin->getIf<std::string>() : nullptr;
	const int			originValue = dict.get<int>("origin");
	if ((origin != nullptr && origin->isNumber()) ||
		((originName != nullptr) && (originValue != 0 || *originName == "0")))
	{
		// Number or numerical string
		setOriginSystem(originValue);
	}
	else if (originName != nullptr)
	{
		OOSystemID sys = (UNIVERSE != nullptr ? UNIVERSE->findSystemFromName(*originName) : 0);
		if (sys < 0)
		{
			OO_LOG_ERR("character.load.unknownSystem", "could not find a system named '{}' in this galaxy.", *originName);
			setOriginSystem((ranrot_rand() & 0xff));
		}
		else
		{
			setOriginSystem(sys);
		}
	}
	else
	{
		// no origin defined, select one at random.
		setOriginSystem((ranrot_rand() & 0xff));
	}

	if (dict.find("random_seed") != nullptr)
	{
		seed = cxx_RandomSeedFromString(OptionalStringForKey(dict, "random_seed"));  // returns kNilRandomSeed on failure
	}
	else
	{
		seed.a = (ranrot_rand() & 0xff);
		seed.b = (ranrot_rand() & 0xff);
		seed.c = (ranrot_rand() & 0xff);
		seed.d = (ranrot_rand() & 0xff);
		seed.e = (ranrot_rand() & 0xff);
		seed.f = (ranrot_rand() & 0xff);
	}
	setGenSeed(seed);
	basicSetUp();

	if (const std::optional<std::string> role = OptionalStringForKey(dict, "role"))  castInRole(*role);
	if (const std::optional<std::string> name = OptionalStringForKey(dict, "name"))  _name = name;
	if (const std::optional<std::string> shortDescription = OptionalStringForKey(dict, "short_description"))  _shortDescription = shortDescription;
	if (dict.find("legal_status") != nullptr)  setLegalStatus(dict.get<int>("legal_status"));
	if (dict.find("bounty") != nullptr)  setLegalStatus(dict.get<int>("bounty"));
	if (dict.find("insurance") != nullptr)  setInsuranceCredits(dict.get<unsigned long long>("insurance"));
	if (const std::optional<std::string> script = OptionalStringForKey(dict, "script")) setCharacterScript(*script);
	if (const oo::PList *scriptActions = dict.get<oo::PList::Array>("script_actions"))  setLegacyScript(*scriptActions);

}

