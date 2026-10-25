/*	test_AI.mm
	Unit tests for AI (src/Core/AI.h): bead oo-puw9, a Phase 3 conversion in the house style of
	the OOColor exemplar (proposed ADR-0056). AI's superclass, the weak-reference root, was then
	Objective-C, so the AI facade keeps it and owns its C++ object (amendment oo-o89 item 2).

	The AI is a state machine: it loads a state machine (a property list of states, each a
	dictionary of messages, each an array of actions), whitelists its actions, keeps a stack of
	suspended machines, queues messages for its next think, and performs an action by sending its
	owner (a ship) the action's selector, by name. Its collaborators link the whole game, so the
	test defines them itself (amendment oo-z1s4 item 4): the resource manager (one table of AI
	files and the whitelist), the cache manager (a map), the property-list reader, the deferred-call
	scheduler (which keeps the calls until the test fires them) and the log indentation functions
	(which do what OOLogging.mm's do). The owner is an Objective-C object of the test's own answering
	the ship's selectors that AI sends, and recording the actions it is sent; since bead oo-9ht.144
	it is the object of a C++ ship stand-in, which answers what AI asks the ship. The log is captured.

	The expectations were written against the Objective-C API and run on the unconverted class
	first; they ran through the facade (its forwarding test, amendment oo-8kx7 item 6) until bead
	oo-9ht.73 deleted it, and now call the C++ class with the same expectations (each
	[[[AI alloc] init] autorelease] an autoreleased oo::makeRef<AI>(), each send a member call); the
	owner stand-in is an object holding the ship, since the AI holds the ship's C++ part weakly
	(oo::WeakRef). It was rooted on the Objective-C root class OOObject until bead oo-4aq6a.2 made it
	C++ (Phase 4 deletes the root): its actions, once found and called by selector, are a table of
	its members by the same names, answering as they did.
	Run: bash tools/check-core-tests.sh
*/

#include "AI.h"
#include "GameController.h"	// OOScheduleDeferredCall, stood in below (bead oo-pvhrh)
#include "OOCallByName.h"	// oo::CallEntityByName, stood in below (bead oo-9ht.39.7.1)

#include "oofnd/Log.hpp"
#include "oofnd/objc/OOException.h"	// oo::Exception (bead oo-rskgl.1)
#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <functional>
#include <map>
#include <string>
#include <vector>


// --- Collaborators the game would provide ----------------------------------------------------

namespace {

std::map<std::string, oo::PList> gAIFiles;		// file name -> its property list
oo::PList gWhitelist;
std::vector<std::string> gLog;

}	// namespace


#include "ResourceManager.h"


// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
std::optional<std::string> ResourceManager::pathForFileNamed(const std::string &fileName, const std::optional<std::string> &folderName)
{
	if (gAIFiles.find(fileName) == gAIFiles.end())  return std::nullopt;
	return folderName.value_or("") + "/" + fileName;
}


oo::PList ResourceManager::whitelistDictionary()
{
	return gWhitelist;
}



oo::PList cxx_OOPropertyListFromFile(const std::string &path)
{
	const std::string name = path.substr(path.find('/') + 1);
	const auto found = gAIFiles.find(name);
	return found != gAIFiles.end() ? found->second : oo::PList();
}


// The cache manager is C++ since bead oo-9ht.31 deleted its facade: a C++ stand-in with the Objective-C
// stand-in's answers.
static std::map<std::string, oo::PList>	gCacheEntries;	// "cache/key" -> value

#include "OOCacheManager.h"

OOCacheManager *OOCacheManager::sharedCache()
{
	static OOCacheManager *shared = new OOCacheManager;
	return shared;
}
OOCacheManager::~OOCacheManager()  {}
oo::PList OOCacheManager::pListForKey(const std::string &key, const std::string &cache)
{
	const auto found = gCacheEntries.find(cache + "/" + key);
	return found != gCacheEntries.end() ? found->second : oo::PList();
}
void OOCacheManager::setPList(const oo::PList &value, const std::string &key, const std::string &cache)
{
	gCacheEntries[cache + "/" + key] = value;
}


