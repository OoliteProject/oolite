/*

NSScannerOOExtensions.m

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

#import "NSScannerOOExtensions.h"
#import "OOStringBridge.h"

@implementation NSScanner (OOExtensions)

- (BOOL)ooliteScanCharactersFromSet:(NSCharacterSet*)set intoString:(std::string*)value
{
    NSUInteger currentLocation = [self scanLocation];
    NSRange matchedRange = NSMakeRange(currentLocation, 0);
    NSUInteger scanLength = [[self string] length];

    while ((currentLocation < scanLength) && ([set characterIsMember:[[self string] characterAtIndex:currentLocation]])) {
        currentLocation++;
    }

    [self setScanLocation:currentLocation];

    matchedRange.length = currentLocation - matchedRange.location;

    if (!matchedRange.length)
        return NO;

    if (value != NULL) {
        *value = oo::StdString([[self string] substringWithRange:matchedRange]);
    }

    return YES;
}

- (BOOL)ooliteScanUpToCharactersFromSet:(NSCharacterSet*)set intoString:(std::string*)value
{
    NSUInteger currentLocation = [self scanLocation];
    NSRange matchedRange = NSMakeRange(currentLocation, 0);
    NSUInteger scanLength = [[self string] length];

    while ((currentLocation < scanLength) && (![set characterIsMember:[[self string] characterAtIndex:currentLocation]])) {
        currentLocation++;
    }

    [self setScanLocation:currentLocation];

    matchedRange.length = currentLocation - matchedRange.location;

    if (!matchedRange.length)
        return NO;

    if (value != NULL) {
        *value = oo::StdString([[self string] substringWithRange:matchedRange]);
    }

    return YES;
}

@end
