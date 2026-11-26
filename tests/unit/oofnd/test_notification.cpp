/*	test_notification.cpp
	Unit tests for oofnd/Notification.hpp (bead oo-3rb.9): oo::NotificationCenter, the replacement
	for NSNotificationCenter, checked against the semantics the header documents: name and object
	filters (empty name / nullptr object as wildcards), registration-order synchronous delivery,
	removal by observer, by (observer, name, object) and by token, removal and addition during a
	post, nested posts, and posting from another thread.
*/

// Included under OOCocoa.h's true/false macros, as the game includes it (see test_cocoa_macros.cpp).
#define true						1
#define false						0
#include "oofnd/Notification.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "Notification.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <string>
#include <thread>
#include <vector>

namespace {

const char kWillReset[] = "org.aegidian.oolite OOJavaScriptEngine will reset";
const char kDidReset[] = "org.aegidian.oolite OOJavaScriptEngine did reset";

int gEngine = 0;   // stand-ins for Objective-C ids: only their addresses matter
int gOtherEngine = 0;
int gA = 0, gB = 0, gC = 0;

OO_TEST(deliversByNameAndObjectInRegistrationOrder)
{
	oo::NotificationCenter nc;
	std::vector<std::string> log;
	nc.addObserver(&gA, kWillReset, &gEngine, [&](const oo::Notification&) { log.push_back("a"); });
	nc.addObserver(&gB, kWillReset, &gEngine, [&](const oo::Notification&) { log.push_back("b"); });
	nc.addObserver(&gC, kWillReset, &gEngine, [&](const oo::Notification&) { log.push_back("c"); });
	nc.addObserver(&gC, kDidReset, &gEngine, [&](const oo::Notification&) { log.push_back("did"); });

	nc.post(kWillReset, &gEngine);
	OO_CHECK((log == std::vector<std::string>{ "a", "b", "c" }));

	log.clear();
	nc.post(kDidReset, &gEngine);
	OO_CHECK((log == std::vector<std::string>{ "did" }));

	log.clear();
	nc.post(kWillReset, &gOtherEngine);          // a different object: nobody listens to it
	nc.post("unrelated", &gEngine);
	OO_CHECK(log.empty());
}

OO_TEST(namesCompareByValue)
{
	oo::NotificationCenter nc;
	int calls = 0;
	nc.addObserver(&gA, std::string("will reset"), nullptr, [&](const oo::Notification&) { ++calls; });
	const std::string sameTextElsewhere = std::string("will ") + "reset";
	nc.post(sameTextElsewhere, nullptr);
	OO_CHECK_EQ(calls, 1);
}

OO_TEST(wildcardsWhenAdding)
{
	oo::NotificationCenter nc;
	std::vector<std::string> log;
	nc.addObserver(&gA, kWillReset, nullptr, [&](const oo::Notification& n)
	{
		log.push_back(std::string("anyObject:") + std::string(n.name));
		OO_CHECK(n.object == &gOtherEngine);
	});
	nc.addObserver(&gB, "", &gOtherEngine, [&](const oo::Notification& n) { log.push_back(std::string("anyName:") + std::string(n.name)); });
	nc.post(kWillReset, &gOtherEngine);
	OO_CHECK((log == std::vector<std::string>{ std::string("anyObject:") + kWillReset, std::string("anyName:") + kWillReset }));
}

OO_TEST(removeByObserverNameAndObject)
{
	oo::NotificationCenter nc;
	int a = 0, b = 0, did = 0;
	nc.addObserver(&gA, kWillReset, &gEngine, [&](const oo::Notification&) { ++a; });
	nc.addObserver(&gA, kDidReset, &gEngine, [&](const oo::Notification&) { ++did; });
	nc.addObserver(&gB, kWillReset, &gEngine, [&](const oo::Notification&) { ++b; });

	nc.removeObserver(&gA, kWillReset, &gEngine);   // only that registration of a
	nc.post(kWillReset, &gEngine);
	nc.post(kDidReset, &gEngine);
	OO_CHECK_EQ(a, 0);
	OO_CHECK_EQ(b, 1);
	OO_CHECK_EQ(did, 1);

	nc.removeObserver(&gB, kWillReset, &gOtherEngine);   // object does not match: stays
	nc.post(kWillReset, &gEngine);
	OO_CHECK_EQ(b, 2);

	nc.removeObserver(&gA);                          // everything of a
	nc.post(kDidReset, &gEngine);
	OO_CHECK_EQ(did, 1);
	OO_CHECK_EQ(nc.observerCount(), 1u);

	nc.removeObserver(&gB, "", nullptr);            // wildcards when removing
	OO_CHECK_EQ(nc.observerCount(), 0u);
	nc.removeObserver(&gB);                          // removing twice is harmless
	nc.removeObserver(nullptr);
}

OO_TEST(duplicateRegistrationsDeliverTwiceAndRemoveTogether)
{
	oo::NotificationCenter nc;
	int calls = 0;
	nc.addObserver(&gA, kWillReset, &gEngine, [&](const oo::Notification&) { ++calls; });
	nc.addObserver(&gA, kWillReset, &gEngine, [&](const oo::Notification&) { ++calls; });
	nc.post(kWillReset, &gEngine);
	OO_CHECK_EQ(calls, 2);
	nc.removeObserver(&gA, kWillReset, &gEngine);
	nc.post(kWillReset, &gEngine);
	OO_CHECK_EQ(calls, 2);
}

OO_TEST(removeByToken)
{
	oo::NotificationCenter nc;
	int first = 0, second = 0;
	const auto t1 = nc.addObserver(nullptr, kWillReset, nullptr, [&](const oo::Notification&) { ++first; });
	const auto t2 = nc.addObserver(nullptr, kWillReset, nullptr, [&](const oo::Notification&) { ++second; });
	OO_CHECK(t1 != 0);
	OO_CHECK(t1 != t2);
	nc.removeObserver(t1);
	nc.post(kWillReset, &gEngine);
	OO_CHECK_EQ(first, 0);
	OO_CHECK_EQ(second, 1);
	nc.removeObserver(t1);                           // unknown token: no-op
	nc.removeObserver(nullptr);                      // a null observer never matches token-only entries
	OO_CHECK_EQ(nc.observerCount(), 1u);
}

// The game's pattern: each JS-holding object removes itself from inside its will-reset callback.
OO_TEST(removalDuringPostIsSafe)
{
	oo::NotificationCenter nc;
	std::vector<std::string> log;
	nc.addObserver(&gA, kWillReset, &gEngine, [&](const oo::Notification&)
	{
		log.push_back("a");
		nc.removeObserver(&gA, kWillReset, &gEngine);   // removes itself mid-post
		nc.removeObserver(&gC);                         // and a later observer, which must not run
	});
	nc.addObserver(&gB, kWillReset, &gEngine, [&](const oo::Notification&) { log.push_back("b"); });
	nc.addObserver(&gC, kWillReset, &gEngine, [&](const oo::Notification&) { log.push_back("c"); });

	nc.post(kWillReset, &gEngine);
	OO_CHECK((log == std::vector<std::string>{ "a", "b" }));

	log.clear();
	nc.post(kWillReset, &gEngine);
	OO_CHECK((log == std::vector<std::string>{ "b" }));
}

OO_TEST(additionDuringPostWaitsForTheNextPost)
{
	oo::NotificationCenter nc;
	int added = 0;
	bool once = false;
	nc.addObserver(&gA, kWillReset, nullptr, [&](const oo::Notification&)
	{
		if (once)  return;
		once = true;
		nc.addObserver(&gB, kWillReset, nullptr, [&](const oo::Notification&) { ++added; });
	});
	nc.post(kWillReset, nullptr);
	OO_CHECK_EQ(added, 0);
	nc.post(kWillReset, nullptr);
	OO_CHECK_EQ(added, 1);
}

OO_TEST(nestedPosts)
{
	oo::NotificationCenter nc;
	std::vector<std::string> log;
	nc.addObserver(&gA, kWillReset, nullptr, [&](const oo::Notification&)
	{
		log.push_back("will");
		nc.post(kDidReset, nullptr);
		log.push_back("will-end");
	});
	nc.addObserver(&gB, kDidReset, nullptr, [&](const oo::Notification&) { log.push_back("did"); });
	nc.post(kWillReset, nullptr);
	OO_CHECK((log == std::vector<std::string>{ "will", "did", "will-end" }));
}

OO_TEST(postsOnThePostingThread)
{
	oo::NotificationCenter nc;
	std::thread::id deliveredOn;
	nc.addObserver(&gA, kWillReset, nullptr, [&](const oo::Notification&) { deliveredOn = std::this_thread::get_id(); });
	std::thread::id postedOn;
	std::thread t([&] { postedOn = std::this_thread::get_id(); nc.post(kWillReset, nullptr); });
	t.join();
	OO_CHECK(deliveredOn == postedOn);
	OO_CHECK(deliveredOn != std::this_thread::get_id());
}

OO_TEST(defaultCenterIsOneInstance)
{
	oo::NotificationCenter& a = oo::NotificationCenter::defaultCenter();
	oo::NotificationCenter& b = oo::NotificationCenter::defaultCenter();
	OO_CHECK(&a == &b);
	int calls = 0;
	const auto token = a.addObserver(&gA, "test_notification.default", nullptr, [&](const oo::Notification&) { ++calls; });
	b.post("test_notification.default", nullptr);
	OO_CHECK_EQ(calls, 1);
	a.removeObserver(token);
	OO_CHECK_EQ(a.observerCount(), 0u);
}

} // namespace

OO_TEST_MAIN()