namespace {

struct DeferredCall
{
	std::function<void()>	call;	// the AI's C++ deferred call (bead oo-pvhrh; an Objective-C target and -fire before)
	double					delay;
};

std::vector<DeferredCall> gDeferred;


// Fires every scheduled call, as the frame loop does once it is due.
void FireDeferredCalls()
{
	std::vector<DeferredCall> calls = std::move(gDeferred);
	gDeferred.clear();
	for (DeferredCall &call : calls)
	{
		call.call();
		call.call = nullptr;	// released after its call, as the target was
	}
}

}	// namespace


void OOScheduleDeferredCall(std::function<void()> call, NSTimeInterval delay)
{
	gDeferred.push_back({ std::move(call), delay });
}


// Link stub (amendment oo-zffj item 2): the graph dump runs only under a default the test never sets.
void GenerateGraphVizForAIStateMachine(const oo::PList &, const std::string &)
{
	std::abort();
}


const char *const cxx_kOOLogException = "exception";
void OOLogPushIndent(void)	{ oo::log::pushIndent(); }
void OOLogPopIndent(void)	{ oo::log::popIndent(); }
void OOLogIndent(void)		{ oo::log::indent(); }
void OOLogOutdent(void)		{ oo::log::outdent(); }


// --- The owner -------------------------------------------------------------------------------

/*	The ship is C++ since bead oo-9ht.144 deleted the Objective-C ship: AI asks the C++ ship its
	universal ID, whether it is the player, its name and whether it reports AI messages, and sets its
	AI script, and sends its actions to the ship's object by name, as before. The object is the
	root's (which holds the C++ part, oo::ToCxx reads it, and which oo::ToObjC answers for it); the
	classes are declared as Entity.h and ShipEntity.h declare them (the test imports neither), and
	the part answers from its object's fields, as the object's selectors did.
*/
class TestEntityObject;

class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	OOUniversalID getUniversalID();
	bool getIsPlayer();

	::TestEntityObject *_object = nullptr;	// not retained
};

class ShipEntity : public Entity
{
public:
	bool getReportAIMessages();
	std::optional<std::string> getName();
	void setAIScript(const std::string &aiString);
};

// The AI holds its owner's C++ part weakly since bead oo-9ht.73.
class TestEntityObject : public oo::RefCounted
{
public:
	virtual const char *className() const  { return "Entity"; }	// its Objective-C class's runtime name

	oo::Ref<Entity> _cxxEntity;
};

class TestShip final : public TestEntityObject
{
public:
	// Every test ship has its C++ part (the ship).
	TestShip() : TestEntityObject()
	{
		_cxxEntity = oo::makeRef<ShipEntity>();
		_cxxEntity->_object = this;
	}

	const char *className() const override  { return "TestShip"; }

	void interpretAIMessage(const std::string &message)
	{
		_calls.push_back("interpretAIMessage: " + message);
	}

	void doThing(const std::string &argument)
	{
		_calls.push_back("doThing: " + argument);
		_runningAIs.push_back(AI::currentlyRunningAIDescription().value_or("(null)"));
		if (AI::currentlyRunningAI() == _ai)  _runningAIs.back() += " (this AI)";
	}

	void doNothing()
	{
		_calls.push_back("doNothing");
	}

	void setStateTo(const std::string &state)
	{
		_calls.push_back("setStateTo: " + state);
		_ai->setState(state);
	}

	void sendLoop()
	{
		_ai->reactToMessage("LOOP", "loop");
	}

