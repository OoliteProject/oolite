/*	test_OOJSTimeLimiter.mm
        Unit tests for the script time limiter: start/stop, pause/resume, and
   the interrupt handler that stops a script which runs too long
   (OOJSEngineCore.h, implemented in src/Core/Scripting/OOJavaScriptEngine.mm,
   as #768 does).

        These cases were test_OOJSEngineTimeManagement's, when the limiter and
   its watchdog thread lived in OOJSEngineTimeManagement. The limiter is now the
   engine's, so the test links every game object but main's
   (tests/unit/core/meson.build entry ['*']), points the user's directories at a
        scratch folder and runs the real engine. The expectations cover the
   limiter's limit through nesting, an extra stop, pause and resume; and the
        engine stopping an endless script, logging the running script's name,
   after which scripts run again. Run: tests/run.sh unit
*/

#include <process.h>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <thread>
#include <vector>

#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "oo_test.hpp"
#include "oofnd/AutoreleaseScope.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

#define StartLimiter(limit) OOJSStartTimeLimiterWithTimeLimit(limit)
#define StopLimiter() OOJSStopTimeLimiter()

namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;
std::vector<std::string> sLogLines;

void SleepMs(int ms) {
  std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

void WriteText(const stdfs::path& path, const std::string& text) {
  stdfs::create_directories(path.parent_path());
  OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()),
                             oo::fs::WriteMode::kDirect)
               .has_value());
}

// The scratch home and game folder, made once, before the cache manager and the
// engine exist.
void SetUp() {
  if (!sRoot.empty()) return;
  sRoot = stdfs::temp_directory_path() /
          ("oo-test-jstimelimiter-" +
           std::to_string(static_cast<unsigned long>(::_getpid())));
  stdfs::remove_all(sRoot);
  stdfs::create_directories(sRoot);
  OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
  stdfs::current_path(sRoot);
  WriteText(sRoot / "Resources" / "Info-gnustep.plist",
            "{ CFBundleVersion = \"9.9.9-test\"; }");
  // In a scope of its own, as the game's main() has one: what starting the
  // engine autoreleases (an OOJSValue, which observes the engine's reset) is
  // released here, not at process exit, after the notification centre has gone.
  {
    oo::AutoreleaseScope pool;  // was @autoreleasepool
    (void)OOJavaScriptEngine::sharedEngine();
  }
}

// Evaluates source in the engine's context; true if it ran to completion. A
// pending exception is cleared.
bool Evaluate(const char* source, const char* fileName) {
  JSContext* context = OOJSAcquireContext();
  JSValue result = JS_Eval(context, source, std::strlen(source), fileName,
                           JS_EVAL_TYPE_GLOBAL);
  const bool completed = !JS_IsException(result);
  JS_FreeValue(context, result);
  if (!completed) JS_FreeValue(context, JS_GetException(context));
  OOJSRelinquishContext(context);
  return completed;
}

}  // namespace

// MARK: Tests
// -------------------------------------------------------------------------------------

OO_TEST(limiter) {
  SetUp();
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 0.0);
  StartLimiter(0.0);  // the default limit
  const double defaultLimit = OOJSGetTimeLimiterLimit();
  OO_CHECK(defaultLimit == 0.2 ||
           defaultLimit == 1.0);  // debug-limiter builds keep a short leash
  StartLimiter(5.0);              // nested: the outermost limit stays
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), defaultLimit);
  StopLimiter();
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), defaultLimit);
  StopLimiter();
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 0.0);

  // A stop too many is logged and ignored: the next start is outermost again.
  StopLimiter();
  StartLimiter(3.0);
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 3.0);
  OOJSSetTimeLimiterLimit(4.5);
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 4.5);
  StopLimiter();
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 0.0);
}

OO_TEST(pauseAndResume) {
  SetUp();
  StartLimiter(10.0);
  OOJSPauseTimeLimiter();
  OOJSPauseTimeLimiter();  // nested: only the outermost pause counts
  SleepMs(60);
  OOJSResumeTimeLimiter();
  OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 10.0);
  OOJSResumeTimeLimiter();
  const double extended = OOJSGetTimeLimiterLimit();
  OO_CHECK(extended > 10.04 &&
           extended < 11.0);  // the paused time is added to the limit
  StopLimiter();
}

OO_TEST(watchdog) {
  // The engine stops a script that runs past its limit (QuickJS-ng's interrupt
  // handler, which replaced the watchdog thread).
  SetUp();
  {
    oo::AutoreleaseScope pool;  // was @autoreleasepool
    const stdfs::path scriptPath = sRoot / "running" / "running.js";
    WriteText(scriptPath, "this.name = \"test script\";\n");
    const std::shared_ptr<OOJSScript> script =
        OOJSScript::scriptWithPath(scriptPath.generic_string(), oo::PList());
    OO_CHECK(script != nullptr);
    OOJSScript::pushScript(script.get());  // the script named in the log line

    oo::log::logger().setSink(
        [](std::string_view line) { sLogLines.emplace_back(line); });
    oo::log::logger().setInitialized(true);

    StartLimiter(0.05);
    OOJSResetTimeLimiter();
    const auto start = std::chrono::steady_clock::now();
    const bool completed = Evaluate("for (;;) {}", "endless.js");
    const double seconds =
        std::chrono::duration<double>(std::chrono::steady_clock::now() - start)
            .count();
    StopLimiter();
    OOJSResetTimeLimiter();
    oo::log::logger().setSink(nullptr);
    OOJSScript::popScript(script.get());

    OO_CHECK(!completed);
    OO_CHECK(seconds < 10.0);
    bool logged = false;
    int stackDumps = 0;
    for (const std::string& line : sLogLines) {
      if (line.find("Script \"test script\" ran for ") != std::string::npos &&
          line.find(" seconds and has been terminated.") != std::string::npos)
        logged = true;
      // OOJSDumpStack()'s entry: the stack's frames, or none.
      if (line.rfind("    at ", 0) == 0 ||
          line.find("<no JavaScript stack>") != std::string::npos)
        stackDumps++;
    }
    OO_CHECK(logged);
#ifdef OO_DEBUG_MONITOR_ENABLED
    OO_CHECK_EQ(stackDumps, 1);  // the engine dumps the stack (OOJSDumpStack)
#else
    (void)stackDumps;
#endif

    // After a reset, scripts run again.
    StartLimiter(0.0);
    OO_CHECK(Evaluate("1 + 1", "quick.js"));
    StopLimiter();
  }
}

OO_TEST(cleanUp) {
  stdfs::current_path(stdfs::temp_directory_path());
  std::error_code ignored;
  stdfs::remove_all(sRoot, ignored);
  OO_CHECK(true);
}

OO_TEST_MAIN()
