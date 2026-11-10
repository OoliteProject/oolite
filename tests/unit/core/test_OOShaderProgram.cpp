/*	test_OOShaderProgram.mm
	Unit tests for OOShaderProgram (src/Core/Materials/OOShaderProgram.h).

	A linked GLSL program, made from sources or from shader files and shared through a cache keyed
	by what made it. This pins, through the C++ API its callers use (OOShaderMaterial,
	OOShaderUniform, DustEntity, Universe), what it did before the conversion, in a hidden GL
	context: the programs made (the prefix prepended, an empty prefix counting as none, the
	attribute bindings), the failures (no source, a source that does not compile, a file that is not
	there), the cache (one program per key while it lives, none without a key, a new one once it has
	gone), the files asked for, and apply() / applyNone() (the program in use, kept while it is).
	There is no game view here, so no standard matrix uniforms are bound. The cases ask the C++
	class (null for nil, a
	held Ref for retain/release). Run: bash tools/check-core-tests.sh
*/

#include "OOShaderProgram.h"
#include "OORegExpMatcher.h"
#include "OODescription.h"
#include "MyOpenGLView.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <regex>
#include <sstream>
#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

// OOLogging.mm's (it would bring the resource manager into the link).
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}
const char *const cxx_kOOLogFileNotFound = "files.notFound";


// The resource manager: the extension manager's two class methods, and shader files from a table.
static std::map<std::string, std::string> gShaderFiles;
static std::vector<std::string> gShaderFileRequests;

#include "ResourceManager.h"

// ResourceManager: C++ definitions of the statics the code under test calls,
// with the stand-in's answers.
std::vector<std::string> ResourceManager::paths()  { return {}; }
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &/*fileName*/, const std::optional<std::string> &/*folderName*/, bool /*mergeFiles*/)  { return oo::PList(oo::PList::Dict{}); }
std::optional<std::string> ResourceManager::stringFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName)
{
	gShaderFileRequests.push_back(folderName.value_or("") + "/" + fileName);
	auto found = gShaderFiles.find(fileName);
	if (found == gShaderFiles.end())  return std::nullopt;
	return found->second;
}



// OORegExpMatcher stub: answers no match.
oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher()  { return oo::makeRef<OORegExpMatcher>(); }
bool OORegExpMatcher::string(const std::string &, const std::string &)  { return false; }
OORegExpMatcher::~OORegExpMatcher()  {}


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


// UNIVERSE is gSharedUniverse: nil, so there is no game view and no matrix
// manager. The view is C++ (MyOpenGLView), and its manager accessor is never
// reached.
class Universe;
Universe *gSharedUniverse = nullptr;

OOOpenGLMatrixManager *MyOpenGLView::getOpenGLMatrixManager()  { return matrixManager.get(); }


namespace {

const std::string kVertex =
	"attribute vec3 tangent;\n"
	"void main() { gl_Position = gl_Vertex + vec4(tangent, 0.0); }\n";
const std::string kFragment =
	"void main() { gl_FragColor = vec4(1.0); }\n";
const std::string kFragmentNeedingPrefix =
	"void main() { gl_FragColor = vec4(PREFIXED); }\n";

const oo::PList kBindings = oo::PList(oo::PList::Dict{ { "tangent", oo::PList::signedInteger(15) } });


typedef GLint (APIENTRY *GetAttribLocationProc)(GLhandleARB, const GLcharARB *);
typedef GLboolean (APIENTRY *IsProgramProc)(GLuint);
GetAttribLocationProc gGetAttribLocation = nullptr;
IsProgramProc gIsProgram = nullptr;


bool SetUp()
{
	if (!OOTestGLContext())  return false;
	OOOpenGLExtensionManager::sharedManager();	// loads the ARB shader entry points
	gGetAttribLocation = (GetAttribLocationProc)SDL_GL_GetProcAddress("glGetAttribLocationARB");
	gIsProgram = (IsProgramProc)SDL_GL_GetProcAddress("glIsProgram");
	return gGetAttribLocation != nullptr && gIsProgram != nullptr;
}


oo::Ref<OOShaderProgram> Make(const std::optional<std::string> &vertex, const std::optional<std::string> &fragment, const std::optional<std::string> &prefix = std::nullopt, const std::optional<std::string> &key = std::nullopt)
{
	return OOShaderProgram::shaderProgramWithVertexShader(vertex, fragment, std::string("v"), std::string("f"), prefix, kBindings, key);
}


GLint CurrentProgram()
{
	GLint current = -1;
	glGetIntegerv(GL_CURRENT_PROGRAM, &current);
	return current;
}


/*	A failed initialiser's teardown deletes program 0 (glDeleteObjectARB(0), as upstream's -dealloc
	does). Drivers differ there: NVIDIA reports GL_INVALID_VALUE, Mesa ignores it (as every driver
	ignores glDeleteProgram(0)). That one error or none, and nothing else, is left behind.
*/
bool OnlyTheTeardownsError()
{
	const GLenum first = glGetError();
	return (first == GL_INVALID_VALUE || first == GL_NO_ERROR) && glGetError() == GL_NO_ERROR;
}

}	// namespace


