/*	test_OOProbabilisticTextureManager.mm
	Unit tests for OOProbabilisticTextureManager (src/Core/OOProbabilisticTextureManager.h), C++: bead
	oo-9hdp (Phase 3, house style of proposed ADR-0056).

	The manager reads a list of textures from a Config plist (a name, or a dictionary with a
	texture name, a probability and a galaxy), loads each with the options it was given, and then
	picks one at random, weighted, from those allowed in the player's galaxy, with its own seed.
	The test pins which entries it keeps (no name, probability 0, a texture that does not load and
	an entry of another type are dropped; a galaxy that is not a string makes the entry
	galaxy-wide), what it asks the resource manager and the texture class, its description, the
	seed (copied from the global one unless given, advanced by each pick), the sequence of picks
	for two seeds in two galaxies (including the "galaxy list requirements not met" and "last
	texture" fallbacks), that it fails (null) when nothing loads, and that it retains its textures
	until it goes.
	The game around it is replaced (ADR-0056 amendments oo-z1s4 item 4, oo-8kx7 item 7): the
	resource manager answers the configuration below, OOTexture is a stand-in that records how it
	was asked and counts -ensureFinishedLoading, and the player answers a galaxy. The expectations
	were written against the Objective-C API and run on the unconverted class first, then ported to
	the C++ calls (amendment oo-3lj8 item 5: the class has no facade). Only the description's
	"<OOProbabilisticTextureManager 0x...>" wrapper, which OOObject's -description added, went with
	that API: the components are checked as they were.
	Run: bash tools/check-core-tests.sh
*/

#import "OOProbabilisticTextureManager.h"
#import "OODescription.h"
#import "OOTypes.h"

#include "oo_test.hpp"

#include <cstdio>
#include <string>
#include <vector>


// --- The game around the class ------------------------------------------------------------------

static oo::PList gConfig;
static std::vector<std::string> gLog;


@interface ResourceManager: OOObject
+ (oo::PList) cxx_arrayFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName andMerge:(BOOL)mergeFiles;
@end

@implementation ResourceManager
+ (oo::PList) cxx_arrayFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName andMerge:(BOOL)mergeFiles
{
	gLog.push_back("config " + fileName + " in " + folderName.value_or("(nil)") + (mergeFiles ? " merged" : " unmerged"));
	return gConfig;
}
@end


// Every texture loads, but for "missing.png".
@interface OOTexture: OOObject
{
@public
	std::string		_name;
	unsigned		_loaded;
}
+ (id) cxx_textureWithName:(const std::optional<std::string> &)name inFolder:(const std::optional<std::string> &)directory options:(uint32_t)options anisotropy:(GLfloat)anisotropy lodBias:(GLfloat)lodBias;
- (void) ensureFinishedLoading;
@end

@implementation OOTexture
+ (id) cxx_textureWithName:(const std::optional<std::string> &)name inFolder:(const std::optional<std::string> &)directory options:(uint32_t)options anisotropy:(GLfloat)anisotropy lodBias:(GLfloat)lodBias
{
	char args[128];
	std::snprintf(args, sizeof args, " options=%#x anisotropy=%g lodBias=%g", options, anisotropy, lodBias);
	gLog.push_back("texture " + name.value_or("(nil)") + " in " + directory.value_or("(nil)") + args);
	if (name == "missing.png")  return nil;
	OOTexture *texture = [[[OOTexture alloc] init] autorelease];
	texture->_name = *name;
	return texture;
}
- (void) ensureFinishedLoading  { _loaded++; }
@end


static OOGalaxyID gGalaxy = 0;

@interface PlayerEntity: OOObject
- (OOGalaxyID) currentGalaxyID;
@end

@implementation PlayerEntity
- (OOGalaxyID) currentGalaxyID  { return gGalaxy; }
@end

PlayerEntity *gOOPlayer = nil;


// --- Helpers ------------------------------------------------------------------------------------

