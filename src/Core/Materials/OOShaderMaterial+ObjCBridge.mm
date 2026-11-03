/*

OOShaderMaterial+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-vl43): the Objective-C OOShaderMaterial
facade (see OOShaderMaterial+ObjCBridge.h). Each method forwards to its C++ member through
oo::ToCxx(self); the initialisers run the C++ factory and adopt the result. Deleted with
OOShaderMaterial+ObjCBridge.h.


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

// A facade of this class is only ever made for a cxx::OOShaderMaterial (oo::ToObjC names the
// facade class after the C++ class, and the initialisers below make one), so the casts are exact.
OOShaderMaterial* oo::ToObjC(cxx::OOShaderMaterial* material)
{
    return static_cast<OOShaderMaterial*>(oo::ToObjC(static_cast<cxx::OOMaterial*>(material)));
}

cxx::OOShaderMaterial* oo::ToCxx(OOShaderMaterial* material)
{
    return static_cast<cxx::OOShaderMaterial*>(oo::ToCxx(static_cast<OOMaterial*>(material)));
}

@interface OOShaderMaterial (OOObjCBridgePrivate)

- (id)initWithNewCxxShaderMaterial:(const oo::Ref<cxx::OOShaderMaterial>&)material;

@end

@implementation OOShaderMaterial

// The facade of material, a new C++ material; nil (self released) where the C++ initialiser failed.
- (id)initWithNewCxxShaderMaterial:(const oo::Ref<cxx::OOShaderMaterial>&)material
{
    if (material == nullptr) {
        [self release];
        return nil;
    }
    return [super initWithNewCxxMaterial:material];
}

// Every ivar zero, as before: -init did not run an initialiser of this class.
- (id)init
{
    return [self initWithNewCxxShaderMaterial:oo::makeRef<cxx::OOShaderMaterial>()];
}

+ (BOOL)configurationDictionarySpecifiesShaderMaterial:(const oo::PList&)configuration
{
    return cxx::OOShaderMaterial::configurationDictionarySpecifiesShaderMaterial(configuration);
}

+ (instancetype)shaderMaterialWithName:(const std::optional<std::string>&)name
                         configuration:(const oo::PList&)configuration
                                macros:(const oo::PList&)macros
                         bindingTarget:(id<OOWeakReferenceSupport>)target
{
    return oo::ToObjC(cxx::OOShaderMaterial::shaderMaterialWithName(name, configuration, macros, target));
}

- (id)initWithName:(const std::optional<std::string>&)name
     configuration:(const oo::PList&)configuration
            macros:(const oo::PList&)macros
     bindingTarget:(id<OOWeakReferenceSupport>)target
{
    return [self initWithNewCxxShaderMaterial:cxx::OOShaderMaterial::shaderMaterialWithName(name, configuration, macros, target)];
}

- (BOOL)bindUniform:(const std::string&)uniformName
           toObject:(id<OOWeakReferenceSupport>)target
           property:(SEL)selector
     convertOptions:(OOUniformConvertOptions)options
{
    return oo::ToCxx(self)->bindUniform(uniformName, target, selector, options);
}

- (BOOL)bindSafeUniform:(const std::string&)uniformName
               toObject:(id<OOWeakReferenceSupport>)target
          propertyNamed:(const std::optional<std::string>&)property
         convertOptions:(OOUniformConvertOptions)options
{
    return oo::ToCxx(self)->bindSafeUniform(uniformName, target, property, options);
}

- (void)setUniform:(const std::string&)uniformName intValue:(int)value
{
    oo::ToCxx(self)->setUniform(uniformName, value);
}
- (void)setUniform:(const std::string&)uniformName floatValue:(float)value
{
    oo::ToCxx(self)->setUniform(uniformName, value);
}
- (void)setUniform:(const std::string&)uniformName vectorValue:(GLfloat[4])value
{
    oo::ToCxx(self)->setUniform(uniformName, value);
}
- (void)setUniform:(const std::string&)uniformName vectorObjectValue:(const oo::PList&)value
{
    oo::ToCxx(self)->setUniform(uniformName, value);
}
- (void)setUniform:(const std::string&)uniformName quaternionValue:(Quaternion)value asMatrix:(BOOL)asMatrix
{
    oo::ToCxx(self)->setUniform(uniformName, value, asMatrix);
}

- (void)addUniformsFromDictionary:(const oo::PList&)uniformDefs withBindingTarget:(id<OOWeakReferenceSupport>)target
{
    oo::ToCxx(self)->addUniformsFromDictionary(uniformDefs, target);
}

@end

#endif // OO_SHADERS
