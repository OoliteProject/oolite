/*	test_EntityShaderBindings.mm
	Unit tests for the category Entity (ShaderBindings) (src/Core/Entities/EntityShaderBindings.mm):
	bead oo-aeev, the values a shader's uniforms bind to by name on any entity (the clock, the
	system's "flavour" numbers and its attributes), all read from PLAYER.

	The category has no header: the shader uniforms find its methods by selector and read their
	return types from the runtime (OOShaderUniformTypeFromMethod). So the test declares the
	category itself, sends its selectors to an entity, and pins each method's return type
	encoding, which decides the uniform's type. PLAYER is an entity that answers the selectors the
	category sends with values the test sets; a system attribute that is not a number reads 0, as
	-unsignedIntValue of nil did. The test links the whole game but main (['*']) for Entity. The
	expectations were written against the Objective-C category and run on it first; the
	conversion (amendment oo-9fwb: members of cxx::Entity, the category's forwarders in
	EntityShaderBindings+ObjCBridge.mm) changed no line here. Since the uniforms bind the members
	through the entities' member table (bead oo-9ht.158) and the forwarders went (bead oo-9ht.127),
	the test asks the binding a uniform makes for each name on an entity's object, and pins the
	uniform type the row gives, which is the one the method's return type encoding gave
	('f' a float, 'I' an unsigned int); every expected value is kept.
	Run: bash tools/check-core-tests.sh
*/

#import "Entity.h"
#import "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)

#include "oo_test.hpp"
#include "oofnd/PList.hpp"

#include <cmath>
#include <cstring>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;


// The values under test, as the uniforms reach them: the binding for a name (bead oo-9ht.158).
#import "OOShaderUniformMethodType.h"


// PLAYER: answers what the category asks for, with the test's values (C++ since bead oo-9ht.177
// deleted the Objective-C player).
class TestPlayer : public PlayerEntity
{
public:
	double		_clockTime = 0;
	unsigned	_random100 = 0;
	unsigned	_random256 = 0;
	oo::PList	_government;
	oo::PList	_economy;
	oo::PList	_techLevel;
	oo::PList	_population;
	oo::PList	_productivity;

	double clockTime() override						{ return _clockTime; }
	unsigned systemPseudoRandom100() override		{ return _random100; }
	unsigned systemPseudoRandom256() override		{ return _random256; }
	oo::PList systemGovernment_number() override	{ return _government; }
	oo::PList systemEconomy_number() override		{ return _economy; }
	oo::PList systemTechLevel_number() override		{ return _techLevel; }
	oo::PList systemPopulation_number() override	{ return _population; }
	oo::PList systemProductivity_number() override	{ return _productivity; }
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	@autoreleasepool
	{
		[oo::NewEntityFacade(player) retain];
	}
	return player.get();
}


namespace {

TestPlayer *sPlayer = nullptr;


void SetUp()
{
	if (sPlayer == nullptr)  sPlayer = NewTestPlayer<TestPlayer>();	// never released
	gOOPlayer = sPlayer;
	sPlayer->_clockTime = 0;
	sPlayer->_random100 = 0;
	sPlayer->_random256 = 0;
	sPlayer->_government = oo::PList();
	sPlayer->_economy = oo::PList();
	sPlayer->_techLevel = oo::PList();
	sPlayer->_population = oo::PList();
	sPlayer->_productivity = oo::PList();
}


Entity *AnEntity()
{
	return [[[Entity alloc] init] autorelease];
}


// The binding a uniform bound to the name on the entity's object makes (the member table).
OOShaderMemberBinding Binding(Entity *entity, const char *name)
{
	OOShaderMemberBinding binding = {};
	if (!OOShaderMemberBindingFor(entity, sel_registerName(name), &binding))  binding = {};
	return binding;
}

// What a uniform bound to the name reads: an integer or a float.
long long BoundInt(Entity *entity, const char *name)
{
	OOShaderBindingValue value = {};
	const OOShaderMemberBinding binding = Binding(entity, name);
	if (binding.get != nullptr)  binding.get(entity, value);
	return value.i;
}

double BoundFloat(Entity *entity, const char *name)
{
	OOShaderBindingValue value = {};
	const OOShaderMemberBinding binding = Binding(entity, name);
	if (binding.get != nullptr)  binding.get(entity, value);
	return value.f;
}

}	// namespace


