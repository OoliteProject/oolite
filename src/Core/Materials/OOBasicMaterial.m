/*

OOBasicMaterial.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOBasicMaterial.h"
#import "OOCollectionExtractors.h"
#import "OOFunctionAttributes.h"
#import "Universe.h"


static OOBasicMaterial *sDefaultMaterial = nil;


#define FACE		GL_FRONT_AND_BACK


@implementation OOBasicMaterial

- (id)initWithName:(NSString *)name
{
	self = [super init];
	if (EXPECT_NOT(self == nil))  return nil;
	
	materialName = [name copy];
	
	[self setDiffuseRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
	[self setAmbientRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
	specular[3] = 1.0;
	emission[3] = 1.0;
	
	return self;
}


- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration
{
	id					colorDesc = nil;
	int					shininessVal;
	
	self = [self initWithName:name];
	if (EXPECT_NOT(self == nil))  return nil;
	
	if (configuration == nil)  configuration = [NSDictionary dictionary];
	
	colorDesc = [configuration objectForKey:@"diffuse"];
	if (colorDesc != nil)  [self setDiffuseColor:[OOColor colorWithDescription:colorDesc]];
	
	colorDesc = [configuration objectForKey:@"ambient"];
	if (colorDesc != nil)  [self setAmbientColor:[OOColor colorWithDescription:colorDesc]];
	else  [self setAmbientColor:[self diffuseColor]];
	
	colorDesc = [configuration objectForKey:@"emission"];
	if (colorDesc != nil)  [self setEmissionColor:[OOColor colorWithDescription:colorDesc]];
	
	shininessVal = [configuration oo_intForKey:@"shininess" defaultValue:-1];
	if (shininessVal != 0 && ![UNIVERSE reducedDetail])
	{
		colorDesc = [configuration objectForKey:@"specular"];
		if (shininessVal < 0)
		{
			shininessVal = 10;
			if (colorDesc == nil)  colorDesc = @"0.2 0.2 0.2 1.0";
		}
		[self setShininess:shininessVal];
		if (colorDesc != nil)  [self setSpecularColor:[OOColor colorWithDescription:colorDesc]];
	}
	
	return self;
}


- (void)dealloc
{
	[super willDealloc];
	[materialName release];
	
	[super dealloc];
}


- (NSString *)name
{
	return materialName;
}


- (BOOL)doApply
{
	glMaterialfv(FACE, GL_DIFFUSE, diffuse);
	glMaterialfv(FACE, GL_SPECULAR, specular);
	glMaterialfv(FACE, GL_AMBIENT, ambient);
	glMaterialfv(FACE, GL_EMISSION, emission);
	glMateriali(FACE, GL_SHININESS, shininess);
	
	return YES;
}


- (void)unapplyWithNext:(OOMaterial *)next
{
	if (![next isKindOfClass:[OOBasicMaterial class]])
	{
		if (EXPECT_NOT(sDefaultMaterial == nil))  sDefaultMaterial = [[OOBasicMaterial alloc] initWithName:@"<default material>"];
		[sDefaultMaterial doApply];
	}
}


- (OOColor *)diffuseColor
{
	return [OOColor colorWithCalibratedRed:diffuse[0]
									 green:diffuse[1]
									  blue:diffuse[2]
									 alpha:diffuse[3]];
}


- (void)setDiffuseColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setDiffuseRed:[color redComponent] 
					  green:[color greenComponent]
					   blue:[color blueComponent]
					  alpha:[color alphaComponent]];
	}
}


- (void)setAmbientAndDiffuseColor:(OOColor *)color
{
	[self setAmbientColor:color];
	[self setDiffuseColor:color];
}


- (OOColor *)specularColor
{
	return [OOColor colorWithCalibratedRed:specular[0]
									 green:specular[1]
									  blue:specular[2]
									 alpha:specular[3]];
}


- (void)setSpecularColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setSpecularRed:[color redComponent] 
					   green:[color greenComponent]
						blue:[color blueComponent]
					   alpha:[color alphaComponent]];
	}
}


- (OOColor *)ambientColor
{
	return [OOColor colorWithCalibratedRed:ambient[0]
									 green:ambient[1]
									  blue:ambient[2]
									 alpha:ambient[3]];
}


- (void)setAmbientColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setAmbientRed:[color redComponent] 
					  green:[color greenComponent]
					   blue:[color blueComponent]
					  alpha:[color alphaComponent]];
	}
}


- (OOColor *)emmisionColor
{
	return [OOColor colorWithCalibratedRed:emission[0]
									 green:emission[1]
									  blue:emission[2]
									 alpha:emission[3]];
}


- (void)setEmissionColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setEmissionRed:[color redComponent] 
					   green:[color greenComponent]
						blue:[color blueComponent]
					   alpha:[color alphaComponent]];
	}
}


- (void)getDiffuseComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, diffuse, 4 * sizeof *outComponents);
}


- (void)setDiffuseComponents:(const GLfloat[4])components
{
	memcpy(diffuse, components, 4 * sizeof *components);
}


- (void)setAmbientAndDiffuseComponents:(const GLfloat[4])components
{
	[self setAmbientComponents:components];
	[self setDiffuseComponents:components];
}


- (void)getSpecularComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, specular, 4 * sizeof *outComponents);
}


- (void)setSpecularComponents:(const GLfloat[4])components
{
	memcpy(specular, components, 4 * sizeof *components);
}


- (void)getAmbientComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, ambient, 4 * sizeof *outComponents);
}


- (void)setAmbientComponents:(const GLfloat[4])components
{
	memcpy(ambient, components, 4 * sizeof *components);
}


- (void)getEmissionComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, emission, 4 * sizeof *outComponents);
}


- (void)setEmissionComponents:(const GLfloat[4])components
{
	memcpy(emission, components, 4 * sizeof *components);
}


- (void)setDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	diffuse[0] = r;
	diffuse[1] = g;
	diffuse[2] = b;
	diffuse[3] = a;
}


- (void)setAmbientAndDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	[self setAmbientRed:r green:g blue:b alpha:a];
	[self setDiffuseRed:r green:g blue:b alpha:a];
}


- (void)setSpecularRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	specular[0] = r;
	specular[1] = g;
	specular[2] = b;
	specular[3] = a;
}


- (void)setAmbientRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	ambient[0] = r;
	ambient[1] = g;
	ambient[2] = b;
	ambient[3] = a;
}


- (void)setEmissionRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	emission[0] = r;
	emission[1] = g;
	emission[2] = b;
	emission[3] = a;
}



- (uint8_t)shininess
{
	return shininess;
}


- (void)setShininess:(uint8_t)value
{
	shininess = MIN(value, 128);
}

@end
