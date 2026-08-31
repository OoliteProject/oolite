/*

OODefaultShaderSynthesizer.m


Copyright © 2011-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
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

#import "OODefaultShaderSynthesizer.h"
#import "OOMesh.h"
#import "OOTexture.h"
#import "OOColor.h"

#import "NSStringOOExtensions.h"
#import "OOCollectionExtractors.h"
#import "NSDictionaryOOExtensions.h"
#import "OOMaterialSpecifier.h"
#import "ResourceManager.h"

/* 
 * GNUstep 1.20.1 does not support NSIntegerHashCallBacks but uses 
 * NSIntHashCallBacks instead. NSIntHashCallBacks was deprecated in favor of
 * NSIntegerHashCallBacks in GNUstep versions later than 1.20.1. If we move to
 * a newer GNUstep version for Oolite the #define below may not be necessary
 * anymore but for now we need it to be able to build. - Nikos 20120208.
*/
#if OOLITE_GNUSTEP
#define NSIntegerHashCallBacks	NSIntHashCallBacks
#endif


static NSDictionary *CanonicalizeMaterialSpecifier(NSDictionary *spec, NSString *materialKey);

static NSString *FormatFloat(double value);


@interface OODefaultShaderSynthesizer: NSObject
{
@private
	NSDictionary				*_configuration;
	NSString					*_materialKey;
	NSString					*_entityName;
	
	NSString					*_vertexShader;
	NSString					*_fragmentShader;
	NSMutableArray				*_textures;
	NSMutableDictionary			*_uniforms;
	
	NSMutableString				*_attributes;
	NSMutableString				*_varyings;
	NSMutableString				*_vertexUniforms;
	NSMutableString				*_fragmentUniforms;
	NSMutableString				*_vertexHelpers;
	NSMutableString				*_fragmentHelpers;
	NSMutableString				*_vertexBody;
	NSMutableString				*_fragmentPreTextures;
	NSMutableString				*_fragmentTextureLookups;
	NSMutableString				*_fragmentBody;
	
	// _texturesByName: dictionary mapping texture file names to texture specifications.
	NSMutableDictionary			*_texturesByName;
	// _textureIDs: dictionary mapping texture file names to numerical IDs used to name variables.
	NSMutableDictionary			*_textureIDs;
	// _sampledTextures: hash of integer texture IDs for which we’ve set up a sample.
	NSHashTable					*_sampledTextures;
	
	NSMutableDictionary			*_uniformBindingNames;
	
	NSUInteger					_usesNormalMap: 1,
								_usesDiffuseTerm: 1,
								_constZNormal: 1,
								_haveDiffuseLight: 1,
	
	// Completion flags for various generation stages.
								_completed_writeFinalColorComposite: 1,
								_completed_writeDiffuseColorTerm: 1,
								_completed_writeSpecularLighting: 1,
								_completed_writeLightMaps: 1,
								_completed_writeDiffuseLighting: 1,
								_completed_writeDiffuseColorTermIfNeeded: 1,
								_completed_writeVertexPosition: 1,
								_completed_writeNormalIfNeeded: 1,
						//		_completedwriteNormal: 1,
								_completed_writeLightVector: 1,
								_completed_writeEyeVector: 1, 
								_completed_writeTotalColor: 1,
								_completed_writeTextureCoordRead: 1,
								_completed_writeVertexTangentBasis: 1;
	
#ifndef NDEBUG
	NSHashTable					*_stagesInProgress;
#endif
}

- (id) initWithMaterialConfiguration:(NSDictionary *)configuration
						 materialKey:(NSString *)materialKey
						  entityName:(NSString *)name;

- (BOOL) run;

- (NSString *) vertexShader;
- (NSString *) fragmentShader;
- (NSArray *) textureSpecifications;
- (NSDictionary *) uniformSpecifications;

- (NSString *) materialKey;
- (NSString *) entityName;

- (void) createTemporaries;
- (void) destroyTemporaries;

- (void) composeVertexShader;
- (void) composeFragmentShader;

// Write various types of declarations.
- (void) appendVariable:(NSString *)name ofType:(NSString *)type withPrefix:(NSString *)prefix to:(NSMutableString *)buffer;
- (void) addAttribute:(NSString *)name ofType:(NSString *)type;
- (void) addVarying:(NSString *)name ofType:(NSString *)type;
- (void) addVertexUniform:(NSString *)name ofType:(NSString *)type;
- (void) addFragmentUniform:(NSString *)name ofType:(NSString *)type;

// Create or retrieve a uniform variable name for a given binding.
- (NSString *) defineBindingUniform:(NSDictionary *)binding ofType:(NSString *)type;

- (NSString *) readRGBForTextureSpec:(NSDictionary *)textureSpec mapName:(NSString *)mapName;	// Generate a read for an RGB value, or a single channel splatted across RGB.
- (NSString *) readOneChannelForTextureSpec:(NSDictionary *)textureSpec mapName:(NSString *)mapName;	// Generate a read for a single channel.

// Details of texture setup; generally use -read*ForTextureSpec:mapName: instead.
- (NSUInteger) textureIDForSpec:(NSDictionary *)textureSpec;
- (void) setUpOneTexture:(NSDictionary *)textureSpec;
- (void) getSampleName:(NSString **)outSampleName andSwizzleOp:(NSString **)outSwizzleOp forTextureSpec:(NSDictionary *)textureSpec;


/*	Stages. These should only be called through the REQUIRE_STAGE macro to
	avoid duplicated code and ensure data depedencies are met.
*/


/*	writeTextureCoordRead
	Generate vec2 texCoords.
*/
- (void) writeTextureCoordRead;

/*	writeDiffuseColorTermIfNeeded
	Generates and populates the fragment shader value vec3 diffuseColor, unless
	the diffuse term is black. If a diffuseColor is generated, _usesDiffuseTerm
	is set. The value will be const if possible.
	See also: writeDiffuseColorTerm.
*/
- (void) writeDiffuseColorTermIfNeeded;

/*	writeDiffuseColorTerm
	Generates vec3 diffuseColor unconditionally – that is, even if the diffuse
	term is black.
	See also: writeDiffuseColorTermIfNeeded.
*/
- (void) writeDiffuseColorTerm;

/*	writeDiffuseLighting
	Generate the fragment variable vec3 diffuseLight and add Lambertian and
	ambient terms to it.
*/
- (void) writeDiffuseLighting;

/*	writeLightVector
	Generate the fragment variable vec3 lightVector (unit vector) for temporary
	lighting. Calling this if lighting mode is kLightingUniform will cause an
	exception.
*/
- (void) writeLightVector;

/*	writeEyeVector
	Generate vec3 lightVector, the normalized direction from the fragment to
	the light source.
*/
- (void) writeEyeVector;

/*	writeVertexTangentBasis
	Generates tangent space basis matrix (TBN) in vertex shader, if in tangent-
	space lighting mode. If not, an exeception is raised.
*/
- (void) writeVertexTangentBasis;

/*	writeNormalIfNeeded
	Writes fragment variable vec3 normal if necessary. Otherwise, it sets
	_constZNormal, indicating that the normal is always (0, 0, 1).
	
	See also: writeNormal.
*/
- (void) writeNormalIfNeeded;

/*	writeNormal
	Generates vec3 normal unconditionally – if _constZNormal is set, normal will
	be const vec3 normal = vec3 (0.0, 0.0, 1.0).
*/
- (void) writeNormal;

