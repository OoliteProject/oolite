/*	test_OODefaultShaderSynthesizer.mm
	Unit tests for OODefaultShaderSynthesizer (src/Core/Materials/OODefaultShaderSynthesizer.h/.mm),
	the default shader synthesizer: beads oo-bm1q, oo-bhxc and oo-4s5i, the three slices of
	docs/phases/3-slices/OODefaultShaderSynthesizer.md (Phase 3, house style of proposed ADR-0056,
	amendments oo-dqxj and oo-pni4).

	The synthesizer's one entry point, OOSynthesizeMaterialShader(), canonicalises a material
	configuration (legacy keys, combined maps, the diffuse map named after the material key) and
	writes a vertex and a fragment shader for it, with the list of textures they sample and the
	uniforms they read. It reaches no OpenGL: the texture options are read from the
	game's own texture code with no universe (gSharedUniverse nil) and no extension manager. The
	file reaches the texture and material-specifier code, which reach most of the game, so the
	test links every game object but main's (tests/unit/core/meson.build entry ['*']) and defines
	gDebugFlags. The log is captured, so the warnings and errors are pinned too.

	The expectations were written against the entry point while the class was Objective-C and
	run on it first (commit 643b5358b); they pin the whole of each shader text, the description of the texture
	list and of the uniforms, and the warnings and errors logged. Light-map bindings are not
	covered: they read the binding types from the game's resources (ResourceManager).
	Slice 1 made the class C++ (cxx::OODefaultShaderSynthesizer) with an Objective-C facade for the
	stages; the last tests pin the C++ API and the facade's contract.
	Run: bash tools/check-core-tests.sh
*/

#import "OODefaultShaderSynthesizer.h"
#import "OODescription.h"

#include "oofnd/Log.hpp"
#include "oo_test.hpp"

#include <cstdio>
#include <optional>
#include <string>
#include <string_view>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

// The log, as the synthesizer writes it.
std::vector<std::string> gLog;


void Capture(std::string_view line)
{
	gLog.emplace_back(line);
}


void StartLog()
{
	oo::log::logger().setInitialized(true);
	oo::log::logger().setSink(&Capture);
	gLog.clear();
}


int LogLinesContaining(std::string_view text)
{
	int count = 0;
	for (const std::string &line : gLog)
	{
		if (line.find(text) != std::string::npos)  count++;
	}
	return count;
}


// A text as a C string literal, for a pin that does not match (so the actual text can be read).
std::string Literal(const std::string &text)
{
	std::string result = "\"";
	for (char c : text)
	{
		switch (c)
		{
			case '\n':	result += "\\n\"\n\""; break;
			case '\t':	result += "\\t"; break;
			case '"':	result += "\\\""; break;
			case '\\':	result += "\\\\"; break;
			default:	result += c;
		}
	}
	return result + "\"";
}


bool Pin(const char *what, const std::string &actual, const char *expected)
{
	bool same = (expected != nullptr && actual == expected);
	if (!same)  std::printf("PIN %s:\n%s\n", what, Literal(actual).c_str());
	return same;
}


struct Synthesized
{
	BOOL		ok = NO;
	std::string	vertex;
	std::string	fragment;
	oo::PList	textures;
	oo::PList	uniforms;
};


Synthesized Synthesize(oo::PList::Dict configuration, const std::optional<std::string> &materialKey)
{
	Synthesized result;
	result.vertex = "unwritten";
	result.fragment = "unwritten";
	StartLog();
	result.ok = OOSynthesizeMaterialShader(oo::PList(std::move(configuration)), materialKey, std::string("test entity"), &result.vertex, &result.fragment, &result.textures, &result.uniforms);
	return result;
}


oo::PList Color(double r, double g, double b)
{
	return oo::PList(oo::PList::Array{ oo::PList(r), oo::PList(g), oo::PList(b) });
}


oo::PList Map(const char *name, const char *extract = nullptr)
{
	oo::PList::Dict spec{ { "name", oo::PList(name) } };
	if (extract != nullptr)  spec["extract_channel"] = oo::PList(extract);
	return oo::PList(std::move(spec));
}


// One synthesized material, pinned whole.
struct Expected
{
	const char	*vertex;
	const char	*fragment;
	const char	*textures;	// oo::DescriptionOf the texture list
	const char	*uniforms;	// oo::DescriptionOf the uniforms
};


