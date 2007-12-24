/*

OOShaderMaterial.m

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

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef NO_SHADERS

#import "OOShaderMaterial.h"
#import "OOShaderUniform.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOShaderProgram.h"
#import "OOTexture.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMacroOpenGL.h"
#import "Universe.h"


static NSString *MacrosToString(NSDictionary *macros);


@interface OOShaderMaterial (OOPrivate)

- (void)addTexturesFromArray:(NSArray *)textureNames unitCount:(GLuint)max;

@end


@implementation OOShaderMaterial

+ (BOOL)configurationDictionarySpecifiesShaderMaterial:(NSDictionary *)configuration
{
	if (configuration == nil)  return NO;
	
	if ([configuration stringForKey:@"vertex_shader"] != nil)  return YES;
	if ([configuration stringForKey:@"fragment_shader"] != nil)  return YES;
	
	return NO;
}


+ (id)shaderMaterialWithName:(NSString *)name
			   configuration:(NSDictionary *)configuration
					  macros:(NSDictionary *)macros
			   bindingTarget:(id<OOWeakReferenceSupport>)target
{
	return [[[self alloc] initWithName:name configuration:configuration macros:macros bindingTarget:target] autorelease];
}


- (id)initWithName:(NSString *)name
	 configuration:(NSDictionary *)configuration
			macros:(NSDictionary *)macros
	 bindingTarget:(id<OOWeakReferenceSupport>)target
{
	BOOL					OK = YES;
	NSDictionary			*uniformDefs = nil;
	NSArray					*textureDefs = nil;
	NSString				*macroString = nil;
	NSString				*vertexShader = nil;
	NSString				*fragmentShader = nil;
	GLint					textureUnits;
	NSMutableDictionary		*modifiedMacros = nil;
	
	if (configuration == nil)  OK = NO;
	
	OO_ENTER_OPENGL();
	
	self = [super initWithName:name configuration:configuration];
	if (self == nil)  OK = NO;
	
	if (OK)
	{
		modifiedMacros = macros ? [macros mutableCopy] : [[NSMutableDictionary alloc] init];
		
		glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, &textureUnits);
		[modifiedMacros setObject:[NSNumber numberWithInt:textureUnits] forKey:@"OO_TEXTURE_UNIT_COUNT"];
		
		if ([UNIVERSE shaderEffectsLevel] == SHADERS_SIMPLE)
		{
			[modifiedMacros setObject:[NSNumber numberWithInt:1] forKey:@"OO_REDUCED_COMPLEXITY"];
		}
		
		macroString = MacrosToString(modifiedMacros);
		[modifiedMacros release];
	}
	
	if (OK)
	{
		vertexShader = [configuration stringForKey:@"vertex_shader"];
		fragmentShader = [configuration stringForKey:@"fragment_shader"];
		
		if (vertexShader != nil || fragmentShader != nil)
		{
			shaderProgram = [OOShaderProgram shaderProgramWithVertexShaderName:vertexShader fragmentShaderName:fragmentShader prefix:macroString];
		}
		else
		{
			OOLog(@"shader.load.noShader", @"***** Error: no vertex or fragment shader specified specified in shader dictionary:\n%@", configuration);
		}
		
		OK = (shaderProgram != nil);
		if (OK)  [shaderProgram retain];
	}
	
	if (OK)
	{
		// Load uniforms
		uniformDefs = [configuration dictionaryForKey:@"uniforms"];
		textureDefs = [configuration arrayForKey:@"textures"];
		
		uniforms = [[NSMutableDictionary alloc] initWithCapacity:[uniformDefs count] + [textureDefs count]];
		[self addUniformsFromDictionary:uniformDefs withBindingTarget:target];
		// ...and textures, which are a flavour of uniform for our purpose.
		[self addTexturesFromArray:textureDefs unitCount:textureUnits];
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}


- (void)dealloc
{
	uint32_t			i;
	
	[self willDealloc];
	
	[shaderProgram release];
	[uniforms release];
	
	if (textures != NULL)
	{
		for (i = 0; i != texCount; ++i)
		{
			[textures[i] release];
		}
		free(textures);
	}
	
	[bindingTarget release];
	
	[super dealloc];
}


- (void)bindUniform:(NSString *)uniformName
		   toObject:(id<OOWeakReferenceSupport>)source
		   property:(SEL)selector
	 convertOptions:(OOUniformConvertOptions)options
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return;
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName
									  shaderProgram:shaderProgram
									  boundToObject:source
										   property:selector
									 convertOptions:options];
	if (uniform != nil)
	{
		OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
		[uniforms setObject:uniform forKey:uniformName];
		[uniform release];
	}
	else
	{
		OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", uniformName);
		[uniforms removeObjectForKey:uniformName];
	}
}


- (void)setUniform:(NSString *)uniformName intValue:(int)value
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return;
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName shaderProgram:shaderProgram intValue:value];
	if (uniform != nil)
	{
		OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
		[uniforms setObject:uniform forKey:uniformName];
		[uniform release];
	}
	else
	{
		OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", uniformName);
		[uniforms removeObjectForKey:uniformName];
	}
}


- (void)setUniform:(NSString *)uniformName floatValue:(float)value
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return;
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName shaderProgram:shaderProgram floatValue:value];
	if (uniform != nil)
	{
		OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
		[uniforms setObject:uniform forKey:uniformName];
		[uniform release];
	}
	else
	{
		OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", uniformName);
		[uniforms removeObjectForKey:uniformName];
	}
}


-(void)addUniformsFromDictionary:(NSDictionary *)uniformDefs withBindingTarget:(id<OOWeakReferenceSupport>)target
{
	NSEnumerator			*uniformEnum = nil;
	NSString				*name = nil;
	id						definition = nil;
	id						value = nil;
	NSString				*binding = nil;
	NSString				*type = nil;
	GLfloat					floatValue;
	BOOL					gotValue;
	OOShaderUniform			*uniform = nil;
	SEL						selector = NULL;
	OOUniformConvertOptions	convertOptions;
	
	for (uniformEnum = [uniformDefs keyEnumerator]; (name = [uniformEnum nextObject]); )
	{
		gotValue = NO;
		uniform = nil;
		definition = [uniformDefs objectForKey:name];
		
		type = nil;
		value = nil;
		binding = nil;
		
		if ([definition isKindOfClass:[NSDictionary class]])
		{
			value = [definition objectForKey:@"value"];
			binding = [definition objectForKey:@"binding"];
			type = [definition objectForKey:@"type"];
			if (type == nil)
			{
				if (value == nil && binding != nil)  type = @"binding";
				else  type = @"float";
			}
		}
		else if ([definition isKindOfClass:[NSNumber class]])
		{
			value = definition;
			type = @"float";
		}
		else if ([definition isKindOfClass:[NSString class]])
		{
			binding = definition;
			type = @"binding";
		}
		
		if ([type isEqualToString:@"float"] || [type isEqualToString:@"real"])
		{
			gotValue = YES;
			if ([value respondsToSelector:@selector(floatValue)])  floatValue = [value floatValue];
			else if ([value respondsToSelector:@selector(doubleValue)])  floatValue = [value doubleValue];
			else if ([value respondsToSelector:@selector(intValue)])  floatValue = [value intValue];
			else gotValue = NO;
			
			if (gotValue)
			{
				[self setUniform:name floatValue:floatValue];
			}
		}
		else if ([type isEqualToString:@"int"] || [type isEqualToString:@"integer"] || [type isEqualToString:@"texture"])
		{
			/*	"texture" is allowed as a synonym for "int" because shader#d
				uniforms are mapped to texture units by specifying an integer
				index.
				uniforms = { diffuseMap = { type = texture; value = 0; }; };
				means "bind uniform diffuseMap to texture unit 0" (which will
				have the first texture in the textures array).
			*/
			if ([value respondsToSelector:@selector(intValue)])
			{
				[self setUniform:name intValue:[value intValue]];
				gotValue = YES;
			}
		}
		else if (target != nil && [type isEqualToString:@"binding"])
		{
			selector = NSSelectorFromString(binding);
			if (selector)
			{
				if ([definition isKindOfClass:[NSDictionary class]])
				{
					convertOptions = 0;
					if ([definition boolForKey:@"clamped" defaultValue:NO])  convertOptions |= kOOUniformConvertClamp;
					if ([definition boolForKey:@"normalized" defaultValue:[definition boolForKey:@"normalised" defaultValue:NO]])
					{
						convertOptions |= kOOUniformConvertNormalize;
					}
					if ([definition boolForKey:@"asMatrix" defaultValue:YES])  convertOptions |= kOOUniformConvertToMatrix;
					if (![definition boolForKey:@"bindToSubentity" defaultValue:NO])  convertOptions |= kOOUniformBindToSuperTarget;
				}
				else
				{
					convertOptions = kOOUniformConvertDefaults;
				}
				
				[self bindUniform:name toObject:target property:selector convertOptions:convertOptions];
				gotValue = YES;
			}
		}
		
		if (!gotValue)
		{
			OOLog(@"shader.uniform.badDescription", @"----- Warning: could not bind uniform \"%@\" for target %@ -- could not interpret definition:\n%@", name, target, definition);
		}
	}
}


