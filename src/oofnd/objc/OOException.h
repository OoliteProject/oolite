/*	oofnd/objc/OOException.h
        Forwarding header. The game throws the C++ oo::Exception;
   OORaiseException(), the exception names, oo::CurrentOOException() and
   oo::Finally are in oofnd/Exception.hpp, which this header includes so its
   includers need no change.
*/

#pragma once

#include "oofnd/Exception.hpp"
#include "oofnd/objc/OOObject.h"  // what includers of this header have always got with it
