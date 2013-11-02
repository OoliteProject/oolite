/*

OOLogHeader.m


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#import "OOLogHeader.h"
#import "OOCPUInfo.h"
#import "OOLogging.h"
#import "OOOXPVerifier.h"
#import "Universe.h"
#import "OOStellarBody.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"


static NSString *AdditionalLogHeaderInfo(void);

NSString *OOPlatformDescription(void);


#ifdef ALLOW_PROCEDURAL_PLANETS
#warning ALLOW_PROCEDURAL_PLANETS is no longer optional and the macro should no longer be defined.
#endif

#ifdef DOCKING_CLEARANCE_ENABLED
#warning DOCKING_CLEARANCE_ENABLED is no longer optional and the macro should no longer be defined.
#endif

#ifdef WORMHOLE_SCANNER
#warning WORMHOLE_SCANNER is no longer optional and the macro should no longer be defined.
#endif

#ifdef TARGET_INCOMING_MISSILES
#warning TARGET_INCOMING_MISSILES is no longer optional and the macro should no longer be defined.
#endif


void OOPrintLogHeader(void)
{
	// Bunch of string literal macros which are assembled into a CPU info string.
	#if defined (__ppc__)
		#define CPU_TYPE_STRING "PPC-32"
	#elif defined (__ppc64__)
		#define CPU_TYPE_STRING "PPC-64"
	#elif defined (__i386__)
		#define CPU_TYPE_STRING "x86-32"
	#elif defined (__x86_64__)
		#define CPU_TYPE_STRING "x86-64"
	#else
		#if OOLITE_BIG_ENDIAN
			#define CPU_TYPE_STRING "<unknown big-endian architecture>"
		#elif OOLITE_LITTLE_ENDIAN
			#define CPU_TYPE_STRING "<unknown little-endian architecture>"
		#else
			#define CPU_TYPE_STRING "<unknown architecture with unknown byte order>"
		#endif
	#endif
	
	#if OOLITE_MAC_OS_X
		#define OS_TYPE_STRING "Mac OS X"
	#elif OOLITE_WINDOWS
		#define OS_TYPE_STRING "Windows"
	#elif OOLITE_LINUX
		#define OS_TYPE_STRING "Linux"	// Hmm, what about other unices?
	#elif OOLITE_SDL
		#define OS_TYPE_STRING "unknown SDL system"
	#else
		#define OS_TYPE_STRING "unknown system"
	#endif
	
	#if OO_DEBUG
		#define RELEASE_VARIANT_STRING " debug"
	#elif !defined (NDEBUG)
		#define RELEASE_VARIANT_STRING " test release"
	#else
		#define RELEASE_VARIANT_STRING ""
	#endif
	
	NSArray *featureStrings = [NSArray arrayWithObjects:
	// User features
	#if OOLITE_OPENAL
		@"OpenAL",
	#endif

	#if OO_SHADERS
		@"GLSL shaders",
	#endif
	
	#if NEW_PLANETS
		@"new planets",
	#endif
	
	// Debug features
	#if OO_CHECK_GL_HEAVY
		@"heavy OpenGL error checking",
	#endif
	
	#ifndef OO_EXCLUDE_DEBUG_SUPPORT
		@"JavaScript console support",
		#if OOLITE_MAC_OS_X
			// Under Mac OS X, Debug.oxp adds more than console support.
			@"Debug plug-in support",
		#endif
	#endif
	
	#if OO_OXP_VERIFIER_ENABLED
		@"OXP verifier",
	#endif
	
	#if OO_LOCALIZATION_TOOLS
		@"localization tools",
	#endif
	
	#if DEBUG_GRAPHVIZ
		@"debug GraphViz support",
	#endif
	
	#if OOJS_PROFILE
		#ifdef MOZ_TRACE_JSCALLS
			@"JavaScript profiling",
		#else
			@"JavaScript native callback profiling",
		#endif
	#endif
	
		nil];
	
	// systemString: NSString with system type and possibly version.
	#if (OOLITE_MAC_OS_X || (OOLITE_GNUSTEP_1_20 && !OOLITE_WINDOWS))
		NSString *systemString = [NSString stringWithFormat:@OS_TYPE_STRING " %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
	#elif OOLITE_WINDOWS
		NSString *systemString = [NSString stringWithFormat:@OS_TYPE_STRING " %@ %@-bit", operatingSystemFullVersion(), is64BitSystem() ? @"64":@"32"];
	#else
		#define systemString @OS_TYPE_STRING
	#endif
	
	NSString *versionString = nil;
	#if (defined (SNAPSHOT_BUILD) && defined (OOLITE_SNAPSHOT_VERSION))
		versionString = @"development version " OOLITE_SNAPSHOT_VERSION;
	#else
		versionString = [NSString stringWithFormat:@"version %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
	#endif
	if (versionString == nil)  versionString = @"<unknown version>";
	
	NSMutableString *miscString = [NSMutableString stringWithFormat:@"Opening log for Oolite %@ (" CPU_TYPE_STRING RELEASE_VARIANT_STRING ") under %@ at %@.\n", versionString, systemString, [NSDate date]];
	
	[miscString appendString:AdditionalLogHeaderInfo()];
	
	NSString *featureDesc = [featureStrings componentsJoinedByString:@", "];
	if ([featureDesc length] == 0)  featureDesc = @"none";
	[miscString appendFormat:@"\nBuild options: %@.\n", featureDesc];
	
	[miscString appendString:@"\nNote that the contents of the log file can be adjusted by editing logcontrol.plist."];
	
	OOLog(@"log.header", @"%@\n", miscString);
}


NSString *OOPlatformDescription(void)
{
	#if OOLITE_MAC_OS_X
		NSString *systemString = [NSString stringWithFormat:@OS_TYPE_STRING " %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
	#else
		#define systemString @OS_TYPE_STRING
	#endif
	
	return [NSString stringWithFormat:@"%@ ("CPU_TYPE_STRING RELEASE_VARIANT_STRING")", systemString];
}


// System-specific stuff to append to log header.
#if OOLITE_MAC_OS_X
#include <sys/sysctl.h>


static NSString *GetSysCtlString(const char *name);
static unsigned long long GetSysCtlInt(const char *name);
static NSString *GetCPUDescription(void);

static NSString *AdditionalLogHeaderInfo(void)
{
	NSString				*sysModel = nil;
	unsigned long long		sysPhysMem;
	
	sysModel = GetSysCtlString("hw.model");
	sysPhysMem = GetSysCtlInt("hw.memsize");
	
	return [NSString stringWithFormat:@"Machine type: %@, %llu MiB memory, %@.", sysModel, sysPhysMem >> 20, GetCPUDescription()];
}


#ifndef CPUFAMILY_INTEL_HASWELL
	#define CPUFAMILY_INTEL_HASWELL 0x10b282dc
#endif


static NSString *GetCPUDescription(void)
{
	NSString			*typeStr = nil, *subTypeStr = nil;
	
	unsigned long long sysCPUType = GetSysCtlInt("hw.cputype");
	unsigned long long sysCPUFamily = GetSysCtlInt("hw.cpufamily");
	unsigned long long sysCPUFrequency = GetSysCtlInt("hw.cpufrequency");
	unsigned long long sysCPUCount = GetSysCtlInt("hw.physicalcpu");
	unsigned long long sysLogicalCPUCount = GetSysCtlInt("hw.logicalcpu");
	
	/*	Note: CPU_TYPE_STRING tells us the build architecture. This gets the
		physical CPU type. They may differ, for instance, when running under
		Rosetta. The code is written for flexibility, although ruling out
		x86 code running on PPC would be entirely reasonable.
	*/
	switch (sysCPUType)
	{
		case CPU_TYPE_POWERPC:
			typeStr = @"PowerPC";
			break;
			
		case CPU_TYPE_I386:
			typeStr = @"x86";
			switch (sysCPUFamily)
			{
				case CPUFAMILY_INTEL_MEROM:
					subTypeStr = @" (Core 2/Merom)";
					break;
					
				case CPUFAMILY_INTEL_PENRYN:
					subTypeStr = @" (Penryn)";
					break;
					
				case CPUFAMILY_INTEL_NEHALEM:
					subTypeStr = @" (Nehalem)";
					break;
					
				case CPUFAMILY_INTEL_WESTMERE:
					subTypeStr = @" (Westmere)";
					break;
					
				case CPUFAMILY_INTEL_SANDYBRIDGE:
					subTypeStr = @" (Sandy Bridge)";
					break;
					
				case CPUFAMILY_INTEL_IVYBRIDGE:
					subTypeStr = @" (Ivy Bridge)";
					break;
					
				case CPUFAMILY_INTEL_HASWELL:
					subTypeStr = @" (Haswell)";
					break;
					
				default:
					subTypeStr = [NSString stringWithFormat:@" (family 0x%llx)", sysCPUFamily];
			}
			break;
		
		case CPU_TYPE_ARM:
			typeStr = @"ARM";
	}
	
	if (typeStr == nil)  typeStr = [NSString stringWithFormat:@"CPU type %llu", sysCPUType];
	
	NSString *countStr = nil;
	if (sysCPUCount == sysLogicalCPUCount)  countStr = [NSString stringWithFormat:@"%llu", sysCPUCount];
	else countStr = [NSString stringWithFormat:@"%llu (%llu logical)", sysCPUCount, sysLogicalCPUCount];
	
	return [NSString stringWithFormat:@"%@ x %@%@ @ %llu MHz", countStr, typeStr, subTypeStr, (sysCPUFrequency + 500000) / 1000000];
}


static NSString *GetSysCtlString(const char *name)
{
	char					*buffer = NULL;
	size_t					size = 0;
	
	// Get size
	sysctlbyname(name, NULL, &size, NULL, 0);
	if (size == 0)  return nil;
	
	buffer = alloca(size);
	if (sysctlbyname(name, buffer, &size, NULL, 0) != 0)  return nil;
	return [NSString stringWithUTF8String:buffer];
}


static unsigned long long GetSysCtlInt(const char *name)
{
	unsigned long long		llresult = 0;
	unsigned int			intresult = 0;
	size_t					size;
	
	size = sizeof llresult;
	if (sysctlbyname(name, &llresult, &size, NULL, 0) != 0)  return 0;
	if (size == sizeof llresult)  return llresult;
	
	size = sizeof intresult;
	if (sysctlbyname(name, &intresult, &size, NULL, 0) != 0)  return 0;
	if (size == sizeof intresult)  return intresult;
	
	return 0;
}

#else
static NSString *AdditionalLogHeaderInfo(void)
{
	unsigned cpuCount = OOCPUCount();
	return [NSString stringWithFormat:@"%u processor%@ detected.", cpuCount, cpuCount != 1 ? @"s" : @""];
}
#endif