void CheckSynthesized(const char *name, const Synthesized &actual, const Expected &expected)
{
	std::printf("-- %s\n", name);
	OO_CHECK(actual.ok);
	OO_CHECK(Pin("vertex", actual.vertex, expected.vertex));
	OO_CHECK(Pin("fragment", actual.fragment, expected.fragment));
	OO_CHECK(Pin("textures", oo::DescriptionOf(actual.textures), expected.textures));
	OO_CHECK(Pin("uniforms", oo::DescriptionOf(actual.uniforms), expected.uniforms));
}

}	// namespace


// --- The entry point, through the Objective-C era API ------------------------------------------

// No configuration but the material key: a diffuse map named after it, lit by the light source.
OO_TEST(diffuseMapFromMaterialKey)
{
	Synthesized s = Synthesize({}, std::string("hull.png"));
	CheckSynthesized("diffuseMapFromMaterialKey", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // hull.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"hull.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; }" });
	OO_CHECK_EQ(LogLinesContaining("WARNING"), 0);
	OO_CHECK_EQ(LogLinesContaining("ERROR"), 0);
}


// A black diffuse colour: no diffuse term, so no lighting, and no texture.
OO_TEST(blackDiffuseColour)
{
	Synthesized s = Synthesize({ { "diffuse_color", Color(0, 0, 0) } }, std::string("hull.png"));
	CheckSynthesized("blackDiffuseColour", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec3\t\tvEyeVector;\n"
		"varying vec3\t\tvLightVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"}",
		"// Varyings\n"
		"varying vec3\t\tvEyeVector;\n"
		"varying vec3\t\tvLightVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"()",
		"{}" });
}


// A tinted diffuse map (the legacy key "diffuse"): the sample times the colour.
OO_TEST(tintedDiffuseMap)
{
	Synthesized s = Synthesize({ { "diffuse", Color(0.5, 0.25, 1.0) } }, std::string("hull.png"));
	CheckSynthesized("tintedDiffuseMap", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // hull.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\tdiffuseColor *= vec3(0.5, 0.25, 1.0);\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"hull.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; }" });
}


// A single channel of the diffuse map is splatted across RGB.
OO_TEST(diffuseMapOneChannel)
{
	Synthesized s = Synthesize({ { "diffuse_map", Map("d.png", "g") } }, std::string("hull.png"));
	CheckSynthesized("diffuseMapOneChannel", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // d.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.ggg;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"d.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; }" });
}


// Two channels of the diffuse map cannot be read as a colour: a warning and a marker.
OO_TEST(diffuseMapExtractionMismatch)
{
	Synthesized s = Synthesize({ { "diffuse_map", Map("d.png", "rg") } }, std::string("hull.png"));
	CheckSynthesized("diffuseMapExtractionMismatch", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // d.png\n"
		"\t\n"
		"\t// INVALID EXTRACTION KEY\n"
		"\t\n"
		"\tconst vec3 diffuseColor = vec3(1.0, 1.0, 1.0);\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"d.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; }" });
	OO_CHECK_EQ(LogLinesContaining("specifies 2 channels to extract"), 1);
}


// Specular lighting with a constant colour (the legacy key "specular") and exponent.
OO_TEST(specularConstant)
{
	Synthesized s = Synthesize({ { "specular", Color(1, 1, 1) }, { "shininess", oo::PList(20) } }, std::string("hull.png"));
	CheckSynthesized("specularConstant", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // hull.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(1.0, 1.0, 1.0);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"hull.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; }" });
}


// The legacy combined specular map: colour from RGB, exponent from alpha, with a modulate colour.
OO_TEST(specularCombinedMap)
{
	Synthesized s = Synthesize({ { "specular_map", oo::PList("spec.png") }, { "specular_modulate_color", Color(0.5, 0.5, 0.5) }, { "specular_exponent", oo::PList(10) } }, std::string("hull.png"));
	CheckSynthesized("specularCombinedMap", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"uniform sampler2D\tuTexture1;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // hull.png\n"
		"\tvec4 tex1Sample = texture2D(uTexture1, texCoords);  // spec.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = tex1Sample.rgb;\n"
		"\tspecularColor *= vec3(0.5, 0.5, 0.5);  // Constant colour\n"
		"\tfloat specularExponent = tex1Sample.a * 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"hull.png\"; }, {name = \"spec.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; uTexture1 = {type = texture; value = 1; }; }" });
}


// A specular colour map scaled and self-coloured, with no exponent map.
OO_TEST(specularColourMapScaledSelfColoured)
{
	oo::PList::Dict map{ { "name", oo::PList("spec.png") }, { "scale_factor", oo::PList(2.0) }, { "self_color", oo::PList(true) } };
	Synthesized s = Synthesize({ { "specular_color_map", oo::PList(std::move(map)) }, { "specular_exponent", oo::PList(8) } }, std::string("hull.png"));
	CheckSynthesized("specularColourMapScaledSelfColoured", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"uniform sampler2D\tuTexture1;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // hull.png\n"
		"\tvec4 tex1Sample = texture2D(uTexture1, texCoords);  // spec.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = tex1Sample.rgb;\n"
		"\tspecularColor *= 2.0;  // Scale factor\n"
		"\tspecularColor *= diffuseColor;  // Self-colouring\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"hull.png\"; }, {name = \"spec.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; uTexture1 = {type = texture; value = 1; }; }" });
}


// The legacy combined normal and parallax map: tangent basis, eye vector, parallax-offset coordinates.
OO_TEST(normalAndParallaxMap)
{
	Synthesized s = Synthesize({ { "normal_and_parallax_map", oo::PList("normal.png") }, { "parallax_scale", oo::PList(0.02) }, { "parallax_bias", oo::PList(0.5) }, { "specular_exponent", oo::PList(5) } }, std::string("hull.png"));
	CheckSynthesized("normalAndParallaxMap", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvEyeVector;\n"
		"varying vec3\t\tvLightVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"uniform sampler2D\tuTexture1;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvEyeVector;\n"
		"varying vec3\t\tvLightVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t// Parallax mapping\n"
		"\tfloat parallax = texture2D(uTexture0, vTexCoords).a;\n"
		"\tparallax *= 0.02;  // Parallax scale\n"
		"\tparallax += 0.5;  // Parallax bias\n"
		"\tvec2 texCoords = vTexCoords - parallax * eyeVector.xy * vec2(1.0, -1.0);\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex1Sample = texture2D(uTexture1, texCoords);  // hull.png\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // normal.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex1Sample.rgb;\n"
		"\t\n"
		"\tvec3 normal = normalize(tex0Sample.rgb - 0.5);\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, dot(normal, lightVector)) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = reflect(lightVector, normal);\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"normal.png\"; }, {name = \"hull.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; uTexture1 = {type = texture; value = 1; }; }" });
}


