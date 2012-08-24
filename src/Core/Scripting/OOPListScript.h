/*

OOPListScript.h

Property list-based script.

I started off reimplementing plist scripting here, in order to remove one of
PlayerEntity's many overloaded functions. The scale of the task was such that
I've stepped back, and this simply wraps the old plist scripting in
PlayerEntity.


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

#import "OOScript.h"


@interface OOPListScript: OOScript
{
@private
	NSArray					*_script;
	NSDictionary			*_metadata;
}

+ (NSArray *)scriptsInPListFile:(NSString *)filePath;

@end
