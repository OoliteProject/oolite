/*	test_OOGraphicsResetManager.mm
	Unit tests for OOGraphicsResetManager (src/Core/OOGraphicsResetManager.h): bead oo-jpd8, a
	Phase 3 class conversion (proposed ADR-0056).

	The expectations were written against the Objective-C API and run on the unconverted class
	first: one shared manager; a reset re-reads the extension manager (its ResourceManager stub
	counts the re-read), rebinds the textures (this file's OOTexture stub counts it), then tells
	every registered client once; nil is never registered, a client can be registered twice but
	is told once, unregistered clients are not told, a client unregistered by an earlier client
	during the reset is skipped, and a client that raises is logged and does not stop the rest.
	Clients are not retained. The GL context is a hidden window's (oo_gl_test_context.hpp). The
	clients still reach the manager through its facade; the last test pins the facade's contract.
	Run: bash tools/check-core-tests.sh
*/

#import "OOGraphicsResetManager.h"
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


@interface OORegExpMatcher: OOObject
+ (instancetype) regExpMatcher;
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp;
@end

@implementation OORegExpMatcher
+ (instancetype) regExpMatcher  { return [[[self alloc] init] autorelease]; }
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp  { return NO; }
@end


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


// A client: counts its resets; may unregister another client, or raise, when told.
@interface OOTestResetClient: OOObject <OOGraphicsResetClient>
{
@public
	int					tag;
	unsigned			resets;
	OOTestResetClient	*victim;
	BOOL				raises;
}
@end

@implementation OOTestResetClient

- (void) resetGraphicsState
{
	resets++;
	sOrder.push_back(tag);
	if (victim != nil)  [[OOGraphicsResetManager sharedManager] unregisterClient:victim];
	if (raises)  [OOException raise:"OOTestException" format:"client %d raised", tag];
}

@end


namespace {

OOTestResetClient *Client(int tag)
{
	OOTestResetClient *client = [[[OOTestResetClient alloc] init] autorelease];
	client->tag = tag;
	return client;
}

}	// namespace


// --- Tests --------------------------------------------------------------------------------------

OO_TEST(resetTellsEachClientOnce)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		cxx::OOGraphicsResetManager *manager = cxx::OOGraphicsResetManager::sharedManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(cxx::OOGraphicsResetManager::sharedManager() == manager);

		(void)cxx::OOOpenGLExtensionManager::sharedManager();
		const unsigned pathsBefore = sPathsCalls;

		OOTestResetClient *a = Client(1), *b = Client(2), *c = Client(3);
		manager->registerClient(a);
		manager->registerClient(b);
		manager->registerClient(b);	// a set: told once
		manager->registerClient(c);
		manager->registerClient(nil);
		manager->unregisterClient(c);
		manager->unregisterClient(c);	// not registered: nothing
		manager->unregisterClient(nil);

		sOrder.clear();
		manager->resetGraphicsState();
		OO_CHECK(sPathsCalls == pathsBefore + 1);	// the extension manager was reset
		OO_CHECK(sRebinds == 1);
		OO_CHECK(a->resets == 1 && b->resets == 1 && c->resets == 0);
		OO_CHECK(sOrder.size() == 3 && sOrder[0] == 0);	// textures first, then the clients

		manager->unregisterClient(a);
		manager->unregisterClient(b);
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
		cxx::OOGraphicsResetManager *manager = cxx::OOGraphicsResetManager::sharedManager();

		// Two clients that each unregister the other: whichever is told first is the only one told.
		OOTestResetClient *x = Client(10), *y = Client(11);
		x->victim = y;
		y->victim = x;
		manager->registerClient(x);
		manager->registerClient(y);
		manager->resetGraphicsState();
		OO_CHECK(x->resets + y->resets == 1);
		manager->unregisterClient(x);
		manager->unregisterClient(y);

		// A client that raises is logged and ignored; the others are still told.
		OOTestResetClient *thrower = Client(20), *p = Client(21), *q = Client(22);
		thrower->raises = YES;
		manager->registerClient(p);
		manager->registerClient(thrower);
		manager->registerClient(q);
		manager->resetGraphicsState();
		OO_CHECK(thrower->resets == 1 && p->resets == 1 && q->resets == 1);
		manager->unregisterClient(thrower);
		manager->unregisterClient(p);
		manager->unregisterClient(q);
	}
}


OO_TEST(clientsAreNotRetained)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		cxx::OOGraphicsResetManager *manager = cxx::OOGraphicsResetManager::sharedManager();
		OOTestResetClient *client = [[OOTestResetClient alloc] init];
		const NSUInteger before = [client retainCount];
		manager->registerClient(client);
		OO_CHECK([client retainCount] == before);
		manager->unregisterClient(client);
		[client release];
	}
}


// A converted client (bead oo-4jjl, amendment oo-jpd8 item 3): told once per reset, after the
// textures, like an Objective-C one; null is never registered; unregistered, it is not told.
namespace {

struct TestCxxClient : cxx::OOGraphicsResetClient
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
		cxx::OOGraphicsResetManager *manager = cxx::OOGraphicsResetManager::sharedManager();
		TestCxxClient c1, c2;
		OOTestResetClient *objc = Client(40);
		manager->registerCxxClient(&c1);
		manager->registerCxxClient(&c1);	// a set: told once
		manager->registerCxxClient(&c2);
		manager->registerCxxClient(nullptr);
		manager->registerClient(objc);
		manager->unregisterCxxClient(&c2);
		manager->unregisterCxxClient(nullptr);

		sOrder.clear();
		const unsigned rebinds = sRebinds;
		manager->resetGraphicsState();
		OO_CHECK(sRebinds == rebinds + 1);
		OO_CHECK(c1.resets == 1 && c2.resets == 0 && objc->resets == 1);
		OO_CHECK(sOrder.size() == 3 && sOrder[0] == 0);	// textures first

		manager->unregisterCxxClient(&c1);
		manager->unregisterClient(objc);
		manager->resetGraphicsState();
		OO_CHECK(c1.resets == 1 && objc->resets == 1);
	}
}


// After the conversion: one facade for the process, forwarding to the C++ manager.
OO_TEST(facadeContract)
{
	OO_CHECK(OOTestGLContext());
	cxx::OOGraphicsResetManager *manager = cxx::OOGraphicsResetManager::sharedManager();
	@autoreleasepool
	{
		OOGraphicsResetManager *facade = [OOGraphicsResetManager sharedManager];
		OO_CHECK(facade != nil && oo::ToCxx(facade) == manager);
		OO_CHECK(oo::ToObjC(manager) == facade);

		OOTestResetClient *client = Client(30);
		[facade registerClient:client];
		manager->resetGraphicsState();
		OO_CHECK(client->resets == 1);
		[facade resetGraphicsState];
		OO_CHECK(client->resets == 2);
		manager->unregisterClient(client);
		[facade resetGraphicsState];
		OO_CHECK(client->resets == 2);
	}
	@autoreleasepool
	{
		OO_CHECK(oo::ToCxx([OOGraphicsResetManager sharedManager]) == manager);
		OO_CHECK(oo::ToObjC(manager) == [OOGraphicsResetManager sharedManager]);
	}

	OOGraphicsResetManager *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOGraphicsResetManager *>(nullptr)) == nil);
}


OO_TEST_MAIN()
