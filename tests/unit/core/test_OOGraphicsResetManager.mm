/*	test_OOGraphicsResetManager.mm
	Unit tests for OOGraphicsResetManager (src/Core/OOGraphicsResetManager.h): bead oo-jpd8, a
	Phase 3 class conversion (proposed ADR-0056).

	The expectations were written against the Objective-C API and run on the unconverted class
	first: one shared manager; a reset re-reads the extension manager (its ResourceManager stub
	counts the re-read), rebinds the textures (this file's OOTexture stub counts it), then tells
	every registered client once; nil is never registered, a client can be registered twice but
	is told once, unregistered clients are not told, a client unregistered by an earlier client
	during the reset is skipped, and a client that raises is logged and does not stop the rest.
	Clients are not retained. The GL context is a hidden window's (oo_gl_test_context.hpp). Bead
	oo-9ht.23 deleted the manager's facade and the OOGraphicsResetClient protocol: the test's
	Objective-C client is a C++ client with the same answers, and the facade's contract case went
	with the facade (standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOGraphicsResetManager.h"
#import "OORegExpMatcher.h"
#import "OOOpenGLExtensionManager.h"
#include "oofnd/objc/OOException.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"
#include "oofnd/PList.hpp"

#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

static unsigned sPathsCalls = 0;
static unsigned sRebinds = 0;
static std::vector<int> sOrder;	// client tags, in the order they were told, texture rebinds as 0


@interface ResourceManager: OOObject
+ (std::vector<std::string>) cxx_paths;
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles;
@end

@implementation ResourceManager
+ (std::vector<std::string>) cxx_paths  { sPathsCalls++; return {}; }
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles  { return oo::PList(oo::PList::Dict{}); }
@end


// OORegExpMatcher is C++ since its facade was deleted (bead oo-9ht.12): the stub answers no match.
oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher()  { return oo::makeRef<OORegExpMatcher>(); }
bool OORegExpMatcher::string(const std::string &, const std::string &)  { return false; }
OORegExpMatcher::~OORegExpMatcher()  {}


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


// OOLogging.mm's (it would bring the resource manager into the link).
extern const char *const cxx_kOOLogException;
const char *const cxx_kOOLogException = "exception";


@interface OOTexture: OOObject
+ (void) rebindAllTextures;
@end

@implementation OOTexture
+ (void) rebindAllTextures
{
	sRebinds++;
	sOrder.push_back(0);
}
@end


// A client: counts its resets; may unregister another client, or raise, when told. Reference
// counted, so the test can see the manager does not retain it (an Objective-C client until bead
// oo-9ht.23).
struct OOTestResetClient : oo::RefCounted, OOGraphicsResetClient
{
	int					tag = 0;
	unsigned			resets = 0;
	OOTestResetClient	*victim = nullptr;
	bool				raises = false;

	void resetGraphicsState() override
	{
		resets++;
		sOrder.push_back(tag);
		if (victim != nullptr)  OOGraphicsResetManager::sharedManager()->unregisterCxxClient(victim);
		if (raises)  [OOException raise:"OOTestException" format:"client %d raised", tag];
	}
};


namespace {

// Kept until the test's process ends, as the autoreleased clients outlived each case's use.
std::vector<oo::Ref<OOTestResetClient>> sClients;

OOTestResetClient *Client(int tag)
{
	sClients.push_back(oo::makeRef<OOTestResetClient>());
	sClients.back()->tag = tag;
	return sClients.back().get();
}

}	// namespace


// --- Tests --------------------------------------------------------------------------------------

OO_TEST(resetTellsEachClientOnce)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OOGraphicsResetManager *manager = OOGraphicsResetManager::sharedManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(OOGraphicsResetManager::sharedManager() == manager);

		(void)cxx::OOOpenGLExtensionManager::sharedManager();
		const unsigned pathsBefore = sPathsCalls;

		OOTestResetClient *a = Client(1), *b = Client(2), *c = Client(3);
		manager->registerCxxClient(a);
		manager->registerCxxClient(b);
		manager->registerCxxClient(b);	// a set: told once
		manager->registerCxxClient(c);
		manager->registerCxxClient(nullptr);
		manager->unregisterCxxClient(c);
		manager->unregisterCxxClient(c);	// not registered: nothing
		manager->unregisterCxxClient(nullptr);

		sOrder.clear();
		manager->resetGraphicsState();
		OO_CHECK(sPathsCalls == pathsBefore + 1);	// the extension manager was reset
		OO_CHECK(sRebinds == 1);
		OO_CHECK(a->resets == 1 && b->resets == 1 && c->resets == 0);
		OO_CHECK(sOrder.size() == 3 && sOrder[0] == 0);	// textures first, then the clients

		manager->unregisterCxxClient(a);
		manager->unregisterCxxClient(b);
		manager->resetGraphicsState();
		OO_CHECK(sRebinds == 2);
		OO_CHECK(a->resets == 1 && b->resets == 1);
	}
}


OO_TEST(clientsMayUnregisterAndRaise)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OOGraphicsResetManager *manager = OOGraphicsResetManager::sharedManager();

		// Two clients that each unregister the other: whichever is told first is the only one told.
		OOTestResetClient *x = Client(10), *y = Client(11);
		x->victim = y;
		y->victim = x;
		manager->registerCxxClient(x);
		manager->registerCxxClient(y);
		manager->resetGraphicsState();
		OO_CHECK(x->resets + y->resets == 1);
		manager->unregisterCxxClient(x);
		manager->unregisterCxxClient(y);

		// A client that raises is logged and ignored; the others are still told.
		OOTestResetClient *thrower = Client(20), *p = Client(21), *q = Client(22);
		thrower->raises = true;
		manager->registerCxxClient(p);
		manager->registerCxxClient(thrower);
		manager->registerCxxClient(q);
		manager->resetGraphicsState();
		OO_CHECK(thrower->resets == 1 && p->resets == 1 && q->resets == 1);
		manager->unregisterCxxClient(thrower);
		manager->unregisterCxxClient(p);
		manager->unregisterCxxClient(q);
	}
}


OO_TEST(clientsAreNotRetained)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OOGraphicsResetManager *manager = OOGraphicsResetManager::sharedManager();
		oo::Ref<OOTestResetClient> client = oo::makeRef<OOTestResetClient>();
		const std::uint32_t before = client->retainCount();
		manager->registerCxxClient(client.get());
		OO_CHECK(client->retainCount() == before);
		manager->unregisterCxxClient(client.get());
	}
}


// A converted client (bead oo-4jjl, amendment oo-jpd8 item 3): told once per reset, after the
// textures, like the other client; null is never registered; unregistered, it is not told.
namespace {

struct TestCxxClient : OOGraphicsResetClient
{
	unsigned resets = 0;
	void resetGraphicsState() override  { resets++; sOrder.push_back(100); }
};

}	// namespace


OO_TEST(cxxClients)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OOGraphicsResetManager *manager = OOGraphicsResetManager::sharedManager();
		TestCxxClient c1, c2;
		OOTestResetClient *objc = Client(40);
		manager->registerCxxClient(&c1);
		manager->registerCxxClient(&c1);	// a set: told once
		manager->registerCxxClient(&c2);
		manager->registerCxxClient(nullptr);
		manager->registerCxxClient(objc);
		manager->unregisterCxxClient(&c2);
		manager->unregisterCxxClient(nullptr);

		sOrder.clear();
		const unsigned rebinds = sRebinds;
		manager->resetGraphicsState();
		OO_CHECK(sRebinds == rebinds + 1);
		OO_CHECK(c1.resets == 1 && c2.resets == 0 && objc->resets == 1);
		OO_CHECK(sOrder.size() == 3 && sOrder[0] == 0);	// textures first

		manager->unregisterCxxClient(&c1);
		manager->unregisterCxxClient(objc);
		manager->resetGraphicsState();
		OO_CHECK(c1.resets == 1 && objc->resets == 1);
	}
}


OO_TEST_MAIN()
