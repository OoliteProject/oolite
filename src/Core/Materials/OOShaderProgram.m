/*

OOShaderProgram.m


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

#import "OOGLStateCompat.h"
#import "OOOpenGLExtensionManager.h"

#if OO_SHADERS

#import "MyOpenGLView.h"
#import "OOCollectionExtractors.h"
#import "OODebugFlags.h"
#import "OOFunctionAttributes.h"
#import "OOMacroOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OORendererProgram.h"
#import "OOShaderProgram.h"
#import "OOStringParsing.h"
#import "ResourceManager.h"
#import "Universe.h"

static NSMutableDictionary* sShaderCache = nil;
static OOShaderProgram* sActiveProgram = nil;

static BOOL GetShaderSource(NSString* fileName, NSString* shaderType, NSString* prefix, NSString** outResult);
#if OOLITE_MAC_OS_X || OO_RENDERER_SDL_GPU
static NSString* TranslateGLSL330To120(NSString* source, BOOL isVertexShader, NSMutableDictionary* attributeBindings);
#endif

@interface OOShaderProgram (OOPrivate)

- (id)initWithVertexShaderSource:(NSString*)vertexSource
            fragmentShaderSource:(NSString*)fragmentSource
                    prefixString:(NSString*)prefixString
                      vertexName:(NSString*)vertexName
                    fragmentName:(NSString*)fragmentName
               attributeBindings:(NSDictionary*)attributeBindings
                             key:(NSString*)key;

- (void)bindStandardMatrixUniforms;

@end

@implementation OOShaderProgram

+ (id)shaderProgramWithVertexShader:(NSString*)vertexShaderSource
                     fragmentShader:(NSString*)fragmentShaderSource
                   vertexShaderName:(NSString*)vertexShaderName
                 fragmentShaderName:(NSString*)fragmentShaderName
                             prefix:(NSString*)prefixString // String prepended to program source (both vs and fs)
                  attributeBindings:(NSDictionary*)attributeBindings // Maps vertex attribute names to "locations".
                           cacheKey:(NSString*)cacheKey
{
    OOShaderProgram* result = nil;

    if ([prefixString length] == 0)
        prefixString = nil;

    // Use cache to avoid creating duplicate shader programs -- saves on GPU resources and potentially state changes.
    // FIXME: probably needs to respond to graphics resets.
    result = [[sShaderCache objectForKey:cacheKey] pointerValue];

    if (result == nil) {
        // No cached program; create one...
        result = [[OOShaderProgram alloc] initWithVertexShaderSource:vertexShaderSource
                                                fragmentShaderSource:fragmentShaderSource
                                                        prefixString:prefixString
                                                          vertexName:vertexShaderName
                                                        fragmentName:fragmentShaderName
                                                   attributeBindings:attributeBindings
                                                                 key:cacheKey];
        [result autorelease];

        if (result != nil && cacheKey != nil) {
            // ...and add it to the cache.
            if (sShaderCache == nil)
                sShaderCache = [[NSMutableDictionary alloc] init];
            [sShaderCache setObject:[NSValue valueWithPointer:result] forKey:cacheKey]; // Use NSValue so dictionary doesn't retain program
        }
    }

    return result;
}

+ (id)shaderProgramWithVertexShaderName:(NSString*)vertexShaderName
                     fragmentShaderName:(NSString*)fragmentShaderName
                                 prefix:(NSString*)prefixString
                      attributeBindings:(NSDictionary*)attributeBindings
{
    NSString* cacheKey = nil;
    OOShaderProgram* result = nil;
    NSString* vertexSource = nil;
    NSString* fragmentSource = nil;

    if ([prefixString length] == 0)
        prefixString = nil;

    // Use cache to avoid creating duplicate shader programs -- saves on GPU resources and potentially state changes.
    // FIXME: probably needs to respond to graphics resets.
    cacheKey = [NSString stringWithFormat:@"vertex:%@\nfragment:%@\n----\n%@", vertexShaderName, fragmentShaderName, prefixString ?: (NSString*)@""];
    result = [[sShaderCache objectForKey:cacheKey] pointerValue];

    if (result == nil) {
        // No cached program; create one...
        if (!GetShaderSource(vertexShaderName, @"vertex", prefixString, &vertexSource))
            return nil;
        if (!GetShaderSource(fragmentShaderName, @"fragment", prefixString, &fragmentSource))
            return nil;
#if OOLITE_MAC_OS_X || OO_RENDERER_SDL_GPU
        /*	The macOS legacy OpenGL context only supports GLSL 1.20, so shaders
                written for #version 330 are translated when loaded. SDL_GPU
                builds do the same everywhere, so the GLSL translator always sees
                legacy GLSL with attribute bindings.
        */
        if ([prefixString hasPrefix:@"#version 330"]) {
            NSMutableDictionary* bindings = [NSMutableDictionary dictionaryWithDictionary:attributeBindings ?: [NSDictionary dictionary]];
            vertexSource = TranslateGLSL330To120(vertexSource, YES, bindings);
            fragmentSource = TranslateGLSL330To120(fragmentSource, NO, bindings);
            attributeBindings = bindings;
            prefixString = [@"#version 120\n#extension GL_EXT_gpu_shader4 : enable\n" stringByAppendingString:[prefixString substringFromIndex:[@"#version 330" length]]];
        }
