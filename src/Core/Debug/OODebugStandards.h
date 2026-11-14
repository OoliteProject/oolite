/*

OODebugStandards.h

OXP strictness warnings for errors and deprecated content


Copyright (C) 2014

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
#pragma once

#include "OOFoundation.h"

#ifdef __cplusplus
#include "oofnd/StdLib.hpp"

// Warn/exit if deprecated functionality used
void cxx_OOStandardsDeprecated(const std::string& message);

// Warn/exit if an OXP error is detected
void cxx_OOStandardsError(const std::string& message);
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Return true if in standard enforcing mode
// Always false in release builds
// This will *not* exit in "exit on error" mode
bool OOEnforceStandards(void);

void OOSetStandardsForOXPVerifierMode(void);

#ifdef __cplusplus
}
#endif

/*	TRANSITIONAL: the Foundation-typed API forwarding to the cxx_ functions
   above, so unmigrated callers compile unchanged. Callers move to the cxx_
   API; the bridge then goes.
*/