	OOUniversalID				_id = {};
	BOOL						_isPlayer = NO;
	AI							*_ai = nullptr;	// not retained (C++ since bead oo-9ht.73)
	std::vector<std::string>	_calls;			// "selector argument", in order
	std::vector<std::string>	_runningAIs;	// +cxx_currentlyRunningAIDescription during each action
	std::optional<std::string>	_script;
};


Entity::~Entity() = default;
OOUniversalID Entity::getUniversalID()					{ return static_cast<TestShip *>(_object)->_id; }
bool Entity::getIsPlayer()								{ return static_cast<TestShip *>(_object)->_isPlayer; }
bool ShipEntity::getReportAIMessages()						{ return false; }
std::optional<std::string> ShipEntity::getName()			{ return std::string("Test ship"); }
void ShipEntity::setAIScript(const std::string &aiString)	{ static_cast<TestShip *>(_object)->_script = aiString; }

// The test's object of an entity (oo::ToObjC() until bead oo-4aq6a.2; Entity+ObjCBridge.mm's, which
// the test does not link).
::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? entity->_object : nullptr; }
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects (bead oo-dpyk8)

/*	OOEntityCalledByName.mm's (bead oo-9ht.39.7.1), which the test does not link: the test ship has
	no C++ table, so every name goes to its object, the path that file takes for an untabled name.
	The object's methods by their selectors' names, each taking its argument or none, as the
	Objective-C methods did; OOCallByName's answers for a name the object has no method for
	(callByName.unknownSelector) or called with or without an argument it does not take
	(callByName.badSignature) are logged as it logged them.
*/
namespace {

struct TestShipMethod
{
	void (TestShip::*withArgument)(const std::string &);
	void (TestShip::*withoutArgument)();
};

const TestShipMethod *TestShipMethodNamed(::TestEntityObject *object, const std::string &name)
{
	static const std::map<std::string, TestShipMethod> methods = {
		{ "interpretAIMessage:",	{ &TestShip::interpretAIMessage, nullptr } },
		{ "doThing:",				{ &TestShip::doThing, nullptr } },
		{ "doNothing",				{ nullptr, &TestShip::doNothing } },
		{ "setStateTo:",			{ &TestShip::setStateTo, nullptr } },
		{ "sendLoop",				{ nullptr, &TestShip::sendLoop } },
	};
	if (dynamic_cast<TestShip *>(object) == nullptr)  return nullptr;
	auto found = methods.find(name);
	return (found != methods.end()) ? &found->second : nullptr;
}


oo::PList CallTestObjectByName(::TestEntityObject *object, const std::string &name, const std::string *argument)
{
	if (object == nullptr)  return oo::PList();
	const TestShipMethod *method = TestShipMethodNamed(object, name);
	if (method == nullptr)
	{
		OO_LOG_ERR("callByName.unknownSelector", "{} does not respond to {}.", object->className(), name);
	}
	else if (argument != nullptr && method->withArgument != nullptr)
	{
		(static_cast<TestShip *>(object)->*method->withArgument)(*argument);
	}
	else if (argument == nullptr && method->withoutArgument != nullptr)
	{
		(static_cast<TestShip *>(object)->*method->withoutArgument)();
	}
	else
	{
		OO_LOG_ERR("callByName.badSignature", "-[{} {}] has no signature a by-name call can use.", object->className(), name);
	}
	return oo::PList();
}

}	// namespace

bool oo::EntityRespondsToName(Entity *entity, const std::string &name)
{
	return TestShipMethodNamed(TestObjectOf(entity), name) != nullptr;
}
oo::PList oo::CallEntityByName(Entity *entity, const std::string &name)  { return CallTestObjectByName(TestObjectOf(entity), name, nullptr); }
oo::PList oo::CallEntityByName(Entity *entity, const std::string &name, const std::string &argument)  { return CallTestObjectByName(TestObjectOf(entity), name, &argument); }
oo::PList oo::CallEntityByName(Entity *entity, const std::string &name, const oo::PList &argument)
{
	// A PList reaches a string parameter only when it is a string (OOCallByName).
	const std::string *string = argument.getIf<std::string>();
	if (string != nullptr || TestShipMethodNamed(TestObjectOf(entity), name) == nullptr)  return CallTestObjectByName(TestObjectOf(entity), name, string);
	OO_LOG_ERR("callByName.badSignature", "-[{} {}] has no signature a by-name call can use.", TestObjectOf(entity)->className(), name);
	return oo::PList();
}


