/*

OOBasicSoundReferencePoint.h

No-op implementation of OOSoundReferencePoint; see OOSound.h for information
about sound architecture.

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

#ifndef OOBASICSOUNDREFERENCEPOINT_H
#define OOBASICSOUNDREFERENCEPOINT_H

#include "oofnd/Ref.hpp"
#include "OOMaths.h"


/*	C++ since bead oo-odlx (proposed ADR-0056). Nothing outside this file messages it, so it has
	no Objective-C facade and is global: the one outside mention, OOSoundSource's no-op
	-positionRelativeTo:, takes it by (borrowed) pointer.
*/
class OOSoundReferencePoint : public oo::RefCounted
{
public:
	// Positional audio attributes are ignored in this implementation
	void setPosition(Vector inPosition);
	void setVelocity(Vector inVelocity);
	void setOrientation(Vector inOrientation);
};

#endif	// OOBASICSOUNDREFERENCEPOINT_H
