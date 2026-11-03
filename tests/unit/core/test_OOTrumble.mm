/*	test_OOTrumble.mm
	Unit tests for cxx::OOTrumble (src/Core/OOTrumble.h) and its Objective-C facade: bead oo-862e (Phase 3, proposed ADR-0056).

	A trumble is set up from a two-character digram (its colours, pattern, maximum size, and the
	RNG seed for its position, motion and animation timings), and then lives by updateTrumble:, which
	moves it against the player's dials and view, grows it, makes it hungry and uncomfortable, feeds
	it from the player's cargo, and steps its animations: idle, blink, proot, snarl, shudder, sleep,
	spawn (which asks the player to add a trumble) and pop (which asks the player to remove it).
	The test pins that state, the savegame dictionary, and what it asks of the game.

	The game around it is replaced (ADR-0056 amendments oo-zffj, oo-8kx7): UNIVERSE, the player, the
	cargo pods, the commodity market, textures and sounds are fakes below that answer from fields and
	record what they are asked; drawTrumble: is GL and its matrix calls are aborting link stubs. The
	RNG is the game's own (legacy_random.c). The expectations were written against the Objective-C
	class and run on it first, reading its private state through the runtime; they now run through
	the facade (OOTrumble+ObjCBridge.h) and read that state through the class's test friend. The
	last tests pin the C++ API and the facade's contract. Run: bash tools/check-core-tests.sh
*/

#import "OOTrumble.h"

#include "oo_test.hpp"

#include "oofnd/objc/OOObjCRef.h"

#include <objc/runtime.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#import "OOTypes.h"
#import "OOMaths.h"


// --- The game around the class --------------------------------------------------------------

static std::vector<std::string> gLog;	// what the trumble asked of the game, in order

@interface OOTexture: OOObject
+ (id) cxx_textureWithName:(const std::optional<std::string> &)name inFolder:(const std::optional<std::string> &)directory options:(uint32_t)options anisotropy:(GLfloat)anisotropy lodBias:(GLfloat)lodBias;
- (void) apply;
@end

@implementation OOTexture
+ (id) cxx_textureWithName:(const std::optional<std::string> &)name inFolder:(const std::optional<std::string> &)directory options:(uint32_t)options anisotropy:(GLfloat)anisotropy lodBias:(GLfloat)lodBias
{
	gLog.push_back("texture " + name.value_or("-") + " in " + directory.value_or("-") + " options " + std::to_string(options) + " anisotropy " + std::to_string(anisotropy) + " lodBias " + std::to_string(lodBias));
	return [[[OOTexture alloc] init] autorelease];
}
- (void) apply  { std::abort(); }
@end


@interface OOSound: OOObject
{
@public
	std::string key;
}
- (id) initWithCustomSoundKey:(const std::string &)key;
@end

@implementation OOSound
- (id) initWithCustomSoundKey:(const std::string &)aKey
{
	if ((self = [super init]))  key = aKey;
	gLog.push_back("sound " + aKey);
	return self;
}
@end


static BOOL gSoundSourcePlaying = NO;

@interface OOSoundSource: OOObject
{
	OOSound *_sound;
}
- (BOOL) isPlaying;
- (OOSound *) sound;
- (void) setPosition:(Vector)inPosition;
- (void) playOOSound:(OOSound *)inSound;
@end

@implementation OOSoundSource
- (BOOL) isPlaying					{ return gSoundSourcePlaying; }
- (OOSound *) sound					{ return _sound; }
- (void) setPosition:(Vector)v		{ }
- (void) playOOSound:(OOSound *)s	{ _sound = s; gLog.push_back("play " + s->key); }
@end


@interface ShipEntity: OOObject
{
@public
	std::string commodity;
}
- (std::optional<std::string>) cxx_commodityType;
@end

@implementation ShipEntity
- (std::optional<std::string>) cxx_commodityType  { return commodity; }
@end


// The market: food is loved (1), furs liked (0.5), anything else refused.
@interface Market: OOObject
- (float) cxx_trumbleOpinionForGood:(const std::string &)good;
@end