namespace {

oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


// a and h everywhere, b three times as likely, g (four) only in galaxy 2; the rest are dropped.
oo::PList Config()
{
	return oo::PList(oo::PList::Array{
		oo::PList("a.png"),
		Dict({ { "texture", oo::PList("b.png") }, { "probability", oo::PList(3) } }),
		Dict({ { "texture", oo::PList("c.png") }, { "probability", oo::PList(0) } }),
		Dict({ { "texture", oo::PList("missing.png") } }),
		Dict({ { "probability", oo::PList(2) } }),
		oo::PList(42),
		Dict({ { "texture", oo::PList("g.png") }, { "probability", oo::PList(4) }, { "galaxy", oo::PList("2") } }),
		Dict({ { "texture", oo::PList("h.png") }, { "galaxy", oo::PList(3) } }),
	});
}


void Reset(const oo::PList &config)
{
	if (gOOPlayer == nil)  gOOPlayer = [[PlayerEntity alloc] init];
	gConfig = config;
	gLog.clear();
	gGalaxy = 0;
}


std::string Picks(const oo::Ref<OOProbabilisticTextureManager> &manager, int count)
{
	std::string picks;
	for (int i = 0; i < count; i++)
	{
		OOTexture *texture = manager->selectTexture();
		picks += (texture != nil ? texture->_name.substr(0, 1) : std::string("-"));
	}
	return picks;
}


bool SameSeed(RANROTSeed a, RANROTSeed b)
{
	return a.high == b.high && a.low == b.low;
}


oo::Ref<OOProbabilisticTextureManager> Manager(RANROTSeed seed)
{
	return OOProbabilisticTextureManager::createWithPListName("test.plist", 0x803, 0.5f, -0.25f, seed);
}


bool CheckPicks(const char *what, const std::string &picks, const char *expected)
{
	if (picks == expected)  return true;
	std::fprintf(stderr, "%s: picked %s, expected %s\n", what, picks.c_str(), expected);
	return false;
}

}	// namespace


// --- Tests --------------------------------------------------------------------------------------

OO_TEST(entriesKeptAndHowTheyAreLoaded)
{
	@autoreleasepool
	{
		Reset(Config());
		oo::Ref<OOProbabilisticTextureManager> manager = Manager(MakeRanrotSeed(1));
		OO_CHECK(manager != nullptr);
		OO_CHECK(manager->textureCount() == 4);
		const std::vector<std::string> expected =
		{
			"config test.plist in Config merged",
			"texture a.png in Textures options=0x803 anisotropy=0.5 lodBias=-0.25",
			"texture b.png in Textures options=0x803 anisotropy=0.5 lodBias=-0.25",
			"texture missing.png in Textures options=0x803 anisotropy=0.5 lodBias=-0.25",
			"texture g.png in Textures options=0x803 anisotropy=0.5 lodBias=-0.25",
			"texture h.png in Textures options=0x803 anisotropy=0.5 lodBias=-0.25",
		};
		OO_CHECK(gLog == expected);
		if (gLog != expected)  for (const std::string &line : gLog)  std::fprintf(stderr, "  %s\n", line.c_str());

		// The cumulative probability of the galaxy-wide entries: a 1, b 3, h 1.
		OO_CHECK(manager->descriptionComponents() == std::optional<std::string>("4 textures, cumulative probability=5"));
	}
}


OO_TEST(nothingLoadedIsNil)
{
	@autoreleasepool
	{
		Reset(oo::PList(oo::PList::Array{}));
		OO_CHECK(Manager(MakeRanrotSeed(1)) == nullptr);
		Reset(oo::PList(oo::PList::Array{ oo::PList("missing.png"), Dict({ { "texture", oo::PList("x.png") }, { "probability", oo::PList(-1) } }) }));
		OO_CHECK(Manager(MakeRanrotSeed(1)) == nullptr);
		Reset(oo::PList());		// no such plist
		OO_CHECK(Manager(MakeRanrotSeed(1)) == nullptr);
		OO_CHECK(gLog.size() == 1);	// asked for the config, and nothing else
	}
}