// A normal map read from two channels cannot be used: a warning, and the constant normal.
OO_TEST(normalMapExtractionMismatch)
{
	Synthesized s = Synthesize({ { "normal_map", Map("n.png", "rg") }, { "specular_exponent", oo::PList(5) } }, std::string("hull.png"));
	CheckSynthesized("normalMapExtractionMismatch", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"uniform sampler2D\tuTexture1;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // hull.png\n"
		"\tvec4 tex1Sample = texture2D(uTexture1, texCoords);  // n.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"hull.png\"; }, {name = \"n.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; uTexture1 = {type = texture; value = 1; }; }" });
	OO_CHECK_EQ(LogLinesContaining("specifies 2 channels to extract"), 1);
}


// Legacy emission and illumination maps become light maps, one tinted, one in illumination mode.
OO_TEST(emissionAndIlluminationMaps)
{
	Synthesized s = Synthesize({ { "emission_map", oo::PList("glow.png") }, { "emission_modulate_color", Color(1, 0, 0) }, { "illumination_map", oo::PList("lit.png") } }, std::string("hull.png"));
	CheckSynthesized("emissionAndIlluminationMaps", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"uniform sampler2D\tuTexture1;\n"
		"uniform sampler2D\tuTexture2;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // hull.png\n"
		"\tvec4 tex1Sample = texture2D(uTexture1, texCoords);  // glow.png\n"
		"\tvec4 tex2Sample = texture2D(uTexture2, texCoords);  // lit.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\tvec3 lightMapColor;\n"
		"\tlightMapColor = tex1Sample.rgb;\n"
		"\tlightMapColor *= vec3(1.0, 0.0, 0.0);\n"
		"\ttotalColor += lightMapColor;\n"
		"\t\n"
		"\tlightMapColor = tex2Sample.rgb;\n"
		"\tdiffuseLight += lightMapColor;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"hull.png\"; }, {name = \"glow.png\"; }, {name = \"lit.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; uTexture1 = {type = texture; value = 1; }; uTexture2 = {type = texture; value = 2; }; }" });
}


