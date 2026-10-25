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

#include "OOLogHeader.h"
#include "oofnd/Process.hpp"
#include "OOCPUInfo.h"
#include "OOLogging.h"
#include "OOOXPVerifier.h"
#include "Universe.h"
#include "OOStellarBody.h"
#include "OOJavaScriptEngine.h"
#include "OOSound.h"
#include "oofnd/Date.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"


namespace {
std::string AdditionalLogHeaderInfo(void);
}


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
	
	const std::vector<std::string> featureStrings = {
	// User features
	#if OOLITE_OPENAL
		"OpenAL",
	#endif

	#if OO_SHADERS
		"GLSL shaders",
	#endif
	
		"new planets",
	
	// Debug features
	#if OO_CHECK_GL_HEAVY
		"heavy OpenGL error checking",
	#endif
	
	#ifndef NDEBUG
		"JavaScript console support",
		#if OOLITE_MAC_OS_X
			// Under Mac OS X, Debug.oxp adds more than console support.
			"Debug plug-in support",
		#endif
	#endif
	
	#if OO_OXP_VERIFIER_ENABLED
		"OXP verifier",
	#endif
	
	#if OO_LOCALIZATION_TOOLS
		"localization tools",
	#endif
	
	#if DEBUG_GRAPHVIZ
		"debug GraphViz support",
	#endif
	
	#if OOJS_PROFILE
		#ifdef MOZ_TRACE_JSCALLS
			"JavaScript profiling",
		#else
			"JavaScript native callback profiling",
		#endif
	#endif
	
	#if OO_FOV_INFLIGHT_CONTROL_ENABLED
		"FOV in-flight control",
	#endif
	
	};
	
	// systemString: UTF-8 string with system type and possibly version.
	#if (OOLITE_MAC_OS_X || !OOLITE_WINDOWS)
		std::string systemString = oo::str::format(OS_TYPE_STRING " %s", oo::process::operatingSystemVersionString().c_str());
	#elif OOLITE_WINDOWS
		std::string systemString = oo::str::format(OS_TYPE_STRING " %s %s-bit", operatingSystemFullVersion().c_str(), is64BitSystem() ? "64":"32");
	#else
		#define systemString std::string(OS_TYPE_STRING)
	#endif

	std::string versionString;
	#if (defined (DEV_RELEASE))
		versionString = "development version " OO_VERSION_FULL;
	#else
		versionString = "version " OO_VERSION_FULL;
	#endif
	if (versionString.empty())  versionString = "<unknown version>";

	std::string miscString = oo::str::format("Opening log for Oolite %s by %s (" CPU_TYPE_STRING RELEASE_VARIANT_STRING ") under %s at %s.\n", versionString.c_str(), OO_BUILDER, systemString.c_str(), oo::date::description().c_str());

	miscString += AdditionalLogHeaderInfo();

	std::string featureDesc;
	for (const std::string &feature : featureStrings)
	{
		if (!featureDesc.empty())  featureDesc += ", ";
		featureDesc += feature;
	}
	if (featureDesc.empty())  featureDesc = "none";
	miscString += oo::str::format("\nBuild options: %s.\n", featureDesc.c_str());

	miscString += "\nNote that the contents of the log file can be adjusted by editing logcontrol.plist.";

	OO_LOG("log.header", "{}\n", miscString);
}


// Foundation sweep (proposed ADR-0043, bead oo-vnsl): a std::string, for OOJSConsole's
// console.platformDescription; the same "<system> (<cpu><variant>)" text.
std::string OOPlatformDescription(void)
{
	#if OOLITE_MAC_OS_X
		const std::string platformSystem = OS_TYPE_STRING " " + oo::process::operatingSystemVersionString();
	#else
		const std::string platformSystem = OS_TYPE_STRING;
	#endif

	return platformSystem + " (" CPU_TYPE_STRING RELEASE_VARIANT_STRING ")";
}


// System-specific stuff to append to log header.
#if OOLITE_MAC_OS_X
#include <sys/sysctl.h>


static std::optional<std::string> GetSysCtlString(const char *name);
static unsigned long long GetSysCtlInt(const char *name);
static std::string GetCPUDescription(void);

