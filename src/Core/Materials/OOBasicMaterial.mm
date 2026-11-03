/*

OOBasicMaterial.m


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

#import "OOBasicMaterial.h"
#import "OOCollectionExtractors.h"
#import "OOFoundationBridge.h"
#import "OOFunctionAttributes.h"
#import "OOMaterialSpecifier.h"
#import "OOTexture.h"
#import "Universe.h"

static OOBasicMaterial* sDefaultMaterial = nil;

#define FACE GL_FRONT_AND_BACK

@implementation OOBasicMaterial

- (id)initWithName:(id)name
{
    self = [super init];
    if (EXPECT_NOT(self == nil))
        return nil;

    materialName = oo::OptionalString(name);

    [self setDiffuseRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
    [self setAmbientRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
    specular[3] = 1.0;
    emission[3] = 1.0;

    return self;
}

- (id)initWithName:(id)name configuration:(id)configuration
{
    id colorDesc = nil;
    int specularExponent;

    self = [self initWithName:name];
    if (EXPECT_NOT(self == nil))
        return nil;

    // An empty dictionary, not nil: the specifier defaults (a specular exponent of 10) apply. The
    // configuration mixes plist data with live objects (colours): an oo::PList carries both
    // exactly (proposed ADR-0043 Amendment 2).
    const oo::PList config = (configuration != nil) ? oo::PListFrom(configuration) : oo::PList(oo::PList::Dict { });

    colorDesc = cxx_OOMaterialDiffuseColor(config);
    if (colorDesc != nil)
        [self setDiffuseColor:[OOColor colorWithDescription:colorDesc]];

    colorDesc = cxx_OOMaterialAmbientColor(config);
    if (colorDesc != nil)
        [self setAmbientColor:[OOColor colorWithDescription:colorDesc]];
    else
        [self setAmbientColor:[self diffuseColor]];

    colorDesc = cxx_OOMaterialEmissionColor(config);
    if (colorDesc != nil)
        [self setEmissionColor:[OOColor colorWithDescription:colorDesc]];

    specularExponent = cxx_OOMaterialSpecularExponent(config);
    if (specularExponent != 0 && [self permitSpecular]) {
        colorDesc = cxx_OOMaterialSpecularColor(config);
        [self setShininess:specularExponent];
        if (colorDesc != nil)
            [self setSpecularColor:[OOColor colorWithDescription:colorDesc]];
    }

    return self;
}

- (void)dealloc
{
    [super willDealloc];

    [super dealloc];
}

- (id)name // shared selector (proposed ADR-0043)
{
    return oo::NSStringOrNil(materialName);
}

- (BOOL)doApply
{
    OOGL(glMaterialfv(FACE, GL_DIFFUSE, diffuse));
    OOGL(glMaterialfv(FACE, GL_SPECULAR, specular));
    OOGL(glMaterialfv(FACE, GL_AMBIENT, ambient));
    OOGL(glMaterialfv(FACE, GL_EMISSION, emission));
    OOGL(glMateriali(FACE, GL_SHININESS, shininess));
    if ([self isMemberOfClass:[OOBasicMaterial class]]) {
        [OOTexture applyNone];
    }

    return YES;
}

- (void)unapplyWithNext:(OOMaterial*)next
{
    if (![next isKindOfClass:[OOBasicMaterial class]]) {
        if (EXPECT_NOT(sDefaultMaterial == nil))
            sDefaultMaterial = [[OOBasicMaterial alloc] initWithName:@"<default material>"];
        [sDefaultMaterial doApply];
    }
}

- (OOColor*)diffuseColor
{
    return [OOColor colorWithRed:diffuse[0]
                           green:diffuse[1]
                            blue:diffuse[2]
                           alpha:diffuse[3]];
}

- (void)setDiffuseColor:(OOColor*)color
{
    if (color != nil) {
        [self setDiffuseRed:[color redComponent]
                      green:[color greenComponent]
                       blue:[color blueComponent]
                      alpha:[color alphaComponent]];
    }
}

- (void)setAmbientAndDiffuseColor:(OOColor*)color
{
    [self setAmbientColor:color];
    [self setDiffuseColor:color];
}

- (OOColor*)specularColor
{
    return [OOColor colorWithRed:specular[0]
                           green:specular[1]
                            blue:specular[2]
                           alpha:specular[3]];
}

- (void)setSpecularColor:(OOColor*)color
{
    if (color != nil) {
        [self setSpecularRed:[color redComponent]
                       green:[color greenComponent]
                        blue:[color blueComponent]
                       alpha:[color alphaComponent]];
    }
}

- (OOColor*)ambientColor
{
    return [OOColor colorWithRed:ambient[0]
                           green:ambient[1]
                            blue:ambient[2]
                           alpha:ambient[3]];
}

- (void)setAmbientColor:(OOColor*)color
{
    if (color != nil) {
        [self setAmbientRed:[color redComponent]
                      green:[color greenComponent]
                       blue:[color blueComponent]
                      alpha:[color alphaComponent]];
    }
}

- (OOColor*)emmisionColor
{
    return [OOColor colorWithRed:emission[0]
                           green:emission[1]
                            blue:emission[2]
                           alpha:emission[3]];
}

- (void)setEmissionColor:(OOColor*)color
{
    if (color != nil) {
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

- (BOOL)permitSpecular
{
    return ![UNIVERSE reducedDetail];
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (id)allTextures
{
    return oo::NSSetFromObjects(std::vector<id>()); // an empty set; shared selector (proposed ADR-0043)
}
#endif

@end
