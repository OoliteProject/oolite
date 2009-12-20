/*

OOMaterial.m


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

#import "OOMaterial.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"

#import "OOOpenGLExtensionManager.h"
#import "OOShaderMaterial.h"
#import "OOSingleTextureMaterial.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "OOCacheManager.h"


static OOMaterial *sActiveMaterial = nil;


@implementation OOMaterial

+ (void)setUp
{
	// I thought we'd need this, but the stuff I needed it for turned out to be problematic. Maybe in future. -- Ahruman
}


- (void)dealloc
{
	// Ensure cleanup happens; doing it more than once is safe.
	[self willDealloc];
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%@}", [self className], self, [self name]];
}


- (NSString *)name
{
	OOLogGenericParameterError();
	return nil;
}


// Make this the current GL shader program.
- (void)apply
{
	[sActiveMaterial unapplyWithNext:self];
	[sActiveMaterial release];
	sActiveMaterial = nil;
	
	if ([self doApply])
	{
		sActiveMaterial = [self retain];
	}
}


+ (void)applyNone
{
	[sActiveMaterial unapplyWithNext:nil];
	[sActiveMaterial release];
	sActiveMaterial = nil;
}


+ (OOMaterial *)current
{
	return [[sActiveMaterial retain] autorelease];
}


- (void)ensureFinishedLoading
{
	
}


- (BOOL) isFinishedLoading
{
	return YES;
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	
}

@end


static void SetUniform(NSMutableDictionary *uniforms, NSString *key, NSString *type, id value)
{
	[uniforms setObject:[NSDictionary dictionaryWithObjectsAndKeys:type, @"type", value, @"value", nil] forKey:key];
}


static void SetUniformFloat(NSMutableDictionary *uniforms, NSString *key, float value)
{
	SetUniform(uniforms, key, @"float", [NSNumber numberWithFloat:value]);
}


static void AddTexture(NSMutableDictionary *uniforms, NSMutableArray *textures, NSString *key, NSString *fileName)
{
	SetUniform(uniforms, key, @"texture", [NSNumber numberWithInt:[textures count]]);
	[textures addObject:fileName];
}


@implementation OOMaterial (OOConvenienceCreators)

+ (NSDictionary *)synthesizeMaterialDictionaryWithName:(NSString *)name
										 forModelNamed:(NSString *)modelName
										 configuration:(NSDictionary *)configuration
												macros:(NSDictionary *)macros
{
	OOColor					*ambient = nil,
							*diffuse = nil,
							*specular = nil,
							*emission = nil;
	int						shininess = 0;
	NSString				*diffuseMap = nil,
							*specularMap = nil,
							*emissionMap = nil,
							*emissionAndIlluminationMap = nil,
							*illuminationMap = nil,
							*normalMap = nil,
							*normalAndParallaxMap = nil;
	float					parallaxScale,
							parallaxBias;
	NSMutableDictionary		*modifiedMacros = nil;
	NSMutableArray			*textures = nil;
	NSMutableDictionary		*newConfig = nil;
	NSMutableDictionary		*uniforms = nil;
	NSNumber				*one = [NSNumber numberWithInt:1];
	
	if (configuration == nil)  configuration = [NSDictionary dictionary];	// If it's nil, lookups will always give 0/nil results regardless of defaultValue:.
	ambient = [OOColor colorWithDescription:[configuration objectForKey:@"ambient"]];
	diffuse = [OOColor colorWithDescription:[configuration objectForKey:@"diffuse"]];
	specular = [OOColor colorWithDescription:[configuration objectForKey:@"specular"]];
	emission = [OOColor colorWithDescription:[configuration objectForKey:@"emission"]];
	shininess = [configuration oo_intForKey:@"shininess" defaultValue:-1];
	diffuseMap = [configuration oo_stringForKey:@"diffuse_map"];
	specularMap = [configuration oo_stringForKey:@"specular_map"];
	emissionMap = [configuration oo_stringForKey:@"emission_map"];
	emissionAndIlluminationMap = [configuration oo_stringForKey:@"emission_and_illumination_map"];
	illuminationMap = [configuration oo_stringForKey:@"illumination_map"];
	normalMap = [configuration oo_stringForKey:@"normal_map"];
	normalAndParallaxMap = [configuration oo_stringForKey:@"normal_and_parallax_map"];
	parallaxScale = [configuration oo_floatForKey:@"parallax_scale" defaultValue:0.01];
	parallaxBias = [configuration oo_floatForKey:@"parallax_bias" defaultValue:0.00];
	
	if (diffuseMap == nil)  diffuseMap = name;
	
	if (diffuse == nil)  diffuse = [OOColor whiteColor];
	if (emissionAndIlluminationMap != nil && illuminationMap != nil)
	{
		// Can't have both emissionAndIlluminationMap and illuminationMap
		if (emissionMap == nil)  emissionMap = emissionAndIlluminationMap;
		emissionAndIlluminationMap = nil;
	}
	
	// If there's a parallax map, it's always part of the one and only normal map
	if (normalAndParallaxMap != nil)  normalMap = normalAndParallaxMap;
	
	// Shininess 0 or nil/black specular colour means no specular.
	if (shininess == 0 || [specular isBlack])
	{
		specular = nil;
	}
	
	// No specular means no specular map.
	if (specular == nil)  specularMap = nil;
	
	if ([emission isBlack])  emission = nil;
	
	modifiedMacros = macros ? [[macros mutableCopy] autorelease] : [NSMutableDictionary dictionaryWithCapacity:8];
	
	// Create a synthetic configuration dictionary.
	textures = [NSMutableArray arrayWithCapacity:4];
	newConfig = [NSMutableDictionary dictionaryWithCapacity:16];
	uniforms = [NSMutableDictionary dictionaryWithCapacity:6];
	
	[newConfig setObject:[NSNumber numberWithBool:YES] forKey:@"_oo_is_synthesized_config"];
	[newConfig setObject:@"oolite-tangent-space-vertex.vertex" forKey:@"vertex_shader"];
	[newConfig setObject:@"oolite-default-shader.fragment" forKey:@"fragment_shader"];
	
	if (ambient != nil)  [newConfig setObject:[ambient normalizedArray] forKey:@"ambient"];
	if (diffuse != nil)  [newConfig setObject:[diffuse normalizedArray] forKey:@"diffuse"];
	if (emission != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_EMISSION"];
		[newConfig setObject:[emission normalizedArray] forKey:@"emission"];
	}
	if (shininess != 0)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_SPECULAR"];
		if (specular != nil)  [newConfig setObject:[specular normalizedArray] forKey:@"specular"];
		if (shininess > 0)  [newConfig setObject:[NSNumber numberWithUnsignedInt:shininess] forKey:@"shininess"];
		if (specularMap != nil)
		{
			[modifiedMacros setObject:one forKey:@"OOSTD_SPECULAR_MAP"];
			AddTexture(uniforms, textures, @"uSpecularMap", specularMap);
		}
	}
	[newConfig setObject:diffuseMap forKey:@"diffuse_map"];
	if (![diffuseMap isEqualToString:@""])	// empty string, not nil, means no diffuse map
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_DIFFUSE_MAP"];
		AddTexture(uniforms, textures, @"uDiffuseMap", diffuseMap);
	}
	if (emissionMap != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_EMISSION_MAP"];
		AddTexture(uniforms, textures, @"uEmissionMap", emissionMap);
	}
	else if (emissionAndIlluminationMap != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_EMISSION_AND_ILLUMINATION_MAP"];
		AddTexture(uniforms, textures, @"uEmissionMap", emissionAndIlluminationMap);
	}
	if (illuminationMap != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_ILLUMINATION_MAP"];
		AddTexture(uniforms, textures, @"uIlluminationMap", illuminationMap);
	}
	if (normalMap != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_NORMAL_MAP"];
		AddTexture(uniforms, textures, @"uNormalMap", normalMap);
		if (normalAndParallaxMap != nil)
		{
			[modifiedMacros setObject:one forKey:@"OOSTD_NORMAL_AND_PARALLAX_MAP"];
			SetUniformFloat(uniforms, @"uParallaxScale", parallaxScale);
			SetUniformFloat(uniforms, @"uParallaxBias", parallaxBias);
		}
	}
	if ([UNIVERSE shaderEffectsLevel] == SHADERS_FULL)
	{
		// Add uniforms required for hull heat glow
		[uniforms setObject:@"hullHeatLevel" forKey:@"uHullHeatLevel"];
		[uniforms setObject:@"timeElapsedSinceSpawn" forKey:@"uTime"];
	}
	
	if ([textures count] != 0)  [newConfig setObject:textures forKey:@"textures"];
	if ([uniforms count] != 0)  [newConfig setObject:uniforms forKey:@"uniforms"];
	
	[newConfig setObject:modifiedMacros forKey:@"_oo_synthesized_material_macros"];
	return newConfig;
}


+ (OOMaterial *)defaultShaderMaterialWithName:(NSString *)name
								forModelNamed:(NSString *)modelName
								configuration:(NSDictionary *)configuration
									   macros:(NSDictionary *)macros
								bindingTarget:(id<OOWeakReferenceSupport>)target
{
	OOCacheManager			*cache = nil;
	NSString				*cacheKey = nil;
	NSDictionary			*synthesizedConfig = nil;
	OOMaterial				*result = nil;
	
	// Avoid looping (can happen if shader fails to compile).
	if ([configuration objectForKey:@"_oo_is_synthesized_config"] != nil)
	{
		OOLog(@"material.synthesize.loop", @"Synthesis loop for material %@.", name);
		return nil;
	}
	
	if (modelName != nil)
	{
		cache = [OOCacheManager sharedCache];
		cacheKey = [NSString stringWithFormat:@"%@/%@", modelName, name];
		synthesizedConfig = [cache objectForKey:cacheKey inCache:@"synthesized shader materials"];
	}
	
	if (synthesizedConfig == nil)
	{
		synthesizedConfig = [self synthesizeMaterialDictionaryWithName:name
														 forModelNamed:modelName
														 configuration:configuration
																macros:macros];
		if (synthesizedConfig != nil && modelName != nil)
		{
			[cache setObject:synthesizedConfig
					  forKey:cacheKey
					 inCache:@"synthesized shader materials"];
		}
	}
	
	if (synthesizedConfig != nil)
	{
		result =  [self materialWithName:name
						   forModelNamed:modelName
						   configuration:synthesizedConfig
								  macros:[synthesizedConfig objectForKey:@"_oo_synthesized_material_macros"]
						   bindingTarget:target
						 forSmoothedMesh:YES];
	}
	
	return result;
}


+ (id)materialWithName:(NSString *)name
		 forModelNamed:(NSString *)modelName
		 configuration:(NSDictionary *)configuration
				macros:(NSDictionary *)macros
		 bindingTarget:(id<OOWeakReferenceSupport>)object
	   forSmoothedMesh:(BOOL)smooth
{
	id						result = nil;
	
#ifndef NO_SHADERS
	if ([UNIVERSE useShaders])
	{
		if ([OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:configuration])
		{
			result = [OOShaderMaterial shaderMaterialWithName:name
												configuration:configuration
													   macros:macros
												bindingTarget:object];
		}
		
		// Use default shader if smoothing is on, or shader detail is full, or material uses an effect map.
		if (result == nil &&
				(smooth ||
				 [UNIVERSE shaderEffectsLevel] == SHADERS_FULL ||
				 [configuration objectForKey:@"specular_map"] != nil ||
				 [configuration objectForKey:@"emission_map"] != nil ||
				 [configuration objectForKey:@"illumination_map"] != nil ||
				 [configuration objectForKey:@"emission_and_illumination_map"] != nil
				 ))
		{
			result = [self defaultShaderMaterialWithName:name
										   forModelNamed:modelName
										   configuration:configuration
												  macros:macros
										   bindingTarget:(id<OOWeakReferenceSupport>)object];
		}
	}
#endif
	
	if (result == nil)
	{
		if ([[configuration objectForKey:@"diffuse_map"] isEqual:@""])
		{
			result = [[OOBasicMaterial alloc] initWithName:name configuration:configuration];
		}
		else
		{
			result = [[OOSingleTextureMaterial alloc] initWithName:name configuration:configuration];
		}
		if (result == nil)
		{
			result = [[OOBasicMaterial alloc] initWithName:name configuration:configuration];
		}
		[result autorelease];
	}
	return result;
}


+ (id)materialWithName:(NSString *)name
		 forModelNamed:(NSString *)modelName
	materialDictionary:(NSDictionary *)materialDict
	 shadersDictionary:(NSDictionary *)shadersDict
				macros:(NSDictionary *)macros
		 bindingTarget:(id<OOWeakReferenceSupport>)object
	   forSmoothedMesh:(BOOL)smooth
{
	NSDictionary			*configuration = nil;
	
#ifndef NO_SHADERS
	if ([UNIVERSE useShaders])
	{
		configuration = [shadersDict oo_dictionaryForKey:name];
	}
#endif
	
	if (configuration == nil)
	{
		configuration = [materialDict oo_dictionaryForKey:name];
	}
	
	return [self materialWithName:name
					forModelNamed:modelName
					configuration:configuration
						   macros:macros
					bindingTarget:object
				  forSmoothedMesh:smooth];
}

@end


@implementation OOMaterial (OOSubclassInterface)

- (BOOL)doApply
{
	OOLogGenericSubclassResponsibility();
	return NO;
}


- (void)unapplyWithNext:(OOMaterial *)next;
{
	// Do nothing.
}


- (void)willDealloc
{
	if (EXPECT_NOT(sActiveMaterial == self))
	{
		OOLog(@"shader.dealloc.imbalance", @"***** Material deallocated while active, indicating a retain/release imbalance.");
		[self unapplyWithNext:nil];
		sActiveMaterial = nil;
	}
}

@end