OO_TEST(programsFromSources)
{
	if (!SetUp())  { OO_CHECK(false); return; }
	{
		oo::Ref<OOShaderProgram> p = Make(kVertex, kFragment);
		OO_CHECK(p != nullptr && p->program() != 0);
		OO_CHECK(gGetAttribLocation(p->program(), "tangent") == 15);	// the attribute bindings

		OO_CHECK(Make(std::nullopt, kFragment) != nullptr);	// one shader is enough
		OO_CHECK(Make(kVertex, std::nullopt) != nullptr);
		OO_CHECK(glGetError() == GL_NO_ERROR);

		/*	A failed initialiser leaves at most its teardown's error behind (OnlyTheTeardownsError),
			and a successful one none.
		*/
		OO_CHECK(Make(std::nullopt, std::nullopt) == nullptr);	// none is not
		OO_CHECK(OnlyTheTeardownsError());

		// The prefix is prepended to both sources; an empty one is none.
		OO_CHECK(Make(kVertex, kFragmentNeedingPrefix) == nullptr);
		OO_CHECK(OnlyTheTeardownsError());
		OO_CHECK(Make(kVertex, kFragmentNeedingPrefix, std::string("")) == nullptr);
		OO_CHECK(OnlyTheTeardownsError());
		OO_CHECK(Make(kVertex, kFragmentNeedingPrefix, std::string("#define PREFIXED 0.5\n")) != nullptr);
		OO_CHECK(glGetError() == GL_NO_ERROR);

		OO_CHECK(Make(std::string("this is not GLSL"), kFragment) == nullptr);	// does not compile
		OO_CHECK(OnlyTheTeardownsError());
	}
}


OO_TEST(cache)
{
	if (!SetUp())  { OO_CHECK(false); return; }
	oo::Ref<OOShaderProgram> kept;
	GLhandleARB handle = 0;
	{
		oo::Ref<OOShaderProgram> a = Make(kVertex, kFragment, std::nullopt, std::string("key-a"));
		OO_CHECK(a != nullptr && Make(kVertex, kFragment, std::nullopt, std::string("key-a")) == a);	// one per key
		OO_CHECK(Make(std::string("anything: it is not compiled"), std::nullopt, std::nullopt, std::string("key-a")) == a);
		OO_CHECK(Make(kVertex, kFragment, std::nullopt, std::string("key-b")) != a);
		OO_CHECK(Make(kVertex, kFragment).get() != Make(kVertex, kFragment).get());	// no key: never shared
		kept = a;
		handle = a->program();
	}
	{
		// Still alive (kept): still the cached one.
		OO_CHECK(Make(kVertex, kFragment, std::nullopt, std::string("key-a")) == kept);
	}
	kept = nullptr;
	{
		// Gone: the cache forgot it, and its GL program was deleted.
		OO_CHECK(!gIsProgram(handle));
		oo::Ref<OOShaderProgram> again = Make(kVertex, kFragment, std::nullopt, std::string("key-a"));
		OO_CHECK(again != nullptr && again->program() != 0);
	}
}