// Light maps: a colour only, a texture in illumination mode, one tinted black. The colour-only
// map is read as a texture specifier with no name (cxx_OOTextureSpecFromObject keeps a dictionary
// when there is no default name), which is invalid, so nothing is synthesized (but YES).
OO_TEST(lightMapColourOnlyFails)
{
	oo::PList::Array lightMaps{
		oo::PList(oo::PList::Dict{ { "color", Color(0, 1, 0) } }),
		oo::PList(oo::PList::Dict{ { "name", oo::PList("a.png") }, { "illumination_mode", oo::PList(true) } }),
		oo::PList(oo::PList::Dict{ { "name", oo::PList("b.png") }, { "color", Color(0, 0, 0) } }),
	};
	Synthesized s = Synthesize({ { "light_map", oo::PList(std::move(lightMaps)) } }, std::string("hull.png"));
	OO_CHECK(s.ok);
	OO_CHECK(s.vertex.empty());
	OO_CHECK(s.fragment.empty());
	OO_CHECK(s.textures.isNull());
	OO_CHECK(s.uniforms.isNull());
}


// A colour-only light map and one with neither colour nor name: both are texture specifiers with
// no name, so nothing is synthesized (but YES).
OO_TEST(lightMapWithNoNameFails)
{
	oo::PList::Array lightMaps{
		oo::PList(oo::PList::Dict{ { "color", Color(0, 1, 0) } }),
		oo::PList(oo::PList::Dict{}),
	};
	Synthesized s = Synthesize({ { "light_map", oo::PList(std::move(lightMaps)) } }, std::string("hull.png"));
	OO_CHECK(s.ok);
	OO_CHECK(s.vertex.empty());
	OO_CHECK(s.fragment.empty());
	OO_CHECK(s.textures.isNull());
	OO_CHECK(s.uniforms.isNull());
}


// One texture used for two maps is sampled once, with one sampler uniform.
OO_TEST(sharedTexture)
{
	Synthesized s = Synthesize({ { "diffuse_map", oo::PList("same.png") }, { "emission_map", oo::PList("same.png") } }, std::string("hull.png"));
	CheckSynthesized("sharedTexture", s, {
		"// Attributes\n"
		"attribute vec3\t\ttangent;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvTexCoords = gl_MultiTexCoord0.st;\n"
		"\t\n"
		"\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
		"\tgl_Position = gl_ProjectionMatrix * position;\n"
		"\t\n"
		"\t// Build tangent space basis\n"
		"\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
		"\tvec3 t = gl_NormalMatrix * tangent;\n"
		"\tvec3 b = cross(n, t);\n"
		"\tmat3 TBN = mat3(t, b, n);\n"
		"\t\n"
		"\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
		"\tvLightVector = lightVector * TBN;\n"
		"\t\n"
		"\tvEyeVector = position.xyz * TBN;\n"
		"}",
		"// Uniforms\n"
		"uniform sampler2D\tuTexture0;\n"
		"\n"
		"\n"
		"// Varyings\n"
		"varying vec2\t\tvTexCoords;\n"
		"varying vec3\t\tvLightVector;\n"
		"varying vec3\t\tvEyeVector;\n"
		"\n"
		"\n"
		"void main(void)\n"
		"{\n"
		"\tvec3 totalColor = vec3(0.0);\n"
		"\t\n"
		"\tvec2 texCoords = vTexCoords;\n"
		"\tvec3 eyeVector = normalize(vEyeVector);\n"
		"\t\n"
		"\t\n"
		"\t// Texture lookups\n"
		"\tvec4 tex0Sample = texture2D(uTexture0, texCoords);  // same.png\n"
		"\t\n"
		"\tvec3 diffuseColor = tex0Sample.rgb;\n"
		"\t\n"
		"\tvec3 lightVector = normalize(vLightVector);\n"
		"\t\n"
		"\t// Diffuse (Lambertian) and ambient lighting\n"
		"\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, lightVector.z) + gl_LightModel.ambient).rgb;\n"
		"\t\n"
		"\t// Specular (Blinn-Phong) lighting\n"
		"\tvec3 specularColor = vec3(0.2, 0.2, 0.2);  // Constant colour\n"
		"\tconst float specularExponent = 10.0;\n"
		"\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n"
		"\tfloat specIntensity = dot(reflection, eyeVector);\n"
		"\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
		"\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n"
		"\t\n"
		"\tvec3 lightMapColor;\n"
		"\tlightMapColor = tex0Sample.rgb;\n"
		"\ttotalColor += lightMapColor;\n"
		"\t\n"
		"\ttotalColor += diffuseColor * diffuseLight;\n"
		"\tgl_FragColor = vec4(totalColor, 1.0);\n"
		"}",
		"({name = \"same.png\"; })",
		"{uTexture0 = {type = texture; value = 0; }; }" });
}