OO_TEST(seed)
{
	@autoreleasepool
	{
		Reset(Config());
		RANROTSeed global = MakeRanrotSeed(77);
		RANROTSetFullSeed(global);
		oo::Ref<OOProbabilisticTextureManager> manager = OOProbabilisticTextureManager::createWithPListName("test.plist", 0, 0, 0);
		OO_CHECK(SameSeed(manager->seed(), global));		// copied from the global seed
		OO_CHECK(SameSeed(RANROTGetFullSeed(), global));	// and that is left alone

		manager->setSeed(MakeRanrotSeed(5));
		OO_CHECK(SameSeed(manager->seed(), MakeRanrotSeed(5)));
		manager->selectTexture();
		OO_CHECK(!SameSeed(manager->seed(), MakeRanrotSeed(5)));	// a pick advances it
		OO_CHECK(SameSeed(RANROTGetFullSeed(), global));

		// Two managers with one seed pick alike.
		OO_CHECK(Picks(Manager(MakeRanrotSeed(9)), 30) == Picks(Manager(MakeRanrotSeed(9)), 30));
	}
}


OO_TEST(picks)
{
	@autoreleasepool
	{
		Reset(Config());
		OO_CHECK(CheckPicks("galaxy 0, seed A", Picks(Manager(MakeRanrotSeed(0x1234567)), 40), "bhabhbabbhbhbbhahbahbbbaabbhbbbbbbabbabb"));
		OO_CHECK(CheckPicks("galaxy 0, seed B", Picks(Manager(MakeRanrotSeed(0x7654321)), 40), "bhbabahhabbabbhbbhbhbahbbaabababaaabhbbb"));
		// In galaxy 2, h (added after g, cumulative 5) is never picked: g (cumulative 8) comes first
		// in the list and takes every pick in (4, 8], and the picks only reach 9.
		gGalaxy = 2;
		OO_CHECK(CheckPicks("galaxy 2, seed A", Picks(Manager(MakeRanrotSeed(0x1234567)), 40), "ggabgbbbggbggggaggaggggbagggbbggggagbbgg"));
		OO_CHECK(CheckPicks("galaxy 2, seed B", Picks(Manager(MakeRanrotSeed(0x7654321)), 40), "ggbabbggabbagbggggggbbgbgabbagbbabbggbbg"));

		// g only in galaxy 0, before a galaxy-wide a: both have cumulative 1 of 2, so a pick past g's
		// share is not a's either, and falls back to the galaxy's first texture (g). a is never picked.
		Reset(oo::PList(oo::PList::Array{
			Dict({ { "texture", oo::PList("g.png") }, { "galaxy", oo::PList("0") } }),
			oo::PList("a.png"),
		}));
		OO_CHECK(CheckPicks("fallback to the galaxy's first", Picks(Manager(MakeRanrotSeed(0xBADC0DE)), 40), "gggggggggggggggggggggggggggggggggggggggg"));

		// Nothing for galaxy 1: the last texture, every time.
		Reset(oo::PList(oo::PList::Array{
			Dict({ { "texture", oo::PList("g.png") }, { "galaxy", oo::PList("0") } }),
			Dict({ { "texture", oo::PList("k.png") }, { "galaxy", oo::PList("2") } }),
		}));
		gGalaxy = 1;
		OO_CHECK(CheckPicks("nothing for the galaxy", Picks(Manager(MakeRanrotSeed(3)), 10), "kkkkkkkkkk"));
	}
}


OO_TEST(texturesAreLoadedAndKept)
{
	std::vector<OOTexture *> textures;
	oo::Ref<OOProbabilisticTextureManager> manager;
	@autoreleasepool
	{
		Reset(Config());
		manager = Manager(MakeRanrotSeed(0x1234567));
		for (OOGalaxyID galaxy : { 0, 2 })	// a, b and h in galaxy 0; g only in galaxy 2
		{
			gGalaxy = galaxy;
			for (int i = 0; i < 200; i++)
			{
				OOTexture *texture = manager->selectTexture();
				bool seen = false;
				for (OOTexture *t : textures)  seen = seen || t == texture;
				if (!seen)  textures.push_back([texture retain]);
			}
		}
	}
	OO_CHECK(textures.size() == 4);
	manager->ensureTexturesLoaded();
	manager->ensureTexturesLoaded();
	for (OOTexture *texture : textures)
	{
		OO_CHECK(texture->_loaded == 2);
		OO_CHECK([texture retainCount] == 2);	// the test's and the manager's
	}
	manager = nullptr;
	for (OOTexture *texture : textures)
	{
		OO_CHECK([texture retainCount] == 1);
		[texture release];
	}
}


OO_TEST_MAIN()
