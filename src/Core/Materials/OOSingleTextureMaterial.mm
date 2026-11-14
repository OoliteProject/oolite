/*

OOSingleTextureMaterial.h


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

#import "OOSingleTextureMaterial.h"
#import "OOFoundationBridge.h"
#import "OOFunctionAttributes.h"
#import "OOPListView.h"
#import "OOTexture.h"

@implementation OOSingleTextureMaterial

- (id)initWithName:(id)name configuration:(id)configuration
{
    id texSpec = nil;

    if (configuration != nil) {
        texSpec = oo::PListView(configuration).get<oo::TextureSpecifier>(@"diffuse_map", name);
    } else {
        texSpec = name;
    }

    return [self initWithName:oo::OptionalString(name)
                      texture:[OOTexture cxx_textureWithConfiguration:oo::PListFrom(texSpec)]
                configuration:configuration];
}

- (id)initWithName:(const std::optional<std::string>&)name texture:(OOTexture*)texture configuration:(id)configuration
{
    if (name.has_value() && texture != nil) {
        self = [super initWithName:oo::NSStringOrNil(name) configuration:configuration];
        if (self != nil) {
            _texture = [texture retain];
        }
    } else {
        DESTROY(self);
    }

    return self;
}

- (void)dealloc
{
    [self willDealloc];
    [_texture release];

    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return [_texture cxx_description];
}

- (BOOL)doApply
{
    if (EXPECT_NOT(![super doApply]))
        return NO;

    [_texture apply];
    return YES;
}

- (void)unapplyWithNext:(OOMaterial*)next
{
    if (![next isKindOfClass:[OOSingleTextureMaterial class]])
        [OOTexture applyNone];
    [super unapplyWithNext:next];
}

- (void)ensureFinishedLoading
{
    [_texture ensureFinishedLoading];
}

- (BOOL)isFinishedLoading
{
    return [_texture isFinishedLoading];
}

- (BOOL)wantsNormalsAsTextureCoordinates
{
    return [_texture isCubeMap];
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures
{
    std::vector<oo::ObjCRef<OOTexture*>> result;
    result.emplace_back(_texture);
    return result;
}
#endif

@end
