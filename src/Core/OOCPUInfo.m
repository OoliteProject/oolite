/*

OOCPUInfo.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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
// Workaround for clang/glibc incompatibility.
#define __block __glibc_block
#include <unistd.h>
#undef __block
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


static NSUInteger		sNumberOfCPUs = 0;	// Yes, really 0.


void OOCPUInfoInit(void)
{
	if (sInited)  return;
	
	// Verify correctness of endian macros
	uint8_t			endianTag[4] = {0x12, 0x34, 0x56, 0x78};
	
#if OOLITE_BIG_ENDIAN
	if (*(uint32_t*)endianTag != 0x12345678)
	{
		OOLog(@"cpuInfo.endianTest.failed", @"%@", @"OOLITE_BIG_ENDIAN is set, but the system is not big-endian -- aborting.");
		exit(EXIT_FAILURE);
	}
#endif
	
#if OOLITE_LITTLE_ENDIAN
	if (*(uint32_t*)endianTag != 0x78563412)
	{
		OOLog(@"cpuInfo.endianTest.failed", @"%@", @"OOLITE_LITTLE_ENDIAN is set, but the system is not little-endian -- aborting.");
		exit(EXIT_FAILURE);
	}
#endif
	
	// Count processors
#if OOLITE_MAC_OS_X
	sNumberOfCPUs = [[NSProcessInfo processInfo] processorCount];
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


NSUInteger OOCPUCount(void)
{
	if (!sInited)  OOCPUInfoInit();
	return (sNumberOfCPUs != 0) ? sNumberOfCPUs : 1;
}


#if OOLITE_WINDOWS
NSString* operatingSystemFullVersion(void)
{
	OSVERSIONINFOW	osver;
	char				outUBRString[65] = "";

	osver.dwOSVersionInfoSize = sizeof(osver);
	GetVersionExW (&osver);
	
	// get the Update Build Revision from the Registry
	HKEY hKey;
	if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", 0, KEY_READ, &hKey) == ERROR_SUCCESS)
	{
		DWORD dwUBRSize = sizeof(DWORD);
		DWORD dwUBR = 0;
		if (RegQueryValueEx(hKey,"UBR", NULL, NULL, (BYTE*)&dwUBR, &dwUBRSize) == ERROR_SUCCESS)
		{
			char strUBR[64] = "";
			ltoa(dwUBR, strUBR, 10);
			strcpy(outUBRString, ".");
			strcat(outUBRString, strUBR);
		}
	}
	
	return [NSString stringWithFormat:@"%d.%d.%d%s %S", 
			osver.dwMajorVersion, osver.dwMinorVersion, osver.dwBuildNumber, outUBRString, osver.szCSDVersion];
}

/*
is64bitSystem: Detect operating system bitness. This function is based mainly on code by Mark S. Kolich, as
seen in http://mark.koli.ch/2009/10/reliably-checking-os-bitness-32-or-64-bit-on-windows-with-a-tiny-c-app.html
*/
BOOL is64BitSystem(void)
{
	#if defined(_WIN64)
		// if we have been compiled as a 64-bit app and we are running, we are obviously on a 64-bit system
		return YES;
	#else
		BOOL is64Bit = NO;
	
		IW64PFP IW64P = (IW64PFP)GetProcAddress(GetModuleHandle("kernel32"), "IsWow64Process");
		if(IW64P != NULL)
		{
			IW64P(GetCurrentProcess(), &is64Bit);
		}
	
		return is64Bit;
	#endif
}
#endif	// OOLITE_WINDOWS
