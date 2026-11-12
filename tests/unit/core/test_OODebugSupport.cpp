/*	test_OODebugSupport.mm
        Unit tests for the debug support's start-up
   (src/Core/Debug/OODebugSupport.h), a Debug module file with no class.

        OOInitDebugSupport() reads debugConfig.plist. When the debug OXP's
   beacon file is installed it makes the TCP console client for console-host (a
   string, or a number's string value) and console-port, and tells the monitor
   it is not using a plug-in controller; the console is activated when the
   client connected, or when always-load-debug-console is set, and then the
        monitor is given the debugger (nil if none) and the JavaScript engine
   enables the debugger statement. The stand-ins are the monitor's and client's
   C++ members that the debug support calls (the client is the C++ debugger
   itself).

        What it reaches would bring the game into the link, so this file stands
   in for it: the resource manager (the configuration and the beacon's path),
   the debug monitor, the TCP console client (which records where it was asked
   to connect, and can be made to fail) and the JavaScript engine. Run:
   tests/run.sh unit
*/

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "OODebugMonitor.h"
#include "OODebugSupport.h"
#include "OODebugTCPConsoleClient.h"
#include "oo_test.hpp"
#include "oofnd/PList.hpp"

// MARK: What the rest of the game provides
// ---------------------------------------------------------

namespace {

struct Record {
  oo::PList configuration;                // debugConfig.plist
  std::optional<std::string> beaconPath;  // DebugOXPLocatorBeacon.magic
  bool clientFails = false;
  std::vector<std::pair<std::optional<std::string>, uint16_t>> clientsMade;
  const void* lastClient = nullptr;  // the client made
  std::vector<bool> usingPlugInController;
  std::vector<const void*> debuggersSet;
  int debuggerStatementsEnabled = 0;
};

Record sRecord;

const bool kTrue = (1 == 1);  // a Bool node (OOCocoa.h defines true as 1)

}  // namespace

#include "ResourceManager.h"  // OOResourceMergeMode, as the stand-in declared it

// C++ definitions of the ResourceManager statics the code under test calls,
// with the stand-in's answers.
oo::PList ResourceManager::dictionaryFromFilesNamed(
    const std::string& fileName, const std::optional<std::string>& folderName,
    OOResourceMergeMode mergeMode, bool useCache) {
  if (fileName == "debugConfig.plist" && folderName == "Config" &&
      mergeMode == OOResourceMergeMode::kBasic && !useCache)
    return sRecord.configuration;
  return oo::PList();
}

std::optional<std::string> ResourceManager::pathForFileNamed(
    const std::string& fileName, const std::optional<std::string>& folderName) {
  // The beacon is looked for in the folder named "nil" (sic).
  if (fileName == "DebugOXPLocatorBeacon.magic" && folderName == "nil")
    return sRecord.beaconPath;
  return std::nullopt;
}

// The engine (OOJavaScriptEngine.h), declared with the header's names and
// signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine {
 public:
  static OOJavaScriptEngine* sharedEngine();
  void enableDebuggerStatement();
};

OOJavaScriptEngine* OOJavaScriptEngine::sharedEngine() {
  static OOJavaScriptEngine* engine = new OOJavaScriptEngine;
  return engine;
}

void OOJavaScriptEngine::enableDebuggerStatement() {
  sRecord.debuggerStatementsEnabled++;
}

// The C++ monitor's and TCP client's members that the debug support calls; the
// client's debugger interface members are never reached (the monitor is a
// stand-in). The engine-monitor members, which give the C++ monitor its vtable
// (they are virtual); never reached here.
void OODebugMonitor::jsEngine(::OOJavaScriptEngine*, JSContext*,
                              const std::string&,
                              const std::optional<std::string>&, unsigned,
                              unsigned, bool, const std::string&) {}
void OODebugMonitor::jsEngine(::OOJavaScriptEngine*, JSContext*,
                              const std::string&,
                              const std::optional<std::string>&) {}
// The monitor's JS glue and description, also virtual; never reached here.
JSValue OODebugMonitor::jsValueInContext(JSContext*) { return JS_UNDEFINED; }
void OODebugMonitor::clearJSSelf(JSValueConst) {}
std::string OODebugMonitor::className() const { return "OODebugMonitor"; }
std::string OODebugMonitor::description() const { return "<OODebugMonitor>"; }

OODebugMonitor* OODebugMonitor::sharedDebugMonitor() {
  static OODebugMonitor* monitor = nullptr;
  if (monitor == nullptr) monitor = oo::makeRef<OODebugMonitor>().leakRef();
  return monitor;
}

bool OODebugMonitor::setDebugger(OODebuggerInterface* debugger) {
  sRecord.debuggersSet.push_back(debugger);
  return debugger != nullptr;
}

void OODebugMonitor::setUsingPlugInController(bool flag) {
  sRecord.usingPlugInController.push_back(flag);
}

oo::Ref<OODebugTCPConsoleClient> OODebugTCPConsoleClient::clientWithAddress(
    const std::optional<std::string>& address, uint16_t port) {
  sRecord.clientsMade.emplace_back(address, port);
  if (sRecord.clientFails) return oo::Ref<OODebugTCPConsoleClient>();
  oo::Ref<OODebugTCPConsoleClient> client =
      oo::adopt(new OODebugTCPConsoleClient);
  sRecord.lastClient = client.get();
  return client;
}

