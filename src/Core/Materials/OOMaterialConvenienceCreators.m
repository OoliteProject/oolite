/*

OOMaterialConvenienceCreators.m


Copyright (C) 2007-2010 Jens Ayton

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

#import "OOMaterialConvenienceCreators.h"
#import "OOMaterialSpecifier.h"

#import "OOOpenGLExtensionManager.h"
#import "OOShaderMaterial.h"
#import "OOSingleTextureMaterial.h"
#import "OOMultiTextureMaterial.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "OOCacheManager.h"
#import "OOTexture.h"
#import "OODebugFlags.h"


static void SetUniform(NSMutableDictionary *uniforms, NSString *key, NSString *type, id value);
static void SetUniformFloat(NSMutableDictionary *uniforms, NSString *key, float value);
static void AddTexture(NSMutableDictionary *uniforms, NSMutableArray *textures, NSString *key, NSDictionary *specifier);


@implementation OOMaterial (OOConvenienceCreators)

+ (NSDictionary *)synthesizeMaterialDictionaryWithName:(NSString *)name
										 configuration:(NSDictionary *)configuration
												macros:(NSDictionary *)macros
{
	OOColor					*ambientColor = nil,
							*diffuseColor = nil,
							*specularColor = nil,
							*emissionColor = nil,
							*illuminationColor = nil;
	int						shininess = 0;
	NSDictionary			*diffuseMap = nil,
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
	BOOL					haveIllumination = NO;
	
	if (configuration == nil)  configuration = [NSDictionary dictionary];	// Needs to be non-nil for defaults to work.
	ambientColor = [configuration oo_ambientColor];
	diffuseColor = [configuration oo_diffuseColor];
	specularColor = [configuration oo_specularColor];
	emissionColor = [configuration oo_emissionColor];
	illuminationColor = [configuration oo_illuminationColor];
	shininess = [configuration oo_shininess];
	diffuseMap = [configuration oo_diffuseMapSpecifierWithDefaultName:name];
	specularMap = [configuration oo_specularMapSpecifier];
	emissionMap = [configuration oo_emissionMapSpecifier];
	emissionAndIlluminationMap = [configuration oo_emissionAndIlluminationMapSpecifier];
	illuminationMap = [configuration oo_illuminationMapSpecifier];
	normalMap = [configuration oo_normalMapSpecifier];
	normalAndParallaxMap = [configuration oo_normalAndParallaxMapSpecifier];
	parallaxScale = [configuration oo_parallaxScale];
	parallaxBias = [configuration oo_parallaxBias];
	
	modifiedMacros = macros ? [[macros mutableCopy] autorelease] : [NSMutableDictionary dictionaryWithCapacity:8];
	
	// Create a synthetic configuration dictionary.
	textures = [NSMutableArray arrayWithCapacity:5];
	newConfig = [NSMutableDictionary dictionaryWithCapacity:16];
	uniforms = [NSMutableDictionary dictionaryWithCapacity:6];
	
	[newConfig setObject:one forKey:@"_oo_is_synthesized_config"];
	[newConfig setObject:@"oolite-tangent-space-vertex.vertex" forKey:@"vertex_shader"];
	[newConfig setObject:@"oolite-default-shader.fragment" forKey:@"fragment_shader"];
	
	if (ambientColor != nil)  [newConfig setObject:[ambientColor normalizedArray] forKey:kOOMaterialAmbientColorName];
	if (diffuseColor != nil)  [newConfig setObject:[diffuseColor normalizedArray] forKey:kOOMaterialDiffuseColorName];
	if (emissionColor != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_EMISSION"];
		[newConfig setObject:[emissionColor normalizedArray] forKey:kOOMaterialEmissionColorName];
	}
	if (shininess > 0)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_SPECULAR"];
		if (specularColor != nil)  [newConfig setObject:[specularColor normalizedArray] forKey:kOOMaterialSpecularColorName];
		[newConfig setObject:[NSNumber numberWithUnsignedInt:shininess] forKey:kOOMaterialShininess];
		if (specularMap != nil)
		{
			[modifiedMacros setObject:one forKey:@"OOSTD_SPECULAR_MAP"];
			AddTexture(uniforms, textures, @"uSpecularMap", specularMap);
		}
	}
	if (diffuseMap != nil)
	{
		[newConfig setObject:diffuseMap forKey:kOOMaterialDiffuseMapName];
		[modifiedMacros setObject:one forKey:@"OOSTD_DIFFUSE_MAP"];
		AddTexture(uniforms, textures, @"uDiffuseMap", diffuseMap);
		
		if ([diffuseMap oo_boolForKey:@"cube_map"])
		{
			[modifiedMacros setObject:one forKey:@"OOSTD_DIFFUSE_MAP_IS_CUBE_MAP"];
		}
	}
	else
	{
		[newConfig setObject:@"" forKey:kOOMaterialDiffuseMapName];
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
		haveIllumination = YES;
	}
	if (illuminationMap != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_ILLUMINATION_MAP"];
		AddTexture(uniforms, textures, @"uIlluminationMap", illuminationMap);
		haveIllumination = YES;
	}
	if (haveIllumination && illuminationColor != nil)
	{
		NSString *illumMacro = [NSString stringWithFormat:@"vec4(%g, %g, %g, %g)", [illuminationColor redComponent], [illuminationColor greenComponent], [illuminationColor blueComponent], [illuminationColor alphaComponent]];
		[modifiedMacros setObject:illumMacro forKey:@"OOSTD_ILLUMINATION_COLOR"];
	}
	if (normalMap != nil)
	{
		[modifiedMacros setObject:one forKey:@"OOSTD_NORMAL_MAP"];
		AddTexture(uniforms, textures, @"uNormalMap", normalMap);
	}
	else if (normalAndParallaxMap != nil)
	{
		AddTexture(uniforms, textures, @"uNormalMap", normalAndParallaxMap);
		[modifiedMacros setObject:one forKey:@"OOSTD_NORMAL_MAP"];
		[modifiedMacros setObject:one forKey:@"OOSTD_NORMAL_AND_PARALLAX_MAP"];
		SetUniformFloat(uniforms, @"uParallaxScale", parallaxScale);
		SetUniformFloat(uniforms, @"uParallaxBias", parallaxBias);
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
									 cacheKey:(NSString *)cacheKey
								configuration:(NSDictionary *)configuration
									   macros:(NSDictionary *)macros
								bindingTarget:(id<OOWeakReferenceSupport>)target
{
	OOCacheManager			*cache = nil;
	NSDictionary			*synthesizedConfig = nil;
	OOMaterial				*result = nil;
	
	// Avoid looping (can happen if shader fails to compile).
	if ([configuration objectForKey:@"_oo_is_synthesized_config"] != nil)
	{
		OOLog(@"material.synthesize.loop", @"Synthesis loop for material %@.", name);
		return nil;
	}
	
	if (cacheKey != nil)
	{
		cache = [OOCacheManager sharedCache];
		cacheKey = [NSString stringWithFormat:@"%@/%@", cacheKey, name];
		synthesizedConfig = [cache objectForKey:cacheKey inCache:@"synthesized shader materials"];
	}
	
	if (synthesizedConfig == nil)
	{
		synthesizedConfig = [self synthesizeMaterialDictionaryWithName:name
														 configuration:configuration
																macros:macros];
		if (synthesizedConfig != nil && cacheKey != nil)
		{
			[cache setObject:synthesizedConfig
					  forKey:cacheKey
					 inCache:@"synthesized shader materials"];
		}
	}
	
	if (synthesizedConfig != nil)
	{
		result =  [self materialWithName:name
								cacheKey:cacheKey
						   configuration:synthesizedConfig
								  macros:[synthesizedConfig objectForKey:@"_oo_synthesized_material_macros"]
						   bindingTarget:target
						 forSmoothedMesh:YES];
	}
	
	return result;
}


+ (id)materialWithName:(NSString *)name
			  cacheKey:(NSString *)cacheKey
		 configuration:(NSDictionary *)configuration
				macros:(NSDictionary *)macros
		 bindingTarget:(id<OOWeakReferenceSupport>)object
	   forSmoothedMesh:(BOOL)smooth
{
	id result = nil;
	
#if OO_SHADERS

	if ([UNIVERSE useShaders])
	{
		if ([OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:configuration])
		{
			result = [OOShaderMaterial shaderMaterialWithName:name
												configuration:configuration
													   macros:macros
												bindingTarget:object];
		}
		
		// Use default shader if smoothing is on, or shader detail is full, DEBUG_NO_SHADER_FALLBACK is set, or material uses an effect map.
		if (result == nil &&
				(smooth ||
				 gDebugFlags & DEBUG_NO_SHADER_FALLBACK ||
				 [UNIVERSE shaderEffectsLevel] == SHADERS_FULL ||
				 [configuration oo_specularMapSpecifier] != nil ||
				 [configuration oo_normalMapSpecifier] != nil ||
				 [configuration oo_normalAndParallaxMapSpecifier] != nil ||
				 [configuration oo_emissionMapSpecifier] != nil ||
				 [configuration oo_illuminationMapSpecifier] != nil ||
				 [configuration oo_emissionAndIlluminationMapSpecifier] != nil
				 ))
		{
			result = [self defaultShaderMaterialWithName:name
												cacheKey:cacheKey
										   configuration:configuration
												  macros:macros
										   bindingTarget:(id<OOWeakReferenceSupport>)object];
		}
	}
#endif
	
#if OO_MULTITEXTURE
	if (result == nil && ![UNIVERSE reducedDetail])
	{
		if ([configuration oo_emissionMapSpecifier] != nil ||
			[configuration oo_illuminationMapSpecifier] ||
			[configuration oo_emissionAndIlluminationMapSpecifier] != nil)
		{
			result = [[OOMultiTextureMaterial alloc] initWithName:name configuration:configuration];
			[result autorelease];
		}
	}
#endif
	
	if (result == nil)
	{
		if ([[[configuration oo_diffuseMapSpecifierWithDefaultName:name] oo_stringForKey:@"name"] isEqual:@""])
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
			  cacheKey:(NSString *)cacheKey
	materialDictionary:(NSDictionary *)materialDict
	 shadersDictionary:(NSDictionary *)shadersDict
				macros:(NSDictionary *)macros
		 bindingTarget:(id<OOWeakReferenceSupport>)object
	   forSmoothedMesh:(BOOL)smooth
{
	NSDictionary			*configuration = nil;
	
#if OO_SHADERS

	if ([UNIVERSE useShaders])
	{
		configuration = [shadersDict oo_dictionaryForKey:name];
	}
#endif
	
	if (configuration == nil)
	{
		configuration = [materialDict oo_dictionaryForKey:name];
	}
	
	if (configuration == nil)
	{
		// Use fallback material for non-existent simple texture.
		// Texture caching means this won't be wasted in the general case.
		OOTexture *texture = [OOTexture textureWithName:name inFolder:@"Textures"];
		if (texture == nil)  return nil;
	}
	
	return [self materialWithName:name
						 cacheKey:cacheKey
					configuration:configuration
						   macros:macros
					bindingTarget:object
				  forSmoothedMesh:smooth];
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


static void AddTexture(NSMutableDictionary *uniforms, NSMutableArray *textures, NSString *key, NSDictionary *specifier)
{
	SetUniform(uniforms, key, @"texture", [NSNumber numberWithInt:[textures count]]);
	[textures addObject:specifier];
}
