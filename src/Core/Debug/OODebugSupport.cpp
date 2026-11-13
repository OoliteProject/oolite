/*

OODebugSupport.m


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifdef OO_DEBUG_MONITOR_ENABLED

#include "OODebugSupport.h"

#include "GameController.h"
#include "OODebugMonitor.h"
#include "OODebugTCPConsoleClient.h"
#include "OOJavaScriptEngine.h"
#include "ResourceManager.h"
#include "oofnd/Log.hpp"
#include "oofnd/PListGet.hpp"

void OOInitDebugSupport() {
  std::optional<std::string> debugOXPPath;
  oo::PList debugSettings;
  std::optional<std::string> consoleHost;
  unsigned short consolePort = 0;
  std::shared_ptr<OODebuggerInterface> debugger;
  bool activateDebugConsole = false;

  // Load debug settings.
  debugSettings = ResourceManager::dictionaryFromFilesNamed(
      "debugConfig.plist", "Config", OOResourceMergeMode::kBasic, false);

  // Check that the debug OXP is installed. If not, we don't enable debug
  // support.
  debugOXPPath =
      ResourceManager::pathForFileNamed("DebugOXPLocatorBeacon.magic", "nil");
  if (debugOXPPath.has_value()) {
    // The debug plug-in (Mac Contents/PlugIns/Debug.bundle) is never loaded on
    // the platforms built (the loader answered nil everywhere), so its
    // controller's debugger branch is gone.

    // oo_stringForKey: a string, or a number's string value; nil for anything
    // else.
    const oo::PList* consoleHostValue =
        debugSettings.get<oo::PList>("console-host");
    if (consoleHostValue != nullptr &&
        (consoleHostValue->isString() || consoleHostValue->isNumber())) {
      consoleHost = debugSettings.get<std::string>("console-host");
    }
    consolePort = debugSettings.get<unsigned short>("console-port");

    // Use the TCP debugger connection.
    {
      // The client; null when it cannot connect.
      debugger =
          OODebugTCPConsoleClient::clientWithAddress(consoleHost, consolePort);
      OODebugMonitor::sharedDebugMonitor()->setUsingPlugInController(false);
    }

    activateDebugConsole = (debugger != nullptr);
  }

  if (!activateDebugConsole) {
    activateDebugConsole = debugSettings.get<bool>("always-load-debug-console");
  }

  if (activateDebugConsole) {
    // Set up monitor and register debugger, if any.
    OODebugMonitor::sharedDebugMonitor()->setDebugger(debugger.get());
    OOJavaScriptEngine::sharedEngine()->enableDebuggerStatement();
  }
}

#endif /* OO_DEBUG_MONITOR_ENABLED */