namespace {

// The test ship's C++ part, which AI is given as its owner.
ShipEntity *Part(TestShip *ship)  { return ship != nullptr ? static_cast<ShipEntity *>(ship->_cxxEntity.get()) : nullptr; }

}	// namespace


namespace {

void Capture(std::string_view line)
{
	gLog.emplace_back(line);
}


int LogLinesContaining(std::string_view text)
{
	int count = 0;
	for (const std::string &line : gLog)
	{
		if (line.find(text) != std::string::npos)  count++;
	}
	return count;
}


oo::PList Strings(std::initializer_list<const char *> strings)
{
	oo::PList::Array array;
	for (const char *s : strings)  array.emplace_back(std::string(s));
	return oo::PList(std::move(array));
}


oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


// The AI files and the whitelist, set once (AI reads the whitelist once per process).
void SetUp()
{
	static bool done = false;
	if (done)  return;
	done = true;

	oo::log::logger().setInitialized(true);
	oo::log::logger().setSink(&Capture);

	gWhitelist = Dict({
		{ "ai_methods", Strings({ "setStateTo:", "doThing:", "sendLoop" }) },
		{ "ai_and_action_methods", Strings({ "doNothing", "unknownMethod" }) },
		{ "ai_method_aliases", Dict({ { "nothing", oo::PList(std::string("doNothing")) }, { "thingTwice", Strings({ "doThing:", "twice" }) } }) },
	});

	gAIFiles["test.plist"] = Dict({
		{ "GLOBAL", Dict({ { "ENTER", Strings({ "setStateTo: ATTACK" }) } }) },
		{ "ATTACK", Dict({
			{ "ENTER", Strings({ "  doThing: 1  2 ", "forbidden: 3", "nothing", "thingTwice" }) },
			{ "FOO", Strings({ "doThing: foo" }) },
			{ "BAR", Strings({ "doThing: bar" }) },
			{ "UPDATE", Strings({ "doThing: update" }) },
			{ "UNKNOWN", Strings({ "unknownMethod" }) },
			{ "LOOP", Strings({ "doThing: loop", "sendLoop" }) },
			{ "BADHANDLER", oo::PList(std::string("not an array")) },
		}) },
		{ "BROKEN", oo::PList(std::string("not a dictionary")) },
	});
	gAIFiles["other.plist"] = Dict({ { "GLOBAL", Dict({ { "ENTER", Strings({ "doThing: other" }) } }) } });
}


TestShip *NewShip(OOUniversalID uid)
{
	TestShip *ship = oo::autorelease(oo::makeRef<TestShip>());
	ship->_id = uid;
	return ship;
}


// [[[AI alloc] init] autorelease] (OOAIAutorelease): the AI is C++ since bead oo-9ht.73 deleted its facade.
AI *Autoreleased(oo::Ref<AI> ai)
{
	AI *result = ai.get();
	OOAIAutorelease(std::move(ai));
	return result;
}


AI *NewAI(TestShip *ship)
{
	AI *ai = Autoreleased(oo::makeRef<AI>());
	if (ship != nil)
	{
		ship->_ai = ai;
		ai->setOwner(Part(ship));
	}
	return ai;
}

}	// namespace


