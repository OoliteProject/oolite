/*

main.cpp

Test driver for the QuickJS-ng proof of concept (issue #580). Loads scripts
from the tests directory given on the command line, checks their behaviour
and the engine's error reporting, then destroys the runtime; debug builds of
QuickJS abort if any JS object has leaked.

Usage: oojs-quickjs-poc <tests directory>

*/

#include <chrono>
#include <cstdio>
#include <ctime>
#include <format>
#include <optional>
#include <string>

#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "OOLogStub.h"
#include "legacy_random.h"
#include "oofnd/String.hpp"

namespace {
unsigned sFailures = 0;
unsigned sChecks = 0;

void Check(bool condition, const std::string& description) {
  sChecks++;
  if (!condition) {
    sFailures++;
    fprintf(stdout, "FAIL: %s\n", description.c_str());
  } else {
    fprintf(stdout, "ok:   %s\n", description.c_str());
  }
  fflush(stdout);
}

bool LogContains(const std::string& text) {
  for (const std::string& line : OOPocRecordedLogMessages()) {
    if (line.find(text) != std::string::npos) return true;
  }
  return false;
}

double Now() {
  return std::chrono::duration<double>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

std::string Describe(const std::optional<std::string>& string) {
  return string.value_or("(null)");
}

// Call a script method and convert its result to a string; nullopt if the call
// failed.
std::optional<std::string> CallForString(OOJSScript* script,
                                         const std::string& method) {
  if (script == nullptr) return std::nullopt;

  JSContext* context = OOJSAcquireContext();
  JSValue result;
  std::optional<std::string> string;

  if (script->callMethodNamed(method, NULL, 0, &result)) {
    string = cxx_OOStringFromJSValueEvenIfNull(context, result);
    JS_FreeValue(context, result);
  }
  return string;
}

void RunBehaviourTests(const std::string& testDir,
                       const std::string& fileName) {
  oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(
      oo::str::appendingPathComponent(testDir, fileName));
  Check(script != nullptr, fileName + " loads");

  std::optional<std::string> failures = CallForString(script.get(), "runTests");
  Check(failures == "0", fileName + " behaviour tests pass (failures: " +
                             Describe(failures) + ")");
}

void RunScopeTests(const std::string& testDir) {
  oo::Ref<OOJSScript> scriptA = OOJSScript::scriptWithPath(
      oo::str::appendingPathComponent(testDir, "scope_a.js"));
  oo::Ref<OOJSScript> scriptB = OOJSScript::scriptWithPath(
      oo::str::appendingPathComponent(testDir, "scope_b.js"));
  Check(scriptA != nullptr && scriptB != nullptr,
        "scripts with the same top-level const and var names both load");
  Check(scriptA != nullptr && scriptA->displayName() == "poc_scope_a 1.2",
        "script name and version read after initial run");

  std::optional<std::string> result = CallForString(scriptA.get(), "startUp");
  const std::string expected =
      "1|ab..|poc_scope_a|1.2|a|a|undefined|late|strict|poc_scope_a";
  Check(result == expected,
        "bare names resolve through the script object, strict mode kept (got " +
            Describe(result) + ")");

  result = CallForString(scriptB.get(), "check");
  Check(result == "bbpoc_scope_b",
        "second script sees its own top-level declarations (got " +
            Describe(result) + ")");
}

void RunErrorTests(const std::string& testDir) {
  OOPocClearRecordedLogMessages();
  oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(
      oo::str::appendingPathComponent(testDir, "runtime_error.js"));
  Check(CallForString(script.get(), "startUp") == std::nullopt,
        "handler that throws reports failure");
  Check(LogContains("[script.javaScript.exception.ReferenceError]: ***** "
                    "JavaScript exception (poc_runtime_error): ReferenceError: "
                    "undefinedFunction is not defined"),
        "runtime exception logged with class, script name and message");
  Check(LogContains("runtime_error.js, line 9."),
        "runtime exception logged with correct file and line");

  OOPocClearRecordedLogMessages();
  script = OOJSScript::scriptWithPath(
      oo::str::appendingPathComponent(testDir, "syntax_error.js"));
  Check(script == nullptr, "script with syntax error fails to load");
  Check(LogContains("[script.javaScript.exception.SyntaxError]"),
        "syntax error logged");
  Check(LogContains("syntax_error.js, line "),
        "syntax error logged with file and line");
}

void RunTimeLimiterTests(const std::string& testDir) {
  OOPocClearRecordedLogMessages();
  oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(
      oo::str::appendingPathComponent(testDir, "runaway.js"));

  double start = Now();
  std::optional<std::string> result = CallForString(script.get(), "startUp");
  double elapsed = Now() - start;

  Check(result == std::nullopt, "infinite loop is terminated");
  Check(elapsed >= 1.0 && elapsed < 3.0,
        std::format("termination after the 1 second limit (took {:.2f} s)",
                    elapsed));
  Check(LogContains("Script \"poc_runaway\" ran for"), "termination logged");
  Check(!LogContains("JavaScript exception"),
        "termination not also reported as an exception");
  Check(CallForString(script.get(), "ping") == "pong",
        "engine still usable after termination");
}

// Upstream #768's QuickJS-ng patch: strict code may create a property on a
// primitive without a TypeError, as under SpiderMonkey 1.8.5.
void RunPrimitivePropertyTests(const std::string& testDir) {
  OOPocClearRecordedLogMessages();
  oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(
      oo::str::appendingPathComponent(testDir, "primitive_property.js"));
  Check(script != nullptr, "primitive_property.js loads");

  std::optional<std::string> result = CallForString(script.get(), "startUp");
  Check(result == "undefined|undefined|undefined|text|42|true",
        "strict code ignores properties created on primitives (got " +
            Describe(result) + ")");
  Check(!LogContains("JavaScript exception"),
        "no TypeError for a property on a primitive");
}
}  // namespace

int main(int argc, const char* argv[]) {
  if (argc < 2) {
    fprintf(stderr, "Usage: %s <tests directory>\n", argv[0]);
    return 2;
  }

  OOPocInstallLogging();
  const std::string testDir = argv[1];

  // As the game does at startup; an unseeded RANROT returns 0 forever.
  ranrot_srand(static_cast<uint32_t>(time(NULL)));
  OOJavaScriptEngine* engine = OOJavaScriptEngine::sharedEngine();

  // Each group's scripts are released when it returns, before shutdown.
  RunBehaviourTests(testDir, "vector.js");
  RunBehaviourTests(testDir, "quaternion.js");
  RunScopeTests(testDir);
  RunErrorTests(testDir);
  RunTimeLimiterTests(testDir);
  RunPrimitivePropertyTests(testDir);

  std::size_t leaked = engine->shutDown();
  Check(leaked == 0,
        std::format("runtime destroyed with no leaked objects ({} alive)",
                    static_cast<unsigned long>(leaked)));

  fprintf(stdout, "\n%u checks, %u failures\n", sChecks, sFailures);
  return sFailures == 0 ? 0 : 1;
}
