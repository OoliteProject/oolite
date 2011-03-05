/*

OOCPUInfo.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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
#include <stdlib.h>

#if OOLITE_MAC_OS_X
#include <sys/sysctl.h>
#elif (OOLITE_LINUX || OOLITE_WINDOWS)
#include <unistd.h>
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
#endif


static BOOL				sInited = NO;


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
	
	// Count processors
#if OOLITE_MAC_OS_X
#if OOLITE_LEOPARD
	sNumberOfCPUs = [[NSProcessInfo processInfo] processorCount];
#else
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
#endif	// OOLITE_LEOPARD
#elif OOLITE_WINDOWS
	SYSTEM_INFO	sysInfo;
	
	GetSystemInfo(&sysInfo);
	sNumberOfCPUs = sysInfo.dwNumberOfProcessors;
#elif defined _SC_NPROCESSORS_ONLN
	sNumberOfCPUs = sysconf(_SC_NPROCESSORS_ONLN);
#else
	#warning Do not know how to find number of CPUs on this architecture.
#endif	// OS selection
	
	sInited = YES;
}


unsigned OOCPUCount(void)
{
	if (!sInited)  OOCPUInfoInit();
	return (sNumberOfCPUs != 0) ? sNumberOfCPUs : 1;
}