OO_TEST(initialState)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		AI *ai = NewAI(nil);
		OO_CHECK(ai->name() == std::optional<std::string>("<no AI>"));
		OO_CHECK(!ai->state().has_value());
		OO_CHECK(!ai->associatedJS().has_value());
		OO_CHECK(ai->owner() == nil);
		OO_CHECK(ai->stackDepth() == 0 && !ai->hasSuspendedStateMachines());
		OO_CHECK(ai->getPendingMessages().empty());
		OO_CHECK(ai->getThinkTimeInterval() == AI_THINK_INTERVAL);
		OO_CHECK(std::isinf(ai->getNextThinkTime()));
		ai->setNextThinkTime(5.0);
		OO_CHECK(std::isinf(ai->getNextThinkTime()));		// no state machine: never
		ai->setThinkTimeInterval(0.5);
		OO_CHECK(ai->getThinkTimeInterval() == 0.5);
		OO_CHECK(ai->descriptionComponents() == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for (null)"));
		OO_CHECK(ai->shortDescriptionComponents() == std::optional<std::string>("<no AI>:(null) / (null)"));
		OO_CHECK(AI::currentlyRunningAI() == nil);
		OO_CHECK(AI::currentlyRunningAIDescription() == std::optional<std::string>("<no AI running>"));
	}
}


OO_TEST(ownerIsWeak)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		AI *ai = Autoreleased(oo::makeRef<AI>());
		{
			oo::AutoreleaseScope pool;
			TestShip *ship = oo::makeRef<TestShip>().leakRef();
			ship->_id = 7;
			ai->setOwner(Part(ship));
			OO_CHECK(ai->owner() == Part(ship));
			OO_CHECK(ai->descriptionComponents() == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for Test ship 7"));
			ship->_isPlayer = YES;
			ai->setOwner(Part(ship));
			OO_CHECK(ai->descriptionComponents() == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for player autopilot"));
			ship->release();
		}
		OO_CHECK(ai->owner() == nil);
		ai->setOwner(nil);
		OO_CHECK(ai->descriptionComponents() == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for no owner"));
	}
}


OO_TEST(loadsAndRunsAStateMachine)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewShip(3);
		AI *ai = NewAI(ship);
		ai->setStateMachine("test.plist", "test.js");

		// GLOBAL's ENTER moved it to ATTACK, whose ENTER ran the whitelisted actions only, an alias
		// by its real name, a list alias as its words; GLOBAL had no EXIT, so the ship was told.
		OO_CHECK(ai->name() == std::optional<std::string>("test.plist"));
		OO_CHECK(ai->state() == std::optional<std::string>("ATTACK"));
		OO_CHECK(ai->associatedJS() == std::optional<std::string>("test.js"));
		OO_CHECK(ship->_calls == std::vector<std::string>({ "setStateTo: ATTACK", "interpretAIMessage: EXIT", "doThing: 1 2", "doNothing", "doThing: twice" }));
		OO_CHECK(ship->_runningAIs == std::vector<std::string>({ "test.plist in state ATTACK (this AI)", "test.plist in state ATTACK (this AI)" }));
		OO_CHECK(AI::currentlyRunningAI() == nil);
		OO_CHECK(ai->getNextThinkTime() == 0.0);
		OO_CHECK(ai->descriptionComponents() == std::optional<std::string>("\"test.plist\" in state: \"ATTACK\" for Test ship 3"));
		OO_CHECK(ai->shortDescriptionComponents() == std::optional<std::string>("test.plist:ATTACK / test.js"));
		OO_CHECK(LogLinesContaining("uses \"forbidden:\", which is not a permitted AI method") == 1);
		OO_CHECK(LogLinesContaining("State \"BROKEN\" in AI \"test.plist\" is not a dictionary") == 1);
		OO_CHECK(LogLinesContaining("Handler \"BADHANDLER\" for state \"ATTACK\"") == 1);

		// The cleaned machine is cached, with its script name.
		const oo::PList cached = OOCacheManager::sharedCache()->pListForKey("test.plist", "AIs");
		OO_CHECK(cached.get<std::string>("jsScript") == "test.js");
		OO_CHECK(cached.find("BROKEN") == nullptr);
		OO_CHECK(*cached.find("ATTACK")->find("ENTER") == Strings({ "doThing: 1  2", "doNothing", "doThing: twice" }));

		// A message with no handler goes to the ship; a missing state does nothing.
		ship->_calls.clear();
		ai->reactToMessage("NOHANDLER", std::nullopt);
		OO_CHECK(ship->_calls == std::vector<std::string>({ "interpretAIMessage: NOHANDLER" }));
		ai->setState("NOSUCHSTATE");
		OO_CHECK(ai->state() == std::optional<std::string>("ATTACK"));

		// An action the ship does not answer is logged.
		gLog.clear();
		ai->reactToMessage("UNKNOWN", "test");
		OO_CHECK(LogLinesContaining("Test ship 3 does not respond to unknownMethod") == 1);
	}
}


