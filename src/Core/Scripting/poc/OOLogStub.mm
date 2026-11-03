/*

OOLogStub.mm

Minimal OOLogging implementation for the QuickJS-ng proof-of-concept
harness. Messages are printed in Oolite's log format and recorded so tests
can check what was logged.

*/

#import "OOLogStub.h"

#include "oofnd/Log.hpp"

#include <cstdio>
#include <string_view>

static std::vector<std::string> sRecordedMessages;

static void RecordingSink(std::string_view line)
{
    sRecordedMessages.emplace_back(line);
    fwrite(line.data(), 1, line.size(), stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

void OOPocInstallLogging(void)
{
    oo::log::Logger& logger = oo::log::logger();
    oo::log::Options options;
    options.showClass = true; // "[class]: message", as the tests expect
    logger.setOptions(options);
    logger.setSink(RecordingSink);
    logger.setInitialized(true);
}

const std::vector<std::string>& OOPocRecordedLogMessages(void)
{
    return sRecordedMessages;
}

void OOPocClearRecordedLogMessages(void)
{
    sRecordedMessages.clear();
}
