/*

OOFullScreenController.m


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

#import "OOFullScreenController.h"
#import "OOLogging.h"


@implementation OOFullScreenController

- (id) initWithGameView:(MyOpenGLView *)view
{
	if ((self = [super init]))
	{
		_gameView = [view retain];
	}
	return self;
}


- (void) dealloc
{
	DESTROY(_gameView);
	
	[super dealloc];
}


- (MyOpenGLView *) gameView
{
	return _gameView;
}


- (BOOL) inFullScreenMode
{
	OOLogGenericSubclassResponsibility();
	return NO;
}


- (void) setFullScreenMode:(BOOL)value
{
	OOLogGenericSubclassResponsibility();
}


- (NSArray *) displayModes
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


- (NSDictionary *) currentDisplayMode
{
	return [[self displayModes] objectAtIndex:[self indexOfCurrentDisplayMode]];
}


- (OOUInteger) indexOfCurrentDisplayMode
{
	OOLogGenericSubclassResponsibility();
	return NSNotFound;
}


- (BOOL) setDisplayWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh
{
	OOLogGenericSubclassResponsibility();
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)d_refresh
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode
{
	
}

@end