/*	writeSpecularLighting
	Calculate specular writing and add it to totalColor.
*/
- (void) writeSpecularLighting;

/*	writeLightMaps
	Add emission and illumination maps to totalColor.
*/
- (void) writeLightMaps;

/*	writeVertexPosition
	Calculate vertex position and write it to gl_Position.
*/
- (void) writeVertexPosition;

/*	writeTotalColor
	Generate vec3 totalColor, the accumulator for output colour values.
*/
- (void) writeTotalColor;

/*	writeFinalColorComposite
	This stage writes the final fragment shader. It also pulls in other stages
	through dependencies.
*/
- (void) writeFinalColorComposite;


/*
	REQUIRE_STAGE(): pull in the required stage. A stage must have a
	zero-parameter method and a matching _completed_stage instance variable.
	
	In debug/testrelease builds, this dispatches through performStage: which
	checks for recursive calls.
*/
#ifndef NDEBUG
#define REQUIRE_STAGE(NAME) if (!_completed_##NAME) { [self performStage:@selector(NAME)]; _completed_##NAME = YES; }
- (void) performStage:(SEL)stage;
#else
#define REQUIRE_STAGE(NAME) if (!_completed_##NAME) { [self NAME]; _completed_##NAME = YES; }
#endif

@end


static NSString *GetExtractMode(NSDictionary *textureSpecifier);


BOOL OOSynthesizeMaterialShader(NSDictionary *configuration, NSString *materialKey, NSString *entityName, NSString **outVertexShader, NSString **outFragmentShader, NSArray **outTextureSpecs, NSDictionary **outUniformSpecs)
{
	NSCParameterAssert(configuration != nil && outVertexShader != NULL && outFragmentShader != NULL && outTextureSpecs != NULL && outUniformSpecs != NULL);
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	OODefaultShaderSynthesizer *synthesizer = [[OODefaultShaderSynthesizer alloc]
											   initWithMaterialConfiguration:configuration
																 materialKey:materialKey
																  entityName:entityName];
	[synthesizer autorelease];
	
	BOOL OK = [synthesizer run];
	if (OK)
	{
		*outVertexShader = [[synthesizer vertexShader] retain];
		*outFragmentShader = [[synthesizer fragmentShader] retain];
		*outTextureSpecs = [[synthesizer textureSpecifications] retain];
		*outUniformSpecs = [[synthesizer uniformSpecifications] retain];
	}
	else
	{
		*outVertexShader = nil;
		*outFragmentShader = nil;
		*outTextureSpecs = nil;
		*outUniformSpecs = nil;
	}
	
	[pool release];
	
	[*outVertexShader autorelease];
	[*outFragmentShader autorelease];
	[*outTextureSpecs autorelease];
	[*outUniformSpecs autorelease];
	
	return YES;
}


@implementation OODefaultShaderSynthesizer

- (id) initWithMaterialConfiguration:(NSDictionary *)configuration
						 materialKey:(NSString *)materialKey
						  entityName:(NSString *)name
{
	if ((self = [super init]))
	{
		_configuration = [CanonicalizeMaterialSpecifier(configuration, materialKey) retain];
		_materialKey = [materialKey copy];
		_entityName = [_entityName copy];
	}
	
	return self;
}


- (void) dealloc
{
	[self destroyTemporaries];
	DESTROY(_configuration);
	DESTROY(_materialKey);
	DESTROY(_entityName);
	DESTROY(_vertexShader);
	DESTROY(_fragmentShader);
	DESTROY(_textures);
	
    [super dealloc];
}


- (NSString *) vertexShader
{
	return _vertexShader;
}


- (NSString *) fragmentShader
{
	return _fragmentShader;
}


- (NSArray *) textureSpecifications
{
#ifndef NDEBUG
	return [NSArray arrayWithArray:_textures];
#else
	return _textures;
#endif
}


- (NSDictionary *) uniformSpecifications
{
#ifndef NDEBUG
	return [NSDictionary dictionaryWithDictionary:_uniforms];
#else
	return _uniforms;
#endif
}


- (BOOL) run
{
	[self createTemporaries];
	_uniforms = [[NSMutableDictionary alloc] init];
	[_vertexBody appendString:@"void main(void)\n{\n"];
	[_fragmentPreTextures appendString:@"void main(void)\n{\n"];
	
	@try
	{
		REQUIRE_STAGE(writeFinalColorComposite);
		
		[self composeVertexShader];
		[self composeFragmentShader];
	}
	@catch (NSException *exception)
	{
		// Error should have been reported already.
		return NO;
	}
	@finally
	{
		[self destroyTemporaries];
	}
	
	return YES;
}

- (NSString *) materialKey
{
	return _materialKey;
}


- (NSString *) entityName
{
	return _entityName;
}


// MARK: - Utilities

static void AppendIfNotEmpty(NSMutableString *buffer, NSString *segment, NSString *name)
{
	if ([segment length] > 0)
	{
		if ([buffer length] > 0)  [buffer appendString:@"\n\n"];
		if ([name length] > 0)  [buffer appendFormat:@"// %@\n", name];
		[buffer appendString:segment];
	}
}


static NSString *GetExtractMode(NSDictionary *textureSpecifier)
{
	NSString *result = nil;
	
	NSString *rawMode = [textureSpecifier oo_stringForKey:kOOTextureSpecifierSwizzleKey];
	if (rawMode != nil)
	{
		NSUInteger length = [rawMode length];
		if (1 <= length && length <= 4)
		{
			static NSCharacterSet *nonRGBACharset = nil;
			if (nonRGBACharset == nil)
			{
				nonRGBACharset = [[[NSCharacterSet characterSetWithCharactersInString:@"rgba"] invertedSet] retain];
			}
			
			if ([rawMode rangeOfCharacterFromSet:nonRGBACharset].location == NSNotFound)
			{
				result = rawMode;
			}
		}
	}
	
	return result;
}


- (void) appendVariable:(NSString *)name ofType:(NSString *)type withPrefix:(NSString *)prefix to:(NSMutableString *)buffer
{
	NSUInteger typeDeclLength = [prefix length] + [type length] + 1;
	NSUInteger padding = (typeDeclLength < 20) ? (23 - typeDeclLength) / 4 : 1;
	[buffer appendFormat:@"%@ %@%@%@;\n", prefix, type, OOTabString(padding), name];
}


- (void) addAttribute:(NSString *)name ofType:(NSString *)type
{
	[self appendVariable:name ofType:type withPrefix:@"attribute" to:_attributes];
}


- (void) addVarying:(NSString *)name ofType:(NSString *)type
{
	[self appendVariable:name ofType:type withPrefix:@"varying" to:_varyings];
}


- (void) addVertexUniform:(NSString *)name ofType:(NSString *)type
{
	[self appendVariable:name ofType:type withPrefix:@"uniform" to:_vertexUniforms];
}


- (void) addFragmentUniform:(NSString *)name ofType:(NSString *)type
{
	[self appendVariable:name ofType:type withPrefix:@"uniform" to:_fragmentUniforms];
}


