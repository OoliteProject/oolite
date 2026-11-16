/*	test_OOFlasherEntity.mm
	Unit tests for OOFlasherEntity (src/Core/Entities/OOFlasherEntity.h), the blinking lights that
	ships and visual effects carry as subentities: bead oo-bn5j, a leaf of the Entities seam under
	OOLightParticleEntity (proposed ADR-0056, amendments oo-bj8 item 12, oo-0otc, oo-0mxi and
	oo-2c6g).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised and a plain entity as PLAYER. The expectations were
	written against the Objective-C API and run on the unconverted class first: a flasher reads its
	size, frequency (doubled), phase, bright fraction, colours and initial state from its
	dictionary (defaults 1, 1, 0, 0.5, none, on); its accessors; its colour is its current
	components; -update: cycles its colours on the wave's falling half and sets its brightness, or
	keeps it opaque at frequency 0; it draws only while active; it is a flasher (and an entity is
	not); its collision radius is half its diameter; -rescaleBy: scales the diameter and
	-rescaleBy:writeToCache: does nothing. The colour components, an ivar of OOLightParticleEntity,
	are read and set through the one block of helpers below. The flashers are made by the class
	method the callers send, which the conversion kept on the facade: the last test pins that their
	object is a C++ entity whose Objective-C object is the OOFlasherEntity facade.
	Run: bash tools/check-core-tests.sh
*/

#import "OOFlasherEntity.h"
#import "OOColor.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

@class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


@interface TestPlayer: Entity
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }

@end


// UNIVERSE: never initialised.
@interface TestUniverse: Universe
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime	{ return 0; }

@end


namespace {

void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)  universe = (Universe *)class_createInstance([TestUniverse class], 0);	// never released
	gSharedUniverse = universe;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
}


// --- Ivars the test reads and sets, and nothing else -----------------------------------------------

const GLfloat *ColorComponents(Entity *e)			{ return oo::ToCxx((OOLightParticleEntity *)e)->_colorComponents; }
GLfloat CamZeroDistance(Entity *e)					{ return e->_cxxEntity->cam_zero_distance; }
void SetCamZeroDistance(Entity *e, GLfloat value)	{ e->_cxxEntity->cam_zero_distance = value; }

// --------------------------------------------------------------------------------------------------


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


bool RGBIs(Entity *e, GLfloat r, GLfloat g, GLfloat b)
{
	const GLfloat *c = ColorComponents(e);
	return Near(c[0], r) && Near(c[1], g) && Near(c[2], b);
}


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


oo::PList WhiteBlack(float frequency, float fraction)
{
	return Dict({
		{ "size", oo::PList(4.0) },
		{ "frequency", oo::PList(double(frequency)) },
		{ "bright_fraction", oo::PList(double(fraction)) },
		{ "colors", oo::PList(oo::PList::Array{ oo::PList(std::string("whiteColor")), oo::PList(std::string("blackColor")) }) },
	});
}

}	// namespace


OO_TEST(defaults)
{
	@autoreleasepool
	{
		SetUp();
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:Dict({})];
		OO_CHECK(flasher != nil && [flasher isKindOfClass:[OOFlasherEntity class]]);
		OO_CHECK([flasher isKindOfClass:[OOLightParticleEntity class]]);
		OO_CHECK([flasher diameter] == 1.0f);
		OO_CHECK([flasher frequency] == 2.0f && [flasher phase] == 0.0f && [flasher fraction] == 0.5f);
		OO_CHECK([flasher isActive]);
		OO_CHECK([flasher status] == STATUS_EFFECT && [flasher scanClass] == CLASS_NO_DRAW);
		// No colours: the current colour is nil, which left the components white.
		OO_CHECK(RGBIs(flasher, 1, 1, 1) && ColorComponents(flasher)[3] == 1.0f);
		OO_CHECK([flasher isFlasher]);
		OO_CHECK([flasher findCollisionRadius] == 0.5);
	}
}


OO_TEST(dictionary)
{
	@autoreleasepool
	{
		SetUp();
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:Dict({
			{ "size", oo::PList(6.0) },
			{ "frequency", oo::PList(1.5) },
			{ "phase", oo::PList(0.25) },
			{ "bright_fraction", oo::PList(0.75) },
			{ "initially_on", oo::PList(false) },
			{ "colors", oo::PList(oo::PList::Array{ oo::PList(std::string("blackColor")), oo::PList(std::string("whiteColor")) }) },
		})];
		OO_CHECK([flasher diameter] == 6.0f && [flasher findCollisionRadius] == 3.0);
		OO_CHECK([flasher frequency] == 3.0f && [flasher phase] == 0.25f && [flasher fraction] == 0.75f);
		OO_CHECK(![flasher isActive]);
		OO_CHECK(RGBIs(flasher, 0, 0, 0) && ColorComponents(flasher)[3] == 1.0f);	// the first colour

		OOColor *color = [flasher color];
		float r = -1, g = -1, b = -1, a = -1;
		[color getRed:&r green:&g blue:&b alpha:&a];
		OO_CHECK(r == 0 && g == 0 && b == 0 && a == 1);
	}
}


