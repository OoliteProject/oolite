/*

OOShaderMaterial+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-vl43): the Objective-C OOShaderMaterial,
a facade over the C++ cxx::OOShaderMaterial (OOShaderMaterial.h), for the callers that make and
message it (OOMaterialConvenienceCreators, OOPlanetEntity, and OOShaderUniform's convert options).
Its interface is the one OOShaderMaterial.h declared before the conversion, copied exactly (same
selectors, same types), so they compile and behave unchanged. Imported as the last line of
OOShaderMaterial.h; do not import it directly.

It has no ivars: the root facade's _cxxMaterial holds the C++ material (ADR-0056 amendment of bead
oo-up4b, item 3). Its initialisers make a new C++ material, whose facade it is from then on, or
answer nil where the Objective-C initialiser did. No Objective-C class derives from it. Never add
to this file; converted code does not message the facade. Deleted by its deletion bead once every
caller is C++.


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

#ifndef OOSHADERMATERIAL_OBJCBRIDGE_H
#define OOSHADERMATERIAL_OBJCBRIDGE_H

@interface OOShaderMaterial : OOBasicMaterial

+ (BOOL)configurationDictionarySpecifiesShaderMaterial:(const oo::PList&)configuration; // null -> NO

/*	Set up an OOShaderMaterial (see cxx::OOShaderMaterial::shaderMaterialWithName() for the
        configuration and the macros).
*/
+ (instancetype)shaderMaterialWithName:(const std::optional<std::string>&)name
                         configuration:(const oo::PList&)configuration // null = nil
                                macros:(const oo::PList&)macros // null = nil
                         bindingTarget:(id<OOWeakReferenceSupport>)target;

- (id)initWithName:(const std::optional<std::string>&)name
     configuration:(const oo::PList&)configuration // null = nil
            macros:(const oo::PList&)macros // null = nil
     bindingTarget:(id<OOWeakReferenceSupport>)target;

/*	Bind a uniform to a property of an object. NOTE: this method *does not* check against the
        whitelist. See -bindSafeUniform:toObject:propertyNamed:convertOptions: below.
*/
- (BOOL)bindUniform:(const std::string&)uniformName
           toObject:(id<OOWeakReferenceSupport>)target
           property:(SEL)selector
     convertOptions:(OOUniformConvertOptions)options;

/*	Bind a uniform to a property of an object.

        This is similar to -bindUniform:toObject:property:convertOptions:, except
        that it checks against OOUniformBindingPermitted().
*/
- (BOOL)bindSafeUniform:(const std::string&)uniformName
               toObject:(id<OOWeakReferenceSupport>)target
          propertyNamed:(const std::optional<std::string>&)property // nullopt: no property (not bound)
         convertOptions:(OOUniformConvertOptions)options;

/*	Set a uniform value.
 */
- (void)setUniform:(const std::string&)uniformName intValue:(int)value;
- (void)setUniform:(const std::string&)uniformName floatValue:(float)value;
- (void)setUniform:(const std::string&)uniformName vectorValue:(GLfloat[4])value;
- (void)setUniform:(const std::string&)uniformName vectorObjectValue:(const oo::PList&)value; // Array of four numbers, or something that can be OOVectorFromObject()ed.
- (void)setUniform:(const std::string&)uniformName quaternionValue:(Quaternion)value asMatrix:(BOOL)asMatrix;

/*	Add constant uniforms. Same format as uniforms dictionary of configuration
        parameter to -initWithConfiguration:macros:. The target parameter is used
        for bindings.

        Additionally, the target may implement the following method, used to seed
        any random bindings:
                - (uint32_t) randomSeedForShaders;
*/
- (void)addUniformsFromDictionary:(const oo::PList&)uniformDefs withBindingTarget:(id<OOWeakReferenceSupport>)target;

@end

/*	The informal protocols a shader binding target implements, categories of the Objective-C root
        that the entities implement. They are not the material's: they stay Objective-C until the
        entities convert (ADR-0056 amendment of bead oo-3kqi, item 5), moved here from
        OOShaderMaterial.h unchanged.
*/
@interface OOObject (ShaderBindingHierarchy)

/*	Informal protocol for objects to "forward" their shader bindings up a
        hierarchy (for instance, subentities to parent entities).
*/
- (id<OOWeakReferenceSupport>)superShaderBindingTarget;

@end

@interface OOObject (OOShaderMaterialTargetOptional)

- (uint32_t)randomSeedForShaders;

@end

namespace oo {

// The material's Objective-C object (see oo::ToObjC(cxx::OOMaterial *)); nil for null.
OOShaderMaterial* ToObjC(cxx::OOShaderMaterial* material);
inline OOShaderMaterial* ToObjC(const Ref<cxx::OOShaderMaterial>& material) { return ToObjC(material.get()); }

// The C++ material behind an Objective-C one, borrowed; null for nil.
cxx::OOShaderMaterial* ToCxx(OOShaderMaterial* material);

} // namespace oo

#endif // OOSHADERMATERIAL_OBJCBRIDGE_H