- (NSString *) defineBindingUniform:(NSDictionary *)binding ofType:(NSString *)type
{
	NSString *name = [binding oo_stringForKey:@"binding"];
	NSParameterAssert([name length] > 0);
	
	NSMutableDictionary *bindingSpec = [[binding mutableCopy] autorelease];
	if ([bindingSpec oo_stringForKey:@"type"] == nil)  [bindingSpec setObject:@"binding" forKey:@"type"];
	
	// Use existing uniform if one is defined.
	NSString *uniformName = [_uniformBindingNames objectForKey:bindingSpec];
	if (uniformName != nil)  return uniformName;
	
	// Capitalize first char of name, and prepend u.
	unichar firstChar = toupper([name characterAtIndex:0]);
	NSString *baseName = [NSString stringWithFormat:@"u%C%@", firstChar, [name substringFromIndex:1]];
	
	// Ensure name is unique.
	name = baseName;
	unsigned idx = 1;
	while ([_uniforms objectForKey:name] != nil)
	{
		name = [NSString stringWithFormat:@"%@%u", baseName, ++idx];
	}
	
	[self addFragmentUniform:name ofType:type];
	
	[_uniforms setObject:bindingSpec forKey:name];
	[_uniformBindingNames setObject:name forKey:bindingSpec];
	
	return name;
}


- (void) composeVertexShader
{
	while ([_vertexBody hasSuffix:@"\t\n"])
	{
		[_vertexBody deleteCharactersInRange:(NSRange){ [_vertexBody length] - 2, 2 }];
	}
	[_vertexBody appendString:@"}"];
	
	NSMutableString *vertexShader = [NSMutableString string];
	AppendIfNotEmpty(vertexShader, _attributes, @"Attributes");
	AppendIfNotEmpty(vertexShader, _vertexUniforms, @"Uniforms");
	AppendIfNotEmpty(vertexShader, _varyings, @"Varyings");
	AppendIfNotEmpty(vertexShader, _vertexHelpers, @"Helper functions");
	AppendIfNotEmpty(vertexShader, _vertexBody, nil);
	
#ifndef NDEBUG
	_vertexShader = [vertexShader copy];
#else
	_vertexShader = [vertexShader retain];
#endif
}


- (void) composeFragmentShader
{
	while ([_fragmentBody hasSuffix:@"\t\n"])
	{
		[_fragmentBody deleteCharactersInRange:(NSRange){ [_fragmentBody length] - 2, 2 }];
	}
	
	NSMutableString *fragmentShader = [NSMutableString string];
	AppendIfNotEmpty(fragmentShader, _fragmentUniforms, @"Uniforms");
	AppendIfNotEmpty(fragmentShader, _varyings, @"Varyings");
	AppendIfNotEmpty(fragmentShader, _fragmentHelpers, @"Helper functions");
	AppendIfNotEmpty(fragmentShader, _fragmentPreTextures, nil);
	if ([_fragmentTextureLookups length] > 0)
	{
		[fragmentShader appendString:@"\t\n\t// Texture lookups\n"];
		[fragmentShader appendString:_fragmentTextureLookups];
	}
	[fragmentShader appendString:@"\t\n"];
	[fragmentShader appendString:_fragmentBody];
	[fragmentShader appendString:@"}"];
	
#ifndef NDEBUG
	_fragmentShader = [fragmentShader copy];
#else
	_fragmentShader = [fragmentShader retain];
#endif
}


/*
	Build a key for a texture specifier, taking all texture configuration
	options into account and ignoring the other stuff that might be there.
	
	FIXME: efficiency and stuff.
*/
static NSString *KeyFromTextureParameters(NSString *name, OOTextureFlags options, float anisotropy, float lodBias)
{
#ifndef NDEBUG
	options = OOApplyTextureOptionDefaults(options);
#endif
	
	// Extraction modes are ignored in synthesized shaders, since we use swizzling instead.
	options &= ~kOOTextureExtractChannelMask;
	
	return [NSString stringWithFormat:@"%@:%X:%g:%g", name, options, anisotropy, lodBias];
}

static NSString *KeyFromTextureSpec(NSDictionary *spec)
{
	NSString *texName = nil;
	OOTextureFlags texOptions;
	float anisotropy, lodBias;
	if (!OOInterpretTextureSpecifier(spec, &texName, &texOptions, &anisotropy, &lodBias, YES))
	{
		// OOInterpretTextureSpecifier() will have logged something.
		[NSException raise:NSGenericException format:@"Invalid texture specifier"];
	}
	
	return KeyFromTextureParameters(texName, texOptions, anisotropy, lodBias);
}


- (NSUInteger) assignIDForTexture:(NSDictionary *)spec
{
	NSParameterAssert(spec != nil);
	
	// extract_channel doesn't affect uniqueness, and we don't want OOTexture to do actual extraction.
	if ([spec objectForKey:kOOTextureSpecifierSwizzleKey] != nil)
	{
		spec = [spec dictionaryByRemovingObjectForKey:kOOTextureSpecifierSwizzleKey];
	}
	
	NSString *texName = nil;
	OOTextureFlags texOptions;
	float anisotropy, lodBias;
	if (!OOInterpretTextureSpecifier(spec, &texName, &texOptions, &anisotropy, &lodBias, YES))
	{
		// OOInterpretTextureSpecifier() will have logged something.
		[NSException raise:NSGenericException format:@"Invalid texture specifier"];
	}
	
	if (texOptions & kOOTextureAllowCubeMap)
	{
		// cube_map = true; fail regardless of whether actual texture qualifies.
		OOLogERR(@"material.synthesis.error.cubeMap", @"The material \"%@\" of \"%@\" specifies a cube map texture, but doesn't have custom shaders. Cube map textures are not supported with the default shaders.", [self materialKey], [self entityName]);
		[NSException raise:NSGenericException format:@"Invalid material"];
	}
	
	NSString *key = KeyFromTextureParameters(texName, texOptions, anisotropy, lodBias);
	NSUInteger texID;
	NSObject *existing = [_texturesByName objectForKey:key];
	if (existing == nil)
	{
		texID = [_texturesByName count];
		NSNumber	*texIDObj = [NSNumber numberWithUnsignedInteger:texID];
		NSString	*texUniform = [NSString stringWithFormat:@"uTexture%lu", texID];
		
#ifndef NDEBUG
		BOOL useInternalFormat = NO;
#else
		BOOL useInternalFormat = YES;
#endif
		
		[_textures addObject:OOMakeTextureSpecifier(texName, texOptions, anisotropy, lodBias, useInternalFormat)];
		[_texturesByName setObject:spec forKey:key];
		[_textureIDs setObject:texIDObj forKey:key];
		[_uniforms setObject:[NSDictionary dictionaryWithObjectsAndKeys:@"texture", @"type", texIDObj, @"value", nil]
					  forKey:texUniform];
		
		[self addFragmentUniform:texUniform ofType:@"sampler2D"];
	}
	else
	{
		texID = [_textureIDs oo_unsignedIntegerForKey:texName];
	}
	
	return texID;
}


- (NSUInteger) textureIDForSpec:(NSDictionary *)textureSpec
{
	return [_textureIDs oo_unsignedIntegerForKey:KeyFromTextureSpec(textureSpec)];
}


- (void) setUpOneTexture:(NSDictionary *)textureSpec
{
	if (textureSpec == nil)  return;
	
	REQUIRE_STAGE(writeTextureCoordRead);
	
	NSUInteger texID = [self assignIDForTexture:textureSpec];
	if ((NSUInteger)NSHashGet(_sampledTextures, (const void *)(texID + 1)) == 0)
	{
		NSHashInsertKnownAbsent(_sampledTextures, (const void *)(texID + 1));
		[_fragmentTextureLookups appendFormat:@"\tvec4 tex%luSample = texture2D(uTexture%lu, texCoords);  // %@\n", texID, texID, [textureSpec oo_stringForKey:kOOTextureSpecifierNameKey]];
	}
}