@implementation Market
- (float) cxx_trumbleOpinionForGood:(const std::string &)good
{
	return (good == "food") ? 1.0f : (good == "furs") ? 0.5f : 0.0f;
}
@end


@interface PlayerEntity: OOObject
{
@public
	GLfloat pitch, roll, heat;
	float appetite;
	std::vector<oo::ObjCRef<ShipEntity *>> cargo;
	std::vector<OOTrumble *> added, removed;
}
- (GLfloat) dialRoll;
- (GLfloat) dialPitch;
- (GLfloat) hullHeatLevel;
- (std::vector<oo::ObjCRef<ShipEntity *>> *) cxx_cargo;
- (float) trumbleAppetiteAccumulator;
- (void) setTrumbleAppetiteAccumulator:(float)value;
- (void) addTrumble:(OOTrumble *)papaTrumble;
- (void) removeTrumble:(OOTrumble *)deadTrumble;
@end

@implementation PlayerEntity
- (GLfloat) dialRoll					{ return roll; }
- (GLfloat) dialPitch					{ return pitch; }
- (GLfloat) hullHeatLevel				{ return heat; }
- (std::vector<oo::ObjCRef<ShipEntity *>> *) cxx_cargo	{ return &cargo; }
- (float) trumbleAppetiteAccumulator	{ return appetite; }
- (void) setTrumbleAppetiteAccumulator:(float)value	{ appetite = value; }
- (void) addTrumble:(OOTrumble *)t		{ added.push_back(t); }
- (void) removeTrumble:(OOTrumble *)t	{ removed.push_back(t); }
@end


@interface Universe: OOObject
{
@public
	OOViewID view;
	Market *market;
}
- (OOViewID) viewDirection;
- (Market *) commodityMarket;
- (std::optional<std::string>) cxx_displayNameForCommodity:(const std::string &)co_type;
- (void) cxx_addMessage:(const std::optional<std::string> &)text forCount:(OOTimeDelta)count;
@end

@implementation Universe
- (OOViewID) viewDirection	{ return view; }
- (Market *) commodityMarket	{ return market; }
- (std::optional<std::string>) cxx_displayNameForCommodity:(const std::string &)co_type	{ return "Display " + co_type; }
- (void) cxx_addMessage:(const std::optional<std::string> &)text forCount:(OOTimeDelta)count
{
	gLog.push_back("message " + text.value_or("-") + " for " + std::to_string(count));
}
@end

Universe *gSharedUniverse = nil;


// The savegame's point strings, as OOStringParsing.mm writes and reads them.
std::string cxx_StringFromPoint(NSPoint point)
{
	char buffer[128];
	std::snprintf(buffer, sizeof buffer, "%f %f", point.x, point.y);
	return buffer;
}

NSPoint cxx_PointFromString(const std::string &xyString)
{
	NSPoint result = NSZeroPoint;
	double x, y;
	if (std::sscanf(xyString.c_str(), "%lf %lf", &x, &y) == 2)  result = NSMakePoint(x, y);
	return result;
}

std::string cxx_OOLookUpDescriptionPRIV(const std::string &key)
{
	return (key == "trumbles-eat-@") ? "trumbles ate the %@" : "desc:" + key;
}

// Link stubs: drawTrumble:. The test never draws; a call is a test bug.
void OOGLPushModelView(void)				{ std::abort(); }
OOMatrix OOGLPopModelView(void)				{ std::abort(); }
void OOGLTranslateModelView(Vector)			{ std::abort(); }
void OOGLMultModelView(OOMatrix)			{ std::abort(); }


static std::string Colour(const GLfloat *c)
{
	char buffer[128];
	std::snprintf(buffer, sizeof buffer, "(%.4g %.4g %.4g %.4g)", c[0], c[1], c[2], c[3]);
	return buffer;
}


