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
#include "oofnd/objc/OORuntime.h"

#if OO_SHADERS

#import "OODebugFlags.h"
#import "OOFoundationBridge.h"
#import "OOFunctionAttributes.h"
#import "OOIsNumberLiteral.h"
#import "OOLogging.h"
#import "OOMacroOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OOPListView.h"
#import "OOShaderProgram.h"
#import "OOShaderUniform.h"
#import "OOStringBridge.h"
#import "OOStringParsing.h"
#import "OOTexture.h"
#import "ResourceManager.h"
#import "Universe.h"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

namespace {

// -[NSDictionary oo_stringForKey:] as the old code read it: a string, or a number's -stringValue;
// nullopt (nil) for anything else or a missing key.
std::optional<std::string> StringForKey(const oo::PList& dictionary, std::string_view key)
{
    const oo::PList* entry = dictionary.find(key);
    if (entry == nullptr || !(entry->isString() || entry->isNumber()))
        return std::nullopt;
    return dictionary.get<std::string>(key);
}

} // namespace

NSString* const kOOVertexShaderSourceKey = @"_oo_vertex_shader_source";
NSString* const kOOVertexShaderNameKey = @"vertex_shader";
NSString* const kOOFragmentShaderSourceKey = @"_oo_fragment_shader_source";
NSString* const kOOFragmentShaderNameKey = @"fragment_shader";
NSString* const kOOTexturesKey = @"textures";
NSString* const kOOTextureObjectsKey = @"_oo_texture_objects";
NSString* const kOOUniformsKey = @"uniforms";
NSString* const kOOIsSynthesizedMaterialConfigurationKey = @"_oo_is_synthesized_config";
NSString* const kOOIsSynthesizedMaterialMacrosKey = @"_oo_synthesized_material_macros";

static BOOL GetShaderSource(NSString* fileName, NSString* shaderType, NSString* prefix, NSString** outResult);
static NSString* MacrosToString(NSDictionary* macros);

@interface OOShaderMaterial (OOPrivate)

// Convert a "textures" array to an "_oo_texture_objects" array.
- (NSArray*)loadTexturesFromArray:(NSArray*)textureSpecs unitCount:(GLuint)max;

// Load up an array of texture objects.
- (void)addTexturesFromArray:(NSArray*)textureObjects unitCount:(GLuint)max;

@end

@implementation OOShaderMaterial

+ (BOOL)configurationDictionarySpecifiesShaderMaterial:(NSDictionary*)configuration
{
    if (configuration == nil)
        return NO;

    if (oo::PListView(configuration).get<NSString*>(kOOVertexShaderSourceKey) != nil)
        return YES;
    if (oo::PListView(configuration).get<NSString*>(kOOFragmentShaderSourceKey) != nil)
        return YES;
    if (oo::PListView(configuration).get<NSString*>(kOOVertexShaderNameKey) != nil)
        return YES;
    if (oo::PListView(configuration).get<NSString*>(kOOVertexShaderNameKey) != nil)
        return YES;

    return NO;
}

+ (instancetype)shaderMaterialWithName:(NSString*)name
                         configuration:(NSDictionary*)configuration
                                macros:(NSDictionary*)macros
                         bindingTarget:(id<OOWeakReferenceSupport>)target
{
    return [[[self alloc] initWithName:name configuration:configuration macros:macros bindingTarget:target] autorelease];
}