- (void) getSampleName:(NSString **)outSampleName andSwizzleOp:(NSString **)outSwizzleOp forTextureSpec:(NSDictionary *)textureSpec
{
	NSParameterAssert(outSampleName != NULL && outSwizzleOp != NULL && textureSpec != nil);
	
	[self setUpOneTexture:textureSpec];
	NSUInteger	texID = [self textureIDForSpec:textureSpec];
	
	*outSampleName = [NSString stringWithFormat:@"tex%luSample", texID];
	*outSwizzleOp = GetExtractMode(textureSpec);
}


- (NSString *) readRGBForTextureSpec:(NSDictionary *)textureSpec mapName:(NSString *)mapName
{
	NSString *sample, *swizzle;
	[self getSampleName:&sample andSwizzleOp:&swizzle forTextureSpec:textureSpec];
	
	if (swizzle == nil)
	{
		return [sample stringByAppendingString:@".rgb"];
	}
	
	NSUInteger channelCount = [swizzle length];
	
	if (channelCount == 1)
	{
		return [NSString stringWithFormat:@"%@.%@%@%@", sample, swizzle, swizzle, swizzle];
	}
	else if (channelCount == 3)
	{
		return [NSString stringWithFormat:@"%@.%@", sample, swizzle];
	}
	
	OOLogWARN(@"material.synthesis.warning.extractionMismatch", @"The %@ map for material \"%@\" of \"%@\" specifies %lu channels to extract, but only %@ may be used.", mapName, [self materialKey], [self entityName], channelCount, @"1 or 3");
	return nil;
}


- (NSString *) readOneChannelForTextureSpec:(NSDictionary *)textureSpec mapName:(NSString *)mapName
{
	NSString *sample, *swizzle;
	[self getSampleName:&sample andSwizzleOp:&swizzle forTextureSpec:textureSpec];
	
	if (swizzle == nil)
	{
		return [sample stringByAppendingString:@".r"];
	}
	
	NSUInteger channelCount = [swizzle length];
	
	if (channelCount == 1)
	{
		return [NSString stringWithFormat:@"%@.%@", sample, swizzle];
	}
	
	OOLogWARN(@"material.synthesis.warning.extractionMismatch", @"The %@ map for material \"%@\" of \"%@\" specifies %lu channels to extract, but only %@ may be used.", mapName, [self materialKey], [self entityName], channelCount, @"1");
	return nil;
}


#ifndef NDEBUG
- (void) performStage:(SEL)stage
{
	// Ensure that we aren’t recursing.
	if (NSHashGet(_stagesInProgress, stage) != NULL)
	{
		OOLogERR(@"material.synthesis.error.recursion", @"Shader synthesis recursion for stage %@.", NSStringFromSelector(stage));
		[NSException raise:NSInternalInconsistencyException format:@"stage recursion"];
	}
	
	NSHashInsertKnownAbsent(_stagesInProgress, stage);
	
	[self performSelector:stage];
	
	NSHashRemove(_stagesInProgress, stage);
}
#endif


- (void) createTemporaries
{
	_attributes = [[NSMutableString alloc] init];
	_varyings = [[NSMutableString alloc] init];
	_vertexUniforms = [[NSMutableString alloc] init];
	_fragmentUniforms = [[NSMutableString alloc] init];
	_vertexHelpers = [[NSMutableString alloc] init];
	_fragmentHelpers = [[NSMutableString alloc] init];
	_vertexBody = [[NSMutableString alloc] init];
	_fragmentPreTextures = [[NSMutableString alloc] init];
	_fragmentTextureLookups = [[NSMutableString alloc] init];
	_fragmentBody = [[NSMutableString alloc] init];
	
	_textures = [[NSMutableArray alloc] init];
	_texturesByName = [[NSMutableDictionary alloc] init];
	_textureIDs = [[NSMutableDictionary alloc] init];
	_sampledTextures = NSCreateHashTable(NSIntegerHashCallBacks, 0);
	
	_uniformBindingNames = [[NSMutableDictionary alloc] init];
	
#ifndef NDEBUG
	_stagesInProgress = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 0);
#endif
}


- (void) destroyTemporaries
{
	DESTROY(_attributes);
	DESTROY(_varyings);
	DESTROY(_vertexUniforms);
	DESTROY(_fragmentUniforms);
	DESTROY(_vertexHelpers);
	DESTROY(_fragmentHelpers);
	DESTROY(_vertexBody);
	DESTROY(_fragmentPreTextures);
	DESTROY(_fragmentTextureLookups);
	DESTROY(_fragmentBody);
	
	DESTROY(_texturesByName);
	DESTROY(_textureIDs);
	if (_sampledTextures != NULL)
	{
		NSFreeHashTable(_sampledTextures);
		_sampledTextures = NULL;
	}
	
	DESTROY(_uniformBindingNames);
	
#ifndef NDEBUG
	if (_stagesInProgress != NULL)
	{
		NSFreeHashTable(_stagesInProgress);
		_stagesInProgress = NULL;
	}
#endif
}


// MARK: - Synthesis stages

- (void) writeTextureCoordRead
{
	[self addVarying:@"vTexCoords" ofType:@"vec2"];
	[_vertexBody appendString:@"\tvTexCoords = gl_MultiTexCoord0.st;\n\t\n"];
	
	BOOL haveTexCoords = NO;
	NSDictionary *parallaxMap = [_configuration oo_parallaxMapSpecifier];
	
	if (parallaxMap != nil)
	{
		float parallaxScale = [_configuration oo_parallaxScale];
		if (parallaxScale != 0.0f)
		{
			/*
				We can’t call -getSampleName:... here because the standard
				texture loading mechanism has to occur after determining
				texture coordinates (duh).
			*/
			NSString *swizzle = GetExtractMode(parallaxMap) ?: (NSString *)@"a";
			NSUInteger channelCount = [swizzle length];
			if (channelCount == 1)
			{
				haveTexCoords = YES;
				
				REQUIRE_STAGE(writeEyeVector);
				
				[_fragmentPreTextures appendString:@"\t// Parallax mapping\n"];
				
				NSUInteger texID = [self assignIDForTexture:parallaxMap];
				[_fragmentPreTextures appendFormat:@"\tfloat parallax = texture2D(uTexture%lu, vTexCoords).%@;\n", texID, swizzle];
				
				if (parallaxScale != 1.0f)
				{
					[_fragmentPreTextures appendFormat:@"\tparallax *= %@;  // Parallax scale\n", FormatFloat(parallaxScale)];
				}
				
				float parallaxBias = [_configuration oo_parallaxBias];
				if (parallaxBias != 0.0)
				{
					[_fragmentPreTextures appendFormat:@"\tparallax += %@;  // Parallax bias\n", FormatFloat(parallaxBias)];
				}
				
				[_fragmentPreTextures appendString:@"\tvec2 texCoords = vTexCoords - parallax * eyeVector.xy * vec2(1.0, -1.0);\n"];
			}
			else
			{
				OOLogWARN(@"material.synthesis.warning.extractionMismatch", @"The %@ map for material \"%@\" of \"%@\" specifies %lu channels to extract, but only %@ may be used.", @"parallax", [self materialKey], [self entityName], channelCount, @"1");
			}
		}
	}
	
	if (!haveTexCoords)
	{
		[_fragmentPreTextures appendString:@"\tvec2 texCoords = vTexCoords;\n"];
	}
}


