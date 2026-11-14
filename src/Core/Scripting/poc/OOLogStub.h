/*

OOLogStub.h (QuickJS-ng proof of concept)

Logging for the QuickJS-ng proof-of-concept harness: the game's oo::log
logger (OO_LOG), with every message class shown and each line printed in
Oolite's log format and recorded so tests can check what was logged.

*/

#pragma once

#include <string>
#include <vector>

// Show every message class and record each line; call before logging.
void OOPocInstallLogging(void);

const std::vector<std::string>& OOPocRecordedLogMessages(void);
void OOPocClearRecordedLogMessages(void);
