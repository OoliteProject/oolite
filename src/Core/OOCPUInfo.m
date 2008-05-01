/*

OOCPUInfo.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOCPUInfo.h"
#import <stdlib.h>

#if OOLITE_MAC_OS_X
#import <sys/sysctl.h>
#endif


#if 0
// Confirm settings
#if OOLITE_BIG_ENDIAN
#warning Big-endian.
#endif
#if OOLITE_LITTLE_ENDIAN
#warning Little-endian.
#endif
#if OOLITE_NATIVE_64_BIT
#warning 64-bit.
#else
#warning 32-bit.
#endif
#if OOLITE_ALTIVEC
#warning AltiVec.
#if OOLITE_ALTIVEC_DYNAMIC
#warning Dynamic AltiVec selection.
#endif
#endif
#endif


static BOOL				sInited = NO;
#if OOLITE_ALTIVEC_DYNAMIC
static BOOL				sAltiVecAvailable = NO;
#endif


static unsigned			sNumberOfCPUs = 0;	// Yes, really 0.


void OOCPUInfoInit(void)
{
	if (sInited)  return;
	
	// Verify correctness of endian macros
	uint8_t			endianTag[4] = {0x12, 0x34, 0x56, 0x78};
	
#if OOLITE_BIG_ENDIAN
	if (*(uint32_t*)endianTag != 0x12345678)
	{
		OOLog(@"cpuInfo.endianTest.failed", @"OOLITE_BIG_ENDIAN is set, but the system is not big-endian -- aborting.");
		exit(EXIT_FAILURE);
	}
#endif
	
#if OOLITE_LITTLE_ENDIAN
	if (*(uint32_t*)endianTag != 0x78563412)
	{
		OOLog(@"cpuInfo.endianTest.failed", @"OOLITE_LITTLE_ENDIAN is set, but the system is not little-endian -- aborting.");
		exit(EXIT_FAILURE);
	}
#endif
	
	/*	Count processors - only implemented for OS X and Windows at the moment.
		sysconf(_SC_NPROCESSORS_ONLN) may be appropriate for some Unices, but
		_SC_NPROCESSORS_ONLN is not defined on OS X.
	*/
#if OOLITE_MAC_OS_X
	int		flag = 0;
	size_t	size = sizeof flag;
	if (sysctlbyname("hw.logicalcpu", &flag, &size, NULL, 0) == 0)
	{
		if (1 <= flag)  sNumberOfCPUs = flag;
	}
	if (sNumberOfCPUs == 0 && sysctlbyname("hw.ncpu", &flag, &size, NULL, 0) == 0)
	{
		if (1 <= flag)  sNumberOfCPUs = flag;
	}
#elif OOLITE_WINDOWS
	SYSTEM_INFO	sysInfo;
	
	GetSystemInfo(&sysInfo);
	sNumberOfCPUs = sysInfo.dwNumberOfProcessors;
#endif
	
	// Check for AltiVec if relelevant
#if OOLITE_ALTIVEC_DYNAMIC
#if OOLITE_MAC_OS_X
	flag = 0;
	size = sizeof flag;
	if (sysctlbyname("hw.optional.altivec", &flag, &size, NULL, 0) == 0)
	{
		if (flag)  sAltiVecAvailable = YES;
	}
#else
	#error OOLITE_ALTIVEC_DYNAMIC is (still) set, but Oolite does not know how to check for AltiVec on this platform. (The Mac version may work on other BSDs, at least; give it a shot.)
#endif
#endif
	
	sInited = YES;
}


unsigned OOCPUCount(void)
{
	if (!sInited)  OOCPUInfoInit();
	return (sNumberOfCPUs != 0) ? sNumberOfCPUs : 1;
}


#if OOLITE_ALTIVEC_DYNAMIC
BOOL OOAltiVecAvailable(void)
{
	return sAltiVecAvailable;
}
#endif