- (id)initWithName:(NSString*)name
     configuration:(NSDictionary*)configuration
            macros:(NSDictionary*)macros
     bindingTarget:(id<OOWeakReferenceSupport>)target
{
    BOOL OK = YES;
    NSString* macroString = nil;
    NSString* vertexShader = nil;
    NSString* fragmentShader = nil;
    GLint textureUnits = [[OOOpenGLExtensionManager sharedManager] textureImageUnitCount];
    NSMutableDictionary* modifiedMacros = nil;
    NSString* vsName = @"<synthesized>";
    NSString* fsName = @"<synthesized>";
    NSString* vsCacheKey = nil;
    NSString* fsCacheKey = nil;

    if (configuration == nil)
        OK = NO;

    self = [super initWithName:name configuration:configuration];
    if (self == nil)
        OK = NO;

    if (OK) {
        modifiedMacros = macros ? [macros mutableCopy] : [[NSMutableDictionary alloc] init];
        [modifiedMacros autorelease];

        [modifiedMacros setObject:[NSNumber numberWithUnsignedInt:textureUnits]
                           forKey:@"OO_TEXTURE_UNIT_COUNT"];

        // used to test for simplified shaders - OO_REDUCED_COMPLEXITY - here
        macroString = MacrosToString(modifiedMacros);
    }

    if (OK) {
        vertexShader = oo::PListView(configuration).get<NSString*>(kOOVertexShaderSourceKey);
        if (vertexShader == nil) {
            vsName = oo::PListView(configuration).get<NSString*>(kOOVertexShaderNameKey);
            vsCacheKey = vsName;
            if (vsName != nil) {
                if (!GetShaderSource(vsName, @"vertex", macroString, &vertexShader))
                    OK = NO;
            }
        } else {
            vsCacheKey = vertexShader;
        }
    }

    if (OK) {
        fragmentShader = oo::PListView(configuration).get<NSString*>(kOOFragmentShaderSourceKey);
        if (fragmentShader == nil) {
            fsName = oo::PListView(configuration).get<NSString*>(kOOFragmentShaderNameKey);
            fsCacheKey = fsName;
            if (fsName != nil) {
                if (!GetShaderSource(fsName, @"fragment", macroString, &fragmentShader))
                    OK = NO;
            }
        } else {
            fsCacheKey = fragmentShader;
        }
    }

    if (OK) {
        if (vertexShader != nil || fragmentShader != nil) {
            static NSDictionary* attributeBindings = nil;
            if (attributeBindings == nil) {
                attributeBindings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kTangentAttributeIndex]
                                                                forKey:@"tangent"];
                [attributeBindings retain];
            }

            NSString* cacheKey = [NSString stringWithFormat:@"$VERTEX:\n%@\n\n$FRAGMENT:\n%@\n\n$MACROS:\n%@\n", vsCacheKey, fsCacheKey, macroString];

            OOLogIndent();
            shaderProgram = [OOShaderProgram shaderProgramWithVertexShader:oo::OptionalString(vertexShader)
                                                            fragmentShader:oo::OptionalString(fragmentShader)
                                                          vertexShaderName:oo::OptionalString(vsName)
                                                        fragmentShaderName:oo::OptionalString(fsName)
                                                                    prefix:oo::OptionalString(macroString)
                                                         attributeBindings:oo::PListFrom(attributeBindings)
                                                                  cacheKey:oo::OptionalString(cacheKey)];
            OOLogOutdent();

// no reduced complexity mode now
#if 0
			if (shaderProgram == nil)
			{

				BOOL canFallBack = !oo::PListView(modifiedMacros).get<bool>(@"OO_REDUCED_COMPLEXITY");
#ifdef OO_DEBUG_MONITOR_ENABLED
				if (gDebugFlags & DEBUG_NO_SHADER_FALLBACK)  canFallBack = NO;
#endif
				if (canFallBack)
				{
					OOLogWARN(@"shader.load.fullModeFailed", @"Could not build shader %@/%@ in full complexity mode, trying simple mode.", vsName, fsName);
					
					[modifiedMacros setObject:[NSNumber numberWithInt:1] forKey:@"OO_REDUCED_COMPLEXITY"];
					macroString = MacrosToString(modifiedMacros);
					cacheKey = [cacheKey stringByAppendingString:@"\n$SIMPLIFIED FALLBACK\n"];
					
					OOLogIndent();
					shaderProgram = [OOShaderProgram shaderProgramWithVertexShader:oo::OptionalString(vertexShader)
																	fragmentShader:oo::OptionalString(fragmentShader)
																  vertexShaderName:oo::OptionalString(vsName)
																fragmentShaderName:oo::OptionalString(fsName)
																			prefix:oo::OptionalString(macroString)
																 attributeBindings:oo::PListFrom(attributeBindings)
																		  cacheKey:oo::OptionalString(cacheKey)];
					OOLogOutdent();
					
					if (shaderProgram != nil)
					{
						OOLog(@"shader.load.fallbackSuccess", @"Simple mode fallback successful.");
					}
				}
			}
#endif

            if (shaderProgram == nil) {
                OOLogERR(@"shader.load.failed", @"Could not build shader %@/%@.", vsName, fsName);
            }
        } else {
            OOLog(@"shader.load.noShader", @"***** Error: no vertex or fragment shader specified in shader dictionary:\n%@", configuration);
        }

        OK = (shaderProgram != nil);
        if (OK)
            [shaderProgram retain];
    }

    if (OK) {
        // Load uniforms and textures, which are a flavour of uniform for our purpose.
        NSDictionary* uniformDefs = oo::PListView(configuration).get<NSDictionary*>(kOOUniformsKey); // until chunk 4

        NSArray* textureArray = oo::PListView(configuration).get<NSArray*>(kOOTextureObjectsKey);
        if (textureArray == nil) {
            NSArray* textureSpecs = oo::PListView(configuration).get<NSArray*>(kOOTexturesKey);
            if (textureSpecs != nil) {
                textureArray = [self loadTexturesFromArray:textureSpecs unitCount:textureUnits];
            }
        }

        [self addUniformsFromDictionary:oo::PListFrom(uniformDefs) withBindingTarget:target];
        [self addTexturesFromArray:textureArray unitCount:textureUnits];
    }

    if (OK) {
        // write gloss and gamma correction preference to the uniforms dictionary

        if (uniforms.find("uGloss") == uniforms.end()) {
            float gloss = OOClamp_0_1_f(oo::PListView(configuration).get<float>(@"gloss", 0.5f));
            [self setUniform:"uGloss" floatValue:gloss];
        }

        if (![uniforms objectForKey:@"uGammaCorrect"]) {
            BOOL gammaCorrect = oo::PListView(configuration).get<bool>(@"gamma_correct", ![[NSUserDefaults standardUserDefaults] boolForKey:@"no-gamma-correct"]);
            [self setUniform:@"uGammaCorrect" floatValue:(float)gammaCorrect];
        }
    }

    if (!OK) {
        [self release];
        self = nil;
    }
    return self;
}