// The private state, through the class's test friend (the unconverted test read the same ivars
// through the runtime).
struct OOTrumbleTestAccess
{
	static std::string State(OOTrumble *t)
	{
		const cxx::OOTrumble &c = *oo::ToCxx(t);
		char buffer[1024];
		uint16_t *digram = [t digram];
		std::snprintf(buffer, sizeof buffer,
			"digram %u %u size %.5g/%.5g growth %.5g hunger %.5g discomfort %.5g rot %.5g vel %.5g pos (%.5g %.5g) mov (%.5g %.5g) anim %d next %d time %.5g dur %.5g eyes %d mouth %d eye %.5g mouth %.5g spawn %d",
			digram[0], digram[1], [t size], c.max_size, c.growth_rate, [t hunger], [t discomfort],
			[t rotation], c.rotational_velocity, [t position].x, [t position].y, [t movement].x, [t movement].y,
			(int)c.animation, (int)c.nextAnimation,
			c.animationTime, c.animationDuration,
			(int)c.eyeFrame, (int)c.mouthFrame,
			c.eye_position.y, c.mouth_position.y, (int)c.readyToSpawn);
		return std::string(buffer) + " colours " + Colour(c.colorPoint1) + Colour(c.colorPoint2)
			+ Colour(c.colorEyes) + Colour(c.colorBase);
	}
};


namespace {

PlayerEntity *Player()
{
	static PlayerEntity *player = [[PlayerEntity alloc] init];
	return player;
}


void Reset()
{
	if (gSharedUniverse == nil)
	{
		gSharedUniverse = [[Universe alloc] init];
		gSharedUniverse->market = [[Market alloc] init];
	}
	gSharedUniverse->view = VIEW_FORWARD;
	PlayerEntity *p = Player();
	p->pitch = p->roll = p->heat = 0.0f;
	p->appetite = 0.0f;
	p->cargo.clear();
	p->added.clear();
	p->removed.clear();
	gLog.clear();
	gSoundSourcePlaying = NO;
	ranrot_srand(20260930);
}


// Everything a trumble is, in one line.
std::string State(OOTrumble *t)
{
	return OOTrumbleTestAccess::State(t);
}

// The savegame dictionary, one key=value per entry.
std::string Dictionary(const oo::PList &dict)
{
	std::string result;
	for (const auto &[key, value] : *dict.getIf<oo::PList::Dict>())
	{
		char buffer[64];
		if (value.isString())  result += key + "=" + *value.getIf<std::string>() + " ";
		else
		{
			std::snprintf(buffer, sizeof buffer, "%.6g", value.doubleValue());
			result += key + "=" + buffer + " ";
		}
	}
	return result;
}


OOTrumble *Trumble(const char *digram)
{
	return [[[OOTrumble alloc] initForPlayer:Player() digram:digram] autorelease];
}


void Run(OOTrumble *t, int ticks, double dt = 0.1)
{
	for (int i = 0; i < ticks; i++)  [t updateTrumble:dt];
}


// The expected values of one test, in the order it checks them; a mismatch prints both sides.
class Expected
{
public:
	Expected(std::initializer_list<const char *> values) : values_(values.begin(), values.end()) {}
	~Expected()  { if (next_ != values_.size())  std::fprintf(stderr, "  %zu expected value(s) not checked\n", values_.size() - next_); }

	bool operator()(const std::string &actual)
	{
		const std::string expected = (next_ < values_.size()) ? values_[next_] : "(no more expected values)";
		next_++;
		if (actual == expected)  return true;
		std::fprintf(stderr, "  actual:   %s\n  expected: %s\n", actual.c_str(), expected.c_str());
		return false;
	}

private:
	std::vector<std::string>	values_;
	size_t						next_ = 0;
};


std::string Log()
{
	std::string result;
	for (const std::string &line : gLog)  result += line + "; ";
	return result;
}

}	// namespace