OO_TEST(clockTime)
{
	@autoreleasepool
	{
		SetUp();
		Entity *entity = AnEntity();
		sPlayer->_clockTime = 1234.5;
		OO_CHECK(BoundFloat(entity, "clock") == 1234.5f);
		// A double clock time is narrowed to a float.
		sPlayer->_clockTime = 180054321.75;
		OO_CHECK(BoundFloat(entity, "clock") == (GLfloat)180054321.75);
	}
}


OO_TEST(flavourNumbers)
{
	@autoreleasepool
	{
		SetUp();
		Entity *entity = AnEntity();
		sPlayer->_random100 = 42;
		sPlayer->_random256 = 200;
		OO_CHECK(BoundInt(entity, "pseudoFixedD100") == 42);
		OO_CHECK(BoundInt(entity, "pseudoFixedD256") == 200);
	}
}


OO_TEST(systemAttributes)
{
	@autoreleasepool
	{
		SetUp();
		Entity *entity = AnEntity();
		sPlayer->_government = oo::PList(3);
		sPlayer->_economy = oo::PList(5);
		sPlayer->_techLevel = oo::PList(11);
		sPlayer->_population = oo::PList(47);
		sPlayer->_productivity = oo::PList(21680);
		OO_CHECK(BoundInt(entity, "systemGovernment") == 3);
		OO_CHECK(BoundInt(entity, "systemEconomy") == 5);
		OO_CHECK(BoundInt(entity, "systemTechLevel") == 11);
		OO_CHECK(BoundInt(entity, "systemPopulation") == 47);
		OO_CHECK(BoundInt(entity, "systemProductivity") == 21680);
	}
}


OO_TEST(attributeNotANumberIsZero)
{
	@autoreleasepool
	{
		SetUp();
		Entity *entity = AnEntity();
		// No value (nil), and a value that is not a number: 0, as -unsignedIntValue of nil.
		sPlayer->_government = oo::PList();
		sPlayer->_economy = oo::PList("rich");
		OO_CHECK(BoundInt(entity, "systemGovernment") == 0);
		OO_CHECK(BoundInt(entity, "systemEconomy") == 0);
		OO_CHECK(BoundInt(entity, "systemTechLevel") == 0);
		OO_CHECK(BoundInt(entity, "systemPopulation") == 0);
		OO_CHECK(BoundInt(entity, "systemProductivity") == 0);
	}
}


OO_TEST(uniformTypes)
{
	@autoreleasepool
	{
		// The uniform's type is the method's return type: a float for the clock ('f'), unsigned
		// ints ('I') for the rest.
		Entity *entity = AnEntity();
		OO_CHECK(Binding(entity, "clock").type == kOOShaderUniformTypeFloat);
		OO_CHECK(Binding(entity, "pseudoFixedD100").type == kOOShaderUniformTypeUnsignedInt);
		OO_CHECK(Binding(entity, "pseudoFixedD256").type == kOOShaderUniformTypeUnsignedInt);
		OO_CHECK(Binding(entity, "systemGovernment").type == kOOShaderUniformTypeUnsignedInt);
		OO_CHECK(Binding(entity, "systemEconomy").type == kOOShaderUniformTypeUnsignedInt);
		OO_CHECK(Binding(entity, "systemTechLevel").type == kOOShaderUniformTypeUnsignedInt);
		OO_CHECK(Binding(entity, "systemPopulation").type == kOOShaderUniformTypeUnsignedInt);
		OO_CHECK(Binding(entity, "systemProductivity").type == kOOShaderUniformTypeUnsignedInt);
	}
}


OO_TEST(subclassesAnswerToo)
{
	@autoreleasepool
	{
		SetUp();
		// A subclass of Entity (here the test's player) answers the category's selectors.
		sPlayer->_random100 = 7;
		OO_CHECK(BoundInt(oo::ToObjC(sPlayer), "pseudoFixedD100") == 7);	// the player's object (C++ player since bead oo-9ht.177)
	}
}


OO_TEST_MAIN()