OO_TEST(unknownStateMachines)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewShip(4);
		AI *ai = NewAI(ship);
		gLog.clear();
		ai->setStateMachine("missing.plist", "x.js");
		OO_CHECK(ai->name() == std::optional<std::string>("<no AI>"));
		OO_CHECK(LogLinesContaining("to \"missing.plist\" - could not load file") == 1);
		OO_CHECK(OOCacheManager::sharedCache()->pListForKey("missing.plist", "AIs") == oo::PList(std::string("nil")));

		// Remembered as missing: no second attempt, no second log line.
		const int lines = LogLinesContaining("missing.plist");
		ai->setStateMachine("missing.plist", "x.js");
		OO_CHECK(LogLinesContaining("missing.plist") == lines);
		OO_CHECK(ship->_calls.empty());
	}
}


OO_TEST(stackOfStateMachines)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewShip(5);
		AI *ai = NewAI(ship);
		ai->setStateMachine("test.plist", "test.js");
		ai->message("FOO");
		ship->_calls.clear();

		ai->setStateMachine("other.plist", "other.js");
		OO_CHECK(ai->stackDepth() == 1 && ai->hasSuspendedStateMachines());
		OO_CHECK(ai->name() == std::optional<std::string>("other.plist"));
		OO_CHECK(ai->state() == std::optional<std::string>("GLOBAL"));
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: other" }));
		OO_CHECK(ai->getPendingMessages() == std::set<std::string>({ "FOO" }));	// not cleared by a push

		// Exiting restores the machine, its state, its script and its messages, then restarts it.
		ai->dropMessage("FOO");
		ship->_calls.clear();
		ai->exitStateMachineWithMessage(std::nullopt);
		OO_CHECK(ai->stackDepth() == 0);
		OO_CHECK(ai->name() == std::optional<std::string>("test.plist"));
		OO_CHECK(ai->state() == std::optional<std::string>("ATTACK"));
		OO_CHECK(ship->_script == std::optional<std::string>("test.js"));
		OO_CHECK(ai->getPendingMessages() == std::set<std::string>({ "FOO" }));
		OO_CHECK(ship->_calls == std::vector<std::string>({ "interpretAIMessage: RESTARTED" }));

		// Nothing suspended: nothing happens.
		ship->_calls.clear();
		ai->exitStateMachineWithMessage("BAR");
		OO_CHECK(ship->_calls.empty());

		// Pushing and exiting with a message.
		ai->setStateMachine("other.plist", "other.js");
		ship->_calls.clear();
		ai->exitStateMachineWithMessage("BAR");
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: bar" }));

		ai->setStateMachine("other.plist", "other.js");
		ai->clearStack();
		OO_CHECK(ai->stackDepth() == 0);
		ai->preserveCurrentStateMachine();
		ai->preserveCurrentStateMachine();
		OO_CHECK(ai->stackDepth() == 2);
		ai->restorePreviousStateMachine();
		OO_CHECK(ai->stackDepth() == 1);
		ai->clearAllData();
		OO_CHECK(ai->stackDepth() == 0 && ai->getPendingMessages().empty());
		OO_CHECK(ai->getNextThinkTime() == 36000.0);

		// The stack is limited: the 33rd push raises, after logging.
		gLog.clear();
		for (int i = 0; i < 32; i++)  ai->preserveCurrentStateMachine();
		bool raised = false;
		try
		{
			ai->preserveCurrentStateMachine();
		}
		catch (const oo::Exception &)	// was @catch (id exception): what src throws (bead oo-rskgl.1)
		{
			raised = true;
		}
		OO_CHECK(raised);
		OO_CHECK(ai->stackDepth() == 32);
		OO_CHECK(LogLinesContaining("AI stack overflow for") == 1);
	}
}