OO_TEST(setUp)
{
	Expected expect{
		"digram 97 49 size 0.71506/1.2016 growth 0.0040491 hunger 0 discomfort 0 rot -7.0848 vel -0.60638 pos (-182 -98) mov (-6.8647 9.7904) anim 1 next 1 time 0 dur 4.0683 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; sound [trumble-idle]; sound [trumble-squeal]; ",
		"digram 90 113 size 0.91782/1.1381 growth 0.0019354 hunger 0 discomfort 0 rot -7.2588 vel -2.2403 pos (14 -126) mov (6.0117 16.861) anim 1 next 1 time 0 dur 2.0538 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; ",
		"digram 64 71 size 0.89981/0.9 growth 2.1023e-06 hunger 0 discomfort 0 rot -11.982 vel -0.29419 pos (-42 14) mov (3.5513 -14.518) anim 1 next 1 time 0 dur 1.6434 eyes 1 mouth 4 eye -0.031936 mouth -0.0037299 spawn 0 colours (0.6 0.5 0.5 1)(1 1 0 1)(0.68 0.6 0.6 1)(0.6 0.5 0.5 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; ",
		"digram 56 0 size 0.74725/1.3444 growth 0.0044419 hunger 0 discomfort 0 rot 5.7328 vel 3.225 pos (-70 126) mov (-17.547 -15.743) anim 1 next 1 time 0 dur 4.0409 eyes 1 mouth 4 eye -0.02327 mouth -0.0080958 spawn 0 colours (1 1 0 1)(0.5 0.6 0.5 1)(0.8 0.84 0.4 1)(0.75 0.8 0.25 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; ",
		"digram 0 0 size 0.78384/0.9 growth 0.0012907 hunger 0 discomfort 0 rot 6.414 vel 3.1342 pos (154 -182) mov (19.823 16.954) anim 1 next 1 time 0 dur 4.3708 eyes 1 mouth 4 eye 0.018987 mouth 0.0042976 spawn 0 colours (0.9 1 0.9 1)(1 1 0 1)(0.92 1 0.92 1)(0.9 1 0.9 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; ",
		"digram 0 0 size 0/0 growth 0 hunger 0 discomfort 0 rot 0 vel 0 pos (0 0) mov (0 0) anim 0 next 0 time 0 dur 0 eyes 0 mouth 0 eye 0 mouth 0 spawn 0 colours (1 1 1 1)(1 1 1 1)(0 0 0 0)(0 0 0 0)",
	};

	@autoreleasepool
	{
		Reset();
		OOTrumble *t = [[[OOTrumble alloc] initForPlayer:Player()] autorelease];
		OO_CHECK(expect(State(t)));
		OO_CHECK(expect(Log()));
		for (const char *digram : { "Zq", "@G", "8", "" })
		{
			Reset();
			OO_CHECK(expect(State([[[OOTrumble alloc] initForPlayer:Player() digram:digram] autorelease])));
			OO_CHECK(expect(Log()));
		}
		OO_CHECK(expect(State([[[OOTrumble alloc] init] autorelease])));
	}
}


OO_TEST(spawningAndActions)
{
	Expected expect{
		"digram 122 81 size 0.5/1.3603 growth 0.0063244 hunger 0.25 discomfort 0 rot -7.2588 vel -0.16373 pos (14 -126) mov (6.0117 24.861) anim 1 next 8 time 0 dur 19.806 eyes 1 mouth 4 eye -0.038568 mouth 0.0081001 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"digram 97 49 size 0.5/1.2016 growth 0.0058388 hunger 0.25 discomfort 0 rot -1.6294 vel -0.69031 pos (-210 -182) mov (-15.155 14.051) anim 1 next 8 time 0 dur 18.947 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1)",
		"next 1 time 0 dur 3.6965 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 2 time 0 dur 0.57935 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 3 time 0 dur 4.1346 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 4 time 0 dur 1.727 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 5 time 0 dur 3.4901 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 6 time 0 dur 4.0042 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 9 time 0 dur 1.7563 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 8 time 0 dur 19.656 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / next 7 time 0 dur 10.359 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1) / digram 97 49 size 0.71506/1.2016 growth 0.0040491 hunger 0 discomfort 0 rot -7.0848 vel 3.868 pos (-182 -98) mov (4.2165 4.8422) anim 1 next 7 time 0 dur 10.359 eyes 1 mouth 4 eye -0.012613 mouth 0.0072381 spawn 0 colours (1 0 0 1)(1 0 0 1)(1 0.2 0.2 1)(1 0 0 1)",
	};

	@autoreleasepool
	{
		Reset();
		OOTrumble *parent = Trumble("Zq");
		OOTrumble *child = Trumble("a1");
		[child spawnFrom:parent];
		OO_CHECK(expect(State(child)));
		OOTrumble *orphan = Trumble("a1");
		[orphan spawnFrom:nil];
		OO_CHECK(expect(State(orphan)));

		Reset();
		OOTrumble *t = Trumble("a1");
		std::string actions;
		[t actionIdle];		actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionBlink];	actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionSnarl];	actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionProot];	actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionShudder];	actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionStoned];	actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionPop];		actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionSleep];	actions += State(t).substr(State(t).find("next")) + " / ";
		[t actionSpawn];	actions += State(t).substr(State(t).find("next")) + " / ";
		[t randomizeMotionX];	[t randomizeMotionY];	[t calcGrowthRate];
		actions += State(t);
		OO_CHECK(expect(actions));
	}
}


