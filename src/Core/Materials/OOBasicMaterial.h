/*

OOBasicMaterial.h

Material using basic OpenGL properties. Normal materials
(OOSingleTextureMaterial, OOShaderMaterial) are subclasses of this. It may be
desireable to have a material which does not use normal GL material
properties, in which case it should be based on OOMaterial directly.

C++20 since bead oo-vl43 (proposed ADR-0056, amendment oo-vl43). The Objective-C facade
(its bridge header) was deleted by bead oo-9ht.33, which moved the class out of namespace cxx.


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

#ifndef OOBASICMATERIAL_H
#define OOBASICMATERIAL_H

#include "OOColor.h"
#include "OOMaterial.h"

#include "oofnd/StdLib.hpp"

class OOBasicMaterial : public OOMaterial {
public:
    /*	A new material, initialised by the initialiser of the same arguments (below). They were
            [[OOBasicMaterial alloc] cxx_initWithName:] and [[OOBasicMaterial alloc] initWithName:configuration:].
    */
    static oo::Ref<OOBasicMaterial> materialWithName(const std::optional<std::string>& name);
    static oo::Ref<OOBasicMaterial> materialWithName(const std::optional<std::string>& name, const oo::PList& configuration);

    /*	The initialisers. Each runs once, right after construction: from a factory above, a
            subclass's initialiser, or the facade's initialisers. Not constructors, because the second
            asks the virtual permitSpecular(), which must reach a subclass's override (proposed
            ADR-0056, amendment oo-vl43).

            Initialize with default values (historical Olite defaults, not GL defaults):
                    diffuse		{ 1.0, 1.0, 1.0, 1.0 }
                    specular	{ 0.0, 0.0, 0.0, 1.0 }
                    ambient		{ 1.0, 1.0, 1.0, 1.0 }
                    emission	{ 0.0, 0.0, 0.0, 1.0 }
                    shininess	0
    */
    void initWithName(const std::optional<std::string>& name); // (bead oo-3rb.289.5)

    /*	Initialize with dictionary. Accepted keys:
                    diffuse		colour description
                    specular	colour description
                    ambient		colour description
                    emission	colour description
                    shininess	integer

            "Colour description" refers to anything OOColor::colorWithDescription()
            will accept.
    */
    void initWithName(const std::optional<std::string>& name, const oo::PList& configuration); // a null configuration is an empty one. Shared by the material classes.

    std::optional<std::string> name() override;
    bool doApply() override;
    void unapplyWithNext(OOMaterial* next) override;
    size_t objectSize() const override { return sizeof *this; }
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::Ref<OOTexture>> allTextures() override;
#endif

    oo::Ref<OOColor> diffuseColor();
    void setDiffuseColor(OOColor* color);
    void setAmbientAndDiffuseColor(OOColor* color);
    oo::Ref<OOColor> specularColor();
    void setSpecularColor(OOColor* color);
    oo::Ref<OOColor> ambientColor();
    void setAmbientColor(OOColor* color);
    oo::Ref<OOColor> emmisionColor();
    void setEmissionColor(OOColor* color);

    void getDiffuseComponents(GLfloat outComponents[4]);
    void setDiffuseComponents(const GLfloat components[4]);
    void setAmbientAndDiffuseComponents(const GLfloat components[4]);
    void getSpecularComponents(GLfloat outComponents[4]);
    void setSpecularComponents(const GLfloat components[4]);
    void getAmbientComponents(GLfloat outComponents[4]);
    void setAmbientComponents(const GLfloat components[4]);
    void getEmissionComponents(GLfloat outComponents[4]);
    void setEmissionComponents(const GLfloat components[4]);

    void setDiffuseRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
    void setAmbientAndDiffuseRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
    void setSpecularRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
    void setAmbientRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
    void setEmissionRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a);

    uint8_t shininess();
    void setShininess(uint8_t value); // Clamped to [0, 128]

    /*	For subclasses: return true to permit specular settings, false to deny
            them. By default, this is !(UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false).
    */
    virtual bool permitSpecular();

private:
    std::optional<std::string> materialName = { }; // nil-able, as the name was (proposed ADR-0043)

    // Colours
    GLfloat diffuse[4] = { },
            specular[4] = { },
            ambient[4] = { },
            emission[4] = { };

    // Specular exponent. The leading underscore: shininess() is the getter's name (amendment oo-rdfh).
    uint8_t _shininess = { }; // Default: 0.0
};

#endif // OOBASICMATERIAL_H