OO_TEST(messagesAndThinking)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewShip(6);
		AI *ai = NewAI(ship);
		ai->setStateMachine("test.plist", "test.js");
		ship->_calls.clear();

		ai->message("FOO");
		ai->message("BAR");
		ai->message("FOO");
		OO_CHECK(ai->getPendingMessages() == std::set<std::string>({ "BAR", "FOO" }));
		gLog.clear();
		ai->debugDumpPendingMessages();
		OO_CHECK(LogLinesContaining("Pending messages for AI \"test.plist\" in state: \"ATTACK\" for Test ship 6: BAR, FOO") == 1);

		// A think sends UPDATE, then the queued messages in byte order, and empties the queue.
		ai->think();
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: update", "doThing: bar", "doThing: foo" }));
		OO_CHECK(ai->getPendingMessages().empty());

		// The queue holds 33 messages; more are logged and dropped.
		gLog.clear();
		for (int i = 0; i < 34; i++)  ai->message("M" + std::to_string(100 + i));
		OO_CHECK(ai->getPendingMessages().size() == 33);
		OO_CHECK(LogLinesContaining("AI message \"M133\" received by 'Test ship 6' AI while pending messages stack full") == 1);
		ai->clearAllData();

		// A ship that is not launched neither queues nor thinks.
		ship->_id = NO_TARGET;
		ship->_calls.clear();
		ai->message("FOO");
		OO_CHECK(ai->getPendingMessages().empty());
		ai->think();
		ai->reactToMessage("FOO", std::nullopt);
		OO_CHECK(ship->_calls.empty());

		gLog.clear();
		ai->dumpState();
		OO_CHECK(LogLinesContaining("State machine name: test.plist") == 1);
		OO_CHECK(LogLinesContaining("Current state: ATTACK") == 1);
	}
}


OO_TEST(actionsAndRecursion)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewShip(8);
		AI *ai = NewAI(ship);
		ai->setStateMachine("test.plist", "test.js");

		// An action is the selector and the rest of its words as one string.
		ship->_calls.clear();
		ai->takeAction("doThing:   a b   c");
		ai->takeAction("doNothing");
		ai->takeAction("");
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: a b c", "doNothing" }));
		OO_CHECK(ship->_runningAIs.back() == "<no AI running>");	// not inside a handler

		// A handler whose action sends its own message again recurses until the limiter stops it.
		ship->_calls.clear();
		gLog.clear();
		ai->reactToMessage("LOOP", "test");
		OO_CHECK(LogLinesContaining("hit stack depth limit") == 1);
		OO_CHECK(ship->_calls.size() > 32);

		// An orphaned AI logs instead of acting.
		AI *orphan = NewAI(nil);
		gLog.clear();
		orphan->takeAction("doNothing");
		OO_CHECK(LogLinesContaining("AI <no AI>, trying to perform doNothing, is orphaned (no owner)") == 1);
	}
}


