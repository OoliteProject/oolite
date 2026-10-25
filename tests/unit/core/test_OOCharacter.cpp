/*	test_OOCharacter.mm
	Unit tests for OOCharacter (src/Core/OOCharacter.h): bead oo-8kx7 (Phase 3, proposed ADR-0056).

	A character is generated from a seed and a home system: its name and description come from the
	string expander, its species from the home (or another) system's inhabitants, its legal status
	and insurance from the planet-description RNG and its government, and a role or a dictionary
	(a ship's pilot, a JS crew definition) adjusts them. The test pins what the class computes from
	what it is given. The game around it is replaced (ADR-0056 amendment oo-zffj): UNIVERSE is a
	fake Universe below that answers from a table, the string expander and the description lookup
	return text that records what they were asked, and the JavaScript entry points are link stubs
	that abort. The RNG is the game's own (legacy_random.c), reseeded by each test.
	The expectations were written against the Objective-C class and run on it first; bead oo-9ht.10
	deleted that facade, and the same expectations now ask the C++ class (its factories' oo::Ref
	held where the autoreleased facade was), with the C++ class's own cases at the end.
	Run: bash tools/check-core-tests.sh
*/

#include "OOCharacter.h"
#include "OOStringExpander.h"
#include "OOObjCPList.h"
#include "ooscript/JSEngine.hpp"

#include "oo_test.hpp"

#include <cstdlib>
#include <string>


// --- The game around the class --------------------------------------------------------------

/*	UNIVERSE: the four questions OOCharacter asks. System s is named "System s" (none for 200) and
	has government s % 8; even systems are inhabited by " Human Colonials " (padded, capitalised,
	so trimming and lowercasing show), odd ones by "Furry Felines", and system 9 by nobody.
*/
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade the test's Objective-C stand-in stood in for), with the header's names and signatures.
// It answers virtual members, so it has the game's vtable (UniverseStandIn.h) and StandInUniverse overrides them.
class Universe : public oo::RefCounted
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS

	oo::PList generateSystemData(OOSystemID);
	std::optional<std::string> getSystemInhabitants(OOSystemID, bool);
};

class StandInUniverse : public Universe
{
public:
	const oo::PList *descriptions() override
	{
		static const oo::PList *descriptions = new oo::PList(oo::PList::Dict{});
		return descriptions;
	}
	OOSystemID findSystemFromName(const std::string &sysName) override	{ return (sysName == "Lave") ? 7 : -1; }
};

oo::PList Universe::generateSystemData(OOSystemID s)
{
	oo::PList::Dict data{ { "government", oo::PList(s % 8) } };
	if (s != 200)  data.emplace("name", oo::PList("System " + std::to_string(s)));
	return oo::PList(std::move(data));
}
std::optional<std::string> Universe::getSystemInhabitants(OOSystemID sys, bool /*plural*/)
{
	if (sys == 9)  return std::nullopt;
	return (sys % 2 == 0) ? " Human Colonials " : "Furry Felines";
}

Universe *gSharedUniverse = nil;


// The expander: "%R" gives R1, R2, ... in call order; a key gives <key>, with the species and planet
// overrides a description asks for.
static int gExpansions = 0;

std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed /*seed*/, const std::string &string, const oo::PList &overrides, const oo::PList &/*legacyLocals*/, const std::optional<std::string> &/*systemName*/, OOExpandOptions /*options*/)
{
	if (string == "%R")  return "R" + std::to_string(++gExpansions);
	std::string result = "<" + string;
	for (const char *key : { "species", "planet" })
	{
		const oo::PList *value = overrides.find(key);
		if (value != nullptr && value->isString())  result += std::string(" ") + key + "=" + *value->getIf<std::string>();
	}
	return result + ">";
}

std::string cxx_OOLookUpDescriptionPRIV(const std::string &key)
{
	return "desc:" + key;
}

// "1 2 3 4 5 6" is that seed; anything else is kNilRandomSeed's zeroes.
Random_Seed cxx_RandomSeedFromString(const std::optional<std::string> &abcdefString)
{
	if (abcdefString == "1 2 3 4 5 6")  return Random_Seed{ 1, 2, 3, 4, 5, 6 };
	return Random_Seed{};
}

// Link stubs: character scripts. The test never runs one; a call is a test bug.
ooscript::Context gOOJSMainThreadContext = nullptr;
void ooscript::beginRequest(ooscript::Context)		{ std::abort(); }
void ooscript::endRequest(ooscript::Context)		{ std::abort(); }
bool ooscript::isInRequest(ooscript::Context)		{ std::abort(); }

#include "OOScript.h"