- (void) writeDiffuseColorTermIfNeeded
{
	NSDictionary		*diffuseMap = [_configuration oo_diffuseMapSpecifierWithDefaultName:[self materialKey]];
	OOColor				*diffuseColor = [_configuration oo_diffuseColor] ?: [OOColor whiteColor];
	
	if ([diffuseColor isBlack])  return;
	_usesDiffuseTerm = YES;
	
	BOOL haveDiffuseColor = NO;
	if (diffuseMap != nil)
	{
		NSString *readInstr = [self readRGBForTextureSpec:diffuseMap mapName:@"diffuse"];
		if (EXPECT_NOT(readInstr == nil))
		{
			[_fragmentBody appendString:@"\t// INVALID EXTRACTION KEY\n\t\n"];
		}
		else
		{
			[_fragmentBody appendFormat:@"\tvec3 diffuseColor = %@;\n", readInstr];
			 haveDiffuseColor = YES;
		}
	}
	
	if (!haveDiffuseColor || ![diffuseColor isWhite])
	{
		float rgba[4];
		[diffuseColor getRed:&rgba[0] green:&rgba[1] blue:&rgba[2] alpha:&rgba[3]];
		NSString *format = nil;
		if (haveDiffuseColor)
		{
			format = @"\tdiffuseColor *= vec3(%@, %@, %@);\n";
		}
		else
		{
			format = @"\tconst vec3 diffuseColor = vec3(%@, %@, %@);\n";
			haveDiffuseColor = YES;
		}
		[_fragmentBody appendFormat:format, FormatFloat(rgba[0]), FormatFloat(rgba[1]), FormatFloat(rgba[2])];
	}
	
	(void) haveDiffuseColor;
	[_fragmentBody appendString:@"\t\n"];
}


- (void) writeDiffuseColorTerm
{
	REQUIRE_STAGE(writeDiffuseColorTermIfNeeded);
	
	if (!_usesDiffuseTerm)
	{
		[_fragmentBody appendString:@"\tconst vec3 diffuseColor = vec3(0.0);  // Diffuse colour is black.\n\t\n"];
	}
}


- (void) writeDiffuseLighting
{
	REQUIRE_STAGE(writeDiffuseColorTermIfNeeded);
	if (!_usesDiffuseTerm)  return;
	
	REQUIRE_STAGE(writeTotalColor);
	REQUIRE_STAGE(writeVertexPosition);
	REQUIRE_STAGE(writeNormalIfNeeded);
	REQUIRE_STAGE(writeLightVector);
	
	// FIXME: currently uncoloured diffuse and ambient lighting.
	NSString *normalDotLight = _constZNormal ? @"lightVector.z" : @"dot(normal, lightVector)";
	
	[_fragmentBody appendFormat:
	@"\t// Diffuse (Lambertian) and ambient lighting\n"
	 "\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, %@) + gl_LightModel.ambient).rgb;\n\t\n",
	 normalDotLight];
	
	_haveDiffuseLight = YES;
}


- (void) writeLightVector
{
	REQUIRE_STAGE(writeVertexPosition);
	REQUIRE_STAGE(writeNormalIfNeeded);
	
	[self addVarying:@"vLightVector" ofType:@"vec3"];
	
	[_vertexBody appendString:
	 @"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
	  "\tvLightVector = lightVector * TBN;\n\t\n"];
	[_fragmentBody appendFormat:@"\tvec3 lightVector = normalize(vLightVector);\n\t\n"];
}


- (void) writeEyeVector
{
	REQUIRE_STAGE(writeVertexPosition);
	REQUIRE_STAGE(writeVertexTangentBasis);
	
	[self addVarying:@"vEyeVector" ofType:@"vec3"];
	
	[_vertexBody appendString:@"\tvEyeVector = position.xyz * TBN;\n\t\n"];
	[_fragmentPreTextures appendString:@"\tvec3 eyeVector = normalize(vEyeVector);\n\t\n"];
}


- (void) writeVertexTangentBasis
{
	[self addAttribute:@"tangent" ofType:@"vec3"];
	
	[_vertexBody appendString:
	 @"\t// Build tangent space basis\n"
	  "\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
	  "\tvec3 t = gl_NormalMatrix * tangent;\n"
	  "\tvec3 b = cross(n, t);\n"
	  "\tmat3 TBN = mat3(t, b, n);\n\t\n"];
}


- (void) writeNormalIfNeeded
{
	REQUIRE_STAGE(writeVertexPosition);
	REQUIRE_STAGE(writeVertexTangentBasis);
	
	NSDictionary *normalMap = [_configuration oo_normalMapSpecifier];
	if (normalMap == nil)
	{
		// FIXME: this stuff should be handled in OOMaterialSpecifier.m when synthesizer takes over the world. -- Ahruman 2012-02-08
		normalMap = [_configuration oo_normalAndParallaxMapSpecifier];
	}
	if (normalMap != nil)
	{
		NSString *sample, *swizzle;
		[self getSampleName:&sample andSwizzleOp:&swizzle forTextureSpec:normalMap];
		if (swizzle == nil)  swizzle = @"rgb";
		if ([swizzle length] == 3)
		{
			[_fragmentBody appendFormat:@"\tvec3 normal = normalize(%@.%@ - 0.5);\n\t\n", sample, swizzle];
			_usesNormalMap = YES;
			return;
		}
		else
		{
			OOLogWARN(@"material.synthesis.warning.extractionMismatch", @"The %@ map for material \"%@\" of \"%@\" specifies %lu channels to extract, but only %@ may be used.", @"normal", [self materialKey], [self entityName], [swizzle length], @"3");
		}
	}
	_constZNormal = YES;
}


- (void) writeNormal
{
	REQUIRE_STAGE(writeNormalIfNeeded);
	
	if (_constZNormal)
	{
		[_fragmentBody appendString:@"\tconst vec3 normal = vec3(0.0, 0.0, 1.0);\n\t\n"];
	}
}


