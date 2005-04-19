//
// $Id: Comparison.h,v 1.3 2004/12/12 20:17:24 will_mason Exp $
//
// vi: set ft=objc:

/*
 * ObjectiveLib - a library of containers and algorithms for Objective-C
 *
 * Copyright (c) 2004
 * Will Mason
 *
 * Portions:
 *
 * Copyright (c) 1994
 * Hewlett-Packard Company
 *
 * Copyright (c) 1996,1997
 * Silicon Graphics Computer Systems, Inc.
 *
 * Copyright (c) 1997
 * Moscow Center for SPARC Technology
 *
 * Copyright (c) 1999 
 * Boris Fomitchev
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * You may contact the author at will_mason@users.sourceforge.net.
 */

#if defined(GNUSTEP)

#if !defined(__COMPARISON_OL_GUARD)
#define __COMPARISON_OL_GUARD

#include <Foundation/NSObject.h>

/**
 * @category NSObject(OLComparisonMethods) Comparison.h Objectivelib/Comparison.h
 *
 * Comparison methods used in @ref Functors "function objects". These comparison
 * methods are only required to be included when GNUstep is the platform, as
 * Cocoa already defines them. Under Cocoa they are declared in the
 * intuitively-named file @c NSScriptWhoseTests.h. All of these methods send
 * the message @c compare: to the receiving object.
 *
 * @pre The receiving object must implement the method @c compare:.
 */
@interface NSObject (OLComparisonMethods)

/**
 * Return whether another object is equal to this one. This message returns YES if
 * and only if the message @c compare: returns @c NSOrderedSame.
 *
 * @param object the object to which to compare this one
 * @return YES if @a object is equal to this one, NO otherwise
 */
- (BOOL) isEqualTo: (id)object;

/**
 * Return whether this object is greater than another one. This message returns
 * YES if and only if @c compare: returns @c NSOrderedDescending.
 *
 * @param object the object to which to compare this one
 * @return YES if this object is greater than @a object, NO otherwise
 */
- (BOOL) isGreaterThan: (id)object;

/**
 * Return whether this object is greater than or equal to another one. This message returns
 * YES if and only if @c compare: does not return @c NSOrderedAscending.
 *
 * @param object the object to which to compare this one
 * @return YES if this object is greater than or equal to @a object, NO otherwise
 */
- (BOOL) isGreaterThanOrEqualTo: (id)object;

/**
 * Return whether this object is less than another one. This message returns
 * YES if and only if @c compare: returns @c NSOrderedAscending.
 *
 * @param object the object to which to compare this one
 * @return YES if this object is less than @a object, NO otherwise
 */
- (BOOL) isLessThan: (id)object;

/**
 * Return whether this object is less than or equal to another one. This message returns
 * YES if and only if @c compare: does not return @c NSOrderedDescending.
 *
 * @param object the object to which to compare this one
 * @return YES if this object is less than or equal to @a object, NO otherwise
 */
- (BOOL) isLessThanOrEqualTo: (id)object;

/**
 * Return whether another object is not equal to this one. This message returns YES if
 * and only if the message @c compare: does not return @c NSOrderedSame.
 *
 * @param object the object to which to compare this one
 * @return YES if @a object is not equal to this one, NO otherwise
 */
- (BOOL) isNotEqualTo: (id)object;

@end

#endif

#endif
