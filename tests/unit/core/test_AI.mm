/*	test_AI.mm
	Unit tests for AI (src/Core/AI.h): bead oo-puw9, a Phase 3 conversion in the house style of
	the OOColor exemplar (proposed ADR-0056). AI's superclass, OOWeakRefObject, is still
	Objective-C, so the AI facade keeps it and owns its C++ object (amendment oo-o89 item 2).

	The AI is a state machine: it loads a state machine (a property list of states, each a
	dictionary of messages, each an array of actions), whitelists its actions, keeps a stack of
	suspended machines, queues messages for its next think, and performs an action by sending its
	owner (a ship) the action's selector, by name. Its collaborators link the whole game, so the
	test defines them itself (amendment oo-z1s4 item 4): the resource manager (one table of AI
	files and the whitelist), the cache manager (a map), the property-list reader, the deferred-call
	scheduler (which keeps the calls until the test fires them) and the log indentation functions
	(which do what OOLogging.mm's do). The owner is an OOWeakRefObject of the test's own answering
	the ship's selectors that AI sends, and recording the actions it is sent; since bead oo-9ht.144
	it is the object of a C++ ship stand-in, which answers what AI asks the ship. The log is captured.

	The expectations were written against the Objective-C API and run on the unconverted class
	first; they now run through the facade, which is its forwarding test (amendment oo-8kx7 item
	6). The facade's contract follows.
	Run: bash tools/check-core-tests.sh
*/

#import "AI.h"

#include "oofnd/Log.hpp"
#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>


// --- Collaborators the game would provide ----------------------------------------------------

namespace {

std::map<std::string, oo::PList> gAIFiles;		// file name -> its property list
oo::PList gWhitelist;
std::vector<std::string> gLog;

}	// namespace


@interface ResourceManager: OOObject
+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName;
+ (oo::PList) cxx_whitelistDictionary;
@end


@implementation ResourceManager

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName
{
	if (gAIFiles.find(fileName) == gAIFiles.end())  return std::nullopt;
	return folderName.value_or("") + "/" + fileName;
}


+ (oo::PList) cxx_whitelistDictionary
{
	return gWhitelist;
}

@end


oo::PList cxx_OOPropertyListFromFile(const std::string &path)
{
	const std::string name = path.substr(path.find('/') + 1);
	const auto found = gAIFiles.find(name);
	return found != gAIFiles.end() ? found->second : oo::PList();
}


@interface OOCacheManager: OOObject
{
@public
	std::map<std::string, oo::PList>	_entries;	// "cache/key" -> value
}
+ (OOCacheManager *) sharedCache;
- (oo::PList) cxx_pListForKey:(const std::string &)key inCache:(const std::string &)cache;
- (void) cxx_setPList:(const oo::PList &)value forKey:(const std::string &)key inCache:(const std::string &)cache;
@end


@implementation OOCacheManager

+ (OOCacheManager *) sharedCache
{
	static OOCacheManager *shared = [[OOCacheManager alloc] init];
	return shared;
}


- (oo::PList) cxx_pListForKey:(const std::string &)key inCache:(const std::string &)cache
{
	const auto found = _entries.find(cache + "/" + key);
	return found != _entries.end() ? found->second : oo::PList();
}


- (void) cxx_setPList:(const oo::PList &)value forKey:(const std::string &)key inCache:(const std::string &)cache
{
	_entries[cache + "/" + key] = value;
}

@end


namespace {

struct DeferredCall
{
	id		target;
	SEL		selector;
	id		argument;
	double	delay;
};

std::vector<DeferredCall> gDeferred;


// Fires every scheduled call, as the frame loop does once it is due.
void FireDeferredCalls()
{
	std::vector<DeferredCall> calls = std::move(gDeferred);
	gDeferred.clear();
	for (DeferredCall &call : calls)
	{
		[call.target performSelector:call.selector withObject:call.argument];
		[call.target release];
		[call.argument release];
	}
}

}	// namespace


void OOScheduleDeferredCall(id target, SEL selector, id argument, NSTimeInterval delay)
{
	gDeferred.push_back({ [target retain], selector, [argument retain], delay });
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
@class Entity;

namespace cxx {
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	OOUniversalID getUniversalID();
	bool getIsPlayer();

	::Entity *_object = nil;	// not retained
};
}	// namespace cxx

