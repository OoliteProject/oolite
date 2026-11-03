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

#include "OOBasicMaterial.h"
#include "OOFunctionAttributes.h"
#include "OOMaterialSpecifier.h"
#include "OOObjCPList.h"
#include "OOTexture.h"
#include "Universe.h"

#include <cstring>
#include <typeinfo>

#define FACE GL_FRONT_AND_BACK

namespace {

// Made on first use and never released, as the static Objective-C material was not.
OOBasicMaterial* sDefaultMaterial = nullptr;

} // namespace

oo::Ref<OOBasicMaterial> OOBasicMaterial::materialWithName(const std::optional<std::string>& name)
{
    oo::Ref<OOBasicMaterial> result = oo::makeRef<OOBasicMaterial>();
    result->initWithName(name);
    return result;
}

oo::Ref<OOBasicMaterial> OOBasicMaterial::materialWithName(const std::optional<std::string>& name, const oo::PList& configuration)
{
    oo::Ref<OOBasicMaterial> result = oo::makeRef<OOBasicMaterial>();
    result->initWithName(name, configuration);
    return result;
}

void OOBasicMaterial::initWithName(const std::optional<std::string>& name)
{
    materialName = name;

    setDiffuseRed(1.0f, 1.0f, 1.0f, 1.0f);
    setAmbientRed(1.0f, 1.0f, 1.0f, 1.0f);
    specular[3] = 1.0;
    emission[3] = 1.0;
}

void OOBasicMaterial::initWithName(const std::optional<std::string>& name, const oo::PList& configuration)
{
    oo::Ref<OOColor> colorDesc;
    int specularExponent;

    initWithName(name);

    // An empty dictionary, not nil: the specifier defaults (a specular exponent of 10) apply. The
    // configuration mixes plist data with live objects (colours): an oo::PList carries both
    // exactly (proposed ADR-0043 Amendment 2).
    const oo::PList config = !configuration.isNull() ? configuration : oo::PList(oo::PList::Dict { });

    // The specifier answers the colour; OOColor::colorWithDescription() of its Object node, which
    // +[OOColor cxx_colorWithDescription:] answered, was the colour itself (bead oo-9ht.1).
    colorDesc = cxx_OOMaterialDiffuseColor(config);
    if (colorDesc != nullptr)
        setDiffuseColor(colorDesc.get());

    colorDesc = cxx_OOMaterialAmbientColor(config);
    if (colorDesc != nullptr)
        setAmbientColor(colorDesc.get());
    else
        setAmbientColor(diffuseColor().get());

    colorDesc = cxx_OOMaterialEmissionColor(config);
    if (colorDesc != nullptr)
        setEmissionColor(colorDesc.get());

    specularExponent = cxx_OOMaterialSpecularExponent(config);
    if (specularExponent != 0 && permitSpecular()) {
        colorDesc = cxx_OOMaterialSpecularColor(config);
        setShininess(specularExponent);
        if (colorDesc != nullptr)
            setSpecularColor(colorDesc.get());
    }
}

std::optional<std::string> OOBasicMaterial::name()
{
    return materialName;
}

bool OOBasicMaterial::doApply()
{
    OOGL(glMaterialfv(FACE, GL_DIFFUSE, diffuse));
    OOGL(glMaterialfv(FACE, GL_SPECULAR, specular));
    OOGL(glMaterialfv(FACE, GL_AMBIENT, ambient));
    OOGL(glMaterialfv(FACE, GL_EMISSION, emission));
    OOGL(glMateriali(FACE, GL_SHININESS, _shininess));
    // -isMemberOfClass: (an Objective-C subclass's C++ part is its adapter, another class)
    if (typeid(*this) == typeid(OOBasicMaterial)) {
        OOTexture::applyNone();
    }

    return true;
}

void OOBasicMaterial::unapplyWithNext(OOMaterial* next)
{
    // -isKindOfClass: (an Objective-C subclass's adapter derives from this class; nil is not one)
    if (dynamic_cast<OOBasicMaterial*>(next) == nullptr) {
        if (EXPECT_NOT(sDefaultMaterial == nullptr))
            sDefaultMaterial = materialWithName(std::string("<default material>")).leakRef();
        sDefaultMaterial->doApply();
    }
}

oo::Ref<OOColor> OOBasicMaterial::diffuseColor()
{
    return OOColor::colorWithRed(diffuse[0],
        diffuse[1],
        diffuse[2],
        diffuse[3]);
}