#endif
        result = [[OOShaderProgram alloc] initWithVertexShaderSource:vertexSource
                                                fragmentShaderSource:fragmentSource
                                                        prefixString:prefixString
                                                          vertexName:vertexShaderName
                                                        fragmentName:fragmentShaderName
                                                   attributeBindings:attributeBindings
                                                                 key:cacheKey];

        if (result != nil) {
            // ...and add it to the cache.
            [result autorelease];
            if (sShaderCache == nil)
                sShaderCache = [[NSMutableDictionary alloc] init];
            [sShaderCache setObject:[NSValue valueWithPointer:result] forKey:cacheKey]; // Use NSValue so dictionary doesn't retain program
        }
    }

    return result;
}

- (void)dealloc
{
    OO_ENTER_OPENGL();

#ifndef NDEBUG
    if (EXPECT_NOT(sActiveProgram == self)) {
        OOLog(@"shader.dealloc.imbalance", @"%@", @"***** OOShaderProgram deallocated while active, indicating a retain/release imbalance. Expect imminent crash.");
        [OOShaderProgram applyNone];
    }
#endif

    if (key != nil) {
        [sShaderCache removeObjectForKey:key];
        [key release];
    }

    if (standardMatrixUniformLocations != nil) {
        [standardMatrixUniformLocations release];
    }

    OORendererReleaseProgram(program);

    [super dealloc];
}

- (void)apply
{
    OO_ENTER_OPENGL();

    if (sActiveProgram != self) {
        [sActiveProgram release];
        sActiveProgram = [self retain];
        OORendererUseProgram(program);
        [self bindStandardMatrixUniforms];
    }
}

+ (void)applyNone
{
    OO_ENTER_OPENGL();

    if (sActiveProgram != nil) {
        [sActiveProgram release];
        sActiveProgram = nil;
        OORendererUseProgram(NULL);
    }
}

- (struct OORendererProgram*)rendererProgram
{
    return program;
}

- (OOUniformHandle)uniformHandleForName:(NSString*)name
{
    return OORendererProgramUniform(program, [name UTF8String]);
}

- (void)setUniform:(OOUniformHandle)handle intValue:(GLint)value
{
    int32_t v = value;
    OORendererSetUniform(handle, kOOUniformInt, &v);
}

- (void)setUniform:(OOUniformHandle)handle floatValue:(GLfloat)value
{
    OORendererSetUniform(handle, kOOUniformFloat, &value);
}

- (void)setUniform:(OOUniformHandle)handle vec2Value:(const GLfloat*)value
{
    OORendererSetUniform(handle, kOOUniformVec2, value);
}

- (void)setUniform:(OOUniformHandle)handle vec4Value:(const GLfloat*)value
{
    OORendererSetUniform(handle, kOOUniformVec4, value);
}

- (void)setUniform:(OOUniformHandle)handle matrixValue:(OOMatrix)value
{
    OORendererSetUniform(handle, kOOUniformMat4, OOMatrixValuesForOpenGL(value));
}