OO_TEST(living)
{
	Expected expect{
		"digram 90 113 size 0.9273/1.1381 growth 0.0018522 hunger 0.059472 discomfort 0.01014 rot -6.7916 vel 4.5333 pos (44.058 -91.697) mov (6.0117 16.861) anim 1 next 1 time 2.9 dur 3.3873 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"digram 90 113 size 0.98979/1.1381 growth 0.0013031 hunger 0.52196 discomfort 0.21945 rot -5.1535 vel -1.7835 pos (284.29 77.07) mov (6.0117 -16.158) anim 1 next 1 time 3.2 dur 3.5719 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; play [trumble-idle]; ",
		"digram 90 113 size 0.9273/1.1381 growth 0.0018522 hunger 0.059472 discomfort 0.01014 rot -12.21 vel -2.2403 pos (44.058 8.3033) mov (6.0117 16.861) anim 1 next 1 time 2.9 dur 3.3873 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"digram 90 113 size 0.98979/1.1381 growth 0.0013031 hunger 0.52196 discomfort 0.21945 rot -6.2917 vel -1.7835 pos (-266.55 225.77) mov (-18.801 -16.158) anim 1 next 1 time 0.6 dur 1.9207 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; play [trumble-idle]; ",
		"digram 90 113 size 0.9273/1.1381 growth 0.0018522 hunger 0.059472 discomfort 0.01014 rot -5.9602 vel -2.2403 pos (44.058 -66.697) mov (6.0117 16.861) anim 1 next 1 time 2.9 dur 3.3873 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"digram 90 113 size 0.98979/1.1381 growth 0.0013031 hunger 0.52196 discomfort 0.21945 rot -3.867 vel -3.7748 pos (284.52 -244.88) mov (6.0117 -18.801) anim 1 next 1 time 0.7 dur 2.8609 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; ",
		"digram 90 113 size 0.9273/1.1381 growth 0.0018522 hunger 0.059472 discomfort 0.01014 rot -11.914 vel 3.6022 pos (44.058 -92.476) mov (6.0117 -9.2702) anim 2 next 2 time 0.1 dur 0.5701 eyes 2 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"digram 90 113 size 0.98979/1.1381 growth 0.0013031 hunger 0.52196 discomfort 0.21945 rot -9.9373 vel -2.247 pos (152.17 311.65) mov (-3.7924 -5.4146) anim 1 next 1 time 1.1 dur 2.9626 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; ",
	};

	@autoreleasepool
	{
		for (OOViewID view : { VIEW_FORWARD, VIEW_AFT, VIEW_STARBOARD, VIEW_PORT })
		{
			Reset();
			gSharedUniverse->view = view;
			PlayerEntity *p = Player();
			p->pitch = 0.5f;	p->roll = -0.25f;	p->heat = 0.5f;
			OOTrumble *t = Trumble("Zq");
			Run(t, 50);
			OO_CHECK(expect(State(t)));
			Run(t, 400);
			OO_CHECK(expect(State(t)));
			OO_CHECK(expect(Log()));
		}
	}
}