// OOScript's loader (an Objective-C OOScript stand-in until bead oo-9ht.133 deleted the facade).
oo::Ref<OOScript> OOScript::jsScriptFromFileNamed(const std::string &, const oo::PList &)	{ std::abort(); }






namespace {

void Reseed()
{
	ranrot_srand(20260930);
	setRandomSeed(RNG_Seed{ 1, 2, 3, 4 });
	gExpansions = 0;
}


void Fake()
{
	if (gSharedUniverse == nil)  gSharedUniverse = new StandInUniverse();
	Reseed();
}


std::string Describe(OOCharacter *c)
{
	return c->name().value_or("-") + "|" + c->shortDescription().value_or("-") + "|" + std::to_string(c->legalStatus()) + "|" + std::to_string(c->insuranceCredits()) + "|" + std::to_string(c->planetIDOfOrigin()) + "|" + c->species().value_or("-");
}


std::string Describe(const oo::Ref<OOCharacter> &c)
{
	return Describe(c.get());
}


oo::Ref<OOCharacter> FromDictionary(oo::PList::Dict dict)
{
	return OOCharacter::characterWithDictionary(oo::PList(std::move(dict)));
}


const oo::PList kSeed("1 2 3 4 5 6");


// A failed comparison prints both sides.
bool Same(const std::string &actual, const std::string &expected)
{
	if (actual == expected)  return true;
	std::fprintf(stderr, "  actual:   %s\n  expected: %s\n", actual.c_str(), expected.c_str());
	return false;
}


const std::string kHuman4 = "R1 <nom>|<character-generic-description species=human colonials planet=System 4>";
const std::string kFeline = "R1 R2|<character-generic-description species=furry felines planet=System ";

}	// namespace


OO_TEST(generatedCharacters)
{
	{
		// Human: "%R" and "nom"; a legal status and insurance from the planet-description RNG.
		Fake();
		OO_CHECK(Same(Describe(OOCharacter::randomCharacterWithRole("nobody in particular", 4)), kHuman4 + "|0|125|4|human colonials"));
		Fake();
		oo::Ref<OOCharacter> pirate = OOCharacter::characterWithRole("pirate", 3);
		OO_CHECK(Same(Describe(pirate), "R1 <nom>|<character-generic-description species=human colonials planet=System 3>|8|500|3|human colonials"));
		OO_CHECK(pirate->planetOfOrigin() == std::optional<std::string>("System 3"));

		// Not human: "%R" twice.
		Fake();
		OO_CHECK(Same(Describe(OOCharacter::randomCharacterWithRole("trader", 5)), kFeline + "5>|0|250|5|furry felines"));

		// No species (the description is expanded without one), and no planet name.
		Fake();
		OO_CHECK(Same(Describe(OOCharacter::randomCharacterWithRole("", 9)), "R1 R2|<character-generic-description planet=System 9>|32|0|9|-"));
		Fake();
		oo::Ref<OOCharacter> nowhere = OOCharacter::randomCharacterWithRole("", 200);
		OO_CHECK(Same(Describe(nowhere), "R1 <nom>|<character-generic-description species=human colonials>|36|0|200|human colonials"));
		OO_CHECK(!nowhere->planetOfOrigin().has_value());

		// One RNG run: each character draws the next seed.
		Fake();
		const char *expected[] =
		{
			"R1 <nom>|<character-generic-description species=human colonials planet=System 0>|36|0|0|human colonials",
			"R2 R3|<character-generic-description species=furry felines planet=System 1>|0|0|1|furry felines",
			"R4 <nom>|<character-generic-description species=human colonials planet=System 2>|0|0|2|human colonials",
			"R5 R6|<character-generic-description species=furry felines planet=System 3>|0|0|3|furry felines",
			"R7 <nom>|<character-generic-description species=human colonials planet=System 4>|0|250|4|human colonials",
			"R8 R9|<character-generic-description species=furry felines planet=System 5>|0|0|5|furry felines",
		};
		for (int i = 0; i < 6; i++)
		{
			OO_CHECK(Same(Describe(OOCharacter::randomCharacterWithRole("", i)), expected[i]));
		}
	}
}