- (void) writeSpecularLighting
{
	float specularExponent = [_configuration oo_specularExponent];
	if (specularExponent <= 0)  return;
	
	NSDictionary *specularColorMap = [_configuration oo_specularColorMapSpecifier];
	NSDictionary *specularExponentMap = [_configuration oo_specularExponentMapSpecifier];
	float scaleFactor = 1.0f;
	
	if (specularColorMap)
	{
		scaleFactor = [specularColorMap oo_doubleForKey:kOOTextureSpecifierScaleFactorKey defaultValue:1.0f];
	}
	
	OOColor *specularColor = nil;
	if (specularColorMap == nil)
	{
		specularColor = [_configuration oo_specularColor];
	}
	else
	{
		specularColor = [_configuration oo_specularModulateColor];
	}
	
	if ([specularColor isBlack])  return;
	
	BOOL modulateWithDiffuse = [specularColorMap oo_boolForKey:kOOTextureSpecifierSelfColorKey];
	
	REQUIRE_STAGE(writeTotalColor);
	REQUIRE_STAGE(writeNormalIfNeeded);
	REQUIRE_STAGE(writeEyeVector);
	REQUIRE_STAGE(writeLightVector);
	if (modulateWithDiffuse)
	{
		REQUIRE_STAGE(writeDiffuseColorTerm);
	}
	
	[_fragmentBody appendString:@"\t// Specular (Blinn-Phong) lighting\n"];
	
	BOOL haveSpecularColor = NO;
	if (specularColorMap != nil)
	{
		NSString *readInstr = [self readRGBForTextureSpec:specularColorMap mapName:@"specular colour"];
		if (EXPECT_NOT(readInstr == nil))
		{
			[_fragmentBody appendString:@"\t// INVALID EXTRACTION KEY\n\t\n"];
			return;
		}
		
		[_fragmentBody appendFormat:@"\tvec3 specularColor = %@;\n", readInstr];
		haveSpecularColor = YES;
	}
	
	if (!haveSpecularColor || ![specularColor isWhite])
	{
		float rgba[4];
		[specularColor getRed:&rgba[0] green:&rgba[1] blue:&rgba[2] alpha:&rgba[3]];
		
		NSString *comment = (scaleFactor == 1.0f) ? @"Constant colour" : @"Constant colour and scale factor";
		
		// Handle scale factor, colour, and colour alpha scaling as one multiply.
		scaleFactor *= rgba[3];
		rgba[0] *= scaleFactor;
		rgba[1] *= scaleFactor;
		rgba[2] *= scaleFactor;
		
		// Avoid reapplying scaleFactor below.
		scaleFactor = 1.0;
		
		NSString *format = nil;
		if (haveSpecularColor)
		{
			format = @"\tspecularColor *= vec3(%@, %@, %@);  // %@\n";
		}
		else
		{
			format = @"\tvec3 specularColor = vec3(%@, %@, %@);  // %@\n";
			haveSpecularColor = YES;
		}
		[_fragmentBody appendFormat:format, FormatFloat(rgba[0]), FormatFloat(rgba[1]), FormatFloat(rgba[2]), comment];
	}
	
	// Handle scale_factor if no constant colour.
	if (haveSpecularColor && scaleFactor != 1.0f)
	{
		[_fragmentBody appendFormat:@"\tspecularColor *= %@;  // Scale factor\n", FormatFloat(scaleFactor)];
	}
	
	// Handle self_color.
	if (modulateWithDiffuse)
	{
		[_fragmentBody appendString:@"\tspecularColor *= diffuseColor;  // Self-colouring\n"];
	}
	
	// Specular exponent.
	BOOL haveSpecularExponent = NO;
	if (specularExponentMap != nil)
	{
		NSString *readInstr = [self readOneChannelForTextureSpec:specularExponentMap mapName:@"specular exponent"];
		if (EXPECT_NOT(readInstr == nil))
		{
			[_fragmentBody appendString:@"\t// INVALID EXTRACTION KEY\n\t\n"];
			return;
		}
		
		[_fragmentBody appendFormat:@"\tfloat specularExponent = %@ * %.1f;\n", readInstr, specularExponent];
		haveSpecularExponent = YES;
	}
	if (!haveSpecularExponent)
	{
		[_fragmentBody appendFormat:@"\tconst float specularExponent = %.1f;\n", specularExponent];
	}
	
	if (_usesNormalMap)
	{
		[_fragmentBody appendFormat:@"\tvec3 reflection = reflect(lightVector, normal);\n"];
	}
	else
	{
		/*	reflect(I, N) is defined as I - 2 * dot(N, I) * N
			If N is (0,0,1), this becomes (I.x,I.y,-I.z).
		*/
		[_fragmentBody appendFormat:@"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"];
	}
	
	[_fragmentBody appendFormat:
	@"\tfloat specIntensity = dot(reflection, eyeVector);\n"
	 "\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
	 "\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n\t\n"];
}