class ShipEntity : public cxx::Entity
{
public:
	bool getReportAIMessages();
	std::optional<std::string> getName();
	void setAIScript(const std::string &aiString);
};

@interface Entity: OOWeakRefObject
{
@public
	oo::Ref<cxx::Entity> _cxxEntity;
}
@end

@implementation Entity
@end

@interface TestShip: Entity
{
@public
	OOUniversalID				_id;
	BOOL						_isPlayer;
	AI							*_ai;			// not retained
	std::vector<std::string>	_calls;			// "selector argument", in order
	std::vector<std::string>	_runningAIs;	// +cxx_currentlyRunningAIDescription during each action
	std::optional<std::string>	_script;
}
- (void) interpretAIMessage:(const std::string &)message;
- (void) doThing:(const std::string &)argument;
- (void) doNothing;
- (void) setStateTo:(const std::string &)state;
- (void) sendLoop;
@end


@implementation TestShip

// Every test ship has its C++ part (the ship).
- (id) init
{
	if ((self = [super init]))
	{
		_cxxEntity = oo::makeRef<ShipEntity>();
		_cxxEntity->_object = self;
	}
	return self;
}


- (void) interpretAIMessage:(const std::string &)message
{
	_calls.push_back("interpretAIMessage: " + message);
}


- (void) doThing:(const std::string &)argument
{
	_calls.push_back("doThing: " + argument);
	_runningAIs.push_back([AI cxx_currentlyRunningAIDescription].value_or("(null)"));
	if ([AI currentlyRunningAI] == _ai)  _runningAIs.back() += " (this AI)";
}


- (void) doNothing
{
	_calls.push_back("doNothing");
}


- (void) setStateTo:(const std::string &)state
{
	_calls.push_back("setStateTo: " + state);
	[_ai cxx_setState:state];
}


- (void) sendLoop
{
	[_ai cxx_reactToMessage:"LOOP" context:"loop"];
}

@end


cxx::Entity::~Entity() = default;
OOUniversalID cxx::Entity::getUniversalID()					{ return static_cast<TestShip *>(_object)->_id; }
bool cxx::Entity::getIsPlayer()								{ return static_cast<TestShip *>(_object)->_isPlayer; }
bool ShipEntity::getReportAIMessages()						{ return false; }
std::optional<std::string> ShipEntity::getName()			{ return std::string("Test ship"); }
void ShipEntity::setAIScript(const std::string &aiString)	{ static_cast<TestShip *>(_object)->_script = aiString; }

namespace oo { ::Entity *ToObjC(cxx::Entity *entity); }	// Entity+ObjCBridge.mm's, which the test does not link
::Entity *oo::ToObjC(cxx::Entity *entity)  { return entity != nullptr ? entity->_object : nil; }


namespace {

// The test ship's C++ part, which AI is given as its owner.
ShipEntity *Part(TestShip *ship)  { return ship != nil ? static_cast<ShipEntity *>(ship->_cxxEntity.get()) : nullptr; }

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
	TestShip *ship = [[[TestShip alloc] init] autorelease];
	ship->_id = uid;
	return ship;
}


AI *NewAI(TestShip *ship)
{
	AI *ai = [[[AI alloc] init] autorelease];
	if (ship != nil)
	{
		ship->_ai = ai;
		[ai setOwner:Part(ship)];
	}
	return ai;
}

}	// namespace


