/*	oofnd/objc/OOException.h
        Was the Foundation-free Objective-C exception (proposed ADR-0029 Decision 4, bead oo-3rb.5).
        Since bead oo-rskgl.1 the game throws the C++ oo::Exception, and bead oo-4aq6a.1 deleted the
        Objective-C OOException class (OOException.mm) with its own test. What is left -
        OORaiseException(), the exception names, oo::CurrentOOException(), oo::Finally - is in
        oofnd/Exception.hpp; this header includes it so its includers need no change.
*/

#ifndef OOFND_OBJC_OOEXCEPTION_H
#define OOFND_OBJC_OOEXCEPTION_H

#include "oofnd/Exception.hpp"
#include "oofnd/objc/OOObject.h" // what includers of this header have always got with it

#endif // OOFND_OBJC_OOEXCEPTION_H