OO_TEST(programsFromFiles)
{
	if (!SetUp())  { OO_CHECK(false); return; }
	{
		gShaderFiles = { { "test.vertex", kVertex }, { "test.frag", kFragment }, { "other.vert", kVertex } };
		gShaderFileRequests.clear();

		// Each name bare, then with its type's two extensions until one is found.
		oo::Ref<OOShaderProgram> p = OOShaderProgram::shaderProgramWithVertexShaderName("test", "test", std::nullopt, kBindings);
		OO_CHECK(p != nullptr && gGetAttribLocation(p->program(), "tangent") == 15);
		OO_CHECK(gShaderFileRequests == (std::vector<std::string>{ "Shaders/test", "Shaders/test.vertex", "Shaders/test", "Shaders/test.fragment", "Shaders/test.frag" }));

		// Cached by the names and the prefix: the files are not read again.
		gShaderFileRequests.clear();
		OO_CHECK(OOShaderProgram::shaderProgramWithVertexShaderName("test", "test", std::string(""), kBindings) == p);
		OO_CHECK(gShaderFileRequests.empty());
		oo::Ref<OOShaderProgram> prefixed = OOShaderProgram::shaderProgramWithVertexShaderName("test", "test", std::string("#define UNUSED 1\n"), kBindings);
		OO_CHECK(prefixed != nullptr && prefixed != p && gShaderFileRequests.size() == 5);

		// A name with one of the extensions is not extended; a file that is not there fails.
		gShaderFileRequests.clear();
		OO_CHECK(OOShaderProgram::shaderProgramWithVertexShaderName("other.vert", "missing.frag", std::nullopt, kBindings) == nullptr);
		OO_CHECK(gShaderFileRequests == (std::vector<std::string>{ "Shaders/other.vert", "Shaders/missing.frag" }));
		gShaderFiles.clear();
	}
}