OO_TEST(saturationFactor)
{
	@autoreleasepool
	{
		SetUp();
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:Dict({
			{ "colors", oo::PList(oo::PList::Array{ oo::PList(std::string("redColor")) }) },
		})];
		// Red at three quarters of its saturation.
		OO_CHECK(RGBIs(flasher, 1.0f, 0.25f, 0.25f));
	}
}


OO_TEST(accessors)
{
	@autoreleasepool
	{
		SetUp();
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:WhiteBlack(1, 0.5)];
		[flasher setActive:NO];
		OO_CHECK(![flasher isActive]);
		[flasher setActive:YES];
		OO_CHECK([flasher isActive]);
		[flasher setFrequency:7.0f];
		OO_CHECK([flasher frequency] == 7.0f);
		[flasher setPhase:0.5f];
		OO_CHECK([flasher phase] == 0.5f);
		[flasher setFraction:0.125f];
		OO_CHECK([flasher fraction] == 0.125f);
		[flasher setColor:[OOColor colorWithRed:0.5f green:0.25f blue:0.125f alpha:0.75f] alpha:0.375f];
		float r = -1, g = -1, b = -1, a = -1;
		[[flasher color] getRed:&r green:&g blue:&b alpha:&a];
		OO_CHECK(r == 0.5f && g == 0.25f && b == 0.125f && a == 0.375f);
	}
}


OO_TEST(updateCyclesColours)
{
	@autoreleasepool
	{
		SetUp();
		// frequency 1 (stored 2): wave = sin(2 pi t), fraction 0.5: threshold cos(pi / 2) = 0.
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:WhiteBlack(1, 0.5)];
		OO_CHECK(RGBIs(flasher, 1, 1, 1));

		[flasher update:0.125];		// t 0.125: wave sin(pi/4), rising half: brightness above the fraction
		double wave = std::sin(M_PI / 4);
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
		OO_CHECK(Near(ColorComponents(flasher)[3], 0.5 + (0.5 / 1.0) * wave));

		[flasher update:0.5];		// t 0.625: wave -sin(pi/4), falling: no switch (wave < _wave)
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
		OO_CHECK(Near(ColorComponents(flasher)[3], 0.5 + (0.5 / 1.0) * -wave));

		[flasher update:0.3125];	// t 0.9375: wave still negative and rising: the next colour
		OO_CHECK(RGBIs(flasher, 0, 0, 0));

		[flasher update:0.03125];	// t 0.96875: just switched, no second switch
		OO_CHECK(RGBIs(flasher, 0, 0, 0));

		[flasher update:0.0625];	// t 1.03125: positive again, the switch resets
		[flasher update:0.59375];	// t 1.625: negative but falling: no switch
		OO_CHECK(RGBIs(flasher, 0, 0, 0));
		[flasher update:0.3125];	// t 1.9375: rising below zero: back to the first colour
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
	}
}


OO_TEST(frequencyZeroIsOpaque)
{
	@autoreleasepool
	{
		SetUp();
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:WhiteBlack(0, 0.5)];
		[flasher setColor:[OOColor whiteColor] alpha:0.25f];
		[flasher update:0.3];
		OO_CHECK(ColorComponents(flasher)[3] == 1.0f);
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
	}
}


OO_TEST(drawsOnlyWhileActive)
{
	@autoreleasepool
	{
		SetUp();
		Entity *owner = [[[Entity alloc] init] autorelease];
		SetCamZeroDistance(owner, 1e30f);		// beyond any draw distance: the draw stops at the cut-off
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:WhiteBlack(1, 0.5)];
		[flasher setOwner:owner];
		SetCamZeroDistance(flasher, 5.0f);

		[flasher setActive:NO];
		[flasher drawSubEntityImmediate:true translucent:true];
		OO_CHECK(CamZeroDistance(flasher) == 5.0f);	// not drawn

		[flasher setActive:YES];
		[flasher drawSubEntityImmediate:true translucent:true];
		OO_CHECK(CamZeroDistance(flasher) == 1e30f);	// OOLightParticleEntity's draw read the owner's distance
	}
}


OO_TEST(rescale)
{
	@autoreleasepool
	{
		SetUp();
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:WhiteBlack(1, 0.5)];
		[flasher rescaleBy:2.5f];
		OO_CHECK([flasher diameter] == 10.0f);
		[flasher rescaleBy:3.0f writeToCache:YES];
		OO_CHECK([flasher diameter] == 10.0f);
	}
}


OO_TEST(isFlasher)
{
	@autoreleasepool
	{
		SetUp();
		Entity *plain = [[[Entity alloc] init] autorelease];
		OO_CHECK(![plain isFlasher]);
		OOLightParticleEntity *particle = [[[OOLightParticleEntity alloc] initWithDiameter:1.0f] autorelease];
		OO_CHECK(![particle isFlasher]);
		OO_CHECK([[OOFlasherEntity flasherWithDictionary:Dict({})] isFlasher]);
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp();
		OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:WhiteBlack(1, 0.5)];
		OO_CHECK([flasher class] == [OOFlasherEntity class]);
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<cxx::OOFlasherEntity *>(oo::ToCxx(flasher)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(flasher)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(flasher)) == flasher);
	}
}


OO_TEST_MAIN()