OO_TEST(deferredCalls)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewShip(9);
		AI *ai = NewAI(ship);
		ai->setStateMachine("test.plist", "test.js");
		ship->_calls.clear();

		ai->setState("GLOBAL", 2.5);
		OO_CHECK(gDeferred.size() == 1);
		OO_CHECK(gDeferred[0].call != nullptr);	// the call's own C++ call (bead oo-9ht.73; its Objective-C object and -fire until bead oo-pvhrh)
		OO_CHECK(gDeferred[0].delay == 2.5);
		OO_CHECK(ai->state() == std::optional<std::string>("ATTACK"));	// not yet
		FireDeferredCalls();
		// EXIT in ATTACK (no handler), then GLOBAL's ENTER moves straight back to ATTACK.
		OO_CHECK(ai->state() == std::optional<std::string>("ATTACK"));
		OO_CHECK(ship->_calls.size() == 6);
		OO_CHECK(ship->_calls[0] == "interpretAIMessage: EXIT" && ship->_calls[1] == "setStateTo: ATTACK");

		// The deferred state machine change names a selector the AI does not answer
		// (-setStateMachine: is the ship's), so it does nothing.
		ai->setStateMachine("other.plist", 1.0);
		OO_CHECK(gDeferred.size() == 1);
		FireDeferredCalls();
		OO_CHECK(ai->name() == std::optional<std::string>("test.plist"));

		// The call keeps the AI alive until it fires.
		oo::Ref<AI> keptRef = oo::makeRef<AI>();
		AI *kept = keptRef.get();
		kept->setState("GLOBAL", 0.0);
		keptRef = nullptr;	// [kept release]
		OO_CHECK(kept->name() == std::optional<std::string>("<no AI>"));
		FireDeferredCalls();
	}
}


OO_TEST(initialiserWithStateMachine)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		AI *ai = Autoreleased(AI::newWithStateMachine(std::string("other.plist"), "FROZEN"));
		OO_CHECK(ai->name() == std::optional<std::string>("other.plist"));
		OO_CHECK(ai->state() == std::optional<std::string>("FROZEN"));
		OO_CHECK(ai->owner() == nil);

		AI *plain = Autoreleased(AI::newWithStateMachine(std::nullopt, std::nullopt));
		OO_CHECK(plain->name() == std::optional<std::string>("<no AI>"));
		OO_CHECK(!plain->state().has_value());
	}
}


// After the conversion: the C++ AI's own calls (bead oo-9ht.73 deleted the facade; its crossings,
// oo::ToCxx/oo::ToObjC, the facade's identity and the facade-versus-C++ comparisons, went with it
// under ADR-0049, standing approval oo-9n5p9; facadeContract became this case).
OO_TEST(cxxAPI)
{
	SetUp();
	oo::Ref<AI> kept;
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewShip(10);
		oo::Ref<AI> ai = oo::makeRef<AI>();
		ship->_ai = ai.get();
		ai->setOwner(Part(ship));
		OO_CHECK(ai->owner() == Part(ship));

		// The C++ calls run the machine; the actions see it running.
		ai->setStateMachine("test.plist", "test.js");
		OO_CHECK(ai->state() == std::optional<std::string>("ATTACK"));
		OO_CHECK(ship->_runningAIs.size() == 2);
		ai->message("FOO");
		OO_CHECK(ai->getPendingMessages() == std::set<std::string>({ "FOO" }));
		OO_CHECK(AI::currentlyRunningAI() == nullptr);

		// A deferred call holds the AI.
		ai->setState("GLOBAL", 1.0);
		OO_CHECK(gDeferred.size() == 1);
		FireDeferredCalls();
		OO_CHECK(ai->state() == std::optional<std::string>("ATTACK"));

		kept = ai;
	}
	OO_CHECK(kept->name() == std::optional<std::string>("test.plist"));
	{
		oo::AutoreleaseScope pool;
		oo::Ref<AI> bare = oo::makeRef<AI>();
		OO_CHECK(bare->name() == std::optional<std::string>("<no AI>"));
	}
}


OO_TEST_MAIN()
