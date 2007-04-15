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

*/

#ifndef NO_SHADERS

#import "OOShaderMaterial.h"
#import "OOShaderUniform.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOShaderProgram.h"
#import "OOTexture.h"
#import "OOOpenGLExtensionManager.h"


static NSString *MacrosToString(NSDictionary *macros);


@interface OOShaderMaterial (OOPrivate)

- (void)addTexturesFromArray:(NSArray *)textureNames unitCount:(GLint)max;

@end


@implementation OOShaderMaterial

+ (id)shaderWithConfiguration:(NSDictionary *)configuration macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)target
{
	return [[[self alloc] initWithConfiguration:configuration macros:macros bindingTarget:target] autorelease];
}


- (id)initWithConfiguration:(NSDictionary *)configuration macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)target
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
	
	self = [super initWithConfiguration:configuration];
	if (self == nil)  OK = NO;
	
	if (OK && configuration == nil)  OK = NO;
	if (OK)
	{
		modifiedMacros = macros ? [macros mutableCopy] : [[NSMutableDictionary alloc] init];
		
		glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, &textureUnits);
		[modifiedMacros setObject:[NSNumber numberWithInt:textureUnits] forKey:@"OO_TEXTURE_UNIT_COUNT"];
		
		macroString = MacrosToString(modifiedMacros);
	}
	
	if (OK)
	{
		vertexShader = [configuration stringForKey:@"vertex_shader" defaultValue:nil];
		fragmentShader = [configuration stringForKey:@"fragment_shader" defaultValue:nil];
		
		if (vertexShader != nil || fragmentShader != nil)
		{
			// If either shader is in an external file, use external-file-based shader (more efficient due to instance sharing)
			shaderProgram = [OOShaderProgram shaderProgramWithVertexShaderName:vertexShader fragmentShaderName:fragmentShader prefix:macroString];
		}
		else
		{
			// Otherwise, look for inline source
			vertexShader = [configuration stringForKey:@"glsl-vertex" defaultValue:nil];
			fragmentShader = [configuration stringForKey:@"glsl-fragment" defaultValue:nil];
			if (fragmentShader == nil)  fragmentShader = [configuration stringForKey:@"glsl" defaultValue:nil];
			
			if (vertexShader != nil || fragmentShader != nil)
			{
				shaderProgram = [OOShaderProgram shaderProgramWithVertexShaderSource:vertexShader fragmentShaderSource:fragmentShader prefix:macroString];
			}
			else
			{
				OOLog(@"shader.load.noShader", @"***** Error: no vertex or fragment shader specified specified in shader dictionary:\n%@", configuration);
			}
		}
		
		OK = (shaderProgram != nil);
		if (OK)  [shaderProgram retain];
	}
	
	if (OK)
	{
		// Load uniforms
		uniformDefs = [configuration dictionaryForKey:@"uniforms" defaultValue:nil];
		textureDefs = [configuration arrayForKey:@"textures" defaultValue:nil];
		
		uniforms = [[NSMutableDictionary alloc] initWithCapacity:[uniformDefs count] + [textureDefs count]];
		[self addUniformsFromDictionary:uniformDefs withBindingTarget:target];
		
		// ...and textures, which are a flavour of uniform four our purpose.
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
	
	[super dealloc];
}


- (void)bindUniform:(NSString *)uniformName
		   toObject:(id<OOWeakReferenceSupport>)source
		   property:(SEL)selector
			clamped:(BOOL)clamped
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return;
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName	shaderProgram:shaderProgram boundToObject:source property:selector clamped:clamped];
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
	NSString				*type = nil;
	GLfloat					floatValue;
	BOOL					gotValue;
	OOShaderUniform			*uniform = nil;
	BOOL					clamped;
	SEL						selector = NULL;
	
	for (uniformEnum = [uniformDefs keyEnumerator]; (name = [uniformEnum nextObject]); )
	{
		gotValue = NO;
		uniform = nil;
		definition = [uniformDefs objectForKey:name];
		
		if ([definition isKindOfClass:[NSDictionary class]])
		{
			value = [definition objectForKey:@"value"];
			type = [definition objectForKey:@"type"];
		}
		else
		{
			value = definition;
			type = @"float";
		}
		
		if ([type isEqualToString:@"float"])
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
		else if ([type isEqualToString:@"int"] || [type isEqualToString:@"texture"])
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
			selector = NSSelectorFromString(value);
			if (selector)
			{
				clamped = [definition boolForKey:@"clamped" defaultValue:NO];
				[self bindUniform:name toObject:target property:selector clamped:clamped];
				gotValue = YES;
			}
		}
		
		if (!gotValue)
		{
			OOLog(@"shader.uniform.badDescription", @"----- Warning: could not bind uniform \"%@\" -- could not interpret definition:\n", name, definition);
		}
	}
}


- (BOOL)doApply
{
	NSEnumerator			*uniformEnum = nil;
	OOShaderUniform			*uniform = nil;
	uint32_t				i;
	
	[shaderProgram apply];
	
	for (i = 0; i != texCount; ++i)
	{
		glActiveTextureARB(GL_TEXTURE0_ARB + i);
		/*glBindTexture(GL_TEXTURE_2D, textures[i]);*/
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
	if (![next isKindOfClass:[OOShaderMaterial class]])	// Avoid redundant state change
	{
		[OOShaderProgram applyNone];
	}
}

@end


@implementation OOShaderMaterial (OOPrivate)

- (void)addTexturesFromArray:(NSArray *)textureNames unitCount:(GLint)max
{
	id						textureDef = nil;
	unsigned				i = 0;
	
	// Allocate space for texture object name array
	texCount = MAX(MIN(max, [textureNames count]), 0);
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
