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

#import "OODebugStandards.h"
#import "OOLogging.h"
#import "OOCollectionExtractors.h"
#import "GameController.h"

#ifdef NDEBUG
// in release mode, stubs
void OOStandardsDeprecated(NSString *message) {}
void OOStandardsError(NSString *message) {}
BOOL OOEnforceStandards() { return NO; }
void OOSetStandardsForOXPVerifierMode() {}

#else

void OOStandardsSetup();
void OOStandardsInternal(NSString *type, NSString *message);

static BOOL sSetup = NO;

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
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	int s = [prefs oo_intForKey:@"enforce-oxp-standards" 
				   defaultValue:STANDARDS_ENFORCEMENT_WARN];
	if (s < STANDARDS_ENFORCEMENT_OFF)
	{
		s = STANDARDS_ENFORCEMENT_OFF;
	}
	else if (s > STANDARDS_ENFORCEMENT_QUIT)
	{
		s = STANDARDS_ENFORCEMENT_QUIT;
	}
	sEnforcement = s;
}


void OOStandardsInternal(NSString *type, NSString *message)
{
	OOStandardsSetup();
	if (sEnforcement == STANDARDS_ENFORCEMENT_OFF)
	{
		return;
	}

	OOLog(type, @"%@", message);

	if (sEnforcement == STANDARDS_ENFORCEMENT_QUIT)
	{
		[[GameController sharedController] exitAppWithContext:type];
		// exit
	}
}


void OOStandardsDeprecated(NSString *message)
{
	OOStandardsInternal(@"oxp-standards.deprecated",message);
}


void OOStandardsError(NSString *message)
{
	OOStandardsInternal(@"oxp-standards.error",message);
}


BOOL OOEnforceStandards()
{
	OOStandardsSetup();
	return sEnforcement >= STANDARDS_ENFORCEMENT_ENFORCE;
}


void OOSetStandardsForOXPVerifierMode()
{
	sEnforcement = STANDARDS_ENFORCEMENT_WARN;
	sSetup = YES;
}



#endif
