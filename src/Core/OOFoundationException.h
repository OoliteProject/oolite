/*

OOFoundationException.h

The exception half of the NSException -> OOException sweep (beads oo-3rb.27 ff., proposed
ADR-0029 Decision 4 and ADR-0037). Objective-C++ only; deleted by oo-qps together with
gnustep-base.

Game code raises OOException (oofnd/objc/OOException.h). While gnustep-base is linked, gnustep-base
itself still raises NSExceptions (collection range errors, plist parsing, unrecognised selectors),
and a `@catch (OOException *)` does not catch those. A handler that must go on catching them has
two clauses, the converted one first:

        @catch (OOException *exception)
        {
                OOLog(kOOLogException, @"... %@ : %@", oo::NSStringFrom([exception name]), oo::NSStringFrom([exception reason]));
        }
        @catch (OOFoundationException *exception)
        {
                OOLog(kOOLogException, @"... %@ : %@", [exception name], [exception reason]);	// as before
        }

The second clause keeps the handler's original text, so what gnustep-base raises is
handled exactly as it was; the first bridges the UTF-8 name and reason (OOStringBridge.h) into the
same format, so both write the same line. A handler that only ever sees the game's own exceptions
needs the first clause alone. OOFoundationException is the only name game code uses for Foundation's
exception class; when oo-qps deletes this header every remaining clause stops compiling, and that
compile-error list is the list of clauses to delete.

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

#ifndef OO_FOUNDATION_EXCEPTION_H
#define OO_FOUNDATION_EXCEPTION_H

#import "OOFoundation.h"
#include "oofnd/objc/OOException.h"

// gnustep-base's exception class, for the second @catch clause described above. Transitional.
typedef NSException OOFoundationException;

#endif // OO_FOUNDATION_EXCEPTION_H