OO_TEST(applyAndApplyNone)
{
	if (!SetUp())  { OO_CHECK(false); return; }
	oo::Ref<OOShaderProgram> p;
	{
		p = Make(kVertex, kFragment);
		oo::Ref<OOShaderProgram> q = Make(kVertex, kFragment);
		const unsigned retained = p->retainCount();
		p->apply();
		OO_CHECK(CurrentProgram() == (GLint)p->program());
		OO_CHECK(p->retainCount() == retained + 1);	// kept while in use
		p->apply();	// again: no change
		OO_CHECK(p->retainCount() == retained + 1);
		q->apply();
		OO_CHECK(CurrentProgram() == (GLint)q->program() && p->retainCount() == retained);
		OOShaderProgram::applyNone();
		OO_CHECK(CurrentProgram() == 0);
		OOShaderProgram::applyNone();	// nothing in use: nothing
		OO_CHECK(CurrentProgram() == 0);
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
	p = nullptr;
}


// --- The C++ API ----------------------------------------------------------------------------------

OO_TEST(cxxAPI)
{
	if (!SetUp())  { OO_CHECK(false); return; }
	{
		OO_CHECK(OOShaderProgram::shaderProgramWithVertexShader(std::nullopt, std::nullopt, std::nullopt, std::nullopt, std::nullopt, kBindings, std::nullopt) == nullptr);
		const oo::Ref<OOShaderProgram> p = OOShaderProgram::shaderProgramWithVertexShader(kVertex, kFragment, std::string("v"), std::string("f"), std::nullopt, kBindings, std::string("cxx-key"));
		OO_CHECK(p != nullptr && p->program() != 0 && gGetAttribLocation(p->program(), "tangent") == 15);

		// The cache shares it.
		OO_CHECK(OOShaderProgram::shaderProgramWithVertexShader(std::nullopt, std::nullopt, std::nullopt, std::nullopt, std::nullopt, kBindings, std::string("cxx-key")).get() == p.get());
		OO_CHECK(Make(kVertex, kFragment, std::nullopt, std::string("cxx-key")).get() == p.get());

		gShaderFiles = { { "c.vert", kVertex }, { "c.frag", kFragment } };
		const oo::Ref<OOShaderProgram> fromFiles = OOShaderProgram::shaderProgramWithVertexShaderName("c.vert", "c.frag", std::nullopt, kBindings);
		OO_CHECK(fromFiles != nullptr && fromFiles.get() == OOShaderProgram::shaderProgramWithVertexShaderName("c.vert", "c.frag", std::nullopt, kBindings).get());
		OO_CHECK(OOShaderProgram::shaderProgramWithVertexShaderName("none.vert", "c.frag", std::nullopt, kBindings) == nullptr);
		gShaderFiles.clear();

		p->apply();
		OO_CHECK(CurrentProgram() == (GLint)p->program());
		OOShaderProgram::applyNone();
		OO_CHECK(CurrentProgram() == 0);
	}
}


// --- OOTranslateGLSL330To120 (upstream #766, used on macOS) ----------------------------------------------------

namespace {

// A shader from Resources/Shaders, found from this file's directory or the working directory upwards;
// empty when it is not there.
std::string ShaderFile(const std::string &name)
{
	namespace fs = std::filesystem;
	const fs::path rel = fs::path("Resources") / "Shaders" / name;
	for (const fs::path &start : { fs::path(__FILE__).parent_path(), fs::current_path() })
	{
		std::error_code ec;
		fs::path dir = fs::absolute(start, ec);
		for (int i = 0; i < 8 && !dir.empty(); i++)
		{
			if (fs::exists(dir / rel, ec))
			{
				std::ifstream in(dir / rel, std::ios::binary);
				std::stringstream text;
				text << in.rdbuf();
				return text.str();
			}
			if (dir == dir.parent_path())  break;
			dir = dir.parent_path();
		}
	}
	return std::string();
}


bool Contains(const std::string &text, const std::string &part)
{
	return text.find(part) != std::string::npos;
}


// What upstream's regular-expression rewrite gives, run through the C++ one.
std::string Translated(const std::string &source, bool isVertexShader, oo::PList::Dict &bindings)
{
	return OOTranslateGLSL330To120(source, isVertexShader, bindings).value_or("(null)");
}


const std::string kGLSL120Prefix = "#version 120\n#extension GL_EXT_gpu_shader4 : enable\n";

}	// namespace


OO_TEST(translateGLSL330To120)
{
	oo::PList::Dict bindings;
	OO_CHECK(OOTranslateGLSL330To120(std::nullopt, true, bindings) == std::nullopt);
	OO_CHECK(bindings.empty());

	// Vertex: located inputs become attributes and bindings, outputs varyings.
	OO_CHECK_EQ(Translated("layout (location = 0) in vec3 aPos;\n"
	                       "layout(location=3) in vec2 aTexCoords;\n"
	                       "out vec2 TexCoords;\n"
	                       "void main() { TexCoords = aTexCoords; }\n", true, bindings),
	            std::string("attribute vec3 aPos;\n"
	                        "attribute vec2 aTexCoords;\n"
	                        "varying vec2 TexCoords;\n"
	                        "void main() { TexCoords = aTexCoords; }\n"));
	OO_CHECK(bindings.size() == 2);
	OO_CHECK(bindings["aPos"] == oo::PList::signedInteger(0));
	OO_CHECK(bindings["aTexCoords"] == oo::PList::signedInteger(3));

	// Fragment: vec4 outputs become gl_FragData defines (location 0 when none is given), inputs
	// varyings; texture() and textureSize() take their 1.20 names, and a qualifier inside a function
	// is left alone.
	bindings.clear();
	OO_CHECK_EQ(Translated("layout (location = 1) out vec4 bright;\n"
	                       "out vec4 FragColor;\n"
	                       "in vec2 TexCoords;\n"
	                       "uniform sampler2D image;\n"
	                       "void f(in float x, out float y) { y = x; }\n"
	                       "void main() {\n"
	                       "\tvec2 s = 1.0 / textureSize(image, 0);\n"
	                       "\tFragColor = texture (image, TexCoords);\n"
	                       "\tbright = texture2D(image, s);\n"
	                       "}\n", false, bindings),
	            std::string("#define bright gl_FragData[1]\n"
	                        "#define FragColor gl_FragData[0]\n"
	                        "varying vec2 TexCoords;\n"
	                        "uniform sampler2D image;\n"
	                        "void f(in float x, out float y) { y = x; }\n"
	                        "void main() {\n"
	                        "\tvec2 s = 1.0 / textureSize2D(image, 0);\n"
	                        "\tFragColor = texture2D(image, TexCoords);\n"
	                        "\tbright = texture2D(image, s);\n"
	                        "}\n"));
	OO_CHECK(bindings.empty());

	// isnan() is not in GLSL 1.20: a shim is prepended and called instead.
	OO_CHECK_EQ(Translated("void main() { bool b = isnan(1.0) || isnan (2.0); }\n", false, bindings),
	            std::string("bool oo_isnan(float x) { return !(x < 0.0 || x > 0.0 || x == 0.0); }\n"
	                        "void main() { bool b = oo_isnan(1.0) || oo_isnan(2.0); }\n"));
}


OO_TEST(translateGameShadersGLSL330To120)
{
	struct Program { const char *vertex; const char *fragment; };
	const Program programs[] = {
		{ "oolite-texture.vertex", "oolite-texture.fragment" },
		{ "oolite-blur.vertex", "oolite-blur.fragment" },
		{ "oolite-final.vertex", "oolite-final.fragment" },
	};
	const std::regex texture330(R"(\btexture\s*\()");
	const std::regex inOut330(R"(^\s*(in|out)\s)", std::regex::ECMAScript | std::regex::multiline);
	const bool canCompile = SetUp() && OOOpenGLExtensionManager::sharedManager()->haveExtension("GL_EXT_gpu_shader4");
	if (!canCompile)  std::printf("note: no GL_EXT_gpu_shader4, so the translated game shaders are not compiled\n");

	for (const Program &program : programs)
	{
		const std::string vertex330 = ShaderFile(program.vertex);
		const std::string fragment330 = ShaderFile(program.fragment);
		OO_CHECK(!vertex330.empty() && !fragment330.empty());
		oo::PList::Dict bindings;
		const std::string vertex = Translated(vertex330, true, bindings);
		const std::string fragment = Translated(fragment330, false, bindings);

		// Every game vertex shader takes its two inputs at locations 0 and 1.
		OO_CHECK(bindings.size() == 2);
		for (const auto &[name, location] : bindings)
			OO_CHECK(location == oo::PList::signedInteger(0) || location == oo::PList::signedInteger(1));
		for (const std::string *translated : { &vertex, &fragment })
		{
			OO_CHECK(!Contains(*translated, "layout"));
			OO_CHECK(!std::regex_search(*translated, texture330));
			OO_CHECK(!std::regex_search(*translated, inOut330));
		}
		OO_CHECK(Contains(vertex, "attribute "));
		OO_CHECK(Contains(vertex, "varying "));
		OO_CHECK(Contains(fragment, "gl_FragData[0]"));
		OO_CHECK(Contains(fragment, "varying "));
		OO_CHECK(Contains(fragment, "isnan(") == Contains(fragment, "bool oo_isnan(float x)"));

		if (canCompile)
		{
			// GLSL 1.20 with GL_EXT_gpu_shader4, as the macOS legacy context runs it.
			{
				oo::Ref<OOShaderProgram> compiled = Make(vertex, fragment, kGLSL120Prefix);
				if (compiled == nullptr)  std::printf("FAIL: %s + %s do not compile as GLSL 1.20\n", program.vertex, program.fragment);
				OO_CHECK(compiled != nullptr);
			}
		}
	}
	// The texture program's two outputs go to the two colour attachments.
	oo::PList::Dict bindings;
	const std::string texture = Translated(ShaderFile("oolite-texture.fragment"), false, bindings);
	OO_CHECK(Contains(texture, "#define out_color gl_FragData[0]"));
	OO_CHECK(Contains(texture, "#define bright_color gl_FragData[1]"));
}

OO_TEST_MAIN()