- (BOOL)doApply
{
	NSEnumerator			*uniformEnum = nil;
	OOShaderUniform			*uniform = nil;
	uint32_t				i;
	
	OO_ENTER_OPENGL();
	
	[super doApply];
	[shaderProgram apply];
	
	for (i = 0; i != texCount; ++i)
	{
		glActiveTextureARB(GL_TEXTURE0_ARB + i);
		[textures[i] apply];
	}
	glActiveTextureARB(GL_TEXTURE0_ARB);
	
	NS_DURING
		for (uniformEnum = [uniforms objectEnumerator]; (uniform = [uniformEnum nextObject]); )
		{
			[uniform apply];
		}
	NS_HANDLER
		/*	Supress exceptions during application of bound uniforms. We use a
			single exception handler around all uniforms because ObjC
			exceptions have some overhead.
		*/
	NS_ENDHANDLER
	
	return YES;
}


- (void)ensureFinishedLoading
{
	uint32_t			i;
	
	if (textures != NULL)
	{
		for (i = 0; i != texCount; ++i)
		{
			[textures[i] ensureFinishedLoading];
		}
	}
}


- (void)unapplyWithNext:(OOMaterial *)next
{
	uint32_t				i, count;
	
	if (![next isKindOfClass:[OOShaderMaterial class]])	// Avoid redundant state change
	{
		OO_ENTER_OPENGL();
		[OOShaderProgram applyNone];
		
		/*	BUG: unapplyWithNext: was failing to clear texture state. If a
			shader material was followed by a basic material (with no texture),
			the shader's #0 texture would be used.
			It is necessary to clear at least one texture for the case where a
			shader material with textures is followed by a shader material
			without textures, then a basic material.
			-- Ahruman 2007-08-13
		*/
		count = texCount ? texCount : 1;
		for (i = 0; i != count; ++i)
		{
			glActiveTextureARB(GL_TEXTURE0_ARB + i);
			glBindTexture(GL_TEXTURE_2D, 0);
		}
		glActiveTextureARB(GL_TEXTURE0_ARB);
	}
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	if (target != [bindingTarget weakRefUnderlyingObject])
	{
		[[uniforms allValues] makeObjectsPerformSelector:@selector(setBindingTarget:) withObject:target];
		[bindingTarget release];
		bindingTarget = [target weakRetain];
	}
}

