/*

OOMaterialConvenienceCreators.m


Copyright (C) 2007-2012 Jens Ayton

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

#ifndef USE_NEW_SHADER_SYNTHESIZER
#define USE_NEW_SHADER_SYNTHESIZER	0
#endif


#import "OOMaterialConvenienceCreators.h"
#import "OOMaterialSpecifier.h"

#if USE_NEW_SHADER_SYNTHESIZER
#import "OODefaultShaderSynthesizer.h"
#import "ResourceManager.h"
#endif

#import "OOOpenGLExtensionManager.h"
#import "OOShaderMaterial.h"
#import "OOSingleTextureMaterial.h"
#import "OOMultiTextureMaterial.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "OOCacheManager.h"
#import "OOTexture.h"
#import "OODebugFlags.h"


#if !USE_NEW_SHADER_SYNTHESIZER
typedef struct
{
	NSDictionary			*inConfig;
	NSMutableDictionary		*outConfig;
	OOUInteger				texturesUsed;
	OOUInteger				maxTextures;
	
	NSMutableDictionary		*macros;
	NSMutableArray			*textures;
	NSMutableDictionary		*uniforms;
} OOMaterialSynthContext;


static void SetUniform(NSMutableDictionary *uniforms, NSString *key, NSString *type, id value);
static void SetUniformFloat(OOMaterialSynthContext *context, NSString *key, float value);

/*	AddTexture(): add a texture to the configuration being synthesized.
	* specifier is added to the textures array.
	* uniformName is mapped to the appropriate texture unit in the uniforms dictionary.
	* If nonShaderKey is not nil, nonShaderKey (e.g. diffuse_map) is set to specifier.
	* If macroName is not nil, macroName is set to 1 in the macros dictionary.
*/
static void AddTexture(OOMaterialSynthContext *context, NSString *uniformName, NSString *nonShaderKey, NSString *macroName, NSDictionary *specifier);

static void AddColorIfAppropriate(OOMaterialSynthContext *context, SEL selector, NSString *key, NSString *macroName);
static void AddMacroColorIfAppropriate(OOMaterialSynthContext *context, SEL selector, NSString *macroName);

static void SynthDiffuse(OOMaterialSynthContext *context, NSString *name);
static void SynthEmissionAndIllumination(OOMaterialSynthContext *context);
static void SynthNormalMap(OOMaterialSynthContext *context);
static void SynthSpecular(OOMaterialSynthContext *context);

#endif


@implementation OOMaterial (OOConvenienceCreators)

#if !USE_NEW_SHADER_SYNTHESIZER