OO_TEST(roles)
{
	struct { const char *role; BOOL cast; const char *rest; } const cases[] =
	{
		{ "Pirate captain", YES, "|8|250|4|human colonials" },	// a prefix, any case
		{ "trader", YES, "|0|250|4|human colonials" },
		{ "hunter", YES, "|0|250|4|human colonials" },
		{ "police", YES, "|0|125|4|human colonials" },
		{ "miner", YES, "|0|25|4|human colonials" },
		{ "passenger", YES, "|0|250|4|human colonials" },
		{ "slave", YES, "|0|0|4|human colonials" },
		{ "miner-x", NO, "|0|250|4|human colonials" },			// miner is exact
		{ "nobody", NO, "|0|250|4|human colonials" },
	};
	{
		for (const auto &c : cases)
		{
			Fake();
			oo::Ref<OOCharacter> character = FromDictionary({ { "origin", oo::PList(4) }, { "random_seed", kSeed } });
			OO_CHECK(Same(Describe(character), kHuman4 + "|0|250|4|human colonials"));
			OO_CHECK(character->castInRole(c.role) == c.cast);
			OO_CHECK(Same(Describe(character), kHuman4 + c.rest));
		}

		Fake();
		oo::Ref<OOCharacter> thargoid = FromDictionary({ { "origin", oo::PList(4) }, { "random_seed", kSeed } });
		OO_CHECK(thargoid->castInRole("thargoid"));
		OO_CHECK(Same(Describe(thargoid), "desc:character-thargoid-name|desc:character-a-thargoid|100|0|4|human colonials"));
	}
}


OO_TEST(dictionaries)
{
	{
		// The origin: a number, a numerical string, "0", a system name, an unknown name or none
		// (a random system), an object that answers -intValue, or one that does not (random).
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "origin", oo::PList(7) }, { "random_seed", kSeed } })), kFeline + "7>|0|250|7|furry felines"));
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "origin", oo::PList("12") }, { "random_seed", kSeed } })), "R1 <nom>|<character-generic-description species=human colonials planet=System 12>|0|250|12|human colonials"));
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "origin", oo::PList("0") }, { "random_seed", kSeed } })), "R1 <nom>|<character-generic-description species=human colonials planet=System 0>|0|250|0|human colonials"));
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "origin", oo::PList("Lave") }, { "random_seed", kSeed } })), kFeline + "7>|0|250|7|furry felines"));
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "origin", oo::PList("Nowhere") }, { "random_seed", kSeed } })), kFeline + "241>|0|250|241|furry felines"));
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "random_seed", kSeed } })), kFeline + "241>|0|250|241|furry felines"));
		// (An Objective-C origin object answering -intValue, or not, retired with the Object node of an
		// Objective-C object, bead oo-4aq6a.5: ADR-0062 item 2.)

		// The seed: random when absent, kNilRandomSeed's zeroes when it does not parse.
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "origin", oo::PList(4) } })), kHuman4 + "|0|125|4|human colonials"));
		Fake();
		OO_CHECK(Same(Describe(FromDictionary({ { "origin", oo::PList(4) }, { "random_seed", oo::PList("junk") } })), kHuman4 + "|3|0|4|human colonials"));

		// Everything else overrides the generated character; bounty wins over legal_status.
		Fake();
		oo::Ref<OOCharacter> c = FromDictionary({ { "origin", oo::PList(4) }, { "random_seed", kSeed }, { "role", oo::PList("police") },
			{ "name", oo::PList("Jameson") }, { "short_description", oo::PList("a commander") }, { "legal_status", oo::PList(10) },
			{ "bounty", oo::PList(20) }, { "insurance", oo::PList(300) },
			{ "script_actions", oo::PList(oo::PList::Array{ oo::PList("doSomething") }) } });
		OO_CHECK(Same(Describe(c), "Jameson|a commander|20|300|4|human colonials"));
		OO_CHECK(c->legacyScript() == oo::PList(oo::PList::Array{ oo::PList("doSomething") }));
		OO_CHECK(c->script() == nil);
		OO_CHECK(c->descriptionComponents() == std::optional<std::string>("Jameson, a commander. bounty: 20 insurance: 300"));
		OO_CHECK(c->oo_jsClassName() == std::optional<std::string>("Character"));
	}
}


