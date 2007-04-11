/*

OOShaderUniform.h

Manages a uniform variable for OOShaderMaterial.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#ifndef NO_SHADERS

#import "OOShaderMaterial.h"


@interface OOShaderUniform: NSObject
{
	NSString					*name;
	GLint						location;
	BOOL						isBinding;
	uint8_t						type;
	union
	{
		GLint						constInt;
		GLfloat						constFloat;
		struct
		{
			OOWeakReference				*object;
			SEL							selector;
			IMP							method;
			BOOL						clamped;
		}							binding;
	}							value;
}

- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram intValue:(int)constValue;
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram floatValue:(int)constValue;
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram boundToObject:(id<OOWeakReferenceSupport>)source property:(SEL)selector clamped:(BOOL)clamped;

- (void)apply;

@end

#endif // NO_SHADERS