- (void)dealloc
{
    uint32_t i;

    [self willDealloc];

    [shaderProgram release];

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            [textures[i] release];
        }
        free(textures);
    }

    [bindingTarget release];

    [super dealloc];
}

- (BOOL)bindUniform:(const std::string&)uniformName
           toObject:(id<OOWeakReferenceSupport>)source
           property:(SEL)selector
     convertOptions:(OOUniformConvertOptions)options
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                      boundToObject:source
                                           property:selector
                                     convertOptions:options];
    if (uniform != nil) {
        OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
        return YES;
    } else {
        OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", oo::NSStringFrom(uniformName));
        uniforms.erase(uniformName);
        return NO;
    }
}

- (BOOL)bindSafeUniform:(const std::string&)uniformName
               toObject:(id<OOWeakReferenceSupport>)target
          propertyNamed:(const std::optional<std::string>&)property
         convertOptions:(OOUniformConvertOptions)options
{
    SEL selector = NULL;

    selector = OOSelectorFromName(property.has_value() ? property->c_str() : nullptr);

    if (selector != NULL && OOUniformBindingPermitted(*property, target)) {
        return [self bindUniform:uniformName
                        toObject:target
                        property:selector
                  convertOptions:options];
    } else {
        OOLog(@"shader.uniform.unpermittedMethod", @"Did not bind uniform \"%@\" to property -[%@ %@] - unpermitted method.", oo::NSStringFrom(uniformName), [target class], oo::NSStringOrNil(property));
    }

    return NO;
}

