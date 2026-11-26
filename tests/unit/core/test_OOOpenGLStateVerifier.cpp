/*	test_OOOpenGLStateVerifier.cpp
        Characterisation test for the OpenGL state verifier in
   src/Core/OOOpenGLStateManager.cpp (OOVerifyOpenGLState(), debug builds).

        With the context in OPENGL_STATE_OPAQUE, the test changes GL behind the
   state manager's back, one item of each kind, then calls OOVerifyOpenGLState()
   and checks what the verifier logs to rendering.opengl.state: one line per
   mismatched item, in the state list's order, each item shown as the verifier
   shows it (flags, client-array flags and the special items as
   ENABLED/disabled, integers as GL enumerants), then the blend mode. It also
   checks that an item the state leaves open (LIGHT0) is not reported, and that
   the verifier puts GL back as the state says. The GL context and stubs are
   test_OOOpenGLStateManager's. Run: tests/run.sh unit
*/

#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

#include "OOOpenGL.h"
#include "OOOpenGLExtensionManager.h"
#include "OORegExpMatcher.h"
#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/PList.hpp"

// --- Stubs (as test_OOOpenGLStateManager's)
// ----------------------------------------------------

#include "ResourceManager.h"

std::vector<std::string> ResourceManager::paths() { return {}; }
oo::PList ResourceManager::dictionaryFromFilesNamed(
    const std::string& /*fileName*/,
    const std::optional<std::string>& /*folderName*/, bool /*mergeFiles*/) {
  return oo::PList(oo::PList::Dict{});
}

std::shared_ptr<OORegExpMatcher> OORegExpMatcher::regExpMatcher() {
  return oo::makeShared<OORegExpMatcher>();
}
bool OORegExpMatcher::string(const std::string&, const std::string&) {
  return false;
}
OORegExpMatcher::~OORegExpMatcher() {}

OOShaderSetting OOShaderSettingFromString(const std::string& string) {
  return string == "SHADERS_FULL" ? OOShaderSetting::kFull : OOShaderSetting::kNotSupported;
}

void OOLogIndent(void) {}
void OOLogOutdent(void) {}

// --- The log
// -----------------------------------------------------------------------------------

namespace {

constexpr std::string_view kVerifierClass = "rendering.opengl.state";

std::vector<std::string> sLog;

void Capture(std::string_view line) {
  sLog.emplace_back(line);
  std::fprintf(stderr, "log: %s\n", sLog.back().c_str());
}

void CaptureLog() {
  oo::log::Logger& logger = oo::log::logger();
  logger.setInitialized(true);
  logger.setDisplay(kVerifierClass, true);
  logger.setSink(&Capture);
  sLog.clear();
}

// The captured lines that report an item ("should be"), in order.
std::vector<std::string> MismatchLines() {
  std::vector<std::string> lines;
  for (const std::string& line : sLog) {
    if (line.find(" should be ") != std::string::npos) lines.push_back(line);
  }
  return lines;
}

bool Contains(const std::string& line, std::string_view text) {
  return line.find(text) != std::string::npos;
}

bool AnyLineContains(std::string_view text) {
  for (const std::string& line : sLog) {
    if (Contains(line, text)) return true;
  }
  return false;
}

GLint Integer(GLenum name) {
  GLint value = -1;
  glGetIntegerv(name, &value);
  return value;
}

// GL's defaults, which the state manager calls its canonical initial state,
// then OPENGL_STATE_OPAQUE.
void StartInOpaque() {
  glDisable(GL_LIGHTING);
  glDisable(GL_LIGHT0);
  glDisable(GL_TEXTURE_2D);
  glDisable(GL_BLEND);
  glDisable(GL_FOG);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glDisableClientState(GL_VERTEX_ARRAY);
  glDisableClientState(GL_NORMAL_ARRAY);
  glDepthMask(GL_TRUE);
  glShadeModel(GL_SMOOTH);
  glActiveTextureARB(GL_TEXTURE0);
  glBlendFunc(GL_ONE, GL_ZERO);
  OOResetGLStateVerifier();
  OOSetOpenGLState(OOOpenGLStateID::kOpaque);
}

}  // namespace