- (void)setUniform:(OOUniformHandle)handle mat3Value:(OOMatrix)value
{
    // The upper left 3x3, column by column, as GLUniformMatrix3 did.
    float m[9] = {
        value.m[0][0], value.m[0][1], value.m[0][2],
        value.m[1][0], value.m[1][1], value.m[1][2],
        value.m[2][0], value.m[2][1], value.m[2][2]
    };
    OORendererSetUniform(handle, kOOUniformMat3, m);
}

@end

// Log a failed compile or link as OOShaderProgram always has.
static void LogProgramError(const OOProgramError* error, NSString* vertexName, NSString* fragmentName)
{
    NSString* subtypeString = @"shader program";
    NSString* actionString = @"linking";
    NSString* name = [NSString stringWithFormat:@"%@/%@", vertexName, fragmentName];
    BOOL linking = error->stage == kOOProgramStageLink;
    if (!linking) {
        subtypeString = error->stage == kOOProgramStageVertex ? @"vertex shader" : @"fragment shader";
        actionString = @"compilation";
        name = error->stage == kOOProgramStageVertex ? vertexName : fragmentName;
    }
    NSString* msgClass = [NSString stringWithFormat:@"shader.%@.failure", linking ? @"link" : @"compile"];
    NSString* log = error->log != NULL ? [NSString stringWithUTF8String:error->log] : @"";
    OOLogERR(msgClass, @"GLSL %@ %@ failed for %@:\n>>>>> GLSL log:\n%@\n", subtypeString, actionString, name, log);
}

@implementation OOShaderProgram (OOPrivate)

- (id)initWithVertexShaderSource:(NSString*)vertexSource
            fragmentShaderSource:(NSString*)fragmentSource
                    prefixString:(NSString*)prefixString
                      vertexName:(NSString*)vertexName
                    fragmentName:(NSString*)fragmentName
               attributeBindings:(NSDictionary*)attributeBindings
                             key:(NSString*)inKey
{
    BOOL OK = YES;

    OO_ENTER_OPENGL();

    self = [super init];
    if (self == nil)
        OK = NO;

    if (OK && vertexSource == nil && fragmentSource == nil)
        OK = NO; // Must have at least one shader!

    if (OK) {
        NSUInteger bindingCount = [attributeBindings count];
        OOAttributeBinding* bindings = bindingCount > 0 ? malloc(bindingCount * sizeof *bindings) : NULL;
        NSUInteger i = 0;
        NSString* attrKey = nil;
        foreachkey(attrKey, attributeBindings)
        {
            bindings[i++] = (OOAttributeBinding) { [attrKey UTF8String], [attributeBindings oo_unsignedIntForKey:attrKey] };
        }
        OOProgramError error = { kOOProgramStageLink, NULL };
        program = OORendererCreateProgram([vertexSource UTF8String], [fragmentSource UTF8String], [prefixString UTF8String],
            bindings, bindingCount, &error);
        free(bindings);
        if (program == NULL) {
            LogProgramError(&error, vertexName, fragmentName);
            OK = NO;
        }
        free(error.log);
    }

    if (OK) {
        key = [inKey copy];
    }

    if (OK) {
        OOOpenGLMatrixManager* matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
        standardMatrixUniformLocations = [matrixManager standardMatrixUniformLocations:program];
    } else {
        [self release];
        self = nil;
    }
    return self;
}

- (void)bindStandardMatrixUniforms
{
    if (standardMatrixUniformLocations != nil) {
        OOOpenGLMatrixManager* matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
        id obj;
        NSArray* pair;

        OO_ENTER_OPENGL();

        [matrixManager syncModelView];
        foreach (obj, standardMatrixUniformLocations) {
            if ([obj isKindOfClass:[NSArray class]]) {
                pair = (NSArray*)obj;
                if ([[pair oo_stringAtIndex:2] compare:@"mat3"] == 0) {
                    [self setUniform:[pair oo_intAtIndex:0] mat3Value:[matrixManager getMatrix:[pair oo_intAtIndex:1]]];
                } else {
                    [self setUniform:[pair oo_intAtIndex:0] matrixValue:[matrixManager getMatrix:[pair oo_intAtIndex:1]]];
                }
            }
        }
    }
    return;
}