+ (NSDictionary *)synthesizeMaterialDictionaryWithName:(NSString *)name
										 configuration:(NSDictionary *)configuration
												macros:(NSDictionary *)macros
{
	if (configuration == nil)  configuration = [NSDictionary dictionary];
	OOMaterialSynthContext context =
	{
		.inConfig = configuration,
		.outConfig = [NSMutableDictionary dictionary],
		.maxTextures = [[OOOpenGLExtensionManager sharedManager] textureImageUnitCount],
		
		.macros = [NSMutableDictionary dictionaryWithDictionary:macros],
		.textures = [NSMutableArray array],
		.uniforms = [NSMutableDictionary dictionary]
	};
	
	if ([UNIVERSE reducedDetail])
	{
		context.maxTextures = 3;
	}
	
	//	Basic stuff.
	
	/*	Set up the various material attributes.
		Order is significant here, because it determines the order in which
		features will be dropped if we exceed the hardware's texture image
		unit limit.
	*/
	SynthDiffuse(&context, name);
	SynthEmissionAndIllumination(&context);
	SynthNormalMap(&context);
	SynthSpecular(&context);
	
	if ([UNIVERSE shaderEffectsLevel] == SHADERS_FULL)
	{
		//	Add uniforms required for hull heat glow.
		[context.uniforms setObject:@"hullHeatLevel" forKey:@"uHullHeatLevel"];
		[context.uniforms setObject:@"timeElapsedSinceSpawn" forKey:@"uTime"];
	}
	
	//	Stuff in the general properties.
	[context.outConfig setObject:@"true" forKey:@"_oo_is_synthesized_config"];
	[context.outConfig setObject:@"oolite-tangent-space-vertex.vertex" forKey:@"vertex_shader"];
	[context.outConfig setObject:@"oolite-default-shader.fragment" forKey:@"fragment_shader"];
	
	if ([context.textures count] != 0)  [context.outConfig setObject:context.textures forKey:@"textures"];
	if ([context.uniforms count] != 0)  [context.outConfig setObject:context.uniforms forKey:@"uniforms"];
	if ([context.macros count] != 0)  [context.outConfig setObject:context.macros forKey:@"_oo_synthesized_material_macros"];
	
	return context.outConfig;
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

#else

#ifndef NDEBUG
static BOOL sDumpShaderSource = NO;

+ (void) initialize
{
	sDumpShaderSource = [[NSUserDefaults standardUserDefaults] boolForKey:@"dump-synthesized-shaders"];
}
#endif


+ (OOMaterial *) defaultShaderMaterialWithName:(NSString *)name
									  cacheKey:(NSString *)cacheKey
								 configuration:(NSDictionary *)configuration
										macros:(NSDictionary *)macros
								 bindingTarget:(id<OOWeakReferenceSupport>)target
{
	NSString		*vertexShader = nil;
	NSString		*fragmentShader = nil;
	NSArray			*textureSpecs = nil;
	NSDictionary	*uniformSpecs = nil;
	
	if (!OOSynthesizeMaterialShader(configuration, name, cacheKey /* FIXME: entity name for error reporting */, &vertexShader, &fragmentShader, &textureSpecs, &uniformSpecs))
	{
		return nil;
	}
	
	NSDictionary	*synthesizedConfig = [NSDictionary dictionaryWithObjectsAndKeys:
										  [NSNumber numberWithBool:YES], kOOIsSynthesizedMaterialConfigurationKey,
										  textureSpecs, kOOTexturesKey,
										  uniformSpecs, kOOUniformsKey,
										  vertexShader, kOOVertexShaderSourceKey,
										  fragmentShader, kOOFragmentShaderSourceKey,
										  nil];
	
#ifndef NDEBUG
	if (sDumpShaderSource)
	{
		NSString *dumpPath = [NSString stringWithFormat:@"Synthesized Materials/%@/%@", cacheKey, name];
		
		[ResourceManager writeDiagnosticString:vertexShader toFileNamed:[dumpPath stringByAppendingPathExtension:@"vertex"]];
		[ResourceManager writeDiagnosticString:fragmentShader toFileNamed:[dumpPath stringByAppendingPathExtension:@"fragment"]];
		
		// Hide internal keys in the synthesized config before writing it.
		NSMutableDictionary *humanFriendlyConfig = [[synthesizedConfig mutableCopy] autorelease];
		[humanFriendlyConfig removeObjectForKey:kOOVertexShaderSourceKey];
		[humanFriendlyConfig removeObjectForKey:kOOFragmentShaderSourceKey];
		[humanFriendlyConfig removeObjectForKey:kOOIsSynthesizedMaterialConfigurationKey];
		[humanFriendlyConfig setObject:[NSString stringWithFormat:@"%@.vertex", name] forKey:kOOVertexShaderNameKey];
		[humanFriendlyConfig setObject:[NSString stringWithFormat:@"%@.fragment", name] forKey:kOOFragmentShaderNameKey];
		
		[ResourceManager writeDiagnosticPList:humanFriendlyConfig toFileNamed:[dumpPath stringByAppendingPathExtension:@"plist"]];
		
		[ResourceManager writeDiagnosticPList:configuration toFileNamed:[[dumpPath stringByAppendingString:@"-original"] stringByAppendingPathExtension:@"plist"]];
	}
#endif
	
	return [self materialWithName:name
						 cacheKey:cacheKey
					configuration:synthesizedConfig
						   macros:nil
					bindingTarget:target
				  forSmoothedMesh:YES];
}

#endif


+ (OOMaterial *) materialWithName:(NSString *)name
						 cacheKey:(NSString *)cacheKey
					configuration:(NSDictionary *)configuration
						   macros:(NSDictionary *)macros
					bindingTarget:(id<OOWeakReferenceSupport>)object
				  forSmoothedMesh:(BOOL)smooth	// Internally, this flg really means "force use of shaders".
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
				 [configuration oo_combinedSpecularMapSpecifier] != nil ||
				 [configuration oo_normalMapSpecifier] != nil ||
				 [configuration oo_parallaxMapSpecifier] != nil ||
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
		if ([configuration oo_diffuseMapSpecifierWithDefaultName:name] == nil)
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


+ (OOMaterial *) materialWithName:(NSString *)name
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
		
		configuration = [NSDictionary dictionary];
	}
	
	return [self materialWithName:name
						 cacheKey:cacheKey
					configuration:configuration
						   macros:macros
					bindingTarget:object
				  forSmoothedMesh:smooth];
}