OO_TEST(initialState)
{
	SetUp();
	@autoreleasepool
	{
		AI *ai = NewAI(nil);
		OO_CHECK([ai cxx_name] == std::optional<std::string>("<no AI>"));
		OO_CHECK(![ai cxx_state].has_value());
		OO_CHECK(![ai cxx_associatedJS].has_value());
		OO_CHECK([ai owner] == nil);
		OO_CHECK([ai stackDepth] == 0 && ![ai hasSuspendedStateMachines]);
		OO_CHECK([ai pendingMessages].empty());
		OO_CHECK([ai thinkTimeInterval] == AI_THINK_INTERVAL);
		OO_CHECK(std::isinf([ai nextThinkTime]));
		[ai setNextThinkTime:5.0];
		OO_CHECK(std::isinf([ai nextThinkTime]));		// no state machine: never
		[ai setThinkTimeInterval:0.5];
		OO_CHECK([ai thinkTimeInterval] == 0.5);
		OO_CHECK([ai cxx_descriptionComponents] == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for (null)"));
		OO_CHECK([ai cxx_shortDescriptionComponents] == std::optional<std::string>("<no AI>:(null) / (null)"));
		OO_CHECK([AI currentlyRunningAI] == nil);
		OO_CHECK([AI cxx_currentlyRunningAIDescription] == std::optional<std::string>("<no AI running>"));
	}
}


OO_TEST(ownerIsWeak)
{
	SetUp();
	@autoreleasepool
	{
		AI *ai = [[[AI alloc] init] autorelease];
		@autoreleasepool
		{
			TestShip *ship = [[TestShip alloc] init];
			ship->_id = 7;
			[ai setOwner:Part(ship)];
			OO_CHECK([ai owner] == Part(ship));
			OO_CHECK([ai cxx_descriptionComponents] == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for Test ship 7"));
			ship->_isPlayer = YES;
			[ai setOwner:Part(ship)];
			OO_CHECK([ai cxx_descriptionComponents] == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for player autopilot"));
			[ship release];
		}
		OO_CHECK([ai owner] == nil);
		[ai setOwner:nil];
		OO_CHECK([ai cxx_descriptionComponents] == std::optional<std::string>("\"<no AI>\" in state: \"(null)\" for no owner"));
	}
}


OO_TEST(loadsAndRunsAStateMachine)
{
	SetUp();
	@autoreleasepool
	{
		TestShip *ship = NewShip(3);
		AI *ai = NewAI(ship);
		[ai cxx_setStateMachine:"test.plist" withJSScript:"test.js"];

		// GLOBAL's ENTER moved it to ATTACK, whose ENTER ran the whitelisted actions only, an alias
		// by its real name, a list alias as its words; GLOBAL had no EXIT, so the ship was told.
		OO_CHECK([ai cxx_name] == std::optional<std::string>("test.plist"));
		OO_CHECK([ai cxx_state] == std::optional<std::string>("ATTACK"));
		OO_CHECK([ai cxx_associatedJS] == std::optional<std::string>("test.js"));
		OO_CHECK(ship->_calls == std::vector<std::string>({ "setStateTo: ATTACK", "interpretAIMessage: EXIT", "doThing: 1 2", "doNothing", "doThing: twice" }));
		OO_CHECK(ship->_runningAIs == std::vector<std::string>({ "test.plist in state ATTACK (this AI)", "test.plist in state ATTACK (this AI)" }));
		OO_CHECK([AI currentlyRunningAI] == nil);
		OO_CHECK([ai nextThinkTime] == 0.0);
		OO_CHECK([ai cxx_descriptionComponents] == std::optional<std::string>("\"test.plist\" in state: \"ATTACK\" for Test ship 3"));
		OO_CHECK([ai cxx_shortDescriptionComponents] == std::optional<std::string>("test.plist:ATTACK / test.js"));
		OO_CHECK(LogLinesContaining("uses \"forbidden:\", which is not a permitted AI method") == 1);
		OO_CHECK(LogLinesContaining("State \"BROKEN\" in AI \"test.plist\" is not a dictionary") == 1);
		OO_CHECK(LogLinesContaining("Handler \"BADHANDLER\" for state \"ATTACK\"") == 1);

		// The cleaned machine is cached, with its script name.
		const oo::PList cached = [[OOCacheManager sharedCache] cxx_pListForKey:"test.plist" inCache:"AIs"];
		OO_CHECK(cached.get<std::string>("jsScript") == "test.js");
		OO_CHECK(cached.find("BROKEN") == nullptr);
		OO_CHECK(*cached.find("ATTACK")->find("ENTER") == Strings({ "doThing: 1  2", "doNothing", "doThing: twice" }));

		// A message with no handler goes to the ship; a missing state does nothing.
		ship->_calls.clear();
		[ai cxx_reactToMessage:"NOHANDLER" context:std::nullopt];
		OO_CHECK(ship->_calls == std::vector<std::string>({ "interpretAIMessage: NOHANDLER" }));
		[ai cxx_setState:"NOSUCHSTATE"];
		OO_CHECK([ai cxx_state] == std::optional<std::string>("ATTACK"));

		// An action the ship does not answer is logged.
		gLog.clear();
		[ai cxx_reactToMessage:"UNKNOWN" context:"test"];
		OO_CHECK(LogLinesContaining("Test ship 3 does not respond to unknownMethod") == 1);
	}
}


OO_TEST(unknownStateMachines)
{
	SetUp();
	@autoreleasepool
	{
		TestShip *ship = NewShip(4);
		AI *ai = NewAI(ship);
		gLog.clear();
		[ai cxx_setStateMachine:"missing.plist" withJSScript:"x.js"];
		OO_CHECK([ai cxx_name] == std::optional<std::string>("<no AI>"));
		OO_CHECK(LogLinesContaining("to \"missing.plist\" - could not load file") == 1);
		OO_CHECK([[OOCacheManager sharedCache] cxx_pListForKey:"missing.plist" inCache:"AIs"] == oo::PList(std::string("nil")));

		// Remembered as missing: no second attempt, no second log line.
		const int lines = LogLinesContaining("missing.plist");
		[ai cxx_setStateMachine:"missing.plist" withJSScript:"x.js"];
		OO_CHECK(LogLinesContaining("missing.plist") == lines);
		OO_CHECK(ship->_calls.empty());
	}
}


OO_TEST(stackOfStateMachines)
{
	SetUp();
	@autoreleasepool
	{
		TestShip *ship = NewShip(5);
		AI *ai = NewAI(ship);
		[ai cxx_setStateMachine:"test.plist" withJSScript:"test.js"];
		[ai message:"FOO"];
		ship->_calls.clear();

		[ai cxx_setStateMachine:"other.plist" withJSScript:"other.js"];
		OO_CHECK([ai stackDepth] == 1 && [ai hasSuspendedStateMachines]);
		OO_CHECK([ai cxx_name] == std::optional<std::string>("other.plist"));
		OO_CHECK([ai cxx_state] == std::optional<std::string>("GLOBAL"));
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: other" }));
		OO_CHECK([ai pendingMessages] == std::set<std::string>({ "FOO" }));	// not cleared by a push

		// Exiting restores the machine, its state, its script and its messages, then restarts it.
		[ai cxx_dropMessage:"FOO"];
		ship->_calls.clear();
		[ai cxx_exitStateMachineWithMessage:std::nullopt];
		OO_CHECK([ai stackDepth] == 0);
		OO_CHECK([ai cxx_name] == std::optional<std::string>("test.plist"));
		OO_CHECK([ai cxx_state] == std::optional<std::string>("ATTACK"));
		OO_CHECK(ship->_script == std::optional<std::string>("test.js"));
		OO_CHECK([ai pendingMessages] == std::set<std::string>({ "FOO" }));
		OO_CHECK(ship->_calls == std::vector<std::string>({ "interpretAIMessage: RESTARTED" }));

		// Nothing suspended: nothing happens.
		ship->_calls.clear();
		[ai cxx_exitStateMachineWithMessage:"BAR"];
		OO_CHECK(ship->_calls.empty());

		// Pushing and exiting with a message.
		[ai cxx_setStateMachine:"other.plist" withJSScript:"other.js"];
		ship->_calls.clear();
		[ai cxx_exitStateMachineWithMessage:"BAR"];
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: bar" }));

		[ai cxx_setStateMachine:"other.plist" withJSScript:"other.js"];
		[ai clearStack];
		OO_CHECK([ai stackDepth] == 0);
		[ai preserveCurrentStateMachine];
		[ai preserveCurrentStateMachine];
		OO_CHECK([ai stackDepth] == 2);
		[ai restorePreviousStateMachine];
		OO_CHECK([ai stackDepth] == 1);
		[ai clearAllData];
		OO_CHECK([ai stackDepth] == 0 && [ai pendingMessages].empty());
		OO_CHECK([ai nextThinkTime] == 36000.0);

		// The stack is limited: the 33rd push raises, after logging.
		gLog.clear();
		for (int i = 0; i < 32; i++)  [ai preserveCurrentStateMachine];
		bool raised = false;
		@try
		{
			[ai preserveCurrentStateMachine];
		}
		@catch (id exception)
		{
			raised = true;
		}
		OO_CHECK(raised);
		OO_CHECK([ai stackDepth] == 32);
		OO_CHECK(LogLinesContaining("AI stack overflow for") == 1);
	}
}


OO_TEST(messagesAndThinking)
{
	SetUp();
	@autoreleasepool
	{
		TestShip *ship = NewShip(6);
		AI *ai = NewAI(ship);
		[ai cxx_setStateMachine:"test.plist" withJSScript:"test.js"];
		ship->_calls.clear();

		[ai message:"FOO"];
		[ai message:"BAR"];
		[ai message:"FOO"];
		OO_CHECK([ai pendingMessages] == std::set<std::string>({ "BAR", "FOO" }));
		gLog.clear();
		[ai debugDumpPendingMessages];
		OO_CHECK(LogLinesContaining("Pending messages for AI \"test.plist\" in state: \"ATTACK\" for Test ship 6: BAR, FOO") == 1);

		// A think sends UPDATE, then the queued messages in byte order, and empties the queue.
		[ai think];
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: update", "doThing: bar", "doThing: foo" }));
		OO_CHECK([ai pendingMessages].empty());

		// The queue holds 33 messages; more are logged and dropped.
		gLog.clear();
		for (int i = 0; i < 34; i++)  [ai message:"M" + std::to_string(100 + i)];
		OO_CHECK([ai pendingMessages].size() == 33);
		OO_CHECK(LogLinesContaining("AI message \"M133\" received by 'Test ship 6' AI while pending messages stack full") == 1);
		[ai clearAllData];

		// A ship that is not launched neither queues nor thinks.
		ship->_id = NO_TARGET;
		ship->_calls.clear();
		[ai message:"FOO"];
		OO_CHECK([ai pendingMessages].empty());
		[ai think];
		[ai cxx_reactToMessage:"FOO" context:std::nullopt];
		OO_CHECK(ship->_calls.empty());

		gLog.clear();
		[ai dumpState];
		OO_CHECK(LogLinesContaining("State machine name: test.plist") == 1);
		OO_CHECK(LogLinesContaining("Current state: ATTACK") == 1);
	}
}


OO_TEST(actionsAndRecursion)
{
	SetUp();
	@autoreleasepool
	{
		TestShip *ship = NewShip(8);
		AI *ai = NewAI(ship);
		[ai cxx_setStateMachine:"test.plist" withJSScript:"test.js"];

		// An action is the selector and the rest of its words as one string.
		ship->_calls.clear();
		[ai cxx_takeAction:"doThing:   a b   c"];
		[ai cxx_takeAction:"doNothing"];
		[ai cxx_takeAction:""];
		OO_CHECK(ship->_calls == std::vector<std::string>({ "doThing: a b c", "doNothing" }));
		OO_CHECK(ship->_runningAIs.back() == "<no AI running>");	// not inside a handler

		// A handler whose action sends its own message again recurses until the limiter stops it.
		ship->_calls.clear();
		gLog.clear();
		[ai cxx_reactToMessage:"LOOP" context:"test"];
		OO_CHECK(LogLinesContaining("hit stack depth limit") == 1);
		OO_CHECK(ship->_calls.size() > 32);

		// An orphaned AI logs instead of acting.
		AI *orphan = NewAI(nil);
		gLog.clear();
		[orphan cxx_takeAction:"doNothing"];
		OO_CHECK(LogLinesContaining("AI <no AI>, trying to perform doNothing, is orphaned (no owner)") == 1);
	}
}


OO_TEST(deferredCalls)
{
	SetUp();
	@autoreleasepool
	{
		TestShip *ship = NewShip(9);
		AI *ai = NewAI(ship);
		[ai cxx_setStateMachine:"test.plist" withJSScript:"test.js"];
		ship->_calls.clear();

		[ai cxx_setState:"GLOBAL" afterDelay:2.5];
		OO_CHECK(gDeferred.size() == 1);
		OO_CHECK(gDeferred[0].target == (id)[AI class]);
		OO_CHECK(gDeferred[0].delay == 2.5);
		OO_CHECK([ai cxx_state] == std::optional<std::string>("ATTACK"));	// not yet
		FireDeferredCalls();
		// EXIT in ATTACK (no handler), then GLOBAL's ENTER moves straight back to ATTACK.
		OO_CHECK([ai cxx_state] == std::optional<std::string>("ATTACK"));
		OO_CHECK(ship->_calls.size() == 6);
		OO_CHECK(ship->_calls[0] == "interpretAIMessage: EXIT" && ship->_calls[1] == "setStateTo: ATTACK");

		// The deferred state machine change names a selector the AI does not answer
		// (-setStateMachine: is the ship's), so it does nothing.
		[ai cxx_setStateMachine:"other.plist" afterDelay:1.0];
		OO_CHECK(gDeferred.size() == 1);
		FireDeferredCalls();
		OO_CHECK([ai cxx_name] == std::optional<std::string>("test.plist"));

		// The call keeps the AI alive until it fires.
		AI *kept = [[AI alloc] init];
		[kept cxx_setState:"GLOBAL" afterDelay:0.0];
		[kept release];
		OO_CHECK([kept cxx_name] == std::optional<std::string>("<no AI>"));
		FireDeferredCalls();
	}
}


OO_TEST(initialiserWithStateMachine)
{
	SetUp();
	@autoreleasepool
	{
		AI *ai = [[[AI alloc] cxx_initWithStateMachine:std::string("other.plist") andState:"FROZEN"] autorelease];
		OO_CHECK([ai cxx_name] == std::optional<std::string>("other.plist"));
		OO_CHECK([ai cxx_state] == std::optional<std::string>("FROZEN"));
		OO_CHECK([ai owner] == nil);

		AI *plain = [[[AI alloc] cxx_initWithStateMachine:std::nullopt andState:std::nullopt] autorelease];
		OO_CHECK([plain cxx_name] == std::optional<std::string>("<no AI>"));
		OO_CHECK(![plain cxx_state].has_value());
	}
}


// After the conversion: the C++ AI answers as the facade did, the facade is its one Objective-C
// object both ways, and a C++ AI whose facade is gone is never given another (ADR-0056,
// amendment oo-o89 item 2).
OO_TEST(facadeContract)
{
	SetUp();
	oo::Ref<cxx::AI> kept;
	@autoreleasepool
	{
		TestShip *ship = NewShip(10);
		AI *ai = [[AI alloc] init];
		ship->_ai = ai;
		[ai setOwner:Part(ship)];
		cxx::AI *cxxAI = oo::ToCxx(ai);
		OO_CHECK(cxxAI != nullptr);
		OO_CHECK(oo::ToObjC(cxxAI) == ai);
		OO_CHECK(oo::ToObjC(cxxAI) == oo::ToObjC(cxxAI));
		OO_CHECK(cxxAI->owner() == Part(ship));

		// The C++ calls run the machine the facade reports; the actions see the facade running.
		cxxAI->setStateMachine("test.plist", "test.js");
		OO_CHECK([ai cxx_state] == std::optional<std::string>("ATTACK"));
		OO_CHECK(cxxAI->state() == std::optional<std::string>("ATTACK"));
		OO_CHECK(ship->_runningAIs.size() == 2);
		cxxAI->message("FOO");
		OO_CHECK([ai pendingMessages] == std::set<std::string>({ "FOO" }));
		OO_CHECK(cxxAI->getPendingMessages() == [ai pendingMessages]);
		OO_CHECK(cxxAI->getNextThinkTime() == [ai nextThinkTime]);
		OO_CHECK(cxxAI->getThinkTimeInterval() == [ai thinkTimeInterval]);
		OO_CHECK(cxxAI->descriptionComponents() == [ai cxx_descriptionComponents]);
		OO_CHECK(cxx::AI::currentlyRunningAI() == nullptr);

		// A deferred call holds the facade, so the C++ AI behind it too.
		cxxAI->setState("GLOBAL", 1.0);
		OO_CHECK(gDeferred.size() == 1);
		FireDeferredCalls();
		OO_CHECK(cxxAI->state() == std::optional<std::string>("ATTACK"));

		kept = oo::Ref<cxx::AI>(cxxAI);
		[ai release];
	}
	// Its facade gone, the C++ object has none, and is not given a new one.
	OO_CHECK(kept->name() == std::optional<std::string>("test.plist"));
	@autoreleasepool
	{
		OO_CHECK(oo::ToObjC(kept.get()) == nil);
		oo::Ref<cxx::AI> bare = oo::makeRef<cxx::AI>();
		OO_CHECK(oo::ToObjC(bare.get()) == nil);
		OO_CHECK(bare->name() == std::optional<std::string>("<no AI>"));
	}

	AI *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::AI *>(nullptr)) == nil);
	OO_CHECK(![none hasSuspendedStateMachines]);
}


OO_TEST_MAIN()