// --- Tests
// --------------------------------------------------------------------------------------

OO_TEST(anOpenItemIsNotReported) {
  OO_CHECK(OOTestGLContext());
  (void)OOOpenGLExtensionManager::sharedManager();  // loads glActiveTextureARB
                                                    // & co.
  StartInOpaque();
  CaptureLog();

  glEnable(GL_LIGHT0);  // OPENGL_STATE_OPAQUE leaves LIGHT0 open
  OOVerifyOpenGLState();

  OO_CHECK(MismatchLines().empty());
  OO_CHECK(!AnyLineContains("Incorrect OpenGL state"));
  glDisable(GL_LIGHT0);
  OO_CHECK(glGetError() == GL_NO_ERROR);
}

OO_TEST(mismatchesAreReportedInOrderAndRepaired) {
  OO_CHECK(OOTestGLContext());
  (void)OOOpenGLExtensionManager::sharedManager();
  StartInOpaque();
  CaptureLog();

  // One item of each kind, changed in reverse of the list's order.
  glBlendFunc(GL_ONE, GL_ONE);               // the blend mode
  glActiveTextureARB(GL_TEXTURE1);           // a GLenum special item
  glShadeModel(GL_FLAT);                     // an integer item
  glDepthMask(GL_FALSE);                     // a bool special item
  glDisableClientState(GL_NORMAL_ARRAY);     // a client-array flag
  glDisable(GL_DEPTH_TEST);                  // a flag
  OOVerifyOpenGLState();

  OO_CHECK(AnyLineContains("Incorrect OpenGL state in "));
  OO_CHECK(AnyLineContains("->OOVerifyOpenGLState"));
  OO_CHECK(AnyLineContains("Expected previous state: OPENGL_STATE_OPAQUE"));

  const std::vector<std::string> lines = MismatchLines();
  const std::vector<std::string_view> expected = {
      // TEXTURE_2D is read for the active texture unit, which is now unit 1.
      "GL_TEXTURE_2D should be ENABLED but is disabled.",
      "GL_DEPTH_TEST should be ENABLED but is disabled.",
      "GL_NORMAL_ARRAY should be ENABLED but is disabled.",
      "GL_DEPTH_WRITEMASK should be ENABLED but is disabled.",
      "GL_SHADE_MODEL should be GL_SMOOTH but is GL_FLAT.",
      // The special items are shown as flags, whatever their type.
      "GL_ACTIVE_TEXTURE should be ENABLED but is ENABLED.",
      "GL blend mode should be GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA but is "
      "GL_ONE, GL_ONE.",
  };
  OO_CHECK(lines.size() == expected.size());
  for (std::size_t i = 0; i < lines.size() && i < expected.size(); ++i) {
    if (!Contains(lines[i], expected[i]))
      std::fprintf(stderr, "line %zu: expected \"%.*s\"\n", i,
                   static_cast<int>(expected[i].size()), expected[i].data());
    OO_CHECK(Contains(lines[i], expected[i]));
  }

  // The verifier switched GL back to OPENGL_STATE_OPAQUE.
  GLboolean depthMask = GL_FALSE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);
  OO_CHECK(glIsEnabled(GL_DEPTH_TEST) == GL_TRUE);
  OO_CHECK(glIsEnabled(GL_NORMAL_ARRAY) == GL_TRUE);
  OO_CHECK(depthMask == GL_TRUE);
  OO_CHECK(Integer(GL_SHADE_MODEL) == GL_SMOOTH);
  OO_CHECK(Integer(GL_ACTIVE_TEXTURE_ARB) == GL_TEXTURE0);
  OO_CHECK(Integer(GL_BLEND_SRC) == GL_SRC_ALPHA);
  OO_CHECK(Integer(GL_BLEND_DST) == GL_ONE_MINUS_SRC_ALPHA);

  // So a second check finds nothing.
  sLog.clear();
  OOVerifyOpenGLState();
  OO_CHECK(MismatchLines().empty());
  OO_CHECK(glGetError() == GL_NO_ERROR);
}

OO_TEST_MAIN()
