/*

OODefaultShaderSynthesizer.h

Function to automatically write a shader that implements a given material
specification.


Copyright © 2011–2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish,0 distribute, sublicense, and/or sell
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

#pragma once

#include "OOFoundation.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>
#include <vector>

class OOMesh; // C++ since bead oo-9ht.132

/*	Foundation sweep (bead oo-3rb.150): the material configuration is an oo::PList dictionary, the
        material key and entity name are nil-able strings, and the outputs are the two shader sources, the
        texture list (a PList array) and the uniform specifications (a PList dictionary). On failure the
        strings are empty and the two PLists null, where all four used to be nil.
*/
BOOL OOSynthesizeMaterialShader(const oo::PList& materialConfiguration, const std::optional<std::string>& materialKey, const std::optional<std::string>& entityName, std::string* outVertexShader, std::string* outFragmentShader, oo::PList* outTextureSpecs, oo::PList* outUniformSpecs);

/*	The synthesizer itself (Phase 3, beads oo-bm1q and oo-bhxc: slices 1 and 2 of
        docs/phases/3-slices/OODefaultShaderSynthesizer.md). It was an Objective-C class private to
        OODefaultShaderSynthesizer.mm; its one caller is OOSynthesizeMaterialShader() above. Its
        Objective-C facade was deleted, and the class moved to the global namespace, by bead oo-9ht.134.
*/
class OODefaultShaderSynthesizer : public oo::RefCounted {
public:
    OODefaultShaderSynthesizer(const oo::PList& configuration, const std::optional<std::string>& materialKey, const std::optional<std::string>& name); // -initWithMaterialConfiguration:materialKey:entityName:

    bool run();

    std::string vertexShader();
    std::string fragmentShader();
    oo::PList textureSpecifications(); // an array
    oo::PList uniformSpecifications(); // a dictionary

    std::optional<std::string> materialKey();
    std::optional<std::string> entityName();

private:
    void createTemporaries();
    void destroyTemporaries();

    void composeVertexShader();
    void composeFragmentShader();

    // Write various types of declarations.
    void appendVariable(const std::string& name, const std::string& type, const std::string& prefix, std::string& buffer);
    void addAttribute(const std::string& name, const std::string& type);
    void addVarying(const std::string& name, const std::string& type);
    void addVertexUniform(const std::string& name, const std::string& type);
    void addFragmentUniform(const std::string& name, const std::string& type);

    // Create or retrieve a uniform variable name for a given binding.
    std::optional<std::string> defineBindingUniform(const oo::PList& binding, const std::string& type);

    std::optional<std::string> readRGBForTextureSpec(const oo::PList& textureSpec, const std::string& mapName); // Generate a read for an RGB value, or a single channel splatted across RGB.
    std::optional<std::string> readOneChannelForTextureSpec(const oo::PList& textureSpec, const std::string& mapName); // Generate a read for a single channel.

    // Details of texture setup; generally use read*ForTextureSpec() instead.
    NSUInteger assignIDForTexture(const oo::PList& textureSpec);
    NSUInteger textureIDForSpec(const oo::PList& textureSpec);
    void setUpOneTexture(const oo::PList& textureSpec);
    void getSampleName(std::string* outSampleName, std::string* outSwizzleOp, const oo::PList& textureSpec); // swizzle "" = none

#ifndef NDEBUG
    using Stage = void (OODefaultShaderSynthesizer::*)();
    void performStage(const char* name, Stage stage); // runs a stage, checking for recursion
#endif

    /*	Stages. These should only be called through the REQUIRE_STAGE macro (in the .mm) to
            avoid duplicated code and ensure data depedencies are met.
    */

    /*	writeTextureCoordRead
            Generate vec2 texCoords.
    */
    void writeTextureCoordRead();

    /*	writeDiffuseColorTermIfNeeded
            Generates and populates the fragment shader value vec3 diffuseColor, unless
            the diffuse term is black. If a diffuseColor is generated, _usesDiffuseTerm
            is set. The value will be const if possible.
            See also: writeDiffuseColorTerm.
    */
    void writeDiffuseColorTermIfNeeded();

    /*	writeDiffuseColorTerm
            Generates vec3 diffuseColor unconditionally – that is, even if the diffuse
            term is black.
            See also: writeDiffuseColorTermIfNeeded.
    */
    void writeDiffuseColorTerm();

