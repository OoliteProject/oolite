//
// $Id: Comparison.m,v 1.3 2004/11/29 23:35:50 will_mason Exp $
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

#include "Comparison.h"
#include <Foundation/NSString.h>

@implementation NSObject (OLComparison)

- (BOOL) isEqualTo: (id)object
{
    return (object != nil && [self compare: object] == NSOrderedSame) ?
        YES : NO;
}

- (BOOL) isGreaterThan: (id)object
{
    return (object != nil && [self compare: object] == NSOrderedDescending) ?
        YES : NO;
}

- (BOOL) isGreaterThanOrEqualTo: (id)object
{
    return (object != nil && [self compare: object] != NSOrderedAscending) ?
        YES : NO;
}

- (BOOL) isLessThan: (id)object
{
    return (object != nil && [self compare: object] == NSOrderedAscending) ?
        YES : NO;
}

- (BOOL) isLessThanOrEqualTo: (id)object
{
    return (object != nil && [self compare: object] != NSOrderedDescending) ?
        YES : NO;
}

- (BOOL) isNotEqualTo: (id)object
{
    return (object != nil && [self compare: object] != NSOrderedSame) ?
        YES : NO;
}

@end

#endif