OO_TEST(savegame)
{
	Expected expect{
		"digram=Zq discomfort=0.00108162 growth_rate=0.00188507 hunger=0.0357329 movement=6.011658 16.860657 position=32.034973 -75.418030 rotation=-13.9796 rotational_velocity=-2.2403 size=0.923557 ",
		"digram 90 113 size 0.92356/1.1381 growth 0.0018851 hunger 0.035733 discomfort 0.0010816 rot -13.98 vel -2.2403 pos (32.035 -75.418) mov (6.0117 16.861) anim 1 next 1 time 0 dur 2.0538 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"digram=Zq discomfort=0.00108162 growth_rate=0.00188507 hunger=0.0357329 movement=6.011658 16.860657 position=32.034973 -75.418030 rotation=-13.9796 rotational_velocity=-2.2403 size=0.923557 ",
	};

	@autoreleasepool
	{
		Reset();
		OOTrumble *t = Trumble("Zq");
		Run(t, 30);
		oo::PList dict = [t dictionary];
		OO_CHECK(expect(Dictionary(dict)));
		OOTrumble *copy = Trumble("a1");
		[copy setFromDictionary:dict];
		OO_CHECK(expect(State(copy)));
		OO_CHECK(expect(Dictionary([copy dictionary])));
	}
}


OO_TEST(feedingPopAndSpawn)
{
	Expected expect{
		"digram 90 113 size 1.1002/1.1381 growth 0 hunger 0 discomfort 0 rot -7.4828 vel -2.2403 pos (14.601 -124.31) mov (6.0117 16.861) anim 1 next 1 time 0.1 dur 2.0538 eyes 1 mouth 4 eye -0.045637 mouth -0.0014003 spawn 1 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; message trumbles ate the Display food for 4.500000; ",
		"digram 90 113 size 1.1039/1.1381 growth 0.00030021 hunger 0.12273 discomfort 0.013521 rot -0.0010076 vel 0.3978 pos (31.366 -73.732) mov (14.262 0.0004976) anim 4 next 4 time 0 dur 1.9864 eyes 1 mouth 4 eye 0 mouth 0 spawn 0 colours (0 1 0 1)(1 0 0 1)(0.6 0.6 0.2 1)(0.5 0.5 0 1)",
		"digram 64 71 size 0.27375/0.9 growth 0.0069504 hunger 0.050959 discomfort 1 rot -1198.5 vel -1352.1 pos (-27.795 -253.47) mov (3.5513 -222.4) anim 9 next 9 time 2.3 dur 2.2589 eyes 2 mouth 2 eye -0.031936 mouth -0.0037299 spawn 0 colours (0.6 0.04431 0.04431 0.02607)(1 0.08863 0 0.02607)(0.68 0.6 0.6 1)(0.6 0.5 0.5 0.02607)",
		"texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; texture trumblekit.png in Textures options 20 anisotropy 0.000000 lodBias -0.250000; play [trumble-squeal]; ",
	};

	@autoreleasepool
	{
		// Hungry, full grown and content: eats the tastiest pod; past 10 the cargo is gone, and it
		// is ready to spawn.
		Reset();
		PlayerEntity *p = Player();
		for (const char *good : { "gems", "furs", "food" })
		{
			ShipEntity *pod = [[[ShipEntity alloc] init] autorelease];
			pod->commodity = good;
			p->cargo.push_back(oo::ObjCRef<ShipEntity *>(pod));
		}
		ShipEntity *food = p->cargo[2].get();
		p->appetite = 9.5f;
		OOTrumble *t = Trumble("Zq");
		oo::PList::Dict state = *[t dictionary].getIf<oo::PList::Dict>();
		state["hunger"] = oo::PList(0.9);
		state["size"] = oo::PList(1.1);
		state["discomfort"] = oo::PList(0.1);
		[t setFromDictionary:oo::PList(state)];
		Run(t, 1);
		OO_CHECK(expect(State(t)));
		OO_CHECK(expect(Log()));
		OO_CHECK(p->cargo.size() == 2 && p->cargo[0].get() != food && p->cargo[1].get() != food);
		OO_CHECK(std::fabs(p->appetite - 0.401194f) < 1e-5f);
		int ticks = 0;
		while (p->added.empty() && ticks < 5000)  { Run(t, 1); ticks++; }
		OO_CHECK(ticks == 119);
		OO_CHECK(p->added.size() == 1 && p->added[0] == t);
		OO_CHECK(expect(State(t)));

		// Too uncomfortable: pops, and asks to be removed.
		Reset();
		t = Trumble("@G");
		state = *[t dictionary].getIf<oo::PList::Dict>();
		state["discomfort"] = oo::PList(1.0);
		[t setFromDictionary:oo::PList(state)];
		ticks = 0;
		while (p->removed.empty() && ticks < 5000)  { Run(t, 1); ticks++; }
		OO_CHECK(ticks == 40);
		OO_CHECK(p->removed.size() == 1 && p->removed[0] == t);
		OO_CHECK(expect(State(t)));
		OO_CHECK(expect(Log()));
	}
}