- (void)setUniform:(const std::string&)uniformName intValue:(int)value
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                           intValue:value];
    if (uniform != nil) {
        OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", oo::NSStringFrom(uniformName));
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName floatValue:(float)value
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                         floatValue:value];
    if (uniform != nil) {
        OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", oo::NSStringFrom(uniformName));
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName vectorValue:(GLfloat[4])value
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                        vectorValue:value];
    if (uniform != nil) {
        OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", oo::NSStringFrom(uniformName));
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName vectorObjectValue:(const oo::PList&)value
{
    GLfloat vecArray[4];
    if (value.isArray() && value.count() == 4) {
        for (unsigned i = 0; i < 4; i++) {
            vecArray[i] = value.at<float>(i, 0.0f); // OOFloatFromObject's conversion
        }
    } else {
        Vector vec = OOVectorFromObject(oo::ObjectFromPList(value), kZeroVector);
        vecArray[0] = vec.x;
        vecArray[1] = vec.y;
        vecArray[2] = vec.z;
        vecArray[3] = 1.0;
    }

    OOShaderUniform* uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                                       shaderProgram:shaderProgram
                                                         vectorValue:vecArray];
    if (uniform != nil) {
        OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", oo::NSStringFrom(uniformName));
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName quaternionValue:(Quaternion)value asMatrix:(BOOL)asMatrix
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                    quaternionValue:value
                                           asMatrix:asMatrix];
    if (uniform != nil) {
        OOLog(@"shader.uniform.set", @"Set up uniform %@", uniform);
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OOLog(@"shader.uniform.unSet", @"Did not set uniform \"%@\"", oo::NSStringFrom(uniformName));
        uniforms.erase(uniformName);
    }
}

