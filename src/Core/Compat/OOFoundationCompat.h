/*

OOFoundationCompat.h

Compatibility declarations for building Oolite against Apple's Foundation
(the Meson darwin host) where its API surface differs from GNUstep Base.

Entries are strictly audit-driven: a declaration is added here only when a
source file needs it to compile against Apple Foundation, and each entry
must cite where it is used. This header is intentionally included by
OOFoundation.h (and only there), so every translation unit sees a single,
consistent set of compatibility definitions.

Currently empty: as measured by the platform-surface audit and the path-A
probe (31/35 mac-gated files compile clean against Apple Foundation), no
symbol shims are required. The header exists so future audit findings have
a designated, reviewable home instead of scattering #ifdefs across sources.

Oolite
Copyright (C) 2004-2026 Giles C Williams and contributors

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

#ifdef OOLITE_MACOS_APPLE_FOUNDATION

/* (no entries required by the current audit) */

#endif /* OOLITE_MACOS_APPLE_FOUNDATION */
