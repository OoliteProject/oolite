/*

OODebugStandards.m

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

#include "OODebugStandards.h"
#include "oofnd/Log.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "GameController.h"

#ifdef NDEBUG
// in release mode, stubs
void cxx_OOStandardsDeprecated(const std::string &message) {}
void cxx_OOStandardsError(const std::string &message) {}
bool OOEnforceStandards() { return false; }
void OOSetStandardsForOXPVerifierMode() {}

#else

void OOStandardsSetup(void);
namespace {

void OOStandardsInternal(const std::string &type, const std::string &message);

}	// namespace

namespace {

bool sSetup = false;

}	// namespace

typedef enum {
// do nothing (equivalent to release build)
	STANDARDS_ENFORCEMENT_OFF = 0,
// warn in log but otherwise do nothing
	STANDARDS_ENFORCEMENT_WARN,
// warn in log, block use of deprecated or error items
	STANDARDS_ENFORCEMENT_ENFORCE,
// note in log, then exit if deprecated or error condition occurs
	STANDARDS_ENFORCEMENT_QUIT
} OOStandardsEnforcement;

static OOStandardsEnforcement sEnforcement = STANDARDS_ENFORCEMENT_WARN;


void OOStandardsSetup()
{
	if (sSetup) 
	{
		return;
	}
	oo::Defaults &prefs = oo::Defaults::standard();
	const oo::PList enforce = prefs.object("enforce-oxp-standards");
	int s = oo::PListGet<int>::from(enforce.isNull() ? nullptr : &enforce, STANDARDS_ENFORCEMENT_WARN);
	if (s < STANDARDS_ENFORCEMENT_OFF)
	{
		s = STANDARDS_ENFORCEMENT_OFF;
	}
	else if (s > STANDARDS_ENFORCEMENT_QUIT)
	{
		s = STANDARDS_ENFORCEMENT_QUIT;
	}
	sEnforcement = (OOStandardsEnforcement)s;
}


namespace {

void OOStandardsInternal(const std::string &type, const std::string &message)
{
	OOStandardsSetup();
	if (sEnforcement == STANDARDS_ENFORCEMENT_OFF)
	{
		return;
	}

	OO_LOG(type, "{}", message);

	if (sEnforcement == STANDARDS_ENFORCEMENT_QUIT)
	{
		::GameController::sharedController()->exitAppWithContext(type);
		// exit
	}
}

}	// namespace


void cxx_OOStandardsDeprecated(const std::string &message)
{
	OOStandardsInternal("oxp-standards.deprecated",message);
}


void cxx_OOStandardsError(const std::string &message)
{
	OOStandardsInternal("oxp-standards.error",message);
}


bool OOEnforceStandards()
{
	OOStandardsSetup();
	return sEnforcement >= STANDARDS_ENFORCEMENT_ENFORCE;
}


void OOSetStandardsForOXPVerifierMode()
{
	sEnforcement = STANDARDS_ENFORCEMENT_WARN;
	sSetup = true;
}



#endif