- (void)addUniformsFromDictionary:(const oo::PList&)uniformDefs withBindingTarget:(id<OOWeakReferenceSupport>)target
{
    oo::PList value;
    std::optional<std::string> binding;
    std::optional<std::string> type;
    GLfloat floatValue;
    BOOL gotValue;
    OOUniformConvertOptions convertOptions;
    BOOL quatAsMatrix = YES;
    GLfloat scale = 1.0;
    uint32_t randomSeed;
    RANROTSeed savedSeed;

    if ([target respondsToSelector:@selector(randomSeedForShaders)]) {
        randomSeed = [(id)target randomSeedForShaders];
    } else {
        randomSeed = (uint32_t)(uintptr_t)self;
    }
    savedSeed = RANROTGetFullSeed();
    ranrot_srand(randomSeed);

    // The std::map's byte order is the old -compare:-sorted key order (literal UTF-16 order, the
    // same as UTF-8 byte order).
    const oo::PList::Dict* definitions = uniformDefs.getIf<oo::PList::Dict>();
    for (const auto& [name, definition] : (definitions != nullptr) ? *definitions : oo::PList::Dict()) {
        gotValue = NO;

        type.reset();
        value = oo::PList();
        binding.reset();

        if (definition.isDict()) {
            const oo::PList* valueEntry = definition.find("value");
            if (valueEntry != nullptr)
                value = *valueEntry;
            binding = StringForKey(definition, "binding");
            type = StringForKey(definition, "type");
            scale = definition.get<float>("scale", 1.0);
            if (!type.has_value()) {
                if (!value && binding.has_value())
                    type = "binding";
                else
                    type = "float";
            }
        } else if (definition.isNumber()) {
            value = definition;
            type = "float";
        } else if (const std::string* string = definition.getIf<std::string>()) {
            if (OOIsNumberLiteral(*string, NO)) {
                value = definition;
                type = "float";
            } else {
                binding = *string;
                type = "binding";
            }
        } else if (definition.isArray()) {
            // (The old code kept the array as the binding; only a "binding" type reads it.)
            type = "vector";
        }

        // Transform random values to concrete values
        if (type == "randomFloat") {
            type = "float";
            value = oo::PList::singleReal(randf() * scale);
        } else if (type == "randomUnitVector") {
            type = "vector";
            value = oo::PListFrom(OOPropertyListFromVector(vector_multiply_scalar(OORandomUnitVector(), scale)));
        } else if (type == "randomVectorSpatial") {
            type = "vector";
            value = oo::PListFrom(OOPropertyListFromVector(OOVectorRandomSpatial(scale)));
        } else if (type == "randomVectorRadial") {
            type = "vector";
            value = oo::PListFrom(OOPropertyListFromVector(OOVectorRandomRadial(scale)));
        } else if (type == "randomQuaternion") {
            type = "quaternion";
            value = oo::PListFrom(OOPropertyListFromQuaternion(OORandomQuaternion()));
        }

        if (type == "float" || type == "real") {
            // -floatValue: only a number or a string answers it.
            gotValue = YES;
            if (value.isNumber())
                floatValue = oo::plist_get::numberFloatValue(value);
            else if (const std::string* string = value.getIf<std::string>())
                floatValue = (float)oo::str::doubleValue(*string);
            else
                gotValue = NO;

            if (gotValue) {
                [self setUniform:name floatValue:floatValue];
            }
        } else if (type == "int" || type == "integer" || type == "texture") {
            /*	"texture" is allowed as a synonym for "int" because shader
                    uniforms are mapped to texture units by specifying an integer
                    index.
                    uniforms = { diffuseMap = { type = texture; value = 0; }; };
                    means "bind uniform diffuseMap to texture unit 0" (which will
                    have the first texture in the textures array).
            */
            // -intValue: only a number or a string answers it.
            if (value.isNumber()) {
                [self setUniform:name intValue:(int)value.int64Value()];
                gotValue = YES;
            } else if (const std::string* string = value.getIf<std::string>()) {
                [self setUniform:name intValue:oo::str::intValue(*string)];
                gotValue = YES;
            }
        } else if (type == "vector") {
            [self setUniform:name vectorObjectValue:value];
            gotValue = YES;
        } else if ([type isEqualToString:@"quaternion"]) {
            if ([definition isKindOfClass:[NSDictionary class]]) {
                quatAsMatrix = oo::PListView(definition).get<bool>(@"asMatrix", quatAsMatrix);
            }
            [self setUniform:name
                quaternionValue:OOQuaternionFromObject(oo::ObjectFromPList(value), kIdentityQuaternion)
                       asMatrix:quatAsMatrix];
            gotValue = YES;
        } else if (target != nil && type == "binding") {
            if (definition.isDict()) {
                convertOptions = 0;
                if (oo::PListView(definition).get<bool>(@"clamped", NO))
                    convertOptions |= kOOUniformConvertClamp;
                if (oo::PListView(definition).get<bool>(@"normalized", oo::PListView(definition).get<bool>(@"normalised", NO))) {
                    convertOptions |= kOOUniformConvertNormalize;
                }
                if (oo::PListView(definition).get<bool>(@"asMatrix", YES))
                    convertOptions |= kOOUniformConvertToMatrix;
                if (!oo::PListView(definition).get<bool>(@"bindToSubentity", NO))
                    convertOptions |= kOOUniformBindToSuperTarget;
            } else {
                convertOptions = kOOUniformConvertDefaults;
            }

            [self bindSafeUniform:name toObject:target propertyNamed:binding convertOptions:convertOptions];
            gotValue = YES;
        }

        if (!gotValue) {
            OOLog(@"shader.uniform.badDescription", @"----- Warning: could not bind uniform \"%@\" for target %@ -- could not interpret definition:\n%@", oo::NSStringFrom(name), target, oo::ObjectFromPList(definition));
        }
    }

    RANROTSetFullSeed(savedSeed);
}

- (BOOL)doApply
{
    uint32_t i;

    OO_ENTER_OPENGL();

    [super doApply];
    [shaderProgram apply];

    for (i = 0; i != texCount; ++i) {
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
        [textures[i] apply];
    }
    if (texCount > 1)
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));

    @try {
        for (const auto& [name, uniform] : uniforms) {
            [uniform.get() apply];
        }
    }
    @catch (id exception) {
    }

    return YES;
}

- (void)ensureFinishedLoading
{
    uint32_t i;

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            [textures[i] ensureFinishedLoading];
        }
    }
}