@end


#if !USE_NEW_SHADER_SYNTHESIZER

static void SetUniform(NSMutableDictionary *uniforms, NSString *key, NSString *type, id value)
{
	[uniforms setObject:[NSDictionary dictionaryWithObjectsAndKeys:type, @"type", value, @"value", nil] forKey:key];
}


static void SetUniformFloat(OOMaterialSynthContext *context, NSString *key, float value)
{
	SetUniform(context->uniforms, key, @"float", [NSNumber numberWithFloat:value]);
}


static void AddTexture(OOMaterialSynthContext *context, NSString *uniformName, NSString *nonShaderKey, NSString *macroName, NSDictionary *specifier)
{
	NSCParameterAssert(context->texturesUsed < context->maxTextures);
	
	context->texturesUsed++;
	SetUniform(context->uniforms, uniformName, @"texture", [NSNumber numberWithUnsignedInteger:[context->textures count]]);
	[context->textures addObject:specifier];
	if (nonShaderKey != nil)
	{
		[context->outConfig setObject:specifier forKey:kOOMaterialDiffuseMapName];
	}
	if (macroName != nil)
	{
		[context->macros setObject:@"1" forKey:macroName];
	}
}


static void AddColorIfAppropriate(OOMaterialSynthContext *context, SEL selector, NSString *key, NSString *macroName)
{
	OOColor *color = [context->inConfig performSelector:selector];
	
	if (color != nil)
	{
		[context->outConfig setObject:[color normalizedArray] forKey:key];
		if (macroName != nil)  [context->macros setObject:@"1" forKey:macroName];
	}
}


static void AddMacroColorIfAppropriate(OOMaterialSynthContext *context, SEL selector, NSString *macroName)
{
	OOColor *color = [context->inConfig performSelector:selector];
	
	if (color != nil)
	{
		NSString *macroText = [NSString stringWithFormat:@"vec4(%g, %g, %g, %g)",
							   [color redComponent],
							   [color greenComponent],
							   [color blueComponent],
							   [color alphaComponent]];
		[context->macros setObject:macroText forKey:macroName];
	}
}


static void SynthDiffuse(OOMaterialSynthContext *context, NSString *name)
{
	// Set up diffuse map if appropriate.
	NSDictionary *diffuseMapSpec = [context->inConfig oo_diffuseMapSpecifierWithDefaultName:name];
	if (diffuseMapSpec != nil && context->texturesUsed < context->maxTextures)
	{
		AddTexture(context, @"uDiffuseMap", kOOMaterialDiffuseMapName, @"OOSTD_DIFFUSE_MAP", diffuseMapSpec);
		
		if ([diffuseMapSpec oo_boolForKey:@"cube_map"])
		{
			[context->macros setObject:@"1" forKey:@"OOSTD_DIFFUSE_MAP_IS_CUBE_MAP"];
		}
	}
	else
	{
		// No diffuse map must be specified explicitly.
		[context->outConfig setObject:@"" forKey:kOOMaterialDiffuseMapName];
	}
	
	// Set up diffuse colour if any.
	AddColorIfAppropriate(context, @selector(oo_diffuseColor), kOOMaterialDiffuseColorName, nil);
}


