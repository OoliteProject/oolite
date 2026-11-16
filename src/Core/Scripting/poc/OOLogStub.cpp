/*

OOLogStub.cpp (QuickJS-ng proof of concept)

Minimal OOLogging implementation for the QuickJS-ng proof-of-concept
harness. Messages are printed in Oolite's log format and recorded so tests
can check what was logged.

*/

#include "OOLogStub.h"

#include <cstdio>
#include <string_view>

#include "oofnd/Log.hpp"

namespace {
std::vector<std::string> sRecordedMessages;

void RecordingSink(std::string_view line) {
  sRecordedMessages.emplace_back(line);
  std::fwrite(line.data(), 1, line.size(), stdout);
  std::fputc('\n', stdout);
  std::fflush(stdout);
}
}  // namespace

void OOPocInstallLogging() {
  oo::log::Logger& logger = oo::log::logger();
  oo::log::Options options;
  options.showClass = true;  // "[class]: message", as the tests expect
  logger.setOptions(options);
  logger.setSink(RecordingSink);
  logger.setInitialized(true);
}

const std::vector<std::string>& OOPocRecordedLogMessages() {
  return sRecordedMessages;
}

void OOPocClearRecordedLogMessages() { sRecordedMessages.clear(); }
