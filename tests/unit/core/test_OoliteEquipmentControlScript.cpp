/*	test_OoliteEquipmentControlScript.cpp

	The equipment-control world script (Resources/Scripts/oolite-equipment-control.js) on the game's
	JavaScript engine (QuickJS-ng, through its own API), with the two game objects it reads stood in
	by plain JS objects (EquipmentInfo.infoForKey and player.ship.removeEquipment).

	Pins upstream OoliteProject #369: adding an item removes an installed item that lists it as
	incompatible, but no longer "removes" an incompatible item that was installed once and has
	already been removed (its $equipmentEnabled entry is 0, not absent).
*/

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

#include <quickjs.h>

namespace {

int gFailures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); ++gFailures; } } while (0)

// The script, found from this file's directory or the working directory upwards.
std::string ScriptSource()
{
	namespace fs = std::filesystem;
	const fs::path rel = fs::path("Resources") / "Scripts" / "oolite-equipment-control.js";
	for (const fs::path &start : {fs::path(__FILE__).parent_path(), fs::current_path()})
	{
		std::error_code ec;
		fs::path dir = fs::absolute(start, ec);
		for (int i = 0; i < 8 && !dir.empty(); i++)
		{
			if (fs::exists(dir / rel, ec))
			{
				std::ifstream in(dir / rel, std::ios::binary);
				std::stringstream text;
				text << in.rdbuf();
				return text.str();
			}
			if (dir == dir.parent_path())  break;
			dir = dir.parent_path();
		}
	}
	return std::string();
}

// Evaluates JS in the global scope; true when it ran without an exception and, when asked,
// gives the result's truth value in *result.
bool Eval(JSContext *cx, const std::string &code, bool *result = nullptr)
{
	JSValue rval = JS_Eval(cx, code.c_str(), code.size(), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(rval))
	{
		std::printf("JS exception evaluating: %.120s\n", code.c_str());
		JS_FreeValue(cx, JS_GetException(cx));
		return false;
	}
	bool ok = true;
	if (result != nullptr)
	{
		const int truth = JS_ToBool(cx, rval);
		if (truth < 0)
		{
			JS_FreeValue(cx, JS_GetException(cx));
			ok = false;
		}
		else
		{
			*result = truth != 0;
		}
	}
	JS_FreeValue(cx, rval);
	return ok;
}

// Evaluates an expression that must run and be true.
#define CHECK_JS(cx, code) do { bool truth_ = false; if (!(Eval((cx), (code), &truth_) && truth_)) { std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, code); ++gFailures; } } while (0)

}	// namespace


int main()
{
	const std::string script = ScriptSource();
	CHECK(!script.empty());
	if (script.empty())  return 1;

	// A QuickJS-ng context has the standard classes from the start.
	JSRuntime *rt = JS_NewRuntime();
	JSContext *cx = rt != nullptr ? JS_NewContext(rt) : nullptr;
	CHECK(rt != nullptr && cx != nullptr);
	if (cx == nullptr)  return 1;

	// The stand-ins: EQ_A and EQ_B are incompatible with each other; removals are recorded.
	CHECK(Eval(cx,
		"var removed = [];\n"
		"var EquipmentInfo = { infoForKey: function (key) {\n"
		"	return { EQ_A: { equipmentKey: 'EQ_A', incompatibleEquipment: ['EQ_B'] },\n"
		"	         EQ_B: { equipmentKey: 'EQ_B', incompatibleEquipment: ['EQ_A'] },\n"
		"	         EQ_C: { equipmentKey: 'EQ_C' } }[key]; } };\n"
		"var player = { ship: { removeEquipment: function (key) { removed.push(key); } } };\n"
		"var ws = {};\n"));
	// The world script runs with its script object as `this`, as the engine runs a world script.
	CHECK(Eval(cx, "(function () {\n" + script + "\n}).call(ws);"));
	CHECK(Eval(cx, "ws.$started = true;"));

	// Installed, then removed: adding the incompatible item removes nothing (#369).
	CHECK_JS(cx, "ws.equipmentAdded('EQ_A'); ws.equipmentRemoved('EQ_A'); ws.equipmentAdded('EQ_B'); removed.join(',') === ''");
	CHECK_JS(cx, "ws.$equipmentEnabled['EQ_A'] === 0 && ws.$equipmentEnabled['EQ_B'] === 1");

	// Installed and still enabled: adding the incompatible item removes it.
	CHECK_JS(cx, "removed = []; ws.$equipmentEnabled = {}; ws.equipmentAdded('EQ_A'); ws.equipmentAdded('EQ_B'); removed.join(',') === 'EQ_A'");

	// A compatible item removes nothing.
	CHECK_JS(cx, "removed = []; ws.$equipmentEnabled = {}; ws.equipmentAdded('EQ_A'); ws.equipmentAdded('EQ_C'); removed.join(',') === ''");

	JS_FreeContext(cx);
	JS_FreeRuntime(rt);

	if (gFailures == 0)  std::printf("test_OoliteEquipmentControlScript: OK\n");
	return gFailures == 0 ? 0 : 1;
}
