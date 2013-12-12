/*

OOShaderMaterial.m


Copyright (C) 2007-2013 Jens Ayton

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


#import "OOShaderMaterial.h"

#if OO_SHADERS

#import "ResourceManager.h"
#import "OOShaderUniform.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOShaderProgram.h"
#import "OOTexture.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMacroOpenGL.h"
#import "Universe.h"
#import "OOIsNumberLiteral.h"
#import "OOLogging.h"
#import "OODebugFlags.h"
#import "OOStringParsing.h"


NSString * const kOOVertexShaderSourceKey		= @"_oo_vertex_shader_source";
NSString * const kOOVertexShaderNameKey			= @"vertex_shader";
NSString * const kOOFragmentShaderSourceKey		= @"_oo_fragment_shader_source";
NSString * const kOOFragmentShaderNameKey		= @"fragment_shader";
NSString * const kOOTexturesKey					= @"textures";
NSString * const kOOTextureObjectsKey			= @"_oo_texture_objects";
NSString * const kOOUniformsKey					= @"uniforms";
NSString * const kOOIsSynthesizedMaterialConfigurationKey = @"_oo_is_synthesized_config";
NSString * const kOOIsSynthesizedMaterialMacrosKey = @"_oo_synthesized_material_macros";


static BOOL GetShaderSource(NSString *fileName, NSString *shaderType, NSString *prefix, NSString **outResult);
static NSString *MacrosToString(NSDictionary *macros);


@interface OOShaderMaterial (OOPrivate)

// Convert a "textures" array to an "_oo_texture_objects" array.
- (NSArray *) loadTexturesFromArray:(NSArray *)textureSpecs unitCount:(GLuint)max;

// Load up an array of texture objects.
- (void) addTexturesFromArray:(NSArray *)textureObjects unitCount:(GLuint)max;

@end


@implementation OOShaderMaterial

+ (BOOL)configurationDictionarySpecifiesShaderMaterial:(NSDictionary *)configuration
{
	if (configuration == nil)  return NO;
	
	if ([configuration oo_stringForKey:kOOVertexShaderSourceKey] != nil)  return YES;
	if ([configuration oo_stringForKey:kOOFragmentShaderSourceKey] != nil)  return YES;
	if ([configuration oo_stringForKey:kOOVertexShaderNameKey] != nil)  return YES;
	if ([configuration oo_stringForKey:kOOVertexShaderNameKey] != nil)  return YES;
	
	return NO;
}


+ (instancetype) shaderMaterialWithName:(NSString *)name
						  configuration:(NSDictionary *)configuration
								 macros:(NSDictionary *)macros
						  bindingTarget:(id<OOWeakReferenceSupport>)target
{
	return [[[self alloc] initWithName:name configuration:configuration macros:macros bindingTarget:target] autorelease];
}


- (id) initWithName:(NSString *)name
	  configuration:(NSDictionary *)configuration
			 macros:(NSDictionary *)macros
	  bindingTarget:(id<OOWeakReferenceSupport>)target
{
	BOOL					OK = YES;
	NSString				*macroString = nil;
	NSString				*vertexShader = nil;
	NSString				*fragmentShader = nil;
	GLint					textureUnits = [[OOOpenGLExtensionManager sharedManager] textureImageUnitCount];
	NSMutableDictionary		*modifiedMacros = nil;
	NSString				*vsName = @"<synthesized>";
	NSString				*fsName = @"<synthesized>";
	NSString				*vsCacheKey = nil;
	NSString				*fsCacheKey = nil;
	
	if (configuration == nil)  OK = NO;
	
	self = [super initWithName:name configuration:configuration];
	if (self == nil)  OK = NO;
	
	if (OK)
	{
		modifiedMacros = macros ? [macros mutableCopy] : [[NSMutableDictionary alloc] init];
		[modifiedMacros autorelease];
		
		[modifiedMacros setObject:[NSNumber numberWithUnsignedInt:textureUnits]
						   forKey:@"OO_TEXTURE_UNIT_COUNT"];
		
		if ([UNIVERSE shaderEffectsLevel] == SHADERS_SIMPLE)
		{
			[modifiedMacros setObject:[NSNumber numberWithInt:1] forKey:@"OO_REDUCED_COMPLEXITY"];
		}
		
		macroString = MacrosToString(modifiedMacros);
	}
	
	if (OK)
	{
		vertexShader = [configuration oo_stringForKey:kOOVertexShaderSourceKey];
		if (vertexShader == nil)
		{
			vsName = [configuration oo_stringForKey:kOOVertexShaderNameKey];
			vsCacheKey = vsName;
			if (vsName != nil)
			{
				if (!GetShaderSource(vsName, @"vertex", macroString, &vertexShader))  OK = NO;
			}
		}
		else
		{
			vsCacheKey = vertexShader;
		}
	}
	
	if (OK)
	{
		fragmentShader = [configuration oo_stringForKey:kOOFragmentShaderSourceKey];
		if (fragmentShader == nil)
		{
			fsName = [configuration oo_stringForKey:kOOFragmentShaderNameKey];
			fsCacheKey = fsName;
			if (fsName != nil)
			{
				if (!GetShaderSource(fsName, @"fragment", macroString, &fragmentShader))  OK = NO;
			}
		}
		else
		{
			fsCacheKey = fragmentShader;
		}
	}
	
	if (OK)
	{
		if (vertexShader != nil || fragmentShader != nil)
		{
			static NSDictionary *attributeBindings = nil;
			if (attributeBindings == nil)
			{
				attributeBindings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kTangentAttributeIndex]
																forKey:@"tangent"];
				[attributeBindings retain];
			}
			
			NSString *cacheKey = [NSString stringWithFormat:@"$VERTEX:\n%@\n\n$FRAGMENT:\n%@\n\n$MACROS:\n%@\n", vsCacheKey, fsCacheKey, macroString];
			
			OOLogIndent();
			shaderProgram = [OOShaderProgram shaderProgramWithVertexShader:vertexShader
															fragmentShader:fragmentShader
														  vertexShaderName:vsName
														fragmentShaderName:fsName
																	prefix:macroString
														 attributeBindings:attributeBindings
																  cacheKey:cacheKey];
			OOLogOutdent();
			
			if (shaderProgram == nil)
			{
				BOOL canFallBack = ![modifiedMacros oo_boolForKey:@"OO_REDUCED_COMPLEXITY"];
#ifndef NDEBUG
				if (gDebugFlags & DEBUG_NO_SHADER_FALLBACK)  canFallBack = NO;
#endif
				if (canFallBack)
				{
					OOLogWARN(@"shader.load.fullModeFailed", @"Could not build shader %@/%@ in full complexity mode, trying simple mode.", vsName, fsName);
					
					[modifiedMacros setObject:[NSNumber numberWithInt:1] forKey:@"OO_REDUCED_COMPLEXITY"];
					macroString = MacrosToString(modifiedMacros);
					cacheKey = [cacheKey stringByAppendingString:@"\n$SIMPLIFIED FALLBACK\n"];
					
					OOLogIndent();
					shaderProgram = [OOShaderProgram shaderProgramWithVertexShader:vertexShader
																	fragmentShader:fragmentShader
																  vertexShaderName:vsName
																fragmentShaderName:fsName
																			prefix:macroString
																 attributeBindings:attributeBindings
																		  cacheKey:cacheKey];
					OOLogOutdent();
					
					if (shaderProgram != nil)
					{
						OOLog(@"shader.load.fallbackSuccess", @"Simple mode fallback successful.");
					}
				}
			}
			
			if (shaderProgram == nil)
			{
				OOLogERR(@"shader.load.failed", @"Could not build shader %@/%@.", vsName, fsName);
			}
		}
		else
		{
			OOLog(@"shader.load.noShader", @"***** Error: no vertex or fragment shader specified in shader dictionary:\n%@", configuration);
		}
		
		OK = (shaderProgram != nil);
		if (OK)  [shaderProgram retain];
	}
	
	if (OK)
	{
		// Load uniforms and textures, which are a flavour of uniform for our purpose.
		NSDictionary *uniformDefs = [configuration oo_dictionaryForKey:kOOUniformsKey];
		
		NSArray *textureArray = [configuration oo_arrayForKey:kOOTextureObjectsKey];
		if (textureArray == nil)
		{
			NSArray *textureSpecs = [configuration oo_arrayForKey:kOOTexturesKey];
			if (textureSpecs != nil)
			{
				textureArray = [self loadTexturesFromArray:textureSpecs unitCount:textureUnits];
			}
		}
		
		uniforms = [[NSMutableDictionary alloc] initWithCapacity:[uniformDefs count] + [textureArray count]];
		[self addUniformsFromDictionary:uniformDefs withBindingTarget:target];
		[self addTexturesFromArray:textureArray unitCount:textureUnits];
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


- (BOOL)bindUniform:(NSString *)uniformName
		   toObject:(id<OOWeakReferenceSupport>)source
		   property:(SEL)selector
	 convertOptions:(OOUniformConvertOptions)options
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return NO;
	
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
		return YES;
	}
	else
	{
		OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", uniformName);
		[uniforms removeObjectForKey:uniformName];
		return NO;
	}
}


- (BOOL)bindSafeUniform:(NSString *)uniformName
			   toObject:(id<OOWeakReferenceSupport>)target
		  propertyNamed:(NSString *)property
		 convertOptions:(OOUniformConvertOptions)options
{
	SEL					selector = NULL;
	
	selector = NSSelectorFromString(property);
	
	if (selector != NULL && OOUniformBindingPermitted(property, target))
	{
		return [self bindUniform:uniformName
						toObject:target
						property:selector
				  convertOptions:options];
	}
	else
	{
		OOLog(@"shader.uniform.unpermittedMethod", @"Did not bind uniform \"%@\" to property -[%@ %@] - unpermitted method.", uniformName, [target class], property);
	}
	
	return NO;
}


- (void)setUniform:(NSString *)uniformName intValue:(int)value
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return;
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName
									  shaderProgram:shaderProgram
										   intValue:value];
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
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName
									  shaderProgram:shaderProgram
										 floatValue:value];
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


- (void)setUniform:(NSString *)uniformName vectorValue:(GLfloat[4])value
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return;
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName
									  shaderProgram:shaderProgram
										vectorValue:value];
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


- (void)setUniform:(NSString *)uniformName vectorObjectValue:(id)value
{
	if (uniformName == nil) return;
	
	GLfloat vecArray[4];
	if ([value isKindOfClass:[NSArray class]] && [value count] == 4)
	{
		for (unsigned i = 0; i < 4; i++)
		{
			vecArray[i] = OOFloatFromObject([value objectAtIndex:i], 0.0f);
		}
	}
	else
	{
		Vector vec = OOVectorFromObject(value, kZeroVector);
		vecArray[0] = vec.x;
		vecArray[1] = vec.y;
		vecArray[2] = vec.z;
		vecArray[3] = 1.0;
	}
	
	OOShaderUniform *uniform = [[OOShaderUniform alloc] initWithName:uniformName
													   shaderProgram:shaderProgram
														 vectorValue:vecArray];
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


- (void)setUniform:(NSString *)uniformName quaternionValue:(Quaternion)value asMatrix:(BOOL)asMatrix
{
	OOShaderUniform			*uniform = nil;
	
	if (uniformName == nil) return;
	
	uniform = [[OOShaderUniform alloc] initWithName:uniformName
									  shaderProgram:shaderProgram
									quaternionValue:value
										   asMatrix:asMatrix];
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
	OOUniformConvertOptions	convertOptions;
	BOOL					quatAsMatrix = YES;
	GLfloat					scale = 1.0;
	uint32_t				randomSeed;
	RANROTSeed				savedSeed;
	NSArray					*keys = nil;
	
	if ([target respondsToSelector:@selector(randomSeedForShaders)])
	{
		randomSeed = [(id)target randomSeedForShaders];
	}
	else
	{
		randomSeed = (uint32_t)(uintptr_t)self;
	}
	savedSeed = RANROTGetFullSeed();
	ranrot_srand(randomSeed);
	
	keys = [[uniformDefs allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (uniformEnum = [keys objectEnumerator]; (name = [uniformEnum nextObject]); )
	{
		gotValue = NO;
		definition = [uniformDefs objectForKey:name];
		
		type = nil;
		value = nil;
		binding = nil;
		
		if ([definition isKindOfClass:[NSDictionary class]])
		{
			value = [(NSDictionary *)definition objectForKey:@"value"];
			binding = [(NSDictionary *)definition oo_stringForKey:@"binding"];
			type = [(NSDictionary *)definition oo_stringForKey:@"type"];
			scale = [(NSDictionary *)definition oo_floatForKey:@"scale" defaultValue:1.0];
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
			if (OOIsNumberLiteral(definition, NO))
			{
				value = definition;
				type = @"float";
			}
			else
			{
				binding = definition;
				type = @"binding";
			}
		}
		else if ([definition isKindOfClass:[NSArray class]])
		{
			binding = definition;
			type = @"vector";
		}
		
		// Transform random values to concrete values
		if ([type isEqualToString:@"randomFloat"])
		{
			type = @"float";
			value = [NSNumber numberWithFloat:randf() * scale];
		}
		else if ([type isEqualToString:@"randomUnitVector"])
		{
			type = @"vector";
			value = OOPropertyListFromVector(vector_multiply_scalar(OORandomUnitVector(), scale));
		}
		else if ([type isEqualToString:@"randomVectorSpatial"])
		{
			type = @"vector";
			value = OOPropertyListFromVector(OOVectorRandomSpatial(scale));
		}
		else if ([type isEqualToString:@"randomVectorRadial"])
		{
			type = @"vector";
			value = OOPropertyListFromVector(OOVectorRandomRadial(scale));
		}
		else if ([type isEqualToString:@"randomQuaternion"])
		{
			type = @"quaternion";
			value = OOPropertyListFromQuaternion(OORandomQuaternion());
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
			/*	"texture" is allowed as a synonym for "int" because shader
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
		else if ([type isEqualToString:@"vector"])
		{
			[self setUniform:name vectorObjectValue:value];
			gotValue = YES;
		}
		else if ([type isEqualToString:@"quaternion"])
		{
			if ([definition isKindOfClass:[NSDictionary class]])
			{
				quatAsMatrix = [definition oo_boolForKey:@"asMatrix" defaultValue:quatAsMatrix];
			}
			[self setUniform:name
			 quaternionValue:OOQuaternionFromObject(value, kIdentityQuaternion)
					asMatrix:quatAsMatrix];
			gotValue = YES;
		}
		else if (target != nil && [type isEqualToString:@"binding"])
		{
			if ([definition isKindOfClass:[NSDictionary class]])
			{
				convertOptions = 0;
				if ([definition oo_boolForKey:@"clamped" defaultValue:NO])  convertOptions |= kOOUniformConvertClamp;
				if ([definition oo_boolForKey:@"normalized" defaultValue:[definition oo_boolForKey:@"normalised" defaultValue:NO]])
				{
					convertOptions |= kOOUniformConvertNormalize;
				}
				if ([definition oo_boolForKey:@"asMatrix" defaultValue:YES])  convertOptions |= kOOUniformConvertToMatrix;
				if (![definition oo_boolForKey:@"bindToSubentity" defaultValue:NO])  convertOptions |= kOOUniformBindToSuperTarget;
			}
			else
			{
				convertOptions = kOOUniformConvertDefaults;
			}
			
			[self bindSafeUniform:name toObject:target propertyNamed:binding convertOptions:convertOptions];
			gotValue = YES;
		}
		
		if (!gotValue)
		{
			OOLog(@"shader.uniform.badDescription", @"----- Warning: could not bind uniform \"%@\" for target %@ -- could not interpret definition:\n%@", name, target, definition);
		}
	}
	
	RANROTSetFullSeed(savedSeed);
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
		OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
		[textures[i] apply];
	}
	if (texCount > 1)  OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
	
	@try
	{
		for (uniformEnum = [uniforms objectEnumerator]; (uniform = [uniformEnum nextObject]); )
		{
			[uniform apply];
		}
	}
	@catch (id exception) {}
	
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


- (BOOL) isFinishedLoading
{
	uint32_t			i;
	
	if (textures != NULL)
	{
		for (i = 0; i != texCount; ++i)
		{
			if (![textures[i] isFinishedLoading])  return NO;
		}
	}
	
	return YES;
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
			OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
			[OOTexture applyNone];
		}
		if (count != 1)  OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
	}
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	[[uniforms allValues] makeObjectsPerformSelector:@selector(setBindingTarget:) withObject:target];
	[bindingTarget release];
	bindingTarget = [target weakRetain];
}


- (BOOL) permitSpecular
{
	return YES;
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	return [NSSet setWithObjects:textures count:texCount];
}
#endif

@end


@implementation OOShaderMaterial (OOPrivate)

- (NSArray *) loadTexturesFromArray:(NSArray *)textureSpecs unitCount:(GLuint)max
{
	GLuint i, count = (GLuint)MIN([textureSpecs count], (NSUInteger)max);
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
	
	for (i = 0; i < count; i++)
	{
		id textureSpec = [textureSpecs objectAtIndex:i];
		OOTexture *texture = [OOTexture textureWithConfiguration:textureSpec];
		if (texture == nil)  texture = [OOTexture nullTexture];
		[result addObject:texture];
	}
	
	return result;
}


- (void) addTexturesFromArray:(NSArray *)textureObjects unitCount:(GLuint)max
{
	// Allocate space for texture object name array
	texCount = (uint32_t)MIN([textureObjects count], (NSUInteger)max);
	if (texCount == 0)  return;
	
	textures = malloc(texCount * sizeof *textures);
	if (textures == NULL)
	{
		texCount = 0;
		return;
	}
	
	// Set up texture object names and appropriate uniforms
	unsigned i;
	for (i = 0; i != texCount; ++i)
	{
		textures[i] = [textureObjects objectAtIndex:i];
		[textures[i] retain];
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

#endif


/*	Attempt to load fragment or vertex shader source from a file.
	Returns YES if source was loaded or no shader was specified, and NO if an
	external shader was specified but could not be found.
*/
static BOOL GetShaderSource(NSString *fileName, NSString *shaderType, NSString *prefix, NSString **outResult)
{
	NSString				*result = nil;
	NSArray					*extensions = nil;
	NSEnumerator			*extEnum = nil;
	NSString				*extension = nil;
	NSString				*nameWithExtension = nil;
	
	if (fileName == nil)  return YES;	// It's OK for one or the other of the shaders to be undefined.
	
	result = [ResourceManager stringFromFilesNamed:fileName inFolder:@"Shaders"];
	if (result == nil)
	{
		extensions = [NSArray arrayWithObjects:shaderType, [shaderType substringToIndex:4], nil];	// vertex and vert, or fragment and frag
		
		// Futureproofing -- in future, we may wish to support automatic selection between supported shader languages.
		if (![fileName pathHasExtensionInArray:extensions])
		{
			for (extEnum = [extensions objectEnumerator]; (extension = [extEnum nextObject]); )
			{
				nameWithExtension = [fileName stringByAppendingPathExtension:extension];
				result = [ResourceManager stringFromFilesNamed:nameWithExtension
													  inFolder:@"Shaders"];
				if (result != nil) break;
			}
		}
		if (result == nil)
		{
			OOLog(kOOLogFileNotFound, @"GLSL ERROR: failed to find %@ program %@.", shaderType, fileName);
			return NO;
		}
	}
	
	if (outResult != NULL) *outResult = result;
	return YES;
}
