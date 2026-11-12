/*

OODemangle.h

The readable name of a C++ type: OODemangle(typeid(x).name()) is what
abi::__cxa_demangle gives, or the mangled name itself when it cannot be
demangled. The C++ ABI hands the demangled text back in C-allocated memory that
the caller must release with std::free; the unique_ptr deleter below is the only
place first-party code reaches the C allocator for it.

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

#include <cxxabi.h>

#include <cstdlib>
#include <memory>
#include <string>

inline std::string OODemangle(const char* mangled) {
  int status = 0;
  const std::unique_ptr<char, decltype(&std::free)> demangled(
      abi::__cxa_demangle(mangled, nullptr, nullptr, &status), &std::free);
  return (status == 0 && demangled != nullptr) ? std::string(demangled.get())
                                               : std::string(mangled);
}
