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
	EntityShaderBindings+ObjCBridge.mm) changed no line here.
	Run: bash tools/check-core-tests.sh
*/

#import "Entity.h"

#include "oo_test.hpp"
#include "oofnd/PList.hpp"

#include <cmath>
#include <cstring>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

@class PlayerEntity;
extern PlayerEntity *gOOPlayer;


// The category under test, as the uniforms reach it: by selector.
@interface Entity (ShaderBindingsUnderTest)

- (GLfloat) clock;
- (unsigned) pseudoFixedD100;
- (unsigned) pseudoFixedD256;
- (unsigned) systemGovernment;
- (unsigned) systemEconomy;
- (unsigned) systemTechLevel;
- (unsigned) systemPopulation;
- (unsigned) systemProductivity;

@end


// PLAYER: answers what the category asks for, with the test's values.
@interface TestPlayer: Entity
{
@public
	double		_clockTime;
	unsigned	_random100;
	unsigned	_random256;
	oo::PList	_government;
	oo::PList	_economy;
	oo::PList	_techLevel;
	oo::PList	_population;
	oo::PList	_productivity;
}
@end


@implementation TestPlayer

- (double) clockTime						{ return _clockTime; }
- (unsigned) systemPseudoRandom100			{ return _random100; }
- (unsigned) systemPseudoRandom256			{ return _random256; }
- (oo::PList) systemGovernment_number		{ return _government; }
- (oo::PList) systemEconomy_number			{ return _economy; }
- (oo::PList) systemTechLevel_number		{ return _techLevel; }
- (oo::PList) systemPopulation_number		{ return _population; }
- (oo::PList) systemProductivity_number		{ return _productivity; }

@end


namespace {

TestPlayer *sPlayer = nil;


void SetUp()
{
	if (sPlayer == nil)  sPlayer = [[TestPlayer alloc] init];	// never released
	gOOPlayer = (PlayerEntity *)sPlayer;
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


// The return type the runtime records for an instance method of Entity (what the uniform reads).
char ReturnType(const char *selector)
{
	Method method = class_getInstanceMethod([Entity class], sel_registerName(selector));
	if (method == NULL)  return '\0';
	const char *types = method_getTypeEncoding(method);
	return types != NULL ? types[0] : '\0';
}

}	// namespace


OO_TEST(clockTime)
{
	@autoreleasepool
	{
		SetUp();
		Entity *entity = AnEntity();
		sPlayer->_clockTime = 1234.5;
		OO_CHECK([entity clock] == 1234.5f);
		// A double clock time is narrowed to a float.
		sPlayer->_clockTime = 180054321.75;
		OO_CHECK([entity clock] == (GLfloat)180054321.75);
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
		OO_CHECK([entity pseudoFixedD100] == 42);
		OO_CHECK([entity pseudoFixedD256] == 200);
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
		OO_CHECK([entity systemGovernment] == 3);
		OO_CHECK([entity systemEconomy] == 5);
		OO_CHECK([entity systemTechLevel] == 11);
		OO_CHECK([entity systemPopulation] == 47);
		OO_CHECK([entity systemProductivity] == 21680);
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
		OO_CHECK([entity systemGovernment] == 0);
		OO_CHECK([entity systemEconomy] == 0);
		OO_CHECK([entity systemTechLevel] == 0);
		OO_CHECK([entity systemPopulation] == 0);
		OO_CHECK([entity systemProductivity] == 0);
	}
}


OO_TEST(uniformTypes)
{
	@autoreleasepool
	{
		// The uniform's type is the method's return type: a float for the clock, unsigned ints
		// for the rest.
		OO_CHECK(ReturnType("clock") == 'f');
		OO_CHECK(ReturnType("pseudoFixedD100") == 'I');
		OO_CHECK(ReturnType("pseudoFixedD256") == 'I');
		OO_CHECK(ReturnType("systemGovernment") == 'I');
		OO_CHECK(ReturnType("systemEconomy") == 'I');
		OO_CHECK(ReturnType("systemTechLevel") == 'I');
		OO_CHECK(ReturnType("systemPopulation") == 'I');
		OO_CHECK(ReturnType("systemProductivity") == 'I');
	}
}


OO_TEST(subclassesAnswerToo)
{
	@autoreleasepool
	{
		SetUp();
		// A subclass of Entity (here the test's player) answers the category's selectors.
		sPlayer->_random100 = 7;
		OO_CHECK([(Entity *)sPlayer pseudoFixedD100] == 7);
	}
}


OO_TEST_MAIN()
