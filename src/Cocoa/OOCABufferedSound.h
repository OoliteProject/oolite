/*

OOCABufferedSound.h

Subclass of OOSound playing from an in-memory buffer.

This class is an implementation detail. Do not use it directly; use OOSound.

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006  Jens Ayton

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

#import <Cocoa/Cocoa.h>
#import "OOCASound.h"

@class OOCASoundDecoder;


@interface OOCABufferedSound: OOSound
{
	float				*_bufferL,
						*_bufferR;
	size_t				_size;
	Float64				_sampleRate;
	NSString			*_name;
	BOOL				_stereo;
}

- (id)initWithDecoder:(OOCASoundDecoder *)inDecoder;

@end