namespace {
std::string AdditionalLogHeaderInfo(void)
{
	std::optional<std::string>	sysModel;
	unsigned long long		sysPhysMem;

	sysModel = GetSysCtlString("hw.model");
	sysPhysMem = GetSysCtlInt("hw.memsize");

	// "%@" printed a nil model as "(null)".
	return oo::str::format("Machine type: %s, %zu MiB memory, %s.", sysModel ? sysModel->c_str() : "(null)", sysPhysMem >> 20, GetCPUDescription().c_str());
}
}

#ifndef CPUFAMILY_INTEL_MEROM
	#define CPUFAMILY_INTEL_MEROM		0x426f69ef
#endif

#ifndef CPUFAMILY_INTEL_HASWELL
	#define CPUFAMILY_INTEL_HASWELL		0x10b282dc
#endif

#ifndef CPUFAMILY_INTEL_BROADWELL
	#define CPUFAMILY_INTEL_BROADWELL	0x582ed09c
#endif

#ifndef CPUFAMILY_INTEL_SKYLAKE
	#define CPUFAMILY_INTEL_SKYLAKE		0x37fc219f
#endif


static std::string GetCPUDescription(void)
{
	std::optional<std::string>	typeStr, subTypeStr;
	
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
			typeStr = "PowerPC";
			break;
			
		case CPU_TYPE_I386:
			typeStr = "x86";
			switch (sysCPUFamily)
			{
				case CPUFAMILY_INTEL_MEROM:
					subTypeStr = " (Core 2/Merom)";
					break;
					
				case CPUFAMILY_INTEL_PENRYN:
					subTypeStr = " (Penryn)";
					break;
					
				case CPUFAMILY_INTEL_NEHALEM:
					subTypeStr = " (Nehalem)";
					break;
					
				case CPUFAMILY_INTEL_WESTMERE:
					subTypeStr = " (Westmere)";
					break;
					
				case CPUFAMILY_INTEL_SANDYBRIDGE:
					subTypeStr = " (Sandy Bridge)";
					break;
					
				case CPUFAMILY_INTEL_IVYBRIDGE:
					subTypeStr = " (Ivy Bridge)";
					break;
					
				case CPUFAMILY_INTEL_HASWELL:
					subTypeStr = " (Haswell)";
					break;
					
				case CPUFAMILY_INTEL_BROADWELL:
					subTypeStr = " (Broadwell)";
					break;
					
				case CPUFAMILY_INTEL_SKYLAKE:
					subTypeStr = " (Skylake)";
					break;
					
				default:
					subTypeStr = oo::str::format(" (family 0x%llx)", sysCPUFamily);
			}
			break;
		
		case CPU_TYPE_ARM:
			typeStr = "ARM";
	}
	
	if (!typeStr.has_value())  typeStr = oo::str::format("CPU type %zu", sysCPUType);

	std::string countStr;
	if (sysCPUCount == sysLogicalCPUCount)  countStr = oo::str::format("%zu", sysCPUCount);
	else countStr = oo::str::format("%zu (%zu logical)", sysCPUCount, sysLogicalCPUCount);

	// "%@" printed a nil sub-type as "(null)".
	return oo::str::format("%s x %s%s @ %zu MHz", countStr.c_str(), typeStr->c_str(), subTypeStr ? subTypeStr->c_str() : "(null)", (sysCPUFrequency + 500000) / 1000000);
}


static std::optional<std::string> GetSysCtlString(const char *name)
{
	char					*buffer = NULL;
	size_t					size = 0;

	// Get size
	sysctlbyname(name, NULL, &size, NULL, 0);
	if (size == 0)  return std::nullopt;

	buffer = alloca(size);
	if (sysctlbyname(name, buffer, &size, NULL, 0) != 0)  return std::nullopt;
	return std::string(buffer);
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
namespace {
std::string AdditionalLogHeaderInfo(void)
{
	unsigned cpuCount = OOCPUCount();
	const std::string cpuDescription = OOCPUDescription();
	OOMemoryStatus systemMemoryStatus = OOSystemMemoryStatus();
	
	return oo::str::format("%s %u processor%s detected. System RAM: %llu MB (free: %llu MB).", cpuDescription.c_str(), cpuCount, cpuCount != 1 ? "s" : "", systemMemoryStatus.ooPhysicalMemory, systemMemoryStatus.ooAvailableMemory);
}
}
#endif