void OOBasicMaterial::setDiffuseColor(OOColor* color)
{
    if (color != nullptr) {
        setDiffuseRed(color->redComponent(),
            color->greenComponent(),
            color->blueComponent(),
            color->alphaComponent());
    }
}

void OOBasicMaterial::setAmbientAndDiffuseColor(OOColor* color)
{
    setAmbientColor(color);
    setDiffuseColor(color);
}

oo::Ref<OOColor> OOBasicMaterial::specularColor()
{
    return OOColor::colorWithRed(specular[0],
        specular[1],
        specular[2],
        specular[3]);
}

void OOBasicMaterial::setSpecularColor(OOColor* color)
{
    if (color != nullptr) {
        setSpecularRed(color->redComponent(),
            color->greenComponent(),
            color->blueComponent(),
            color->alphaComponent());
    }
}

oo::Ref<OOColor> OOBasicMaterial::ambientColor()
{
    return OOColor::colorWithRed(ambient[0],
        ambient[1],
        ambient[2],
        ambient[3]);
}

void OOBasicMaterial::setAmbientColor(OOColor* color)
{
    if (color != nullptr) {
        setAmbientRed(color->redComponent(),
            color->greenComponent(),
            color->blueComponent(),
            color->alphaComponent());
    }
}

oo::Ref<OOColor> OOBasicMaterial::emmisionColor()
{
    return OOColor::colorWithRed(emission[0],
        emission[1],
        emission[2],
        emission[3]);
}

void OOBasicMaterial::setEmissionColor(OOColor* color)
{
    if (color != nullptr) {
        setEmissionRed(color->redComponent(),
            color->greenComponent(),
            color->blueComponent(),
            color->alphaComponent());
    }
}

void OOBasicMaterial::getDiffuseComponents(GLfloat outComponents[4])
{
    memcpy(outComponents, diffuse, 4 * sizeof *outComponents);
}

void OOBasicMaterial::setDiffuseComponents(const GLfloat components[4])
{
    memcpy(diffuse, components, 4 * sizeof *components);
}

void OOBasicMaterial::setAmbientAndDiffuseComponents(const GLfloat components[4])
{
    setAmbientComponents(components);
    setDiffuseComponents(components);
}

void OOBasicMaterial::getSpecularComponents(GLfloat outComponents[4])
{
    memcpy(outComponents, specular, 4 * sizeof *outComponents);
}

void OOBasicMaterial::setSpecularComponents(const GLfloat components[4])
{
    memcpy(specular, components, 4 * sizeof *components);
}

void OOBasicMaterial::getAmbientComponents(GLfloat outComponents[4])
{
    memcpy(outComponents, ambient, 4 * sizeof *outComponents);
}

void OOBasicMaterial::setAmbientComponents(const GLfloat components[4])
{
    memcpy(ambient, components, 4 * sizeof *components);
}

void OOBasicMaterial::getEmissionComponents(GLfloat outComponents[4])
{
    memcpy(outComponents, emission, 4 * sizeof *outComponents);
}

void OOBasicMaterial::setEmissionComponents(const GLfloat components[4])
{
    memcpy(emission, components, 4 * sizeof *components);
}

void OOBasicMaterial::setDiffuseRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
    diffuse[0] = r;
    diffuse[1] = g;
    diffuse[2] = b;
    diffuse[3] = a;
}

void OOBasicMaterial::setAmbientAndDiffuseRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
    setAmbientRed(r, g, b, a);
    setDiffuseRed(r, g, b, a);
}

void OOBasicMaterial::setSpecularRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
    specular[0] = r;
    specular[1] = g;
    specular[2] = b;
    specular[3] = a;
}

void OOBasicMaterial::setAmbientRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
    ambient[0] = r;
    ambient[1] = g;
    ambient[2] = b;
    ambient[3] = a;
}

void OOBasicMaterial::setEmissionRed(GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
    emission[0] = r;
    emission[1] = g;
    emission[2] = b;
    emission[3] = a;
}

uint8_t OOBasicMaterial::shininess()
{
    return _shininess;
}

void OOBasicMaterial::setShininess(uint8_t value)
{
    _shininess = MIN(value, 128);
}

bool OOBasicMaterial::permitSpecular()
{
    return !(UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false);
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::Ref<OOTexture>> OOBasicMaterial::allTextures()
{
    return { };
}
#endif