- (BOOL)isFinishedLoading
{
    uint32_t i;

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            if (![textures[i] isFinishedLoading])
                return NO;
        }
    }

    return YES;
}

- (void)unapplyWithNext:(OOMaterial*)next
{
    uint32_t i, count;

    if (![next isKindOfClass:[OOShaderMaterial class]]) // Avoid redundant state change
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
        for (i = 0; i != count; ++i) {
            OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
            [OOTexture applyNone];
        }
        if (count != 1)
            OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
    }
}

- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
    for (const auto& [name, uniform] : uniforms) {
        [uniform.get() setBindingTarget:target];
    }
    [bindingTarget release];
    bindingTarget = [target weakRetain];
}

- (BOOL)permitSpecular
{
    return YES;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (NSSet*)allTextures
{
    return [NSSet setWithObjects:textures count:texCount];
}
#endif

@end

@implementation OOShaderMaterial (OOPrivate)

- (NSArray*)loadTexturesFromArray:(NSArray*)textureSpecs unitCount:(GLuint)max
{
    GLuint i, count = (GLuint)MIN([textureSpecs count], (NSUInteger)max);
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:count];

    for (i = 0; i < count; i++) {
        id textureSpec = [textureSpecs objectAtIndex:i];
        OOTexture* texture = [OOTexture textureWithConfiguration:textureSpec];
        if (texture == nil)
            texture = [OOTexture nullTexture];
        [result addObject:texture];
    }

    return result;
}

- (void)addTexturesFromArray:(NSArray*)textureObjects unitCount:(GLuint)max
{
    // Allocate space for texture object name array
    texCount = (uint32_t)MIN([textureObjects count], (NSUInteger)max);
    if (texCount == 0)
        return;

    textures = (OOTexture**)malloc(texCount * sizeof *textures);
    if (textures == NULL) {
        texCount = 0;
        return;
    }

    // Set up texture object names and appropriate uniforms
    unsigned i;
    for (i = 0; i != texCount; ++i) {
        textures[i] = [textureObjects objectAtIndex:i];
        [textures[i] retain];
    }
}

@end

static NSString* MacrosToString(NSDictionary* macros)
{
    NSMutableString* result = nil;
    id key = nil, value = nil;

    if (macros == nil)
        return nil;

    result = [NSMutableString string];
    foreachkey(key, macros)
    {
        if (![key isKindOfClass:[NSString class]])
            continue;
        value = [macros objectForKey:key];

        [result appendFormat:@"#define %@  %@\n", key, value];
    }

    if ([result length] == 0)
        return nil;
    [result appendString:@"\n\n"];
    return result;
}

#endif

/*	Attempt to load fragment or vertex shader source from a file.
        Returns YES if source was loaded or no shader was specified, and NO if an
        external shader was specified but could not be found.
*/
static BOOL GetShaderSource(NSString* fileName, NSString* shaderType, NSString* prefix, NSString** outResult)
{
    NSString* result = nil;
    NSArray* extensions = nil;
    NSString* extension = nil;
    NSString* nameWithExtension = nil;

    if (fileName == nil)
        return YES; // It's OK for one or the other of the shaders to be undefined.

    result = [ResourceManager stringFromFilesNamed:fileName inFolder:@"Shaders"];
    if (result == nil) {
        extensions = [NSArray arrayWithObjects:shaderType, [shaderType substringToIndex:4], nil]; // vertex and vert, or fragment and frag

        // Futureproofing -- in future, we may wish to support automatic selection between supported shader languages.
        if (![fileName pathHasExtensionInArray:extensions]) {
            foreach (extension, extensions) {
                nameWithExtension = [fileName stringByAppendingPathExtension:extension];
                result = [ResourceManager stringFromFilesNamed:nameWithExtension
                                                      inFolder:@"Shaders"];
                if (result != nil)
                    break;
            }
        }
        if (result == nil) {
            OOLog(kOOLogFileNotFound, @"GLSL ERROR: failed to find %@ program %@.", shaderType, fileName);
            return NO;
        }
    }

    if (outResult != NULL)
        *outResult = result;
    return YES;
}
