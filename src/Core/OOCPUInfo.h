/*

OOCPUInfo.h

Capabilities and features of CPUs.

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

#pragma once

#include <stdint.h>

#include "OOFoundation.h"
#include "oofnd/StdLib.hpp"

#if OOLITE_LINUX
#include <sys/sysinfo.h>
#endif

void OOCPUInfoInit(void);

/*	Number of processors (whether they be individual or cores), used to
   select number of threads to use for things like texture loading.
*/
NSUInteger OOCPUCount(void);

/*
        Returns the CPU identifier string. Currently Windows and Linux only.
*/
#if (OOLITE_WINDOWS || OOLITE_LINUX)
std::string OOCPUDescription(void);  // UTF-8
void OOCPUID(int CPUInfo[4], int InfoType);

typedef struct {
  unsigned long long ooPhysicalMemory;
  unsigned long long ooAvailableMemory;
} OOMemoryStatus;
OOMemoryStatus OOSystemMemoryStatus(void);
#endif

#if OOLITE_WINDOWS
#include <windows.h>

// IsWow64Process, to check for a 64/32 bit system: windows.h's BOOL is an int
typedef BOOL(WINAPI* IW64PFP)(HANDLE, BOOL*);
bool is64BitSystem(void);
std::string operatingSystemFullVersion(void);  // UTF-8
#endif

#include "OOCPUInfoEndian.h"

/*	Set up OOLITE_NATIVE_64_BIT. This is intended for 64-bit optimizations
        (see OOTextureScaling.m). It is not set for systems where 64-bitness may
        be determined at runtime (such as 32-bit OS X binaries), because I can't
        be bothered to do the set-up required to use switch to a 64-bit code
   path at runtime while being cross-platform.
        -- Ahruman
*/

#ifndef OOLITE_NATIVE_64_BIT

#ifdef _UINT64_T
#ifdef __ppc64__
#define OOLITE_NATIVE_64_BIT 1
#elif __amd64__
#define OOLITE_NATIVE_64_BIT 1
#elif __x86_64__
#define OOLITE_NATIVE_64_BIT 1
#endif
#endif  // _UINT64_T

#ifndef OOLITE_NATIVE_64_BIT
#define OOLITE_NATIVE_64_BIT 0
#endif

#endif  // defined(OOLITE_NATIVE_64_BIT)