@end


@implementation OOShaderMaterial (OOPrivate)

- (void)addTexturesFromArray:(NSArray *)textureNames unitCount:(GLuint)max
{
	id						textureDef = nil;
	unsigned				i = 0;
	
	// Allocate space for texture object name array
	texCount = MAX(MIN(max, [textureNames count]), 0U);
	if (texCount == 0)  return;
	
	textures = malloc(texCount * sizeof *textures);
	if (textures == NULL)
	{
		texCount = 0;
		return;
	}
	
	// Set up texture object names and appropriate uniforms
	for (i = 0; i != texCount; ++i)
	{
		[self setUniform:[NSString stringWithFormat:@"tex%u", i] intValue:i];
		
		textureDef = [textureNames objectAtIndex:i];
		textures[i] = [[OOTexture textureWithConfiguration:textureDef] retain];
	}
}

@end


static NSString *MacrosToString(NSDictionary *macros)
{
	NSMutableString			*result = nil;
	NSEnumerator			*macroEnum = nil;
	id						key = nil, value = nil;
	
	if (macros == nil)  return nil;
	
	result = [NSMutableString string];
	for (macroEnum = [macros keyEnumerator]; (key = [macroEnum nextObject]); )
	{
		if (![key isKindOfClass:[NSString class]]) continue;
		value = [macros objectForKey:key];
		
		[result appendFormat:@"#define %@  %@\n", key, value];
	}
	
	if ([result length] == 0) return nil;
	[result appendString:@"\n\n"];
	return result;
}

#endif // NO_SHADERS