// A cube map cannot be used by the default shader: an error, and nothing synthesized (but YES).
OO_TEST(cubeMapFails)
{
	oo::PList::Dict map{ { "name", oo::PList("cube.png") }, { "cube_map", oo::PList(true) } };
	Synthesized s = Synthesize({ { "diffuse_map", oo::PList(std::move(map)) } }, std::string("hull.png"));
	OO_CHECK(s.ok);
	OO_CHECK(s.vertex.empty());
	OO_CHECK(s.fragment.empty());
	OO_CHECK(s.textures.isNull());
	OO_CHECK(s.uniforms.isNull());
	OO_CHECK_EQ(LogLinesContaining("specifies a cube map texture"), 1);
}


// --- The C++ class and its facade (bead oo-bm1q) -------------------------------------------------

// The C++ synthesizer, run directly, answers what the entry point wrote; it keeps the material key
// and (as upstream did) not the entity name.
OO_TEST(cxxSynthesizerAnswersAsTheEntryPoint)
{
	Synthesized expected = Synthesize({ { "specular", Color(1, 1, 1) }, { "shininess", oo::PList(20) } }, std::string("hull.png"));
	@autoreleasepool
	{
		oo::Ref<cxx::OODefaultShaderSynthesizer> synthesizer = oo::makeRef<cxx::OODefaultShaderSynthesizer>(oo::PList(oo::PList::Dict{ { "specular", Color(1, 1, 1) }, { "shininess", oo::PList(20) } }), std::string("hull.png"), std::string("test entity"));
		OO_CHECK(synthesizer->run());
		OO_CHECK(synthesizer->vertexShader() == expected.vertex);
		OO_CHECK(synthesizer->fragmentShader() == expected.fragment);
		OO_CHECK(synthesizer->textureSpecifications() == expected.textures);
		OO_CHECK(synthesizer->uniformSpecifications() == expected.uniforms);
		OO_CHECK(synthesizer->materialKey() == std::optional<std::string>("hull.png"));
		OO_CHECK(!synthesizer->entityName().has_value());
	}
}


// The facade: one per C++ object, nil for null, the C++ object behind it, the same answers; and a
// facade made from Objective-C is its object's facade.
OO_TEST(facadeContract)
{
	@autoreleasepool
	{
		oo::Ref<cxx::OODefaultShaderSynthesizer> synthesizer = oo::makeRef<cxx::OODefaultShaderSynthesizer>(oo::PList(oo::PList::Dict{}), std::string("hull.png"), std::nullopt);
		OODefaultShaderSynthesizer *facade = oo::ToObjC(synthesizer);
		OO_CHECK(facade != nil);
		OO_CHECK(oo::ToObjC(synthesizer) == facade);
		OO_CHECK(oo::ToCxx(facade) == synthesizer.get());
		OO_CHECK(oo::ToObjC(static_cast<cxx::OODefaultShaderSynthesizer *>(nullptr)) == nil);
		OO_CHECK(oo::ToCxx(static_cast<OODefaultShaderSynthesizer *>(nil)) == nullptr);
		
		OO_CHECK([facade run]);
		OO_CHECK([facade vertexShader] == synthesizer->vertexShader());
		OO_CHECK([facade fragmentShader] == synthesizer->fragmentShader());
		OO_CHECK([facade textureSpecifications] == synthesizer->textureSpecifications());
		OO_CHECK([facade uniformSpecifications] == synthesizer->uniformSpecifications());
		OO_CHECK([facade materialKey] == synthesizer->materialKey());
		
		OODefaultShaderSynthesizer *made = [[[OODefaultShaderSynthesizer alloc] initWithMaterialConfiguration:oo::PList(oo::PList::Dict{}) materialKey:std::string("hull.png") entityName:std::nullopt] autorelease];
		OO_CHECK(oo::ToCxx(made) != nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);
		OO_CHECK([made run]);
		OO_CHECK([made fragmentShader] == synthesizer->fragmentShader());
	}
}


OO_TEST_MAIN()