static void SynthEmissionAndIllumination(OOMaterialSynthContext *context)
{
	// Read the various emission and illumination textures, and decide what to do with them.
	NSDictionary *emissionMapSpec = [context->inConfig oo_emissionMapSpecifier];
	NSDictionary *illuminationMapSpec = [context->inConfig oo_illuminationMapSpecifier];
	NSDictionary *emissionAndIlluminationSpec = [context->inConfig oo_emissionAndIlluminationMapSpecifier];
	BOOL isCombinedSpec = NO;
	BOOL haveIlluminationMap = NO;
	
	if (emissionMapSpec == nil && emissionAndIlluminationSpec != nil)
	{
		emissionMapSpec = emissionAndIlluminationSpec;
		if (illuminationMapSpec == nil)  isCombinedSpec = YES;  // Else use only emission part of emission_and_illumination_map, combined with full illumination_map.
	}
	
	if (emissionMapSpec != nil && context->texturesUsed < context->maxTextures)
	{
		/*	FIXME: at this point, if there is an illumination map, we should
			consider merging it into the emission map using
			OOCombinedEmissionMapGenerator if the total number of texture
			specifiers is greater than context->maxTextures. This will
			require adding a new type of texture specifier - not a big deal.
			-- Ahruman 2010-05-21
		*/
		AddTexture(context, @"uEmissionMap", nil, isCombinedSpec ? @"OOSTD_EMISSION_AND_ILLUMINATION_MAP" : @"OOSTD_EMISSION_MAP", emissionMapSpec);
		/*	Note that this sets emission_color, not emission_modulate_color.
			This is because the emission colour value is sent through the
			standard OpenGL emission colour attribute by OOBasicMaterial.
		*/
		AddColorIfAppropriate(context, @selector(oo_emissionModulateColor), kOOMaterialEmissionColorName, @"OOSTD_EMISSION");
		
		haveIlluminationMap = isCombinedSpec;
	}
	else
	{
		//	No emission map, use overall emission colour if specified.
		AddColorIfAppropriate(context, @selector(oo_emissionColor), kOOMaterialEmissionColorName, @"OOSTD_EMISSION");
	}
	
	if (illuminationMapSpec != nil && context->texturesUsed < context->maxTextures)
	{
		AddTexture(context, @"uIlluminationMap", nil, @"OOSTD_ILLUMINATION_MAP", illuminationMapSpec);
		haveIlluminationMap = YES;
	}
	
	if (haveIlluminationMap)
	{
		AddMacroColorIfAppropriate(context, @selector(oo_illuminationModulateColor), @"OOSTD_ILLUMINATION_COLOR");
	}
}


static void SynthNormalMap(OOMaterialSynthContext *context)
{
	if (context->texturesUsed < context->maxTextures)
	{
		BOOL hasParallax = YES;
		NSDictionary *normalMapSpec = [context->inConfig oo_normalAndParallaxMapSpecifier];
		if (normalMapSpec == nil)
		{
			hasParallax = NO;
			normalMapSpec = [context->inConfig oo_normalMapSpecifier];
		}
		
		if (normalMapSpec != nil)
		{
			AddTexture(context, @"uNormalMap", nil, @"OOSTD_NORMAL_MAP", normalMapSpec);
			
			if (hasParallax)
			{
				[context->macros setObject:@"1" forKey:@"OOSTD_NORMAL_AND_PARALLAX_MAP"];
				SetUniformFloat(context, @"uParallaxScale", [context->inConfig oo_parallaxScale]);
				SetUniformFloat(context, @"uParallaxBias", [context->inConfig oo_parallaxBias]);
			}
		}
	}
}


static void SynthSpecular(OOMaterialSynthContext *context)
{
	GLint shininess = [context->inConfig oo_specularExponent];
	if (shininess <= 0)  return;
	
	NSDictionary *specularMapSpec = nil;
	OOColor *specularColor = nil;
	
	if (context->texturesUsed < context->maxTextures)
	{
		specularMapSpec = [context->inConfig oo_combinedSpecularMapSpecifier];
	}
	
	if (specularMapSpec != nil)  specularColor = [context->inConfig oo_specularModulateColor];
	else  specularColor = [context->inConfig oo_specularColor];
	if ([specularColor isBlack])  return;
	
	[context->outConfig setObject:[NSNumber numberWithUnsignedInt:shininess] forKey:kOOMaterialSpecularExponentLegacyName];
	
	if (specularMapSpec != nil)
	{
		AddTexture(context, @"uSpecularMap", kOOMaterialDiffuseMapName, @"OOSTD_SPECULAR_MAP", specularMapSpec);
	}
	
	if (specularColor != nil)
	{
		/*	As with emission colour, specular_modulate_color is transformed to
		 specular_color here because the shader reads it from the standard
		 material specular colour property set by OOBasicMaterial.
		 */
		[context->outConfig setObject:[specularColor normalizedArray] forKey:kOOMaterialSpecularColorName];
	}
	[context->macros setObject:@"1" forKey:@"OOSTD_SPECULAR"];
}

#endif