OO_TEST(cxxClass)
{
	// The same trumble as the Objective-C API's, and its growth.
	Reset();
	oo::Ref<cxx::OOTrumble> t = oo::makeRef<cxx::OOTrumble>(Player(), "Zq");
	OO_CHECK(t->getDigram()[0] == 'Z' && t->getDigram()[1] == 'q');
	OO_CHECK(std::fabs(t->getSize() - 0.91782f) < 1e-5f && t->getHunger() == 0.0f && t->getDiscomfort() == 0.0f);
	OO_CHECK(t->getPosition().x == 14 && t->getPosition().y == -126);
	OO_CHECK(std::fabs(t->getRotation() - -7.2588f) < 1e-4f);
	OO_CHECK(std::fabs(t->getMovement().y - 16.861f) < 1e-3f);
	Reset();
	OOTrumble *same = Trumble("Zq");
	OO_CHECK(State(same) == State(oo::ToObjC(t)));

	oo::Ref<cxx::OOTrumble> child = oo::makeRef<cxx::OOTrumble>(Player());
	child->spawnFrom(t.get());
	OO_CHECK(child->getSize() == 0.5f && child->getHunger() == 0.25f);
	child->spawnFrom(nullptr);
	OO_CHECK(child->getSize() == 0.5f);

	oo::Ref<cxx::OOTrumble> blank = oo::makeRef<cxx::OOTrumble>();
	OO_CHECK(blank->getSize() == 0.0f && blank->getDigram()[0] == 0);
	OO_CHECK(blank->dictionary().count() == 9);
}


OO_TEST(facadeNilStaysNil)
{
	OOTrumble *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOTrumble *>(nullptr)) == nil);
	OO_CHECK([none size] == 0.0f);
	OO_CHECK([none dictionary].isNull());
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		Reset();
		OOTrumble *t = Trumble("a1");
		OO_CHECK(oo::ToObjC(oo::ToCxx(t)) == t);
		OOTrumble *plain = [[[OOTrumble alloc] init] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(plain)) == plain);
		OOTrumble *defaultDigram = [[[OOTrumble alloc] initForPlayer:Player()] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(defaultDigram)) == defaultDigram);

		// A C++ trumble crosses to one facade, and back to itself.
		oo::Ref<cxx::OOTrumble> cxxTrumble = oo::makeRef<cxx::OOTrumble>(Player(), "Zq");
		OOTrumble *facade = oo::ToObjC(cxxTrumble);
		OO_CHECK(facade != nil && facade == oo::ToObjC(cxxTrumble.get()));
		OO_CHECK(oo::ToCxx(facade) == cxxTrumble.get());

		// What the trumble hands the player is the player's own object (see feedingPopAndSpawn).
		OO_CHECK(Trumble("a1") != Trumble("a1"));
	}
}


OO_TEST_MAIN()
