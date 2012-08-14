/*

OOMacSnowLeopardFullScreenController.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOMacSnowLeopardFullScreenController.h"

#if OOLITE_MAC_OS_X && OOLITE_64_BIT

#import "MyOpenGLView.h"


@implementation OOMacSnowLeopardFullScreenController

@synthesize fullScreenMode = _fullScreenMode;	// Future note: needs to be explicit because property declaration is inherited.


- (NSArray *) displayModes
{
	return [NSArray array];
}


- (OOUInteger) indexOfCurrentDisplayMode
{
	return NSNotFound;
}


- (BOOL) setDisplayWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh
{
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh
{
	return nil;
}

@end

#endif