OO_TEST(scriptingInfoAndSetters)
{
	{
		Fake();
		oo::Ref<OOCharacter> c = FromDictionary({ { "origin", oo::PList(4) }, { "random_seed", kSeed } });
		OO_CHECK(c->infoForScripting() == oo::PList(oo::PList::Dict{
			{ "name", oo::PList("R1 <nom>") },
			{ "description", oo::PList("<character-generic-description species=human colonials planet=System 4>") },
			{ "species", oo::PList("human colonials") },
			{ "legalStatus", oo::PList::signedInteger(0) },
			{ "insuranceCredits", oo::PList::unsignedInteger(250) },
			{ "homeSystem", oo::PList::signedInteger(4) } }));

		c->setName("Bob");
		c->setShortDescription("a nobody");
		c->setLegalStatus(-5);
		c->setInsuranceCredits(7);
		c->setLegacyScript(oo::PList(oo::PList::Array{}));
		OO_CHECK(Same(Describe(c), "Bob|a nobody|-5|7|4|human colonials"));
		OO_CHECK(c->legacyScript() == oo::PList(oo::PList::Array{}));

		// The list ended at the first missing value: no species, no description, no name.
		Fake();
		oo::Ref<OOCharacter> alien = OOCharacter::randomCharacterWithRole("", 9);
		OO_CHECK(alien->infoForScripting() == oo::PList(oo::PList::Dict{
			{ "name", oo::PList("R1 R2") },
			{ "description", oo::PList("<character-generic-description planet=System 9>") } }));
		alien->setShortDescription(std::nullopt);
		OO_CHECK(alien->infoForScripting() == oo::PList(oo::PList::Dict{ { "name", oo::PList("R1 R2") } }));
		alien->setName(std::nullopt);
		OO_CHECK(alien->infoForScripting() == oo::PList(oo::PList::Dict{}));
		OO_CHECK(alien->descriptionComponents() == std::optional<std::string>("(null), (null). bounty: 32 insurance: 0"));
	}
}


// --- The C++ class, and what the facade's contract kept --------------------------------------------------

OO_TEST(cxxClass)
{
	// The same answers as the Objective-C API above.
	Fake();
	OO_CHECK(Same(Describe(OOCharacter::randomCharacterWithRole("nobody in particular", 4).get()), kHuman4 + "|0|125|4|human colonials"));
	Fake();
	oo::Ref<OOCharacter> pirate = OOCharacter::characterWithRole("pirate", 3);
	OO_CHECK(Same(Describe(pirate.get()), "R1 <nom>|<character-generic-description species=human colonials planet=System 3>|8|500|3|human colonials"));
	OO_CHECK(pirate->planetOfOrigin() == std::optional<std::string>("System 3"));
	Fake();
	OO_CHECK(Same(Describe(oo::makeRef<OOCharacter>("pirate", 3).get()), "R1 <nom>|<character-generic-description species=human colonials planet=System 3>|8|500|3|human colonials"));

	Fake();
	oo::Ref<OOCharacter> c = OOCharacter::characterWithDictionary(oo::PList(oo::PList::Dict{ { "origin", oo::PList(4) }, { "random_seed", kSeed } }));
	OO_CHECK(Same(Describe(c.get()), kHuman4 + "|0|250|4|human colonials"));
	OO_CHECK(c->castInRole("police"));
	OO_CHECK(!c->castInRole("nobody"));
	OO_CHECK(Same(Describe(c.get()), kHuman4 + "|0|125|4|human colonials"));
	OO_CHECK(c->descriptionComponents() == std::optional<std::string>("R1 <nom>, <character-generic-description species=human colonials planet=System 4>. bounty: 0 insurance: 125"));
	OO_CHECK(c->oo_jsClassName() == std::optional<std::string>("Character"));
	OO_CHECK(c->script() == nil);
	OO_CHECK(c->infoForScripting().count() == 6);

	// [[OOCharacter alloc] init]: every field zero.
	oo::Ref<OOCharacter> blank = oo::makeRef<OOCharacter>();
	OO_CHECK(!blank->name().has_value() && !blank->shortDescription().has_value());
	OO_CHECK(blank->legalStatus() == 0 && blank->insuranceCredits() == 0 && blank->planetIDOfOrigin() == 0);
	OO_CHECK(blank->legacyScript().isNull());
}


OO_TEST(facadeIdentity)
{
	Fake();
	oo::Ref<OOCharacter> pilot = FromDictionary({ { "origin", oo::PList(4) }, { "random_seed", kSeed } });

	// A crew list (oo::Ref) keeps finding the same object.
	std::vector<oo::Ref<OOCharacter>> crew{ pilot };
	OO_CHECK(crew[0] == pilot);

	// Objects made as +alloc and an initialiser made them.
	oo::Ref<OOCharacter> blank = oo::makeRef<OOCharacter>();
	OO_CHECK(!blank->name().has_value() && blank->legalStatus() == 0 && blank->planetIDOfOrigin() == 0);
	Fake();
	oo::Ref<OOCharacter> trader = oo::makeRef<OOCharacter>("pirate", 3);
	OO_CHECK(Same(Describe(trader), "R1 <nom>|<character-generic-description species=human colonials planet=System 3>|8|500|3|human colonials"));

	OO_CHECK(OOCharacter::characterWithRole("", 1) != OOCharacter::characterWithRole("", 1));	// distinct objects, as before
}


OO_TEST_MAIN()