OODebugTCPConsoleClient::~OODebugTCPConsoleClient() {}

bool OODebugTCPConsoleClient::connectDebugMonitor(OODebugMonitor*,
                                                  std::optional<std::string>*) {
  return true;
}
void OODebugTCPConsoleClient::disconnectDebugMonitor(
    OODebugMonitor*, const std::optional<std::string>&) {}
void OODebugTCPConsoleClient::debugMonitor(OODebugMonitor*, const std::string&,
                                           const std::optional<std::string>&,
                                           NSRange) {}
void OODebugTCPConsoleClient::debugMonitorClearConsole(OODebugMonitor*) {}
void OODebugTCPConsoleClient::debugMonitorShowConsole(OODebugMonitor*) {}
void OODebugTCPConsoleClient::debugMonitor(OODebugMonitor*, const oo::PList&) {}
void OODebugTCPConsoleClient::debugMonitor(OODebugMonitor*, const oo::PList&,
                                           const std::string&) {}
std::string OODebugTCPConsoleClient::description() const {
  return "<OODebugTCPConsoleClient>";
}

namespace {

void Reset(oo::PList::Dict configuration, bool beacon) {
  sRecord = Record();
  sRecord.configuration = oo::PList(std::move(configuration));
  if (beacon)
    sRecord.beaconPath = "AddOns/Debug.oxp/DebugOXPLocatorBeacon.magic";
}

}  // namespace

// MARK: Tests
// -------------------------------------------------------------------------------------

// No debug OXP and no always-load: nothing is set up.
OO_TEST(nothingWithoutTheDebugOXP) {
  {
    Reset({}, false);
    OOInitDebugSupport();
    OO_CHECK(sRecord.clientsMade.empty());
    OO_CHECK(sRecord.usingPlugInController.empty());
    OO_CHECK(sRecord.debuggersSet.empty());
    OO_CHECK(sRecord.debuggerStatementsEnabled == 0);
  }
}

// always-load-debug-console without the OXP: the console with no debugger.
OO_TEST(alwaysLoadWithoutTheDebugOXP) {
  {
    Reset({{"always-load-debug-console", oo::PList(kTrue)}}, false);
    OOInitDebugSupport();
    OO_CHECK(sRecord.clientsMade.empty());
    OO_CHECK(sRecord.debuggersSet.size() == 1 &&
             sRecord.debuggersSet[0] == nullptr);
    OO_CHECK(sRecord.debuggerStatementsEnabled == 1);
  }
}

// The debug OXP: a TCP client for the configured host and port becomes the
// monitor's debugger.
OO_TEST(theTCPConsoleClient) {
  {
    Reset({{"console-host", oo::PList(std::string("console.example"))},
           {"console-port", oo::PList(8564)}},
          true);
    OOInitDebugSupport();
    OO_CHECK(sRecord.clientsMade.size() == 1);
    if (sRecord.clientsMade.size() == 1) {
      OO_CHECK(sRecord.clientsMade[0].first ==
               std::optional<std::string>("console.example"));
      OO_CHECK(sRecord.clientsMade[0].second == 8564);
    }
    OO_CHECK(sRecord.usingPlugInController == std::vector<bool>{false});
    OO_CHECK(sRecord.lastClient != nullptr);
    OO_CHECK(sRecord.debuggersSet.size() == 1 &&
             sRecord.debuggersSet[0] == sRecord.lastClient);
    OO_CHECK(sRecord.debuggerStatementsEnabled == 1);
  }
}

// No host: the client's default (nullopt), and port 0; a number is read as its
// string value; anything else is no host.
OO_TEST(theHostSetting) {
  {
    Reset({}, true);
    OOInitDebugSupport();
    OO_CHECK(sRecord.clientsMade.size() == 1 &&
             !sRecord.clientsMade[0].first.has_value() &&
             sRecord.clientsMade[0].second == 0);

    Reset({{"console-host", oo::PList(42)}}, true);
    OOInitDebugSupport();
    OO_CHECK(sRecord.clientsMade.size() == 1 &&
             sRecord.clientsMade[0].first == std::optional<std::string>("42"));

    Reset({{"console-host",
            oo::PList(oo::PList::Array{oo::PList(std::string("x"))})}},
          true);
    OOInitDebugSupport();
    OO_CHECK(sRecord.clientsMade.size() == 1 &&
             !sRecord.clientsMade[0].first.has_value());
  }
}

// The client cannot connect: no console, unless always-load is set, and then no
// debugger.
OO_TEST(theClientFails) {
  {
    Reset({{"console-host", oo::PList(std::string("127.0.0.1"))}}, true);
    sRecord.clientFails = true;
    OOInitDebugSupport();
    OO_CHECK(sRecord.clientsMade.size() == 1);
    OO_CHECK(sRecord.usingPlugInController == std::vector<bool>{false});
    OO_CHECK(sRecord.debuggersSet.empty());
    OO_CHECK(sRecord.debuggerStatementsEnabled == 0);

    Reset({{"always-load-debug-console", oo::PList(kTrue)}}, true);
    sRecord.clientFails = true;
    OOInitDebugSupport();
    OO_CHECK(sRecord.debuggersSet.size() == 1 &&
             sRecord.debuggersSet[0] == nullptr);
    OO_CHECK(sRecord.debuggerStatementsEnabled == 1);
  }
}

OO_TEST_MAIN()