- (void) writeLightMaps
{
	NSArray *lightMaps = [_configuration oo_arrayForKey:kOOMaterialLightMapsName];
	NSUInteger idx, count = [lightMaps count];
	if (count == 0)  return;
	
	REQUIRE_STAGE(writeTotalColor);
	
	// Check if we need the diffuse colour term.
	for (idx = 0; idx < count; idx++)
	{
		NSDictionary *lightMapSpec = [lightMaps oo_dictionaryAtIndex:idx];
		if ([lightMapSpec oo_boolForKey:kOOTextureSpecifierIlluminationModeKey])
		{
			REQUIRE_STAGE(writeDiffuseColorTerm);
			REQUIRE_STAGE(writeDiffuseLighting);
			break;
		}
	}
	
	[_fragmentBody appendString:@"\tvec3 lightMapColor;\n"];
	
	for (idx = 0; idx < count; idx++)
	{
		NSDictionary	*lightMapSpec = [lightMaps oo_dictionaryAtIndex:idx];
		NSDictionary	*textureSpec = OOTextureSpecFromObject(lightMapSpec, nil);
		NSArray			*color = [lightMapSpec oo_arrayForKey:kOOTextureSpecifierModulateColorKey];
		float			rgba[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
		BOOL			isIllumination = [lightMapSpec oo_boolForKey:kOOTextureSpecifierIlluminationModeKey];
		
		if (EXPECT_NOT(color == nil && textureSpec == nil))
		{
			[_fragmentBody appendString:@"\t// Light map with neither colour nor texture has no effect.\n\t\n"];
			continue;
		}
		
		if (color != nil)
		{
			NSUInteger idx, count = [color count];
			if (count > 4)  count = 4;
			for (idx = 0; idx < count; idx++)
			{
				rgba[idx] = [color oo_doubleAtIndex:idx];
			}
			rgba[0] *= rgba[3]; rgba[1] *= rgba[3]; rgba[2] *= rgba[3];
		}
		
		if (EXPECT_NOT((rgba[0] == 0.0f && rgba[1] == 0.0f && rgba[2] == 0.0f) ||
					   (!_usesDiffuseTerm && isIllumination)))
		{
			[_fragmentBody appendString:@"\t// Light map tinted black has no effect.\n\t\n"];
			continue;
		}
		
		if (textureSpec != nil)
		{
			NSString *readInstr = [self readRGBForTextureSpec:textureSpec mapName:@"light"];
			if (EXPECT_NOT(readInstr == nil))
			{
				[_fragmentBody appendString:@"\t// INVALID EXTRACTION KEY\n\n"];
				continue;
			}
			
			[_fragmentBody appendFormat:@"\tlightMapColor = %@;\n", readInstr];
			
			if (rgba[0] != 1.0f || rgba[1] != 1.0f || rgba[2] != 1.0f)
			{
				[_fragmentBody appendFormat:@"\tlightMapColor *= vec3(%@, %@, %@);\n", FormatFloat(rgba[0]), FormatFloat(rgba[1]), FormatFloat(rgba[2])];
			}
		}
		else
		{
			[_fragmentBody appendFormat:@"\tlightMapColor = vec3(%@, %@, %@);\n", FormatFloat(rgba[0]), FormatFloat(rgba[1]), FormatFloat(rgba[2])];
		}
		
		NSDictionary *binding = [textureSpec oo_dictionaryForKey:kOOTextureSpecifierBindingKey];
		if (binding != nil)
		{
			NSString *bindingName = [binding oo_stringForKey:@"binding"];
			NSDictionary *typeDict = [[ResourceManager shaderBindingTypesDictionary] oo_dictionaryForKey:@"player"];	// FIXME: select appropriate binding subset.
			NSString *bindingType = [typeDict oo_stringForKey:bindingName];
			NSString *glslType = nil;
			NSString *swizzle = @"";
			
			if ([bindingType isEqualToString:@"float"])
			{
				glslType = @"float";
			}
			else if ([bindingType isEqualToString:@"vector"])
			{
				glslType = @"vec3";
			}
			else if ([bindingType isEqualToString:@"color"])
			{
				glslType = @"vec4";
				swizzle = @".rgb";
			}
			
			if (glslType != nil)
			{
				NSString *uniformName = [self defineBindingUniform:binding ofType:bindingType];
				[_fragmentBody appendFormat:@"\tlightMapColor *= %@%@;\n", uniformName, swizzle];
			}
			else
			{
				if (bindingType == nil)
				{
					OOLogERR(@"material.binding.error.unknown", @"Cannot bind light map to unknown attribute \"%@\".", bindingName);
				}
				else
				{
					OOLogERR(@"material.binding.error.badType", @"Cannot bind light map to attribute \"%@\" of type %@.", bindingName, bindingType);
				}
				[_fragmentBody appendString:@"\tlightMapColor = vec3(0.0);  // Bad binding, see log.\n"];
			}
		}
		
		if (!isIllumination)
		{
			[_fragmentBody appendString:@"\ttotalColor += lightMapColor;\n\t\n"];
		}
		else
		{
			[_fragmentBody appendString:@"\tdiffuseLight += lightMapColor;\n\t\n"];
		}
	}
}


- (void) writeVertexPosition
{
	[_vertexBody appendString:
	@"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
	 "\tgl_Position = gl_ProjectionMatrix * position;\n\t\n"];
}


- (void) writeTotalColor
{
	[_fragmentPreTextures appendString:@"\tvec3 totalColor = vec3(0.0);\n\t\n"];
}


- (void) writeFinalColorComposite
{
	REQUIRE_STAGE(writeTotalColor);	// Needed even if none of the following stages does anything.
	REQUIRE_STAGE(writeDiffuseLighting);
	REQUIRE_STAGE(writeSpecularLighting);
	REQUIRE_STAGE(writeLightMaps);
	
	if (_haveDiffuseLight)
	{
		[_fragmentBody appendString:@"\ttotalColor += diffuseColor * diffuseLight;\n"];
	}
	
	[_fragmentBody appendString:@"\tgl_FragColor = vec4(totalColor, 1.0);\n\t\n"];
}

@end

/*
	Convert any legacy properties and simplified forms in a material specifier
	to the standard form.
	
	FIXME: this should be done up front in OOShipRegistry. When doing that, it
	also need to be done when materials are set on the fly through JS,
*/
static NSDictionary *CanonicalizeMaterialSpecifier(NSDictionary *spec, NSString *materialKey)
{
	NSMutableDictionary		*result = [NSMutableDictionary dictionary];
	OOColor					*col = nil;
	id						texSpec = nil;
	
	// Colours.
	col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialDiffuseColorName]];
	if (col == nil)  col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialDiffuseColorLegacyName]];
	if (col != nil)  [result setObject:[col normalizedArray] forKey:kOOMaterialDiffuseColorName];
	
	col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialAmbientColorName]];
	if (col == nil)  col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialAmbientColorLegacyName]];
	if (col != nil)  [result setObject:[col normalizedArray] forKey:kOOMaterialAmbientColorName];
	
	col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialSpecularColorName]];
	if (col == nil)  col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialSpecularColorLegacyName]];
	if (col != nil)  [result setObject:[col normalizedArray] forKey:kOOMaterialSpecularColorName];
	
	col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialSpecularModulateColorName]];
	if (col != nil)  [result setObject:[col normalizedArray] forKey:kOOMaterialSpecularModulateColorName];
	
	col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialEmissionColorName]];
	if (col == nil)  col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialEmissionColorLegacyName]];
	if (col != nil)  [result setObject:[col normalizedArray] forKey:kOOMaterialEmissionColorName];
	
	// Diffuse map.
	texSpec = [spec objectForKey:kOOMaterialDiffuseMapName];
	if ([texSpec isKindOfClass:[NSString class]])
	{
		if ([texSpec length] > 0)
		{
			texSpec = [NSDictionary dictionaryWithObject:texSpec forKey:kOOTextureSpecifierNameKey];
		}
	}
	else if ([texSpec isKindOfClass:[NSDictionary class]])
	{
		/*	Special case for diffuse map: no name is changed to
			name = materialKey, while name = "" is changed to no name.
		*/
		NSString *name = [texSpec objectForKey:kOOTextureSpecifierNameKey];
		if (name == nil)  texSpec = [texSpec dictionaryByAddingObject:materialKey forKey:kOOTextureSpecifierNameKey];
		else if ([name length] == 0)
		{
			texSpec = [texSpec dictionaryByRemovingObjectForKey:kOOTextureSpecifierNameKey];
		}
	}
	else
	{
		// Special case for unspecified diffuse map.
		texSpec = [NSDictionary dictionaryWithObject:materialKey forKey:kOOTextureSpecifierNameKey];
	}
	[result setObject:texSpec forKey:kOOMaterialDiffuseMapName];
	
	// Specular maps.
	{
		BOOL haveNewSpecular = NO;
		texSpec = [spec objectForKey:kOOMaterialSpecularColorMapName];
		if ([texSpec isKindOfClass:[NSString class]])
		{
			texSpec = [NSDictionary dictionaryWithObject:texSpec forKey:kOOTextureSpecifierNameKey];
		}
		else if (![texSpec isKindOfClass:[NSDictionary class]])
		{
			texSpec = nil;
		}
		if (texSpec != nil)
		{
			haveNewSpecular = YES;
			[result setObject:texSpec forKey:kOOMaterialSpecularColorMapName];
		}
		
		texSpec = [spec objectForKey:kOOMaterialSpecularExponentMapName];
		if ([texSpec isKindOfClass:[NSString class]])
		{
			texSpec = [NSDictionary dictionaryWithObject:texSpec forKey:kOOTextureSpecifierNameKey];
		}
		else if (![texSpec isKindOfClass:[NSDictionary class]])
		{
			texSpec = nil;
		}
		if (texSpec != nil)
		{
			haveNewSpecular = YES;
			[result setObject:texSpec forKey:kOOMaterialSpecularExponentMapName];
		}
		
		if (!haveNewSpecular)
		{
			// Fall back to legacy combined specular map if defined.
			texSpec = [spec objectForKey:kOOMaterialCombinedSpecularMapName];
			if ([texSpec isKindOfClass:[NSString class]])
			{
				texSpec = [NSDictionary dictionaryWithObject:texSpec forKey:kOOTextureSpecifierNameKey];
			}
			else if (![texSpec isKindOfClass:[NSDictionary class]])
			{
				texSpec = nil;
			}
			if (texSpec != nil)
			{
				[result setObject:texSpec forKey:kOOMaterialSpecularColorMapName];
				texSpec = [texSpec dictionaryByAddingObject:@"a" forKey:kOOTextureSpecifierSwizzleKey];
				[result setObject:texSpec forKey:kOOMaterialSpecularExponentMapName];
			}
		}
	}
	
	// Normal and parallax maps.
	{
		BOOL haveParallax = NO;
		BOOL haveNewNormal = NO;
		texSpec = [spec objectForKey:kOOMaterialNormalMapName];
		if ([texSpec isKindOfClass:[NSString class]])
		{
			texSpec = [NSDictionary dictionaryWithObject:texSpec forKey:kOOTextureSpecifierNameKey];
		}
		else if (![texSpec isKindOfClass:[NSDictionary class]])
		{
			texSpec = nil;
		}
		if (texSpec != nil)
		{
			haveNewNormal = YES;
			[result setObject:texSpec forKey:kOOMaterialNormalMapName];
		}
		
		texSpec = [spec objectForKey:kOOMaterialParallaxMapName];
		if ([texSpec isKindOfClass:[NSString class]])
		{
			texSpec = [NSDictionary dictionaryWithObject:texSpec forKey:kOOTextureSpecifierNameKey];
		}
		else if (![texSpec isKindOfClass:[NSDictionary class]])
		{
			texSpec = nil;
		}
		if (texSpec != nil)
		{
			haveNewNormal = YES;
			haveParallax = YES;
			[result setObject:texSpec forKey:kOOMaterialParallaxMapName];
		}
		
		if (!haveNewNormal)
		{
			// Fall back to legacy combined normal and parallax map if defined.
			texSpec = [spec objectForKey:kOOMaterialNormalAndParallaxMapName];
			if ([texSpec isKindOfClass:[NSString class]])
			{
				texSpec = [NSDictionary dictionaryWithObject:texSpec forKey:kOOTextureSpecifierNameKey];
			}
			else if (![texSpec isKindOfClass:[NSDictionary class]])
			{
				texSpec = nil;
			}
			if (texSpec != nil)
			{
				haveParallax = YES;
				[result setObject:texSpec forKey:kOOMaterialNormalMapName];
				texSpec = [texSpec dictionaryByAddingObject:@"a" forKey:kOOTextureSpecifierSwizzleKey];
				[result setObject:texSpec forKey:kOOMaterialParallaxMapName];
			}
		}
		
		// Additional parallax parameters.
		if (haveParallax)
		{
			float parallaxScale = [spec oo_floatForKey:kOOMaterialParallaxScaleName defaultValue:kOOMaterialDefaultParallaxScale];
			[result oo_setFloat:parallaxScale forKey:kOOMaterialParallaxScaleName];
			
			float parallaxBias = [spec oo_floatForKey:kOOMaterialParallaxBiasName];
			[result oo_setFloat:parallaxBias forKey:kOOMaterialParallaxBiasName];
		}
	}
	
	// Light maps.
	{
		NSMutableArray *lightMaps = [NSMutableArray array];
		id lightMapSpecs = [spec objectForKey:kOOMaterialLightMapsName];
		if (lightMapSpecs != nil && ![lightMapSpecs isKindOfClass:[NSArray class]])
		{
			lightMapSpecs = [NSArray arrayWithObject:lightMapSpecs];
		}
		
		id lmSpec = nil;
		foreach (lmSpec, lightMapSpecs)
		{
			if ([lmSpec isKindOfClass:[NSString class]])
			{
				lmSpec = [NSMutableDictionary dictionaryWithObject:lmSpec forKey:kOOTextureSpecifierNameKey];
			}
			else if ([lmSpec isKindOfClass:[NSDictionary class]])
			{
				lmSpec = [[lmSpec mutableCopy] autorelease];
			}
			else
			{
				continue;
			}
			
			id modulateColor = [lmSpec objectForKey:kOOTextureSpecifierModulateColorKey];
			if (modulateColor != nil && ![modulateColor isKindOfClass:[NSArray class]])
			{
				// Don't convert arrays here, because we specifically don't want the behaviour of treating numbers greater than 1 as 0..255 components.
				col = [OOColor colorWithDescription:modulateColor];
				[lmSpec setObject:[col normalizedArray] forKey:kOOTextureSpecifierModulateColorKey];
			}
			
			id binding = [lmSpec objectForKey:kOOTextureSpecifierBindingKey];
			if (binding != nil)
			{
				if ([binding isKindOfClass:[NSString class]])
				{
					NSDictionary *expandedBinding = [NSDictionary dictionaryWithObjectsAndKeys:@"binding", @"type", binding, @"binding", nil];
					[lmSpec setObject:expandedBinding forKey:kOOTextureSpecifierBindingKey];
				}
				else if (![binding isKindOfClass:[NSDictionary class]] || [[binding oo_stringForKey:@"binding"] length] == 0)
				{
					[lmSpec removeObjectForKey:kOOTextureSpecifierBindingKey];
				}
			}
			
			[lightMaps addObject:[[lmSpec copy] autorelease]];
		}
		
		if ([lightMaps count] == 0)
		{
			// If light_map isn't use, handle legacy emission_map, illumination_map and emission_and_illumination_map.
			id emissionSpec = [spec objectForKey:kOOMaterialEmissionMapName];
			id illuminationSpec = [spec objectForKey:kOOMaterialIlluminationMapName];
			
			if (emissionSpec == nil && illuminationSpec == nil)
			{
				emissionSpec = [spec objectForKey:kOOMaterialEmissionAndIlluminationMapName];
				if ([emissionSpec isKindOfClass:[NSString class]])
				{
					// Redundantish check required because we want to modify this as a dictionary to make illuminationSpec.
					emissionSpec = [NSDictionary dictionaryWithObject:emissionSpec forKey:kOOTextureSpecifierNameKey];
				}
				else if (![emissionSpec isKindOfClass:[NSDictionary class]])
				{
					emissionSpec = nil;
				}
				
				if (emissionSpec != nil)
				{
					illuminationSpec = [emissionSpec dictionaryByAddingObject:@"a" forKey:kOOTextureSpecifierSwizzleKey];
				}
			}
			
			if (emissionSpec != nil)
			{
				if ([emissionSpec isKindOfClass:[NSString class]])
				{
					emissionSpec = [NSDictionary dictionaryWithObject:emissionSpec forKey:kOOTextureSpecifierNameKey];
				}
				if ([emissionSpec isKindOfClass:[NSDictionary class]])
				{
					col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialEmissionModulateColorName]];
					if (col != nil)  emissionSpec = [emissionSpec dictionaryByAddingObject:[col normalizedArray] forKey:kOOTextureSpecifierModulateColorKey];
					
					[lightMaps addObject:emissionSpec];
				}
			}
			
			if (illuminationSpec != nil)
			{
				if ([illuminationSpec isKindOfClass:[NSString class]])
				{
					illuminationSpec = [NSDictionary dictionaryWithObject:illuminationSpec forKey:kOOTextureSpecifierNameKey];
				}
				if ([illuminationSpec isKindOfClass:[NSDictionary class]])
				{
					col = [OOColor colorWithDescription:[spec objectForKey:kOOMaterialIlluminationModulateColorName]];
					if (col != nil)  illuminationSpec = [illuminationSpec dictionaryByAddingObject:[col normalizedArray] forKey:kOOTextureSpecifierModulateColorKey];
					
					illuminationSpec = [illuminationSpec dictionaryByAddingObject:[NSNumber numberWithBool:YES] forKey:kOOTextureSpecifierIlluminationModeKey];
					
					[lightMaps addObject:illuminationSpec];
				}
			}
		}
		
		[result setObject:lightMaps forKey:kOOMaterialLightMapsName];
	}
	
	OOLog(@"material.canonicalForm", @"Canonicalized material %@:\nORIGINAL:\n%@\n\n@CANONICAL:\n%@", materialKey, spec, result);
	
	return result;
}


static NSString *FormatFloat(double value)
{
	long long intValue = value;
	if (value == intValue)
	{
		return [NSString stringWithFormat:@"%lli.0", intValue];
	}
	else
	{
		return [NSString stringWithFormat:@"%g", value];
	}
}