@end

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
            OOLog(kOOLogFileNotFound, @"GLSL ERROR: failed to find fragment program %@.", fileName);
            return NO;
        }
    }
    /*
    if (result != nil && prefix != nil)
    {
            result = [prefix stringByAppendingString:result];
    }
    */
    if (outResult != NULL)
        *outResult = result;
    return YES;
}

#endif // OO_SHADERS

#if OOLITE_MAC_OS_X || OO_RENDERER_SDL_GPU
static NSString* ReplaceRegex(NSString* source, NSString* pattern, NSString* replacement)
{
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionAnchorsMatchLines error:NULL];
    return [regex stringByReplacingMatchesInString:source options:0 range:NSMakeRange(0, [source length]) withTemplate:replacement];
}

/*	Translate the subset of GLSL 3.30 used by Oolite's post-processing shaders
        to GLSL 1.20 (plus GL_EXT_gpu_shader4). Only top-level declarations are
        rewritten, so in/out parameter qualifiers inside functions are untouched.
*/
static NSString* TranslateGLSL330To120(NSString* source, BOOL isVertexShader, NSMutableDictionary* attributeBindings)
{
    if (source == nil)
        return nil;

    NSRegularExpression* regex = nil;
    NSArray* matches = nil;
    NSTextCheckingResult* match = nil;

    if (isVertexShader) {
        // layout(location = N) in TYPE NAME;  ->  attribute binding NAME = N
        regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*layout\\s*\\(\\s*location\\s*=\\s*(\\d+)\\s*\\)\\s*in\\s+\\w+\\s+(\\w+)\\s*;" options:NSRegularExpressionAnchorsMatchLines error:NULL];
        matches = [regex matchesInString:source options:0 range:NSMakeRange(0, [source length])];
        foreach (match, matches) {
            NSString* location = [source substringWithRange:[match rangeAtIndex:1]];
            NSString* name = [source substringWithRange:[match rangeAtIndex:2]];
            [attributeBindings setObject:[NSNumber numberWithInt:[location intValue]] forKey:name];
        }
    } else {
        // [layout(location = N)] out vec4 NAME;  ->  #define NAME gl_FragData[N]
        NSMutableString* result = [NSMutableString stringWithString:source];
        regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(?:layout\\s*\\(\\s*location\\s*=\\s*(\\d+)\\s*\\)\\s*)?out\\s+vec4\\s+(\\w+)\\s*;" options:NSRegularExpressionAnchorsMatchLines error:NULL];
        matches = [regex matchesInString:source options:0 range:NSMakeRange(0, [source length])];
        foreach (match, [matches reverseObjectEnumerator]) {
            NSRange locationRange = [match rangeAtIndex:1];
            NSString* location = locationRange.location != NSNotFound ? [source substringWithRange:locationRange] : @"0";
            NSString* name = [source substringWithRange:[match rangeAtIndex:2]];
            [result replaceCharactersInRange:[match range] withString:[NSString stringWithFormat:@"#define %@ gl_FragData[%@]", name, location]];
        }
        source = result;
    }

    source = ReplaceRegex(source, @"layout\\s*\\([^)]*\\)\\s*", @"");
    if (isVertexShader) {
        source = ReplaceRegex(source, @"^(\\s*)in\\s+", @"$1attribute ");
        source = ReplaceRegex(source, @"^(\\s*)out\\s+", @"$1varying ");
    } else {
        source = ReplaceRegex(source, @"^(\\s*)in\\s+", @"$1varying ");
    }
    source = ReplaceRegex(source, @"\\btexture\\s*\\(", @"texture2D(");
    source = ReplaceRegex(source, @"\\btextureSize\\s*\\(", @"textureSize2D(");
    if ([source rangeOfString:@"isnan("].location != NSNotFound) {
        // isnan() is not available before GLSL 1.30.
        source = [@"bool oo_isnan(float x) { return !(x < 0.0 || x > 0.0 || x == 0.0); }\n" stringByAppendingString:ReplaceRegex(source, @"\\bisnan\\s*\\(", @"oo_isnan(")];
    }

    return source;
}
#endif