    /*	writeDiffuseLighting
            Generate the fragment variable vec3 diffuseLight and add Lambertian and
            ambient terms to it.
    */
    void writeDiffuseLighting();

    /*	writeLightVector
            Generate the fragment variable vec3 lightVector (unit vector) for temporary
            lighting. Calling this if lighting mode is kLightingUniform will cause an
            exception.
    */
    void writeLightVector();

    /*	writeEyeVector
            Generate vec3 lightVector, the normalized direction from the fragment to
            the light source.
    */
    void writeEyeVector();

    /*	writeVertexTangentBasis
            Generates tangent space basis matrix (TBN) in vertex shader, if in tangent-
            space lighting mode. If not, an exeception is raised.
    */
    void writeVertexTangentBasis();

    /*	writeNormalIfNeeded
            Writes fragment variable vec3 normal if necessary. Otherwise, it sets
            _constZNormal, indicating that the normal is always (0, 0, 1).

            See also: writeNormal.
    */
    void writeNormalIfNeeded();

    /*	writeNormal
            Generates vec3 normal unconditionally – if _constZNormal is set, normal will
            be const vec3 normal = vec3 (0.0, 0.0, 1.0).
    */
    void writeNormal();

    /*	writeSpecularLighting
            Calculate specular writing and add it to totalColor.
    */
    void writeSpecularLighting();

    /*	writeLightMaps
            Add emission and illumination maps to totalColor.
    */
    void writeLightMaps();

    /*	writeVertexPosition
            Calculate vertex position and write it to gl_Position.
    */
    void writeVertexPosition();

    /*	writeTotalColor
            Generate vec3 totalColor, the accumulator for output colour values.
    */
    void writeTotalColor();

    /*	writeFinalColorComposite
            This stage writes the final fragment shader. It also pulls in other stages
            through dependencies.
    */
    void writeFinalColorComposite();

    // The state (the old ivars).
    oo::PList _configuration;
    std::optional<std::string> _materialKey;
    std::optional<std::string> _entityName;

    std::string _vertexShader;
    std::string _fragmentShader;
    std::vector<oo::PList> _textures; // the texture list, in insertion order
    oo::PList::Dict _uniforms; // uniform name -> specification (byte order of the name)

    std::string _attributes;
    std::string _varyings;
    std::string _vertexUniforms;
    std::string _fragmentUniforms;
    std::string _vertexHelpers;
    std::string _fragmentHelpers;
    std::string _vertexBody;
    std::string _fragmentPreTextures;
    std::string _fragmentTextureLookups;
    std::string _fragmentBody;

    // _texturesByName: dictionary mapping texture file names to texture specifications.
    std::map<std::string, oo::PList> _texturesByName;
    // _textureIDs: dictionary mapping texture file names to numerical IDs used to name variables.
    std::map<std::string, NSUInteger> _textureIDs;
    // _sampledTextures: hash of integer texture IDs for which we’ve set up a sample.
    std::unordered_set<NSUInteger> _sampledTextures; // was an integer hash table (bead oo-3rb.20)

    // _uniformBindingNames: binding specification -> uniform name (compared with oo::PList ==).
    std::vector<std::pair<oo::PList, std::string>> _uniformBindingNames;

    NSUInteger _usesNormalMap : 1 = 0,
                                _usesDiffuseTerm : 1 = 0,
                                _constZNormal : 1 = 0,
                                _haveDiffuseLight : 1 = 0,

                                // Completion flags for various generation stages.
        _completed_writeFinalColorComposite : 1 = 0,
                                _completed_writeDiffuseColorTerm : 1 = 0,
                                _completed_writeSpecularLighting : 1 = 0,
                                _completed_writeLightMaps : 1 = 0,
                                _completed_writeDiffuseLighting : 1 = 0,
                                _completed_writeDiffuseColorTermIfNeeded : 1 = 0,
                                _completed_writeVertexPosition : 1 = 0,
                                _completed_writeNormalIfNeeded : 1 = 0,
                                //		_completedwriteNormal: 1,
        _completed_writeLightVector : 1 = 0,
                                _completed_writeEyeVector : 1 = 0,
                                _completed_writeTotalColor : 1 = 0,
                                _completed_writeTextureCoordRead : 1 = 0,
                                _completed_writeVertexTangentBasis : 1 = 0;

#ifndef NDEBUG
    std::unordered_set<std::string_view> _stagesInProgress; // the stages' names (was a hash table of selectors)
#endif
};
