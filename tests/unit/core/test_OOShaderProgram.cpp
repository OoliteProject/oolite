/*	test_OOShaderProgram.mm
	Unit tests for OOShaderProgram (src/Core/Materials/OOShaderProgram.h): bead oo-f9zg.

	A linked GLSL program, made from sources or from shader files and shared through a cache keyed
	by what made it. This pins, through the C++ API its callers use (OOShaderMaterial,
	OOShaderUniform, DustEntity, Universe), what it did before the conversion, in a hidden GL context: the
	programs made (the prefix prepended, an empty prefix counting as none, the attribute bindings),
	the failures (no source, a source that does not compile, a file that is not there), the cache
	(one program per key while it lives, none without a key, a new one once it has gone), the
	files asked for, and apply() / applyNone() (the program in use, kept while it is). There is no
	game view here, so no standard matrix uniforms are bound. Those checks ran on the Objective-C
	class first, then through its facade; bead oo-9ht.58 deleted the facade (ADR-0049, standing
	approval oo-9n5p9): the cases ask the C++ class with the same expectations (null for nil, a
	held Ref for retain/release) and the facade's own case (facade) was retired with it.
	Run: bash tools/check-core-tests.sh
*/

#include "OOShaderProgram.h"
#include "OORegExpMatcher.h"
#include "OODescription.h"
#include "MyOpenGLView.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

#include <map>
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

// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
std::vector<std::string> ResourceManager::paths()  { return {}; }
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &/*fileName*/, const std::optional<std::string> &/*folderName*/, bool /*mergeFiles*/)  { return oo::PList(oo::PList::Dict{}); }
std::optional<std::string> ResourceManager::stringFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName)
{
	gShaderFileRequests.push_back(folderName.value_or("") + "/" + fileName);
	auto found = gShaderFiles.find(fileName);
	if (found == gShaderFiles.end())  return std::nullopt;
	return found->second;
}



// OORegExpMatcher is C++ since its facade was deleted (bead oo-9ht.12): the stub answers no match.
oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher()  { return oo::makeRef<OORegExpMatcher>(); }
bool OORegExpMatcher::string(const std::string &, const std::string &)  { return false; }
OORegExpMatcher::~OORegExpMatcher()  {}


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


// UNIVERSE is gSharedUniverse: nil, so there is no game view and no matrix manager. The view is
// C++ (MyOpenGLView; its facade's crossing went with bead oo-9ht.153), and its manager accessor is
// never reached.
class Universe;
Universe *gSharedUniverse = nil;

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

		/*	A failed initialiser leaves exactly one GL_INVALID_VALUE behind (observed on the
			Objective-C class before its conversion: its teardown deletes program 0), and a
			successful one none.
		*/
		OO_CHECK(Make(std::nullopt, std::nullopt) == nullptr);	// none is not
		OO_CHECK(glGetError() == GL_INVALID_VALUE && glGetError() == GL_NO_ERROR);

		// The prefix is prepended to both sources; an empty one is none.
		OO_CHECK(Make(kVertex, kFragmentNeedingPrefix) == nullptr);
		OO_CHECK(glGetError() == GL_INVALID_VALUE && glGetError() == GL_NO_ERROR);
		OO_CHECK(Make(kVertex, kFragmentNeedingPrefix, std::string("")) == nullptr);
		OO_CHECK(glGetError() == GL_INVALID_VALUE && glGetError() == GL_NO_ERROR);
		OO_CHECK(Make(kVertex, kFragmentNeedingPrefix, std::string("#define PREFIXED 0.5\n")) != nullptr);
		OO_CHECK(glGetError() == GL_NO_ERROR);

		OO_CHECK(Make(std::string("this is not GLSL"), kFragment) == nullptr);	// does not compile
		OO_CHECK(glGetError() == GL_INVALID_VALUE && glGetError() == GL_NO_ERROR);
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


OO_TEST_MAIN()
