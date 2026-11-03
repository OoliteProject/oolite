/*

Universe.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "Universe.h"

#include <vector>
#import "AI.h"
#import "GameController.h"
#import "GuiDisplayGen.h"
#import "HeadUpDisplay.h"
#import "MyOpenGLView.h"
#import "OOCPUInfo.h"
#import "OOCacheManager.h"
#import "OOColor.h"
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OODebugSupport.h"
#import "OOMaterial.h"
#import "OOOpenGLExtensionManager.h"
#import "OOOpenGLMatrixManager.h"
#import "OOPListView.h"
#import "OORoleSet.h"
#import "OOShipGroup.h"
#import "OOSound.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOTexture.h"
#import "ResourceManager.h"
#include "oofnd/Date.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Process.hpp"
#include "oofnd/objc/OOAssert.h"

#import "CollisionRegion.h"
#import "OODebugSupport.h"
#import "OOEntityFilterPredicate.h"
#import "OOGraphicsResetManager.h"
#import "Octree.h"

#import "OOCharacter.h"
#import "OOEquipmentType.h"
#import "OOProbabilitySet.h"
#import "OOShipLibraryDescriptions.h"
#import "OOShipRegistry.h"

#import "DockEntity.h"
#import "DustEntity.h"
#import "OOAsyncWorkManager.h"
#import "OOBreakPatternEntity.h"
#import "OODebugFlags.h"
#import "OODebugStandards.h"
#import "OOExplosionCloudEntity.h"
#import "OOFlashEffectEntity.h"
#import "OOFoundationException.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSFrameCallbacks.h"
#import "OOJSPopulatorDefinition.h"
#import "OOJSScript.h"
#import "OOJoystickManager.h"
#import "OOLightParticleEntity.h"
#import "OOLoggingExtended.h"
#import "OOMusicController.h"
#import "OOOpenGL.h"
#import "OOPlanetEntity.h"
#import "OORingEffectEntity.h"
#import "OOScriptTimer.h"
#import "OOShaderProgram.h"
#import "OOStringBridge.h"
#import "OOSunEntity.h"
#import "OOSystemDescriptionManager.h"
#import "OOVisualEffectEntity.h"
#import "OOWaypointEntity.h"
#import "PlayerEntity.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityScriptMethods.h"
#import "ProxyPlayerEntity.h"
#import "ShipEntityAI.h"
#import "SkyEntity.h"
#import "StationEntity.h"
#import "WormholeEntity.h"

#import "OOFoundationBridge.h" // oo::PListFrom, used by every build, not only OO_LOCALIZATION_TOOLS ones

#if OO_LOCALIZATION_TOOLS
#import "OOConvertSystemDescriptions.h"
#endif

enum {
    DEMO_FLY_IN = 101,
    DEMO_SHOW_THING,
    DEMO_FLY_OUT
};

#define DEMO2_VANISHING_DISTANCE 650.0
#define DEMO2_FLY_IN_STAGE_TIME 0.4

#define MAX_NUMBER_OF_ENTITIES 200
#define STANDARD_STATION_ROLL 0.4
// currently twice scanner radius
#define LANE_WIDTH 51200.0

static const char* const kOOLogUniversePopulateError = "universe.populate.error";
static const char* const kOOLogUniversePopulateWitchspace = "universe.populate.witchspace";
static const char* const kOOLogEntityVerificationError = "entity.linkedList.verify.error";
static const char* const kOOLogEntityVerificationRebuild = "entity.linkedList.verify.rebuild";

const GLfloat framebufferQuadVertices[] = {
    // positions  // texture coords
    1.0f, 1.0f, 1.0f, 1.0f, // top right
    1.0f, -1.0f, 1.0f, 0.0f, // bottom right
    -1.0f, -1.0f, 0.0f, 0.0f, // bottom left
    -1.0f, 1.0f, 0.0f, 1.0f // top left
};
const GLuint framebufferQuadIndices[] = {
    0, 1, 3, // first triangle
    1, 2, 3 // second triangle
};

Universe* gSharedUniverse = nil;

extern Entity* gOOJSPlayerIfStale;
Entity* gOOJSPlayerIfStale = nil;

static BOOL MaintainLinkedLists(Universe* uni);
OOINLINE BOOL EntityInRange(HPVector p1, Entity* e2, float range);

/* TODO: route calculation is really slow - find a way to safely enable this */
#undef CACHE_ROUTE_FROM_SYSTEM_RESULTS

@interface RouteElement : OOObject {
@private
    OOSystemID _location, _parent;
    double _cost, _distance, _time;
    int _jumps;
}

+ (instancetype)elementWithLocation:(OOSystemID)location parent:(OOSystemID)parent cost:(double)cost distance:(double)distance time:(double)time jumps:(int)jumps;
- (OOSystemID)parent;
- (OOSystemID)location;
- (double)cost;
- (double)distance;
- (double)time;
- (int)jumps;

@end

@implementation RouteElement

+ (instancetype)elementWithLocation:(OOSystemID)location parent:(OOSystemID)parent cost:(double)cost distance:(double)distance time:(double)time jumps:(int)jumps
{
    RouteElement* r = [[RouteElement alloc] init];

    r->_location = location;
    r->_parent = parent;
    r->_cost = cost;
    r->_distance = distance;
    r->_time = time;
    r->_jumps = jumps;

    return [r autorelease];
}

- (OOSystemID)parent
{
    return _parent;
}
- (OOSystemID)location
{
    return _location;
}
- (double)cost
{
    return _cost;
}
- (double)distance
{
    return _distance;
}
- (double)time
{
    return _time;
}
- (int)jumps
{
    return _jumps;
}

@end

@interface Universe (OOPrivate)

- (void)initTargetFramebufferWithViewSize:(NSSize)viewSize;
- (void)deleteOpenGLObjects;
- (void)resizeTargetFramebufferWithViewSize:(NSSize)viewSize;
- (void)prepareToRenderIntoDefaultFramebuffer;
- (void)drawTargetTextureIntoDefaultFramebuffer;

- (BOOL)doRemoveEntity:(Entity*)entity;
- (void)setUpCargoPods;
- (void)setUpInitialUniverse;
- (HPVector)fractionalPositionFrom:(HPVector)point0 to:(HPVector)point1 withFraction:(double)routeFraction;

- (void)populateSpaceFromActiveWormholes;

- (std::optional<std::string>)chooseStringForKey:(const std::string&)key inDictionary:(const oo::PList&)dictionary;

#if OO_LOCALIZATION_TOOLS
#if DEBUG_GRAPHVIZ
- (void)dumpDebugGraphViz;
- (void)dumpSystemDescriptionGraphViz;
#endif
- (void)addNumericRefsInString:(const std::string&)string toGraphViz:(std::string&)graphViz fromNode:(const std::string&)fromNode nodeCount:(NSUInteger)nodeCount;

/**
 * \ingroup cli
 * Scans the command line for --complie-sysdesc, --export-sysdec, --xml and --penstep arguments.
 */
- (void)runLocalizationTools;
#endif

#if NEW_PLANETS
- (void)prunePreloadingPlanetMaterials;
#endif

// Set shader effects level without logging or triggering a reset -- should only be used directly during startup.
- (void)setShaderEffectsLevelDirectly:(OOShaderSetting)value;

- (void)setFirstBeacon:(Entity<OOBeaconEntity>*)beacon;
- (void)setLastBeacon:(Entity<OOBeaconEntity>*)beacon;

- (void)verifyDescriptions;
- (void)loadDescriptions;
- (void)loadScenarios;

- (void)verifyEntitySessionIDs;
- (float)randomDistanceWithinScanner;
- (Vector)randomPlaceWithinScannerFrom:(Vector)pos alongRoute:(Vector)route withOffset:(double)offset;

- (void)setDetailLevelDirectly:(OOGraphicsDetail)value;

- (oo::PList)demoShipData; // null where there is no such entry
- (void)setLibraryTextForDemoShip;

@end

namespace {

// The saved detailLevel preference as an OOGraphicsDetail. 0-3 are the levels themselves; any other
// number becomes DETAIL_LEVEL_MAXIMUM, which is what -setDetailLevelDirectly: made of it: the bare
// cast this replaces handed the enum (underlying type unsigned int on this toolchain) an
// out-of-range value, a negative one as a large unsigned number, and the setter clamped anything
// >= DETAIL_LEVEL_MAXIMUM to it. Clamping as an integer means the enum only ever holds one of its
// own values (the same idiom as OOSystemLayerFromNumber, bead oo-2eby).
OOGraphicsDetail OOGraphicsDetailFromNumber(unsigned int number)
{
    return (number > DETAIL_LEVEL_MAXIMUM) ? DETAIL_LEVEL_MAXIMUM : static_cast<OOGraphicsDetail>(number);
}

// Defined with the configuration readers and the shipyard helpers below.
id ObjectForKeyIn(const oo::PList& dict, std::string_view key);
std::string ExpandKeyWith(const std::string& key, const char* name, const oo::PList& value);

// -addObject: on a set of objects (identity, as Entity keeps NSObject's -isEqual:): once each, in
// the order added.
template <class T, class U>
void AddIfAbsent(std::vector<oo::ObjCRef<T>>& objects, U object)
{
    if (std::find(objects.begin(), objects.end(), object) == objects.end())
        objects.emplace_back(object);
}

// An autoreleased list: each element goes to the autorelease pool, which releases it when it
// drains (the list itself released them then). The list is left empty.
template <class T>
void AutoreleaseAll(std::vector<oo::ObjCRef<T>>& objects)
{
    for (oo::ObjCRef<T>& object : objects)
        [object.leakRef() autorelease];
    objects.clear();
}

// -removeObjectAtIndex:0 on the wormhole list: an empty list raised a range exception.
void RemoveFirstWormhole(std::vector<oo::ObjCRef<WormholeEntity*>>& wormholes)
{
    if (wormholes.empty()) {
        [OOException raise:OORangeException format:"Index 0 is out of range 0 (in 'removeObjectAtIndex:')"];
    }
    wormholes.erase(wormholes.begin());
}

/*	[beaconCode rangeOfString:code options:NSCaseInsensitiveSearch].location != NSNotFound: the
        units compared lowercased (oo::str::lowercase maps unit for unit, so a byte search of the two
        lowercased strings finds the same places); an empty code is never found; a nil beacon code
        answered a zeroed range from messaging nil, location 0, which counted as found.
*/
bool BeaconCodeMatches(const std::optional<std::string>& beaconCode, const std::string& code)
{
    if (!beaconCode.has_value())
        return true;
    if (code.empty())
        return false;
    return oo::str::lowercase(*beaconCode).find(oo::str::lowercase(code)) != std::string::npos;
}

}

@implementation Universe

// Flags needed when JS reset fails.
static int JSResetFlags = 0;

// track the position and status of the lights
static BOOL object_light_on = NO;
static BOOL demo_light_on = NO;
static GLfloat sun_off[4] = { 0.0, 0.0, 0.0, 1.0 };
static GLfloat demo_light_position[4] = { DEMO_LIGHT_POSITION, 1.0 };

#define DOCKED_AMBIENT_LEVEL 0.2f // Was 0.05, 'temporarily' set to 0.2.
#define DOCKED_ILLUM_LEVEL 0.7f
static GLfloat docked_light_ambient[4] = { DOCKED_AMBIENT_LEVEL, DOCKED_AMBIENT_LEVEL, DOCKED_AMBIENT_LEVEL, 1.0f };
static GLfloat docked_light_diffuse[4] = { DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, 1.0f }; // white
static GLfloat docked_light_specular[4] = { DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL * 0.75f, (GLfloat)1.0f }; // yellow-white

// Weight of sun in ambient light calculation. 1.0 means only sun's diffuse is used for ambient, 0.0 means only sky colour is used.
// TODO: considering the size of the sun and the number of background stars might be worthwhile. -- Ahruman 20080322
#define SUN_AMBIENT_INFLUENCE 0.75
// How dark the default ambient level of 1.0 will be
#define SKY_AMBIENT_ADJUSTMENT 0.0625

- (BOOL)bloom
{
    return _bloom && [self detailLevel] >= DETAIL_LEVEL_EXTRAS;
}

- (void)setBloom:(BOOL)newBloom
{
    _bloom = !!newBloom;
}

- (int)currentPostFX
{
    return _currentPostFX;
}

- (void)setCurrentPostFX:(int)newCurrentPostFX
{
    if (newCurrentPostFX < 1 || newCurrentPostFX > OO_POSTFX_ENDOFLIST - 1) {
        newCurrentPostFX = OO_POSTFX_NONE;
    }

    if (OO_POSTFX_NONE <= newCurrentPostFX && newCurrentPostFX <= OO_POSTFX_COLORBLINDNESS_TRITAN) {
        _colorblindMode = newCurrentPostFX;
    }

    _currentPostFX = newCurrentPostFX;
}

- (void)terminatePostFX:(int)postFX
{
    if ([self currentPostFX] == postFX) {
        [self setCurrentPostFX:[self colorblindMode]];
    }
}

- (int)nextColorblindMode:(int)index
{
    if (++index > OO_POSTFX_COLORBLINDNESS_TRITAN)
        index = OO_POSTFX_NONE;

    return index;
}

- (int)prevColorblindMode:(int)index
{
    if (--index < OO_POSTFX_NONE)
        index = OO_POSTFX_COLORBLINDNESS_TRITAN;

    return index;
}

- (int)colorblindMode
{
    return _colorblindMode;
}

- (void)initTargetFramebufferWithViewSize:(NSSize)viewSize
{
    // liberate us from the 0.0 to 1.0 rgb range!
    OOGL(glClampColor(GL_CLAMP_VERTEX_COLOR, GL_FALSE));
    OOGL(glClampColor(GL_CLAMP_READ_COLOR, GL_FALSE));
    OOGL(glClampColor(GL_CLAMP_FRAGMENT_COLOR, GL_FALSE));

    // have to do this because on my machine the default framebuffer is not zero
    OOGL(glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &defaultDrawFBO));

    GLint previousProgramID;
    OOGL(glGetIntegerv(GL_CURRENT_PROGRAM, &previousProgramID));
    GLint previousTextureID;
    OOGL(glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTextureID));
    GLint previousVAO;
    OOGL(glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &previousVAO));
    GLint previousArrayBuffer;
    OOGL(glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &previousArrayBuffer));
    GLint previousElementBuffer;
    OOGL(glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &previousElementBuffer));

    // create MSAA framebuffer and attach MSAA texture and depth buffer to framebuffer
    OOGL(glGenFramebuffers(1, &msaaFramebufferID));
    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, msaaFramebufferID));

    // creating MSAA texture that should be rendered into
#if OO_MSAA_COLOR_RENDERBUFFER
    // No multisample textures in the macOS legacy context; a multisample renderbuffer resolves the same way.
    OOGL(glGenRenderbuffers(1, &msaaTextureID));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, msaaTextureID));
    OOGL(glRenderbufferStorageMultisample(GL_RENDERBUFFER, 4, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));
    OOGL(glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, msaaTextureID));
#else
    OOGL(glGenTextures(1, &msaaTextureID));
    OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, msaaTextureID));
    OOGL(glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, GL_TRUE));
    OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0));
    OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D_MULTISAMPLE, msaaTextureID, 0));
#endif

    // create necessary MSAA depth render buffer
    OOGL(glGenRenderbuffers(1, &msaaDepthBufferID));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, msaaDepthBufferID));
    OOGL(glRenderbufferStorageMultisample(GL_RENDERBUFFER, 4, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));
    OOGL(glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, msaaDepthBufferID));

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Multisample framebuffer not complete");
    }

    // create framebuffer and attach texture and depth buffer to framebuffer
    OOGL(glGenFramebuffers(1, &targetFramebufferID));
    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, targetFramebufferID));

    // creating texture that should be rendered into
    OOGL(glGenTextures(1, &targetTextureID));
    OOGL(glBindTexture(GL_TEXTURE_2D, targetTextureID));
    OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
    OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
    OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
    OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
    OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
    OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, targetTextureID, 0));

    // create necessary depth render buffer
    OOGL(glGenRenderbuffers(1, &targetDepthBufferID));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, targetDepthBufferID));
    OOGL(glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
    OOGL(glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, targetDepthBufferID));

    GLenum attachment[1] = { GL_COLOR_ATTACHMENT0 };
    OOGL(glDrawBuffers(1, attachment));

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Framebuffer not complete");
    }

    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));

    targetFramebufferSize = viewSize;

    // passthrough buffer
    // This is a framebuffer whose sole purpose is to pass on the texture rendered from the game to the blur and the final bloom
    // shaders. We need it in order to be able to use the OpenGL 3.3 layout (location = x) out vec4 outVector; construct, which allows
    // us to perform multiple render target operations needed for bloom. The alternative would be to not use this and change all our
    // shaders to be OpenGL 3.3 compatible, but given how Oolite synthesizes them and the work needed to port them over, well yeah no,
    // not doing it at this time - Nikos 20220814.
    OOGL(glGenFramebuffers(1, &passthroughFramebufferID));
    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, passthroughFramebufferID));

    // creating textures that should be rendered into
    OOGL(glGenTextures(2, passthroughTextureID));
    for (unsigned int i = 0; i < 2; i++) {
        OOGL(glBindTexture(GL_TEXTURE_2D, passthroughTextureID[i]));
        OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, passthroughTextureID[i], 0));
    }

    GLenum attachments[2] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1 };
    OOGL(glDrawBuffers(2, attachments));

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Passthrough framebuffer not complete");
    }
    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));

    // ping-pong-framebuffer for blurring
    OOGL(glGenFramebuffers(2, pingpongFBO));
    OOGL(glGenTextures(2, pingpongColorbuffers));
    for (unsigned int i = 0; i < 2; i++) {
        OOGL(glBindFramebuffer(GL_FRAMEBUFFER, pingpongFBO[i]));
        OOGL(glBindTexture(GL_TEXTURE_2D, pingpongColorbuffers[i]));
        OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)); // we clamp to the edge as the blur filter would otherwise sample repeated texture values!
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pingpongColorbuffers[i], 0));
        // check if framebuffers are complete (no need for depth buffer)
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
            OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Pingpong framebuffers not complete");
        }
    }
    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));

    _bloom = [self detailLevel] >= DETAIL_LEVEL_EXTRAS;
    _currentPostFX = _colorblindMode = OO_POSTFX_NONE;

    /* TODO: in OOEnvironmentCubeMap.m call these bind functions not with 0 but with "previousXxxID"s:
      - OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP, 0));
      - OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0));
      - OOGL(glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, 0));
    */

    // shader for drawing a textured quad on the passthrough framebuffer and preparing it for bloom using MRT
    if (![[OOOpenGLExtensionManager sharedManager] shadersForceDisabled]) {
        textureProgram = [[OOShaderProgram shaderProgramWithVertexShaderName:"oolite-texture.vertex"
                                                          fragmentShaderName:"oolite-texture.fragment"
                                                                      prefix:"#version 330\n"
                                                           attributeBindings:oo::PList(oo::PList::Dict { })] retain];
        // shader for blurring the over-threshold brightness image generated from the previous step using Gaussian filter
        blurProgram = [[OOShaderProgram shaderProgramWithVertexShaderName:"oolite-blur.vertex"
                                                       fragmentShaderName:"oolite-blur.fragment"
                                                                   prefix:"#version 330\n"
                                                        attributeBindings:oo::PList(oo::PList::Dict { })] retain];
        // shader for applying bloom and any necessary post-proc fx, tonemapping and gamma correction
        finalProgram = [[OOShaderProgram shaderProgramWithVertexShaderName:"oolite-final.vertex"
#if OOLITE_WINDOWS
                                                        fragmentShaderName:[[UNIVERSE gameView] hdrOutput] ? "oolite-final-hdr.fragment" : "oolite-final.fragment"
#else
                                                        fragmentShaderName:"oolite-final.fragment"
#endif
                                                                    prefix:"#version 330\n"
                                                         attributeBindings:oo::PList(oo::PList::Dict { })] retain];
    }

    OOGL(glGenVertexArrays(1, &quadTextureVAO));
    OOGL(glGenBuffers(1, &quadTextureVBO));
    OOGL(glGenBuffers(1, &quadTextureEBO));

    OOGL(glBindVertexArray(quadTextureVAO));

    OOGL(glBindBuffer(GL_ARRAY_BUFFER, quadTextureVBO));
    OOGL(glBufferData(GL_ARRAY_BUFFER, sizeof(framebufferQuadVertices), framebufferQuadVertices, GL_STATIC_DRAW));

    OOGL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, quadTextureEBO));
    OOGL(glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(framebufferQuadIndices), framebufferQuadIndices, GL_STATIC_DRAW));

    OOGL(glEnableVertexAttribArray(0));
    // position attribute
    OOGL(glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0));
    OOGL(glEnableVertexAttribArray(1));
    // texture coord attribute
    OOGL(glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float))));

    // restoring previous bindings
    OOGL(glUseProgram(previousProgramID));
    OOGL(glBindTexture(GL_TEXTURE_2D, previousTextureID));
    OOGL(glBindVertexArray(previousVAO));
    OOGL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, previousElementBuffer));
    OOGL(glBindBuffer(GL_ARRAY_BUFFER, previousArrayBuffer));
}

- (void)deleteOpenGLObjects
{
#if OO_MSAA_COLOR_RENDERBUFFER
    OOGL(glDeleteRenderbuffers(1, &msaaTextureID));
#else
    OOGL(glDeleteTextures(1, &msaaTextureID));
#endif
    OOGL(glDeleteTextures(1, &targetTextureID));
    OOGL(glDeleteTextures(2, passthroughTextureID));
    OOGL(glDeleteTextures(2, pingpongColorbuffers));
    OOGL(glDeleteRenderbuffers(1, &msaaDepthBufferID));
    OOGL(glDeleteRenderbuffers(1, &targetDepthBufferID));
    OOGL(glDeleteFramebuffers(1, &msaaFramebufferID));
    OOGL(glDeleteFramebuffers(1, &targetFramebufferID));
    OOGL(glDeleteFramebuffers(2, pingpongFBO));
    OOGL(glDeleteFramebuffers(1, &passthroughFramebufferID));
    OOGL(glDeleteVertexArrays(1, &quadTextureVAO));
    OOGL(glDeleteBuffers(1, &quadTextureVBO));
    OOGL(glDeleteBuffers(1, &quadTextureEBO));
    [textureProgram release];
    [blurProgram release];
    [finalProgram release];
}

- (void)resizeTargetFramebufferWithViewSize:(NSSize)viewSize
{
    int i;
    // resize MSAA color attachment
#if OO_MSAA_COLOR_RENDERBUFFER
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, msaaTextureID));
    OOGL(glRenderbufferStorageMultisample(GL_RENDERBUFFER, 4, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));
#else
    OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, msaaTextureID));
    OOGL(glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, GL_TRUE));
    OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0));
#endif

    // resize MSAA depth attachment
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, msaaDepthBufferID));
    OOGL(glRenderbufferStorageMultisample(GL_RENDERBUFFER, 4, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));

    // resize color attachments
    OOGL(glBindTexture(GL_TEXTURE_2D, targetTextureID));
    OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
    OOGL(glBindTexture(GL_TEXTURE_2D, 0));

    for (i = 0; i < 2; i++) {
        OOGL(glBindTexture(GL_TEXTURE_2D, pingpongColorbuffers[i]));
        OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
        OOGL(glBindTexture(GL_TEXTURE_2D, 0));
    }

    for (i = 0; i < 2; i++) {
        OOGL(glBindTexture(GL_TEXTURE_2D, passthroughTextureID[i]));
        OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
        OOGL(glBindTexture(GL_TEXTURE_2D, 0));
    }

    // resize depth attachment
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, targetDepthBufferID));
    OOGL(glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
    OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));

    targetFramebufferSize.width = viewSize.width;
    targetFramebufferSize.height = viewSize.height;
}

- (void)drawTargetTextureIntoDefaultFramebuffer
{
    // save previous bindings state
    GLint previousFBO;
    OOGL(glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previousFBO));
    GLint previousProgramID;
    OOGL(glGetIntegerv(GL_CURRENT_PROGRAM, &previousProgramID));
    GLint previousTextureID;
    OOGL(glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTextureID));
    GLint previousVAO;
    OOGL(glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &previousVAO));
    GLint previousActiveTexture;
    OOGL(glGetIntegerv(GL_ACTIVE_TEXTURE, &previousActiveTexture));

    OOGL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
    // fixes transparency issue for some reason
    OOGL(glDisable(GL_BLEND));

    GLuint program = OOGLProgramName([textureProgram program]);
    GLuint blur = OOGLProgramName([blurProgram program]);
    GLuint final = OOGLProgramName([finalProgram program]);
    NSSize viewSize = [gameView backingViewSize];
    float fboResolution[2] = { (float)viewSize.width, (float)viewSize.height };

    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, passthroughFramebufferID));
    OOGL(glClear(GL_COLOR_BUFFER_BIT));

    OOGL(glUseProgram(program));
    OOGL(glBindTexture(GL_TEXTURE_2D, targetTextureID));
    OOGL(glUniform1i(glGetUniformLocation(program, "image"), 0));

    OOGL(glBindVertexArray(quadTextureVAO));
    OOGL(glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0));
    OOGL(glBindVertexArray(0));

    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));

    BOOL horizontal = YES, firstIteration = YES;
    unsigned int amount = [self bloom] ? 10 : 0; // if not blooming, why bother with the heavy calculations?
    OOGL(glUseProgram(blur));
    for (unsigned int i = 0; i < amount; i++) {
        OOGL(glBindFramebuffer(GL_FRAMEBUFFER, pingpongFBO[horizontal]));
        OOGL(glUniform1i(glGetUniformLocation(blur, "horizontal"), horizontal));
        OOGL(glActiveTexture(GL_TEXTURE0));
        // bind texture of other framebuffer (or scene if first iteration)
        OOGL(glBindTexture(GL_TEXTURE_2D, firstIteration ? passthroughTextureID[1] : pingpongColorbuffers[!horizontal]));
        OOGL(glUniform1i(glGetUniformLocation(blur, "imageIn"), 0));
        OOGL(glBindVertexArray(quadTextureVAO));
        OOGL(glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0));
        OOGL(glBindVertexArray(0));
        horizontal = !horizontal;
        firstIteration = NO;
    }
    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));

    OOGL(glUseProgram(final));

    OOGL(glActiveTexture(GL_TEXTURE0));
    OOGL(glBindTexture(GL_TEXTURE_2D, passthroughTextureID[0]));
    OOGL(glUniform1i(glGetUniformLocation(final, "scene"), 0));
    OOGL(glUniform1i(glGetUniformLocation(final, "bloom"), [self bloom]));
    OOGL(glUniform1f(glGetUniformLocation(final, "uTime"), [self getTime]));
    OOGL(glUniform2fv(glGetUniformLocation(final, "uResolution"), 1, fboResolution));
    OOGL(glUniform1i(glGetUniformLocation(final, "uPostFX"), [self currentPostFX]));
#if OOLITE_WINDOWS
    if ([gameView hdrOutput]) {
        OOGL(glUniform1f(glGetUniformLocation(final, "uMaxBrightness"), [gameView hdrMaxBrightness]));
        OOGL(glUniform1f(glGetUniformLocation(final, "uPaperWhiteBrightness"), [gameView hdrPaperWhiteBrightness]));
        OOGL(glUniform1i(glGetUniformLocation(final, "uHDRToneMapper"), [gameView hdrToneMapper]));
    }
#endif
    OOGL(glUniform1i(glGetUniformLocation(final, "uSDRToneMapper"), [gameView sdrToneMapper]));

    OOGL(glActiveTexture(GL_TEXTURE1));
    OOGL(glBindTexture(GL_TEXTURE_2D, pingpongColorbuffers[!horizontal]));
    OOGL(glUniform1i(glGetUniformLocation(final, "bloomBlur"), 1));
    OOGL(glUniform1f(glGetUniformLocation(final, "uSaturation"), [gameView colorSaturation]));

    OOGL(glBindVertexArray(quadTextureVAO));
    OOGL(glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0));

    // restore GL_TEXTURE1 to 0, just in case we are returning from a
    // DETAIL_LEVEL_NORMAL to DETAIL_LEVEL_SHADERS
    OOGL(glBindTexture(GL_TEXTURE_2D, 0));

    // restore previous bindings
    OOGL(glBindFramebuffer(GL_FRAMEBUFFER, previousFBO));
    OOGL(glActiveTexture(previousActiveTexture));
    OOGL(glBindTexture(GL_TEXTURE_2D, previousTextureID));
    OOGL(glUseProgram(previousProgramID));
    OOGL(glBindVertexArray(previousVAO));
    OOGL(glEnable(GL_BLEND));
}

- (id)initWithGameView:(MyOpenGLView*)inGameView
{
    if (gSharedUniverse != nil) {
        [self release];
        [OOException raise:OOInternalInconsistencyException format:"%s: expected only one Universe to exist at a time.", __PRETTY_FUNCTION__];
    }

    OO_DEBUG_PROGRESS(@"%@", @"Universe initWithGameView:");

    self = [super init];
    if (self == nil)
        return nil;

    _doingStartUp = YES;

    OOInitReallyRandom(oo::date::timeIntervalSinceReferenceDate() * 1e9);

    oo::Defaults& prefs = oo::Defaults::standard();

    // prefs value no longer used - per save game but startup needs to
    // be non-strict
    useAddOns = oo::StdString(SCENARIO_OXP_DEFINITION_ALL);

    [self setGameView:inGameView];
    gSharedUniverse = self;

    allPlanets.clear();
    allStations.clear();

    OOCPUInfoInit();
    [OOJoystickManager sharedStickHandler];

    // init OpenGL extension manager (must be done before any other threads might use it)
    [OOOpenGLExtensionManager sharedManager];
    [self setDetailLevelDirectly:OOGraphicsDetailFromNumber(prefs.object("detailLevel").isNull() ? [[OOOpenGLExtensionManager sharedManager] defaultDetailLevel] : static_cast<unsigned int>(prefs.integerForKey("detailLevel")))];

    [self initTargetFramebufferWithViewSize:[gameView backingViewSize]];

    [OOMaterial setUp];

    // Preload cache
    [OOCacheManager sharedCache];

#if OOLITE_SPEECH_SYNTH
    OO_LOG("speech.synthesis", "Spoken messages are {}.", (prefs.boolForKey("speech_on") ? "on" : "off"));
#endif

    // init the Resource Manager
    [ResourceManager cxx_setUseAddOns:useAddOns]; // also logs the paths if changed

    // Set up the internal game strings
    [self loadDescriptions];
    // DESC expansion is now possible!

    // load starting saves
    [self loadScenarios];

    autoSave = prefs.boolForKey("autosave");
    wireframeGraphics = prefs.boolForKey("wireframe-graphics");
    doProcedurallyTexturedPlanets = prefs.object("procedurally-textured-planets").isNull() ? YES : prefs.boolForKey("procedurally-textured-planets");
    [inGameView setMsaa:prefs.boolForKey("anti-aliasing")];
    OO_LOG("MSAA.setup", "Multisample anti-aliasing {}requested.", [inGameView msaa] ? "" : "not ");
    [inGameView setFov:OOClamp_0_max_f(prefs.object("fov-value").isNull() ? 57.2f : prefs.floatForKey("fov-value"), MAX_FOV_DEG) fromFraction:NO];
    if ([inGameView fov:NO] < MIN_FOV_DEG)
        [inGameView setFov:MIN_FOV_DEG fromFraction:NO];

    [self setECMVisualFXEnabled:prefs.object("ecm-visual-fx").isNull() ? YES : prefs.boolForKey("ecm-visual-fx")];

    // Set up speech synthesizer.
#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_COCOA_UI
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
        ^{
            /*
                    NSSpeechSynthesizer can take over a second on an SSD and several
                    seconds on an HDD for a cold start, and a third of a second upward
                    for a warm start. There are no particular thread safety consider-
                    ations documented for NSSpeechSynthesizer, so I'm assuming the
                    default one-thread-at-a-time access rule applies.
                    -- Ahruman 2012-09-13
            */
            OO_LOG("speech.setup.begin", "Starting to set up speech synthesizer.");
            NSSpeechSynthesizer* synth = [[NSSpeechSynthesizer alloc] init];
            OO_LOG("speech.setup.end", "Finished setting up speech synthesizer.");
            speechSynthesizer = synth;
        });
#elif OOLITE_ESPEAK
    int volume = [OOSound masterVolume] * 100;
    espeak_SetParameter(espeakPUNCTUATION, espeakPUNCT_NONE, 0);
    espeak_SetParameter(espeakVOLUME, volume, 0);
    espeak_voices = espeak_ListVoices(NULL);
    for (espeak_voice_count = 0;
        espeak_voices[espeak_voice_count];
        ++espeak_voice_count)
        /**/;
#endif
#endif

    [[GameController sharedController] logProgress:DESC(@"loading-ships")];
    // Load ship data

    [OOShipRegistry sharedRegistry];

    entities.reserve(MAX_NUMBER_OF_ENTITIES);

    [[GameController sharedController] logProgress:OOExpandKeyRandomized(@"loading-miscellany")];

    // this MUST have the default no. of rows else the GUI_ROW macros in PlayerEntity.h need modification
    gui = [[GuiDisplayGen alloc] init]; // alloc retains
    comm_log_gui = [[GuiDisplayGen alloc] init]; // alloc retains

    missiontext = [ResourceManager cxx_dictionaryFromFilesNamed:"missiontext.plist" inFolder:std::string("Config") andMerge:YES];

    waypoints.clear();

    [self setUpSettings];

    // can't do this here as it might lock an OXZ open
    // [self preloadSounds];	// Must be after setUpSettings.

    // Preload particle effect textures:
    [OOLightParticleEntity setUpTexture];
    [OOFlashEffectEntity setUpTexture];

    // set up cargopod templates
    [self setUpCargoPods];

    PlayerEntity* player = [PlayerEntity sharedPlayer];
    [player deferredInit];
    [self addEntity:player];

    [player setStatus:STATUS_START_GAME];
    [player setShowDemoShips:YES];

    [self setUpInitialUniverse];

    universeRegion = [[CollisionRegion alloc] initAsUniverse];
    entitiesDeadThisUpdate.clear();
    framesDoneThisUpdate = 0;
    drawCounter = 0;

    [[GameController sharedController] logProgress:DESC(@"initializing-debug-support")];
    OOInitDebugSupport();

    [[GameController sharedController] logProgress:DESC(@"running-scripts")];
    [player completeSetUp];

    [[GameController sharedController] logProgress:DESC(@"populating-space")];
    [self populateNormalSpace];

    [[GameController sharedController] logProgress:OOExpandKeyRandomized(@"loading-miscellany")];

#if OO_LOCALIZATION_TOOLS
    [self runLocalizationTools];
#if DEBUG_GRAPHVIZ
    [self dumpDebugGraphViz];
#endif
#endif

    [player startUpComplete];
    _doingStartUp = NO;

    return self;
}

- (void)dealloc
{
    gSharedUniverse = nil;

    currentMessage.reset();

    [gui release];
    [message_gui release];
    [comm_log_gui release];

    entities.clear();

    [commodities release];

    customSounds = oo::PList();
    globalSettings = oo::PList();
    [systemManager release];
    demo_ships = oo::PList();
    screenBackgrounds = oo::PList();
    [gameView release];
    allPlanets.clear();
    allStations.clear();

    activeWormholes.clear();
    characterPool.clear();
    [universeRegion release];

    DESTROY(_firstBeacon);
    DESTROY(_lastBeacon);
    waypoints.clear();

    unsigned i;
    for (i = 0; i < 256; i++)
        system_names[i].reset();

    entitiesDeadThisUpdate.clear();

    [[OOCacheManager sharedCache] flush];

#if OOLITE_SPEECH_SYNTH
    speechArray = oo::PList();
#if OOLITE_MAC_COCOA_UI
    [speechSynthesizer release];
#elif OOLITE_ESPEAK
    espeak_Cancel();
#endif
#endif

    [self deleteOpenGLObjects];

    [super dealloc];
}

- (NSUInteger)sessionID
{
    return _sessionID;
}

- (BOOL)doingStartUp
{
    return _doingStartUp;
}

- (BOOL)doProcedurallyTexturedPlanets
{
    return doProcedurallyTexturedPlanets;
}

- (void)setDoProcedurallyTexturedPlanets:(BOOL)value
{
    doProcedurallyTexturedPlanets = !!value; // ensure yes or no
    oo::Defaults::standard().setBool("procedurally-textured-planets", doProcedurallyTexturedPlanets);
}

- (std::optional<std::string>)cxx_useAddOns
{
    return useAddOns;
}

- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame
{
    return [self cxx_setUseAddOns:newUse fromSaveGame:saveGame forceReinit:NO];
}

- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame forceReinit:(BOOL)force
{
    if (!force && newUse == useAddOns) {
        return YES;
    }
    useAddOns = newUse;

    return [self reinitAndShowDemo:!saveGame];
}

- (NSUInteger)entityCount
{
    return entities.size();
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)debugDumpEntities
{
    int i;
    int show_count = n_entities;

    if (!OOLogWillDisplayMessagesInClass(@"universe.objectDump"))
        return;

    OO_LOG("universe.objectDump", "DEBUG: Entity Dump - [entities count] = {},\tn_entities = {}", static_cast<size_t>(entities.size()), static_cast<unsigned>(n_entities));

    OOLogIndent();
    for (i = 0; i < show_count; i++) {
        OO_LOG("universe.objectDump", "Ent:{:4}  {}", static_cast<unsigned>(i), oo::DescriptionOf([sortedEntities[i] descriptionForObjDump]));
    }
    OOLogOutdent();

    if (entities.size() != n_entities) {
        OO_LOG("universe.objectDump", "entities = {}", oo::DescriptionOf([oo::NSArrayFromObjects(entities) description]));
    }
}

- (std::vector<oo::ObjCRef<Entity*>>)cxx_entityList
{
    return entities;
}
#endif

- (void)pauseGame
{
    // deal with the machine going to sleep, or player pressing 'p'.
    PlayerEntity* player = PLAYER;

    [self setPauseMessageVisible:NO];
    const std::optional<std::string> pauseKey = [PLAYER cxx_keyBindingDescription2:"key_pausebutton"];

    if ([player status] == STATUS_DOCKED) {
        if ([gui setForegroundTextureKey:@"paused_docked_overlay"]) {
            [gui drawGUI:1.0 drawCursor:NO];
        } else {
            [self setPauseMessageVisible:YES];
            [self cxx_addMessage:ExpandKeyWith("game-paused-docked", "pauseKey", pauseKey.has_value() ? oo::PList(*pauseKey) : oo::PList()) forCount:1.0];
        }
    } else {
        if ([player guiScreen] != GUI_SCREEN_MAIN && [gui setForegroundTextureKey:@"paused_overlay"]) {
            [gui drawGUI:1.0 drawCursor:NO];
        } else {
            [self setPauseMessageVisible:YES];
            [self cxx_addMessage:ExpandKeyWith("game-paused", "pauseKey", pauseKey.has_value() ? oo::PList(*pauseKey) : oo::PList()) forCount:1.0];
        }
    }

    [[self gameController] setGamePaused:YES];
}

- (void)quitGame
{
    OO_LOG("universe.quit", "{}", "Quit command received by Universe.");
    [[self gameController] exitAppWithContext:@"Universe Request"];
}

- (void)carryPlayerOn:(StationEntity*)carrier inWormhole:(WormholeEntity*)wormhole
{
    PlayerEntity* player = PLAYER;
    OOSystemID dest = [wormhole destination];

    [player setWormhole:wormhole];
    [player addScannedWormhole:wormhole];
    JSContext* context = OOJSAcquireContext();
    [player setJumpCause:@"carried"];
    [player setPreviousSystemID:[player systemID]];
    ShipScriptEvent(context, player, "shipWillEnterWitchspace", OOJSValueFromNativeObject(context, [player jumpCause]), OOJSValueFromDouble(context, dest));
    OOJSRelinquishContext(context);

    [self allShipsDoScriptEvent:OOJSID("playerWillEnterWitchspace") andReactToAIMessage:@"PLAYER WITCHSPACE"];

    [player setRandom_factor:(ranrot_rand() & 255)]; // random factor for market values is reset

    // misjump on wormhole sets correct travel time if needed
    [player addToAdjustTime:[wormhole travelTime]];
    // clear old entities
    [self removeAllEntitiesExceptPlayer];

    // should we add wear-and-tear to the player ship if they're not doing
    // the jump themselves? Left out for now. - CIM

    if (![wormhole withMisjump]) {
        [player setSystemID:dest];
        [self setSystemTo:dest];

        [self setUpSpace];
        [self populateNormalSpace];
        [player setBounty:([player legalStatus] / 2) withReason:kOOLegalStatusReasonNewSystem];
        if ([player random_factor] < 8)
            [player erodeReputation]; // every 32 systems or so, dro
    } else {
        [player setGalaxyCoordinates:[wormhole destinationCoordinates]];

        [self setUpWitchspaceBetweenSystem:[wormhole origin] andSystem:[wormhole destination]];

        if (randf() < 0.1)
            [player erodeReputation]; // once every 10 misjumps - should be much rarer than successful jumps!
    }
    // which will kick the ship out of the wormhole with the
    // player still aboard
    [wormhole disgorgeShips];

    // reset atmospherics in case carrier was in atmosphere
    [UNIVERSE setSkyColorRed:0.0f // back to black
                       green:0.0f
                        blue:0.0f
                       alpha:0.0f];

    [self setWitchspaceBreakPattern:YES];
    [player doScriptEvent:OOJSID("shipWillExitWitchspace") withArgument:[player jumpCause]];
    [player doScriptEvent:OOJSID("shipExitedWitchspace") withArgument:[player jumpCause]];
    [player setWormhole:nil];
}

- (void)setUpUniverseFromStation
{
    if (![self sun]) {
        // we're in witchspace...

        PlayerEntity* player = PLAYER;
        StationEntity* dockedStation = [player dockedStation];
        NSPoint coords = [player galaxy_coordinates];
        // check the nearest system
        OOSystemID sys = [self findSystemNumberAtCoords:coords withGalaxy:[player galaxyNumber] includingHidden:YES];
        BOOL interstel = [dockedStation interstellarUndockingAllowed]; // && (s_seed.d != coords.x || s_seed.b != coords.y); - Nikos 20110623: Do we really need the commented out check?
        [player setPreviousSystemID:[player currentSystemID]];

        // remove everything except the player and the docked station
        if (dockedStation && !interstel) { // jump to the nearest system
            [player setSystemID:sys];
            closeSystems.reset();
            [self setSystemTo:sys];
            int index = 0;
            while (entities.size() > 2) {
                Entity* ent = entities[index].get();
                if ((ent != player) && (ent != dockedStation)) {
                    if (ent->isStation) // clear out queues
                        [(StationEntity*)ent clear];
                    [self removeEntity:ent];
                } else {
                    index++; // leave that one alone
                }
            }
        } else {
            if (dockedStation == nil)
                [self removeAllEntitiesExceptPlayer]; // get rid of witchspace sky etc. if still extant
        }

        if (!dockedStation || !interstel) {
            [self setUpSpace]; // launching from station that jumped from interstellar space to normal space.
            [self populateNormalSpace];
            if (dockedStation) {
                if ([dockedStation maxFlightSpeed] > 0) // we are a carrier: exit near the WitchspaceExitPosition
                {
                    float d1 = [self randomDistanceWithinScanner];
                    HPVector pos = [UNIVERSE getWitchspaceExitPosition]; // no need to reset the PRNG
                    Quaternion q1;

                    quaternion_set_random(&q1);
                    if (abs((int)d1) < 2750) {
                        d1 += ((d1 > 0.0) ? 2750.0f : -2750.0f); // no closer than 2750m. Carriers are bigger than player ships.
                    }
                    Vector v1 = vector_forward_from_quaternion(q1);
                    pos.x += v1.x * d1; // randomise exit position
                    pos.y += v1.y * d1;
                    pos.z += v1.z * d1;

                    [dockedStation setPosition:pos];
                }
                [self setWitchspaceBreakPattern:YES];
                [player setJumpCause:@"carried"];
                [player doScriptEvent:OOJSID("shipWillExitWitchspace") withArgument:[player jumpCause]];
                [player doScriptEvent:OOJSID("shipExitedWitchspace") withArgument:[player jumpCause]];
            }
        }
    }

    if (!autoSaveNow)
        [self setViewDirection:VIEW_FORWARD];
    displayGUI = NO;

    // reset atmospherics in case we ejected while we were in the atmophere
    [UNIVERSE setSkyColorRed:0.0f // back to black
                       green:0.0f
                        blue:0.0f
                       alpha:0.0f];
}

- (void)setUpUniverseFromWitchspace
{
    PlayerEntity* player;

    //
    // check the player is still around!
    //
    if (entities.empty()) {
        /*- the player ship -*/
        player = [[PlayerEntity alloc] init]; // alloc retains!

        [self addEntity:player];

        /*--*/
    } else {
        player = [PLAYER retain]; // retained here
    }

    [self setUpSpace];
    [self populateNormalSpace];

    [player leaveWitchspace];
    [player release]; // released here

    [self setViewDirection:VIEW_FORWARD];

    // the printed lines go to the player's (unmigrated) comm log as they went before
    std::vector<std::string> printedLines;
    [comm_log_gui cxx_printLongText:oo::str::format("%s %s", TextOrNull([self cxx_getSystemName:systemID]).c_str(), oo::DescriptionOf([player dial_clock_adjusted]).c_str())
                              align:GUI_ALIGN_CENTER
                              color:[OOColor whiteColor]
                           fadeTime:0
                                key:std::nullopt
                         addToArray:&printedLines];
    for (const std::string& line : printedLines)
        [[player commLog] addObject:oo::NSStringFrom(line)];

    displayGUI = NO;
}

- (void)setUpUniverseFromMisjump
{
    PlayerEntity* player;

    //
    // check the player is still around!
    //
    if (entities.empty()) {
        /*- the player ship -*/
        player = [[PlayerEntity alloc] init]; // alloc retains!

        [self addEntity:player];

        /*--*/
    } else {
        player = [PLAYER retain]; // retained here
    }

    [self setUpWitchspace];
    // ensure that if we got here from a jump within a planet's atmosphere,
    // we don't get any residual air friction
    [self setAirResistanceFactor:0.0f];

    [player leaveWitchspace];
    [player release]; // released here

    [self setViewDirection:VIEW_FORWARD];

    displayGUI = NO;
}

- (void)setUpWitchspace
{
    [self setUpWitchspaceBetweenSystem:[PLAYER systemID] andSystem:[PLAYER nextHopTargetSystemID]];
}

- (void)setUpWitchspaceBetweenSystem:(OOSystemID)s1 andSystem:(OOSystemID)s2
{
    // new system is hyper-centric : witchspace exit point is origin

    Entity* thing;
    PlayerEntity* player = PLAYER;
    Quaternion randomQ;

    const std::string override_key = *[self keyForInterstellarOverridesForSystems:s1 s2:s2 inGalaxy:galaxyID];

    const oo::PList systeminfo = [systemManager cxx_getPropertiesForSystemKey:override_key];

    [universeRegion clearSubregions];

    // fixed entities (part of the graphics system really) come first...

    /*- the sky backdrop -*/
    OOColor* col1 = [OOColor colorWithRed:0.0 green:1.0 blue:0.5 alpha:1.0];
    OOColor* col2 = [OOColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    thing = [[SkyEntity alloc] initWithColors:col1 col2:col2 andSystemInfo:systeminfo]; // alloc retains!
    [thing setScanClass:CLASS_NO_DRAW];
    quaternion_set_random(&randomQ);
    [thing setOrientation:randomQ];
    [self addEntity:thing];
    [thing release];

    /*- the dust particle system -*/
    thing = [[DustEntity alloc] init];
    [thing setScanClass:CLASS_NO_DRAW];
    [self addEntity:thing];
    [thing release];

    ambientLightLevel = systeminfo.get<float>("ambient_level", 1.0);
    [self setLighting]; // also sets initial lights positions.

    OO_LOG(kOOLogUniversePopulateWitchspace, "{}", "Populating witchspace ...");
    oo::log::indentIf(kOOLogUniversePopulateWitchspace);

    [self clearSystemPopulator];
    const std::string populator = systeminfo.get<std::string>("populator", "interstellarSpaceWillPopulate");
    system_repopulator = systeminfo.get<std::string>("repopulator", "interstellarSpaceWillRepopulate");
    JSContext* context = OOJSAcquireContext();
    [PLAYER doWorldScriptEvent:cxx_OOJSIDFromString(populator) inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
    OOJSRelinquishContext(context);
    [self populateSystemFromDictionariesWithSun:nil andPlanet:nil];

    // systeminfo might have a 'script_actions' resource we want to activate now...
    const oo::PList* script_actions = systeminfo.get<oo::PList::Array>("script_actions");
    if (script_actions != nullptr) {
        cxx_OOStandardsDeprecated(oo::str::format("The script_actions system info key is deprecated for %s.", override_key.c_str()));
        if (!OOEnforceStandards()) {
            // the legacy script engine is not migrated yet: it gets the array it read before
            [player runUnsanitizedScriptActions:oo::ObjectFromPList(*script_actions)
                              allowingAIMethods:NO
                                withContextName:@"<witchspace script_actions>"
                                      forTarget:nil];
        }
    }

    next_repopulation = randf() * SYSTEM_REPOPULATION_INTERVAL;

    oo::log::outdentIf(kOOLogUniversePopulateWitchspace);
}

- (OOPlanetEntity*)setUpPlanet
{
    // set the system seed for random number generation
    Random_Seed systemSeed = [systemManager getRandomSeedForCurrentSystem];
    seed_for_planet_description(systemSeed);

    // a copy of the system data, marked as the main planet (a bool, as -oo_setBool:forKey: stored it)
    oo::PList planetDict = [systemManager cxx_getPropertiesForCurrentSystem];
    if (!planetDict.isDict())
        planetDict = oo::PList(oo::PList::Dict { });
    (*planetDict.getIf<oo::PList::Dict>())["mainForLocalSystem"] = oo::PList(true);
    OOPlanetEntity* a_planet = [[OOPlanetEntity alloc] initFromDictionary:planetDict withAtmosphere:planetDict.get<bool>("has_atmosphere", YES) andSeed:systemSeed forSystem:systemID];

    double planet_zpos = planetDict.get<float>("planet_distance", 500000);
    planet_zpos *= planetDict.get<float>("planet_distance_multiplier", 1.0);

#ifdef OO_DUMP_PLANETINFO
    OO_LOG("planetinfo.record", "planet zpos = {:f}", planet_zpos);
#endif
    [a_planet setPosition:(HPVector) { 0, 0, planet_zpos }];
    [a_planet setEnergy:1000000.0];

    if (allPlanets.size() > 0) // F7 sets [UNIVERSE planet], which can lead to some trouble! TODO: track down where exactly that happens!
    {
        OOPlanetEntity* tmp = allPlanets[0].get();
        [self addEntity:a_planet];
        std::erase(allPlanets, a_planet);
        cachedPlanet = a_planet;
        allPlanets[0] = oo::ObjCRef<OOPlanetEntity*>(a_planet);
        [self removeEntity:(Entity*)tmp];
    } else {
        [self addEntity:a_planet];
    }
    return [a_planet autorelease];
}

/* At any time other than game start, any call to this must be followed
 * by [self populateNormalSpace]. However, at game start, they need to be
 * separated to allow Javascript startUp routines to be run in-between */
- (void)setUpSpace
{
    Entity* thing;
    //	ShipEntity			*nav_buoy;
    StationEntity* a_station;
    OOSunEntity* a_sun;
    OOPlanetEntity* a_planet;

    HPVector stationPos;

    Vector vf;
    id dict_object;

    const oo::PList systeminfo = [systemManager cxx_getPropertiesForCurrentSystem];
    unsigned techlevel = systeminfo.get<unsigned int>(oo::StdString(KEY_TECHLEVEL));
    std::optional<std::string> stationDesc, defaultStationDesc; // the default is never set: nullopt, as nil
    OOColor* bgcolor;
    OOColor* pale_bgcolor;
    BOOL sunGoneNova;

    Random_Seed systemSeed = [systemManager getRandomSeedForCurrentSystem];

    [[GameController sharedController] logProgress:DESC(@"populating-space")];

    sunGoneNova = systeminfo.get<bool>("sun_gone_nova", NO);

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - clearSubRegions, sky, dust");
    [universeRegion clearSubregions];

    // fixed entities (part of the graphics system really) come first...
    [self setSkyColorRed:0.0f
                   green:0.0f
                    blue:0.0f
                   alpha:0.0f];

#ifdef OO_DUMP_PLANETINFO
    OO_LOG("planetinfo.record", "seed = {} {} {} {}", system_seed.c, system_seed.d, system_seed.e, system_seed.f);
    OO_LOG("planetinfo.record", "coordinates = {} {}", system_seed.d, system_seed.b);

#define SPROP(PROP) OO_LOG("planetinfo.record", #PROP " = \"{}\";", OptionalStringIn(systeminfo, "" #PROP).value_or("(null)"));
#define IPROP(PROP) OO_LOG("planetinfo.record", #PROP " = {};", systeminfo.get<int>(#PROP));
#define FPROP(PROP) OO_LOG("planetinfo.record", #PROP " = {:f};", systeminfo.get<float>("" #PROP));
    IPROP(government);
    IPROP(economy);
    IPROP(techlevel);
    IPROP(population);
    IPROP(productivity);
    SPROP(name);
    SPROP(inhabitant);
    SPROP(inhabitants);
    SPROP(description);
#endif

    // set the system seed for random number generation
    seed_for_planet_description(systemSeed);

    /*- the sky backdrop -*/
    // colors...
    float h1 = randf();
    float h2 = h1 + 1.0 / (1.0 + (Ranrot() % 5));
    while (h2 > 1.0)
        h2 -= 1.0;
    OOColor* col1 = [OOColor colorWithHue:h1 saturation:randf() brightness:0.5 + randf() / 2.0 alpha:1.0];
    OOColor* col2 = [OOColor colorWithHue:h2 saturation:0.5 + randf() / 2.0 brightness:0.5 + randf() / 2.0 alpha:1.0];

    thing = [[SkyEntity alloc] initWithColors:col1 col2:col2 andSystemInfo:systeminfo]; // alloc retains!
    [thing setScanClass:CLASS_NO_DRAW];
    [self addEntity:thing];
    //	bgcolor = [(SkyEntity *)thing skyColor];
    //
    h1 = randf() / 3.0;
    if (h1 > 0.17) {
        h1 += 0.33;
    }

    ambientLightLevel = systeminfo.get<float>("ambient_level", 1.0);

    // pick a main sequence colour

    dict_object = ObjectForKeyIn(systeminfo, "sun_color");
    if (dict_object != nil) {
        bgcolor = [OOColor colorWithDescription:dict_object];
    } else {
        bgcolor = [OOColor colorWithHue:h1 saturation:0.75 * randf() brightness:0.65 + randf() / 5.0 alpha:1.0];
    }

    pale_bgcolor = [bgcolor blendedColorWithFraction:0.5 ofColor:[OOColor whiteColor]];
    [thing release];
    /*--*/

    /*- the dust particle system -*/
    thing = [[DustEntity alloc] init]; // alloc retains!
    [thing setScanClass:CLASS_NO_DRAW];
    [self addEntity:thing];
    [(DustEntity*)thing setDustColor:pale_bgcolor];
    [thing release];
    /*--*/

    float defaultSunFlare = randf() * 0.1;
    float defaultSunHues = 0.5 + randf() * 0.5;
    OO_DEBUG_POP_PROGRESS();

    // actual entities next...

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - planet");
    a_planet = [self setUpPlanet]; // resets RNG when called
    double planet_radius = [a_planet radius];
    OO_DEBUG_POP_PROGRESS();

    // set the system seed for random number generation
    seed_for_planet_description(systemSeed);

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - sun");
    /*- space sun -*/
    double sun_radius;
    double sun_distance;
    double sunDistanceModifier;
    double safeDistance;
    HPVector sunPos;

    sunDistanceModifier = systeminfo.get<oo::NonNegative<double>>("sun_distance_modifier", 0.0);
    if (sunDistanceModifier < 6.0) // <6 isn't valid
    {
        sun_distance = systeminfo.get<oo::NonNegative<double>>("sun_distance", (planet_radius * 20));
        // note, old property was _modifier, new property is _multiplier
        sun_distance *= systeminfo.get<oo::NonNegative<double>>("sun_distance_multiplier", 1);
    } else {
        sun_distance = planet_radius * sunDistanceModifier;
    }

    sun_radius = systeminfo.get<oo::NonNegative<double>>("sun_radius", 2.5 * planet_radius);
    // clamp the sun radius
    if ((sun_radius < 1000.0) || (sun_radius > sun_distance / 2 && !sunGoneNova)) {
        OO_LOG_WARN("universe.setup.badSun", "Sun radius of {:f} is not valid for this system", sun_radius);
        sun_radius = sun_radius < 1000.0 ? 1000.0 : (sun_distance / 2);
    }
#ifdef OO_DUMP_PLANETINFO
    OO_LOG("planetinfo.record", "sun_radius = {:f}", sun_radius);
#endif
    safeDistance = 36 * sun_radius * sun_radius; // 6 times the sun radius

    // here we need to check if the sun collides with (or is too close to) the witchpoint
    // otherwise at (for example) Maregais in Galaxy 1 we go BANG!
    HPVector sun_dir = HPVectorIn(systeminfo, "sun_vector", kZeroHPVector);
    sun_distance /= 2.0;
    do {
        sun_distance *= 2.0;
        sunPos = HPvector_subtract([a_planet position],
            HPvector_multiply_scalar(sun_dir, sun_distance));

        // if not in the safe distance, multiply by two and try again
    } while (HPmagnitude2(sunPos) < safeDistance);

    // set planetary axial tilt to 0 degrees
    // TODO: allow this to vary
    [a_planet setOrientation:quaternion_rotation_betweenHP(sun_dir, make_HPvector(1.0, 0.0, 0.0))];

#ifdef OO_DUMP_PLANETINFO
    OO_LOG("planetinfo.record", "sun_vector = {:.3f} {:.3f} {:.3f}", vf.x, vf.y, vf.z);
    OO_LOG("planetinfo.record", "sun_distance = {:.0f}", sun_distance);
#endif

    // the sun's settings: the values as they were in the system info, else the defaults (floats,
    // as +numberWithFloat: stored them: item 15); the radius a double
    oo::PList::Dict sunSettings;
    sunSettings["sun_radius"] = oo::PList(sun_radius);
    if (const oo::PList* value = systeminfo.find("corona_shimmer"))
        sunSettings["corona_shimmer"] = *value;
    if (const oo::PList* value = systeminfo.find("corona_hues")) {
        sunSettings["corona_hues"] = *value;
    } else {
        sunSettings["corona_hues"] = oo::PList::singleReal(defaultSunHues);
    }
    if (const oo::PList* value = systeminfo.find("corona_flare")) {
        sunSettings["corona_flare"] = *value;
    } else {
        sunSettings["corona_flare"] = oo::PList::singleReal(defaultSunFlare);
    }
    if (const oo::PList* value = systeminfo.find(oo::StdString(KEY_SUNNAME))) {
        sunSettings[oo::StdString(KEY_SUNNAME)] = *value;
    }
    const oo::PList sun_dict(std::move(sunSettings));
#ifdef OO_DUMP_PLANETINFO
    OO_LOG("planetinfo.record", "corona_flare = {:f}", sun_dict.get<float>("corona_flare"));
    OO_LOG("planetinfo.record", "corona_hues = {:f}", sun_dict.get<float>("corona_hues"));
    OO_LOG("planetinfo.record", "sun_color = {}", oo::DescriptionOf([bgcolor descriptionComponents]));
#endif
    a_sun = [[OOSunEntity alloc] initSunWithColor:bgcolor andDictionary:sun_dict]; // alloc retains!

    [a_sun setStatus:STATUS_ACTIVE];
    [a_sun setPosition:sunPos]; // sets also light origin
    [a_sun setEnergy:1000000.0];
    [self addEntity:a_sun];

    if (sunGoneNova) {
        [a_sun setRadius:sun_radius andCorona:0.3];
        [a_sun setThrowSparks:YES];
        [a_sun setVelocity:kZeroVector];
    }

    // set the lighting only after we know which sun we have.
    [self setLighting];
    OO_DEBUG_POP_PROGRESS();

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - main station");
    /*- space station -*/
    stationPos = [a_planet position];

    vf = VectorIn(systeminfo, "station_vector", kZeroVector);
#ifdef OO_DUMP_PLANETINFO
    OO_LOG("planetinfo.record", "station_vector = {:.3f} {:.3f} {:.3f}", vf.x, vf.y, vf.z);
#endif
    stationPos = HPvector_subtract(stationPos, vectorToHPVector(vector_multiply_scalar(vf, 2.0 * planet_radius)));

    //// possibly systeminfo has an override for the station
    stationDesc = systeminfo.get<std::string>("station", "coriolis");
#ifdef OO_DUMP_PLANETINFO
    OO_LOG("planetinfo.record", "station = {}", stationDesc.value_or("(null)"));
#endif

    // a missing role (the unset default) gives no ship, as a nil role did
    a_station = stationDesc.has_value() ? (StationEntity*)[self cxx_newShipWithRole:*stationDesc] : nil; // retain count = 1

    /*	Sanity check: ensure that only stations are generated here. This is an
            attempt to fix exceptions of the form:
                    OOInvalidArgumentException : *** -[ShipEntity setPlanet:]: selector
                    not recognized [self = 0x19b7e000] *****
            which I presume to be originating here since all other uses of
            setPlanet: are guarded by isStation checks. This error could happen if
            a ship that is not a station has a station role, or equivalently if an
            OXP sets a system's station role to a role used by non-stations.
            -- Ahruman 20080303
    */
    if (![a_station isStation] || ![a_station validForAddToUniverse]) {
        if (a_station == nil) {
            // Should have had a more specific error already, just specify context
            OO_LOG("universe.setup.badStation", "Failed to set up a ship for role \"{}\" as system station, trying again with \"{}\".", stationDesc.value_or("(null)"), defaultStationDesc.value_or("(null)"));
        } else {
            OO_LOG("universe.setup.badStation", "***** ERROR: Attempt to use non-station ship of type \"{}\" for role \"{}\" as system station, trying again with \"{}\".", oo::DescriptionOf([a_station name]), stationDesc.value_or("(null)"), defaultStationDesc.value_or("(null)"));
        }
        [a_station release];
        stationDesc = defaultStationDesc;
        a_station = stationDesc.has_value() ? (StationEntity*)[self cxx_newShipWithRole:*stationDesc] : nil; // retain count = 1

        if (![a_station isStation] || ![a_station validForAddToUniverse]) {
            if (a_station == nil) {
                OO_LOG("universe.setup.badStation", "On retry, failed to set up a ship for role \"{}\" as system station. Trying to fall back to built-in Coriolis station.", stationDesc.value_or("(null)"));
            } else {
                OO_LOG("universe.setup.badStation", "***** ERROR: On retry, rolled non-station ship of type \"{}\" for role \"{}\". Non-station ships should not have this role! Trying to fall back to built-in Coriolis station.", oo::DescriptionOf([a_station name]), stationDesc.value_or("(null)"));
            }
            [a_station release];

            a_station = (StationEntity*)[self cxx_newShipWithName:"coriolis-station"];
            if (![a_station isStation] || ![a_station validForAddToUniverse]) {
                OO_LOG("universe.setup.badStation", "{}", "Could not create built-in Coriolis station! Generating a stationless system.");
                DESTROY(a_station);
            }
        }
    }

    if (a_station != nil) {
        [a_station setOrientation:quaternion_rotation_between(vf, make_vector(0.0, 0.0, 1.0))];
        [a_station setPosition:stationPos];
        [a_station setPitch:0.0];
        [a_station setScanClass:CLASS_STATION];
        //[a_station setPlanet:[self planet]];	// done inside addEntity.
        [a_station setEquivalentTechLevel:techlevel];
        [self addEntity:a_station]; // STATUS_IN_FLIGHT, AI state GLOBAL
        [a_station setStatus:STATUS_ACTIVE]; // For backward compatibility. Might not be needed.
        [a_station setAllowsFastDocking:true]; // Main stations always allow fast docking.
        [a_station setAllegiance:@"galcop"]; // Main station is galcop controlled
    }
    OO_DEBUG_POP_PROGRESS();

    cachedSun = a_sun;
    cachedPlanet = a_planet;
    cachedStation = a_station;
    closeSystems.reset();
    OO_DEBUG_POP_PROGRESS();

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - populate from wormholes");
    [self populateSpaceFromActiveWormholes];
    OO_DEBUG_POP_PROGRESS();

    [a_sun release];
    [a_station release];
}

- (void)populateNormalSpace
{
    const oo::PList systeminfo = [systemManager cxx_getPropertiesForCurrentSystem];

    BOOL sunGoneNova = systeminfo.get<bool>("sun_gone_nova");
    // check for nova
    if (sunGoneNova) {
        OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - post-nova");

        HPVector v0 = make_HPvector(0, 0, 34567.89);
        double min_safe_dist2 = 6000000.0 * 6000000.0;
        HPVector sunPos = [cachedSun position];
        while (HPmagnitude2(cachedSun->position) < min_safe_dist2) // back off the planetary bodies
        {
            v0.z *= 2.0;

            sunPos = HPvector_add(sunPos, v0);
            [cachedSun setPosition:sunPos]; // also sets light origin
        }

        [self removeEntity:cachedPlanet]; // and Poof! it's gone
        cachedPlanet = nil;
        [self removeEntity:cachedStation]; // also remove main station
        cachedStation = nil;
    }

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - populate from hyperpoint");
    //	[self populateSpaceFromHyperPoint:witchPos toPlanetPosition: a_planet->position andSunPosition: a_sun->position];
    [self clearSystemPopulator];

    if ([PLAYER status] != STATUS_START_GAME) {
        const std::string populator = systeminfo.get<std::string>("populator", (sunGoneNova) ? "novaSystemWillPopulate" : "systemWillPopulate");
        system_repopulator = systeminfo.get<std::string>("repopulator", (sunGoneNova) ? "novaSystemWillRepopulate" : "systemWillRepopulate");

        JSContext* context = OOJSAcquireContext();
        [PLAYER doWorldScriptEvent:cxx_OOJSIDFromString(populator) inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
        OOJSRelinquishContext(context);
        [self populateSystemFromDictionariesWithSun:cachedSun andPlanet:cachedPlanet];
    }

    OO_DEBUG_POP_PROGRESS();

    // systeminfo might have a 'script_actions' resource we want to activate now...
    const oo::PList* script_actions = systeminfo.get<oo::PList::Array>("script_actions");
    if (script_actions != nullptr) {
        cxx_OOStandardsDeprecated(oo::str::format("The script_actions system info key is deprecated for %s.", TextOrNull([self cxx_getSystemName:systemID]).c_str()));
        if (!OOEnforceStandards()) {
            OO_DEBUG_PUSH_PROGRESS(@"%@", @"setUpSpace - legacy script_actions");
            // the legacy script engine is not migrated yet: it gets the array it read before
            [PLAYER runUnsanitizedScriptActions:oo::ObjectFromPList(*script_actions)
                              allowingAIMethods:NO
                                withContextName:@"<system script_actions>"
                                      forTarget:nil];
            OO_DEBUG_POP_PROGRESS();
        }
    }

    next_repopulation = randf() * SYSTEM_REPOPULATION_INTERVAL;
}

- (void)clearSystemPopulator
{
    populatorSettings = oo::PList(oo::PList::Dict { });
}

- (oo::PList)cxx_getPopulatorSettings
{
    return populatorSettings;
}

- (void)cxx_setPopulatorSetting:(const std::string&)key to:(const oo::PList&)setting
{
    if (!populatorSettings.isDict())
        populatorSettings = oo::PList(oo::PList::Dict { });
    oo::PList::Dict& settings = *populatorSettings.getIf<oo::PList::Dict>();
    if (setting.isNull()) {
        settings.erase(key);
    } else {
        settings[key] = setting;
    }
}

- (BOOL)deterministicPopulation
{
    return deterministic_population;
}

- (void)populateSystemFromDictionariesWithSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet
{
    Random_Seed systemSeed = [systemManager getRandomSeedForCurrentSystem];
    NSArray* blocks = [populatorSettings allValues];
    NSArray* sortedBlocks = [blocks sortedArrayUsingFunction:OOSortFunction(populatorPrioritySort) context:nil];
    NSDictionary* populator = nil;
    HPVector location = kZeroHPVector;
    uint32_t i, locationSeed, groupCount, rndvalue;
    RANROTSeed rndcache = RANROTGetFullSeed();
    RANROTSeed rndlocal = RANROTGetFullSeed();
    std::string locationCode;
    OOJSPopulatorDefinition* pdef = nil;
    for (const oo::PList& populator : sortedBlocks) {
        deterministic_population = populator.get<bool>("deterministic", NO);
        if (EXPECT_NOT(sun == nil || planet == nil)) {
            // needs to be a non-nova system, and not interstellar space
            deterministic_population = NO;
        }

        locationSeed = populator.get<unsigned int>("locationSeed", 0);
        groupCount = populator.get<unsigned int>("groupCount", 1);

        for (i = 0; i < groupCount; i++) {
            locationCode = populator.get<std::string>("location", "COORDINATES");
            if (locationCode == "COORDINATES") {
                location = HPVectorIn(populator, "coordinates", kZeroHPVector);
            } else {
                if (locationSeed != 0) {
                    rndcache = RANROTGetFullSeed();
                    // different place for each system
                    rndlocal = RanrotSeedFromRandomSeed(systemSeed);
                    rndvalue = RanrotWithSeed(&rndlocal);
                    // ...for location seed
                    rndlocal = MakeRanrotSeed(rndvalue + locationSeed);
                    rndvalue = RanrotWithSeed(&rndlocal);
                    // ...for iteration (63647 is nothing special, just a largish prime)
                    RANROTSetFullSeed(MakeRanrotSeed(rndvalue + (i * 63647)));
                } else {
                    // not fixed coordinates and not seeded RNG; can't
                    // be deterministic
                    deterministic_population = NO;
                }
                if (sun == nil || planet == nil) {
                    // all interstellar space and nova locations equal to WITCHPOINT
                    location = [self cxx_locationByCode:"WITCHPOINT" withSun:nil andPlanet:nil];
                } else {
                    location = [self cxx_locationByCode:locationCode withSun:sun andPlanet:planet];
                }
                if (locationSeed != 0) {
                    // go back to the main random sequence
                    RANROTSetFullSeed(rndcache);
                }
            }
            // location now contains a Vector coordinate, one way or another
            pdef = ObjectForKeyIn(populator, "callbackObj"); // an Object node: the populator definition itself
            [pdef runCallback:location];
        }
    }
    // nothing is deterministic once the populator is done
    deterministic_population = NO;
}

/* Generates a position within one of the named regions:
 *
 * WITCHPOINT: within scanner of witchpoint
 * LANE_*: within two scanner of lane, not too near each end
 * STATION_AEGIS: within two scanner of main station, not in planet
 * *_ORBIT_*: around the object, in a shell relative to object radius
 * TRIANGLE: somewhere in the triangle defined by W, P, S
 * INNER_SYSTEM: closer to the sun than the planet is
 * OUTER_SYSTEM: further from the sun than the planet is
 * *_OFFPLANE: like the above, but not on the orbital plane
 *
 * Can be called with nil sun or planet, but if so the calling function
 * must make sure the location code is WITCHPOINT.
 */
- (HPVector)cxx_locationByCode:(const std::string&)code withSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet
{
    HPVector result = kZeroHPVector;
    if (code == "WITCHPOINT" || sun == nil || planet == nil || [sun goneNova]) {
        result = OOHPVectorRandomSpatial(SCANNER_MAX_RANGE);
    }
    // past this point, can assume non-nil sun, planet
    else {
        if (code == "LANE_WPS") {
            // pick position on one of the lanes, weighted by lane length
            double l1 = HPmagnitude([planet position]);
            double l2 = HPmagnitude(HPvector_subtract([sun position], [planet position]));
            double l3 = HPmagnitude([sun position]);
            double total = l1 + l2 + l3;
            float choice = randf();
            if (choice < l1 / total) {
                return [self cxx_locationByCode:"LANE_WP" withSun:sun andPlanet:planet];
            } else if (choice < (l1 + l2) / total) {
                return [self cxx_locationByCode:"LANE_PS" withSun:sun andPlanet:planet];
            } else {
                return [self cxx_locationByCode:"LANE_WS" withSun:sun andPlanet:planet];
            }
        } else if (code == "LANE_WP") {
            result = OORandomPositionInCylinder(kZeroHPVector, SCANNER_MAX_RANGE, [planet position], [planet radius] * 3, LANE_WIDTH);
        } else if (code == "LANE_WS") {
            result = OORandomPositionInCylinder(kZeroHPVector, SCANNER_MAX_RANGE, [sun position], [sun radius] * 3, LANE_WIDTH);
        } else if (code == "LANE_PS") {
            result = OORandomPositionInCylinder([planet position], [planet radius] * 3, [sun position], [sun radius] * 3, LANE_WIDTH);
        } else if (code == "STATION_AEGIS") {
            do {
                result = OORandomPositionInShell([[self station] position], [[self station] collisionRadius] * 1.2, SCANNER_MAX_RANGE * 2.0);
            } while (HPdistance2(result, [planet position]) < [planet radius] * [planet radius] * 1.5);
            // loop to make sure not generated too close to the planet's surface
        } else if (code == "PLANET_ORBIT_LOW") {
            result = OORandomPositionInShell([planet position], [planet radius] * 1.1, [planet radius] * 2.0);
        } else if (code == "PLANET_ORBIT") {
            result = OORandomPositionInShell([planet position], [planet radius] * 2.0, [planet radius] * 4.0);
        } else if (code == "PLANET_ORBIT_HIGH") {
            result = OORandomPositionInShell([planet position], [planet radius] * 4.0, [planet radius] * 8.0);
        } else if (code == "STAR_ORBIT_LOW") {
            result = OORandomPositionInShell([sun position], [sun radius] * 1.1, [sun radius] * 2.0);
        } else if (code == "STAR_ORBIT") {
            result = OORandomPositionInShell([sun position], [sun radius] * 2.0, [sun radius] * 4.0);
        } else if (code == "STAR_ORBIT_HIGH") {
            result = OORandomPositionInShell([sun position], [sun radius] * 4.0, [sun radius] * 8.0);
        } else if (code == "TRIANGLE") {
            do {
                // pick random point in triangle by algorithm at
                // http://adamswaab.wordpress.com/2009/12/11/random-point-in-a-triangle-barycentric-coordinates/
                // simplified by using the origin as A
                OOScalar r = randf();
                OOScalar s = randf();
                if (r + s >= 1) {
                    r = 1 - r;
                    s = 1 - s;
                }
                result = HPvector_add(HPvector_multiply_scalar([planet position], r), HPvector_multiply_scalar([sun position], s));
            }
            // make sure at least 3 radii from vertices
            while (HPdistance2(result, [sun position]) < [sun radius] * [sun radius] * 9.0 || HPdistance2(result, [planet position]) < [planet radius] * [planet radius] * 9.0 || HPmagnitude2(result) < SCANNER_MAX_RANGE2 * 9.0);
        } else if (code == "INNER_SYSTEM") {
            do {
                result = OORandomPositionInShell([sun position], [sun radius] * 3.0, HPdistance([sun position], [planet position]));
                result = OOProjectHPVectorToPlane(result, kZeroHPVector, HPcross_product([sun position], [planet position]));
                result = HPvector_add(result, OOHPVectorRandomSpatial([planet radius]));
                // projection to plane could bring back too close to sun
            } while (HPdistance2(result, [sun position]) < [sun radius] * [sun radius] * 9.0);
        } else if (code == "INNER_SYSTEM_OFFPLANE") {
            result = OORandomPositionInShell([sun position], [sun radius] * 3.0, HPdistance([sun position], [planet position]));
        } else if (code == "OUTER_SYSTEM") {
            result = OORandomPositionInShell([sun position], HPdistance([sun position], [planet position]), HPdistance([sun position], [planet position]) * 10.0); // no more than 10 AU out
            result = OOProjectHPVectorToPlane(result, kZeroHPVector, HPcross_product([sun position], [planet position]));
            result = HPvector_add(result, OOHPVectorRandomSpatial(0.01 * HPdistance(result, [sun position]))); // within 1% of plane
        } else if (code == "OUTER_SYSTEM_OFFPLANE") {
            result = OORandomPositionInShell([sun position], HPdistance([sun position], [planet position]), HPdistance([sun position], [planet position]) * 10.0); // no more than 10 AU out
        } else {
            OO_LOG(kOOLogUniversePopulateError, "Named populator region {} is not implemented, falling back to WITCHPOINT", code);
            result = OOHPVectorRandomSpatial(SCANNER_MAX_RANGE);
        }
    }
    return result;
}

- (void)setAmbientLightLevel:(float)newValue
{
    OOAssert(UNIVERSE != nil, "Attempt to set ambient light level with a non yet existent universe.");

    ambientLightLevel = OOClamp_0_max_f(newValue, 10.0f);
    return;
}

- (float)ambientLightLevel
{
    return ambientLightLevel;
}

- (void)setLighting
{
    /*

    GL_LIGHT1 is the sun and is active while a sun exists in space
    where there is no sun (witch/interstellar space) this is placed at the origin

    Shaders: this light is also used inside the station and needs to have its position reset
    relative to the player whenever demo ships or background scenes are to be shown -- 20100111


    GL_LIGHT0 is the light for inside the station and needs to have its position reset
    relative to the player whenever demo ships or background scenes are to be shown

    Shaders: this light is not used.  -- 20100111

    */

    OOSunEntity* the_sun = [self sun];
    SkyEntity* the_sky = nil;
    GLfloat sun_pos[] = { 0.0, 0.0, 0.0, 1.0 }; // equivalent to kZeroVector - for interstellar space.
    GLfloat sun_ambient[] = { 0.0, 0.0, 0.0, 1.0 }; // overridden later in code
    int i;

    for (i = n_entities - 1; i > 0; i--)
        if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[SkyEntity class]]))
            the_sky = (SkyEntity*)sortedEntities[i];

    if (the_sun) {
        [the_sun getDiffuseComponents:sun_diffuse];
        [the_sun getSpecularComponents:sun_specular];
        OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
        OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
        OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
        sun_pos[0] = the_sun->position.x;
        sun_pos[1] = the_sun->position.y;
        sun_pos[2] = the_sun->position.z;
    } else {
        // witchspace
        stars_ambient[0] = 0.05;
        stars_ambient[1] = 0.20;
        stars_ambient[2] = 0.05;
        stars_ambient[3] = 1.0;
        sun_diffuse[0] = 0.85;
        sun_diffuse[1] = 1.0;
        sun_diffuse[2] = 0.85;
        sun_diffuse[3] = 1.0;
        sun_specular[0] = 0.95;
        sun_specular[1] = 1.0;
        sun_specular[2] = 0.95;
        sun_specular[3] = 1.0;
        OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
        OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
        OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
    }

    OOGL(glLightfv(GL_LIGHT1, GL_POSITION, sun_pos));

    if (the_sky) {
        // ambient lighting!
        GLfloat r, g, b, a;
        [[the_sky skyColor] getRed:&r green:&g blue:&b alpha:&a];
        r = r * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[0] * SUN_AMBIENT_INFLUENCE;
        g = g * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[1] * SUN_AMBIENT_INFLUENCE;
        b = b * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[2] * SUN_AMBIENT_INFLUENCE;
        GLfloat ambient_level = [self ambientLightLevel];
        stars_ambient[0] = ambient_level * SKY_AMBIENT_ADJUSTMENT * (1.0 + r) * (1.0 + r);
        stars_ambient[1] = ambient_level * SKY_AMBIENT_ADJUSTMENT * (1.0 + g) * (1.0 + g);
        stars_ambient[2] = ambient_level * SKY_AMBIENT_ADJUSTMENT * (1.0 + b) * (1.0 + b);
        stars_ambient[3] = 1.0;
    }

    // light for demo ships display..
    OOGL(glLightfv(GL_LIGHT0, GL_AMBIENT, docked_light_ambient));
    OOGL(glLightfv(GL_LIGHT0, GL_DIFFUSE, docked_light_diffuse));
    OOGL(glLightfv(GL_LIGHT0, GL_SPECULAR, docked_light_specular));
    OOGL(glLightfv(GL_LIGHT0, GL_POSITION, demo_light_position));
    OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
}

// Call this method to avoid lighting glich after windowed/fullscreen transition on macs.
- (void)forceLightSwitch
{
    demo_light_on = !demo_light_on;
}

- (void)setMainLightPosition:(Vector)sunPos
{
    main_light_position[0] = sunPos.x;
    main_light_position[1] = sunPos.y;
    main_light_position[2] = sunPos.z;
    main_light_position[3] = 1.0;
}

- (ShipEntity*)addShipWithRole:(const std::string&)desc launchPos:(HPVector)launchPos rfactor:(GLfloat)rfactor
{
    if (rfactor != 0.0) {
        // Calculate the position as soon as possible, to minimise 'lollipop flash'
        launchPos.x += 2 * rfactor * (randf() - 0.5);
        launchPos.y += 2 * rfactor * (randf() - 0.5);
        launchPos.z += 2 * rfactor * (randf() - 0.5);
    }

    ShipEntity* ship = [self cxx_newShipWithRole:desc]; // retain count = 1

    if (ship) {
        [ship setPosition:launchPos]; // minimise 'lollipop flash'

        // Deal with scripted cargopods and ensure they are filled with something.
        if ([ship hasRole:@"cargopod"])
            [self fillCargopodWithRandomCargo:ship];

        // Ensure piloted ships have pilots.
        if (![ship crew] && ![ship isUnpiloted])
            [ship setCrew:oo::NSArrayFromObjects(std::vector<id> {
                              [OOCharacter randomCharacterWithRole:desc
                                                 andOriginalSystem:Ranrot() & 255] })];

        if ([ship scanClass] == CLASS_NOT_SET) {
            [ship setScanClass:CLASS_NEUTRAL];
        }
        [self addEntity:ship]; // STATUS_IN_FLIGHT, AI state GLOBAL
        [ship release];
        return ship;
    }
    return nil;
}

- (void)cxx_addShipWithRole:(const std::string&)desc nearRouteOneAt:(double)route_fraction
{
    // adds a ship within scanner range of a point on route 1

    Entity* theStation = [self station];
    if (!theStation) {
        return;
    }

    HPVector launchPos = OOHPVectorInterpolate([self getWitchspaceExitPosition], [theStation position], route_fraction);

    [self addShipWithRole:desc launchPos:launchPos rfactor:SCANNER_MAX_RANGE];
}

- (HPVector)cxx_coordinatesForPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system returningScalar:(GLfloat*)my_scalar
{
    /*	the point is described using a system selected by a string
            consisting of a three letter code.

            The first letter indicates the feature that is the origin of the coordinate system.
                    w => witchpoint
                    s => sun
                    p => planet

            The next letter indicates the feature on the 'z' axis of the coordinate system.
                    w => witchpoint
                    s => sun
                    p => planet

            Then the 'y' axis of the system is normal to the plane formed by the planet, sun and witchpoint.
            And the 'x' axis of the system is normal to the y and z axes.
            So:
                    ps:		z axis = (planet -> sun)		y axis = normal to (planet - sun - witchpoint)	x axis = normal to y and z axes
                    pw:		z axis = (planet -> witchpoint)	y axis = normal to (planet - witchpoint - sun)	x axis = normal to y and z axes
                    sp:		z axis = (sun -> planet)		y axis = normal to (sun - planet - witchpoint)	x axis = normal to y and z axes
                    sw:		z axis = (sun -> witchpoint)	y axis = normal to (sun - witchpoint - planet)	x axis = normal to y and z axes
                    wp:		z axis = (witchpoint -> planet)	y axis = normal to (witchpoint - planet - sun)	x axis = normal to y and z axes
                    ws:		z axis = (witchpoint -> sun)	y axis = normal to (witchpoint - sun - planet)	x axis = normal to y and z axes

            The third letter denotes the units used:
                    m:		meters
                    p:		planetary radii
                    s:		solar radii
                    u:		distance between first two features indicated (eg. spu means that u = distance from sun to the planet)

            in interstellar space (== no sun) coordinates are absolute irrespective of the system used.

            [1.71] The position code "abs" can also be used for absolute coordinates.

    */

    const std::string l_sys = oo::str::lowercase(system);
    if (oo::str::length(l_sys) != 3) // UTF-16 units, as -length counted
        return kZeroHPVector;
    OOPlanetEntity* the_planet = [self planet];
    OOSunEntity* the_sun = [self sun];
    if (the_planet == nil || the_sun == nil || l_sys == "abs") {
        if (my_scalar)
            *my_scalar = 1.0;
        return pos;
    }
    HPVector w_pos = [self getWitchspaceExitPosition]; // don't reset PRNG
    HPVector p_pos = the_planet->position;
    HPVector s_pos = the_sun->position;

    const char* c_sys = l_sys.c_str();
    HPVector p0, p1, p2;

    switch (c_sys[0]) {
    case 'w':
        p0 = w_pos;
        switch (c_sys[1]) {
        case 'p':
            p1 = p_pos;
            p2 = s_pos;
            break;
        case 's':
            p1 = s_pos;
            p2 = p_pos;
            break;
        default:
            return kZeroHPVector;
        }
        break;
    case 'p':
        p0 = p_pos;
        switch (c_sys[1]) {
        case 'w':
            p1 = w_pos;
            p2 = s_pos;
            break;
        case 's':
            p1 = s_pos;
            p2 = w_pos;
            break;
        default:
            return kZeroHPVector;
        }
        break;
    case 's':
        p0 = s_pos;
        switch (c_sys[1]) {
        case 'w':
            p1 = w_pos;
            p2 = p_pos;
            break;
        case 'p':
            p1 = p_pos;
            p2 = w_pos;
            break;
        default:
            return kZeroHPVector;
        }
        break;
    default:
        return kZeroHPVector;
    }
    HPVector k = HPvector_normal_or_zbasis(HPvector_subtract(p1, p0)); // 'forward'
    HPVector v = HPvector_normal_or_xbasis(HPvector_subtract(p2, p0)); // temporary vector in plane of 'forward' and 'right'

    HPVector j = HPcross_product(k, v); // 'up'
    HPVector i = HPcross_product(j, k); // 'right'

    GLfloat scale = 1.0;
    switch (c_sys[2]) {
    case 'p':
        scale = [the_planet radius];
        break;

    case 's':
        scale = [the_sun radius];
        break;

    case 'u':
        scale = HPmagnitude(HPvector_subtract(p1, p0));
        break;

    case 'm':
        scale = 1.0f;
        break;

    default:
        return kZeroHPVector;
    }
    if (my_scalar)
        *my_scalar = scale;

    // result = p0 + ijk
    HPVector result = p0; // origin
    result.x += scale * (pos.x * i.x + pos.y * j.x + pos.z * k.x);
    result.y += scale * (pos.x * i.y + pos.y * j.y + pos.z * k.y);
    result.z += scale * (pos.x * i.z + pos.y * j.z + pos.z * k.z);

    return result;
}

- (std::optional<std::string>)cxx_expressPosition:(HPVector)pos inCoordinateSystem:(const std::string&)system
{
    HPVector result = [self cxx_legacyPositionFrom:pos asCoordinateSystem:system];
    return oo::str::format("%s %.2f %.2f %.2f", system.c_str(), result.x, result.y, result.z);
}

- (HPVector)cxx_legacyPositionFrom:(HPVector)pos asCoordinateSystem:(const std::string&)system
{
    const std::string l_sys = oo::str::lowercase(system);
    if (oo::str::length(l_sys) != 3) // UTF-16 units, as -length counted
        return kZeroHPVector;
    OOPlanetEntity* the_planet = [self planet];
    OOSunEntity* the_sun = [self sun];
    if (the_planet == nil || the_sun == nil || l_sys == "abs") {
        return pos;
    }
    HPVector w_pos = [self getWitchspaceExitPosition]; // don't reset PRNG
    HPVector p_pos = the_planet->position;
    HPVector s_pos = the_sun->position;

    const char* c_sys = l_sys.c_str();
    HPVector p0, p1, p2;

    switch (c_sys[0]) {
    case 'w':
        p0 = w_pos;
        switch (c_sys[1]) {
        case 'p':
            p1 = p_pos;
            p2 = s_pos;
            break;
        case 's':
            p1 = s_pos;
            p2 = p_pos;
            break;
        default:
            return kZeroHPVector;
        }
        break;
    case 'p':
        p0 = p_pos;
        switch (c_sys[1]) {
        case 'w':
            p1 = w_pos;
            p2 = s_pos;
            break;
        case 's':
            p1 = s_pos;
            p2 = w_pos;
            break;
        default:
            return kZeroHPVector;
        }
        break;
    case 's':
        p0 = s_pos;
        switch (c_sys[1]) {
        case 'w':
            p1 = w_pos;
            p2 = p_pos;
            break;
        case 'p':
            p1 = p_pos;
            p2 = w_pos;
            break;
        default:
            return kZeroHPVector;
        }
        break;
    default:
        return kZeroHPVector;
    }
    HPVector k = HPvector_normal_or_zbasis(HPvector_subtract(p1, p0)); // 'z' axis in m
    HPVector v = HPvector_normal_or_xbasis(HPvector_subtract(p2, p0)); // temporary vector in plane of 'forward' and 'right'

    HPVector j = HPcross_product(k, v); // 'y' axis in m
    HPVector i = HPcross_product(j, k); // 'x' axis in m

    GLfloat scale = 1.0;
    switch (c_sys[2]) {
    case 'p': {
        scale = 1.0f / [the_planet radius];
        break;
    }
    case 's': {
        scale = 1.0f / [the_sun radius];
        break;
    }

    case 'u':
        scale = 1.0f / HPdistance(p1, p0);
        break;

    case 'm':
        scale = 1.0f;
        break;

    default:
        return kZeroHPVector;
    }

    // result = p0 + ijk
    HPVector r_pos = HPvector_subtract(pos, p0);
    HPVector result = make_HPvector(scale * (r_pos.x * i.x + r_pos.y * i.y + r_pos.z * i.z),
        scale * (r_pos.x * j.x + r_pos.y * j.y + r_pos.z * j.z),
        scale * (r_pos.x * k.x + r_pos.y * k.y + r_pos.z * k.z)); // scale * dot_products

    return result;
}

- (HPVector)cxx_coordinatesFromCoordinateSystemString:(const std::string&)system_x_y_z
{
    const std::vector<std::string> tokens = oo::str::tokens(system_x_y_z);
    if (tokens.size() != 4) {
        // Not necessarily an error.
        return make_HPvector(0, 0, 0);
    }
    // each number read as at<float> read the token string before
    oo::PList::Array tokenList;
    for (const std::string& token : tokens)
        tokenList.push_back(oo::PList(token));
    const oo::PList tokenPList(std::move(tokenList));
    GLfloat dummy;
    return [self cxx_coordinatesForPosition:make_HPvector(tokenPList.at<float>(1), tokenPList.at<float>(2), tokenPList.at<float>(3)) withCoordinateSystem:tokens[0] returningScalar:&dummy];
}

- (BOOL)cxx_addShipWithRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system
{
    // initial position
    GLfloat scalar = 1.0;
    HPVector launchPos = [self cxx_coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
    //	randomise
    GLfloat rfactor = scalar;
    if (rfactor > SCANNER_MAX_RANGE)
        rfactor = SCANNER_MAX_RANGE;
    if (rfactor < 1000)
        rfactor = 1000;

    return ([self addShipWithRole:desc launchPos:launchPos rfactor:rfactor] != nil);
}

- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc atPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system
{
    // initial bounding box
    GLfloat scalar = 1.0;
    HPVector launchPos = [self cxx_coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
    GLfloat distance_from_center = 0.0;
    HPVector v_from_center, ship_pos;
    std::vector<HPVector> ship_positions(howMany);
    int i = 0;
    int scale_up_after = 0;
    int current_shell = 0;
    GLfloat walk_factor = 2.0;
    while (i < howMany) {
        ShipEntity* ship = [self addShipWithRole:desc launchPos:launchPos rfactor:0.0];
        if (ship == nil)
            return NO;
        OOScanClass scanClass = [ship scanClass];
        [ship setScanClass:CLASS_NO_DRAW]; // avoid lollipop flash

        GLfloat safe_distance2 = ship->collision_radius * ship->collision_radius * SAFE_ADDITION_FACTOR2;
        BOOL safe;
        int limit_count = 8;

        v_from_center = kZeroHPVector;
        do {
            do {
                v_from_center.x += walk_factor * (randf() - 0.5);
                v_from_center.y += walk_factor * (randf() - 0.5);
                v_from_center.z += walk_factor * (randf() - 0.5); // drunkards walk
            } while ((v_from_center.x == 0.0) && (v_from_center.y == 0.0) && (v_from_center.z == 0.0));
            v_from_center = HPvector_normal(v_from_center); // guaranteed non-zero

            ship_pos = make_HPvector(launchPos.x + distance_from_center * v_from_center.x,
                launchPos.y + distance_from_center * v_from_center.y,
                launchPos.z + distance_from_center * v_from_center.z);

            // check this position against previous ship positions in this shell
            safe = YES;
            int j = i - 1;
            while (safe && (j >= current_shell)) {
                safe = (safe && (HPdistance2(ship_pos, ship_positions[j]) > safe_distance2));
                j--;
            }
            if (!safe) {
                limit_count--;
                if (!limit_count) // give up and expand the shell
                {
                    limit_count = 8;
                    distance_from_center += sqrt(safe_distance2); // expand to the next distance
                }
            }

        } while (!safe);

        [ship setPosition:ship_pos];
        [ship setScanClass:scanClass == CLASS_NOT_SET ? CLASS_NEUTRAL : scanClass];

        Quaternion qr;
        quaternion_set_random(&qr);
        [ship setOrientation:qr];

        // [self addEntity:ship];	// STATUS_IN_FLIGHT, AI state GLOBAL

        ship_positions[i] = ship_pos;
        i++;
        if (i > scale_up_after) {
            current_shell = i;
            scale_up_after += 1 + 2 * i;
            distance_from_center += sqrt(safe_distance2); // fill the next shell
        }
    }
    return YES;
}

- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system
{
    // initial bounding box
    GLfloat scalar = 1.0;
    HPVector launchPos = [self cxx_coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
    GLfloat rfactor = scalar;
    if (rfactor > SCANNER_MAX_RANGE)
        rfactor = SCANNER_MAX_RANGE;
    if (rfactor < 1000)
        rfactor = 1000;
    BoundingBox launch_bbox;
    bounding_box_reset_to_vector(&launch_bbox, make_vector(launchPos.x - rfactor, launchPos.y - rfactor, launchPos.z - rfactor));
    bounding_box_add_xyz(&launch_bbox, launchPos.x + rfactor, launchPos.y + rfactor, launchPos.z + rfactor);

    return [self cxx_addShips:howMany withRole:desc intoBoundingBox:launch_bbox];
}

- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system withinRadius:(GLfloat)radius
{
    // initial bounding box
    GLfloat scalar = 1.0;
    HPVector launchPos = [self cxx_coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
    GLfloat rfactor = radius;
    if (rfactor < 1000)
        rfactor = 1000;
    BoundingBox launch_bbox;
    bounding_box_reset_to_vector(&launch_bbox, make_vector(launchPos.x - rfactor, launchPos.y - rfactor, launchPos.z - rfactor));
    bounding_box_add_xyz(&launch_bbox, launchPos.x + rfactor, launchPos.y + rfactor, launchPos.z + rfactor);

    return [self cxx_addShips:howMany withRole:desc intoBoundingBox:launch_bbox];
}

- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc intoBoundingBox:(BoundingBox)bbox
{
    if (howMany < 1)
        return YES;
    if (howMany > 1) {
        // divide the number of ships in two
        int h0 = howMany / 2;
        int h1 = howMany - h0;
        // split the bounding box into two along its longest dimension
        GLfloat lx = bbox.max.x - bbox.min.x;
        GLfloat ly = bbox.max.y - bbox.min.y;
        GLfloat lz = bbox.max.z - bbox.min.z;
        BoundingBox bbox0 = bbox;
        BoundingBox bbox1 = bbox;
        if ((lx > lz) && (lx > ly)) // longest dimension is x
        {
            bbox0.min.x += 0.5 * lx;
            bbox1.max.x -= 0.5 * lx;
        } else {
            if (ly > lz) // longest dimension is y
            {
                bbox0.min.y += 0.5 * ly;
                bbox1.max.y -= 0.5 * ly;
            } else // longest dimension is z
            {
                bbox0.min.z += 0.5 * lz;
                bbox1.max.z -= 0.5 * lz;
            }
        }
        // place half the ships into each bounding box
        return ([self cxx_addShips:h0 withRole:desc intoBoundingBox:bbox0] && [self cxx_addShips:h1 withRole:desc intoBoundingBox:bbox1]);
    }

    //	randomise within the bounding box (biased towards the center of the box)
    HPVector pos = make_HPvector(bbox.min.x, bbox.min.y, bbox.min.z);
    pos.x += 0.5 * (randf() + randf()) * (bbox.max.x - bbox.min.x);
    pos.y += 0.5 * (randf() + randf()) * (bbox.max.y - bbox.min.y);
    pos.z += 0.5 * (randf() + randf()) * (bbox.max.z - bbox.min.z);

    return ([self addShipWithRole:desc launchPos:pos rfactor:0.0] != nil);
}

- (BOOL)spawnShip:(id)shipdescObject // shared selector (proposed ADR-0043)
{
    const std::string shipdesc = oo::StdString(shipdescObject);

    // no need to do any more than log - enforcing modes wouldn't even have
    // loaded the legacy script
    cxx_OOStandardsDeprecated(oo::str::format("'spawn' via legacy script is deprecated as a way of adding ships for %s", oo::DescriptionOf(shipdescObject).c_str()));

    ShipEntity* ship;
    oo::PList shipdict;

    shipdict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:shipdesc];
    if (shipdict.isNull())
        return NO;

    ship = [self cxx_newShipWithName:shipdesc]; // retain count is 1

    if (ship == nil)
        return NO;

    // set any spawning characteristics
    const oo::PList* spawnEntry = shipdict.get<oo::PList::Dict>("spawn");
    const oo::PList spawndict = (spawnEntry != nullptr) ? *spawnEntry : oo::PList();
    HPVector pos, rpos, spos;
    std::optional<std::string> positionString;

    // position
    positionString = OptionalStringIn(spawndict, "position");
    if (positionString.has_value()) {
        if (oo::str::hasPrefix(*positionString, "abs ") && ([self planet] != nil || [self sun] != nil)) {
            OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.", "position", "entity", oo::DescriptionOf(shipdescObject));
        }

        pos = [self cxx_coordinatesFromCoordinateSystemString:*positionString];
    } else {
        // without position defined, the ship will be added on top of the witchpoint buoy.
        pos = OOHPVectorRandomRadial(SCANNER_MAX_RANGE);
        OO_LOG_ERR("universe.spawnShip.error", "***** ERROR: failed to find a spawn position for ship {}.", oo::DescriptionOf(shipdescObject));
    }
    [ship setPosition:pos];

    // facing_position
    positionString = OptionalStringIn(spawndict, "facing_position");
    if (positionString.has_value()) {
        if (oo::str::hasPrefix(*positionString, "abs ") && ([self planet] != nil || [self sun] != nil)) {
            OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.", "facing_position", "entity", oo::DescriptionOf(shipdescObject));
        }

        spos = [ship position];
        Quaternion q1;
        rpos = [self cxx_coordinatesFromCoordinateSystemString:*positionString];
        rpos = HPvector_subtract(rpos, spos); // position relative to ship

        if (!HPvector_equal(rpos, kZeroHPVector)) {
            rpos = HPvector_normal(rpos);

            if (!HPvector_equal(rpos, HPvector_flip(kBasisZHPVector))) {
                q1 = quaternion_rotation_between(HPVectorToVector(rpos), kBasisZVector);
            } else {
                // for the inverse of the kBasisZVector the rotation is undefined, so we select one.
                q1 = make_quaternion(0, 1, 0, 0);
            }

            [ship setOrientation:q1];
        }
    }

    [self addEntity:ship]; // STATUS_IN_FLIGHT, AI state GLOBAL
    [ship release];

    return YES;
}

- (void)cxx_witchspaceShipWithPrimaryRole:(const std::string&)role
{
    // adds a ship exiting witchspace (corollary of when ships leave the system)
    ShipEntity* ship = nil;
    oo::PList systeminfo;
    OOGovernmentID government;

    systeminfo = [self cxx_currentSystemData];
    government = systeminfo.get<unsigned char>(oo::StdString(KEY_GOVERNMENT));

    ship = [self cxx_newShipWithRole:role]; // retain count = 1

    // Deal with scripted cargopods and ensure they are filled with something.
    if (ship && [ship hasRole:@"cargopod"]) {
        [self fillCargopodWithRandomCargo:ship];
    }

    if (ship) {
        if (([ship scanClass] == CLASS_NO_DRAW) || ([ship scanClass] == CLASS_NOT_SET))
            [ship setScanClass:CLASS_NEUTRAL];
        if (role == "trader") {
            [ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
            if ([ship hasRole:@"sunskim-trader"] && randf() < 0.25) // select 1/4 of the traders suitable for sunskimming.
            {
                [ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
                [self makeSunSkimmer:ship andSetAI:YES];
            } else {
                [ship switchAITo:@"oolite-traderAI.js"];
            }

            if (([ship pendingEscortCount] > 0) && ((Ranrot() % 7) < government)) // remove escorts if we feel safe
            {
                int nx = [ship pendingEscortCount] - 2 * (1 + (Ranrot() & 3)); // remove 2,4,6, or 8 escorts
                [ship setPendingEscortCount:(nx > 0) ? nx : 0];
            }
        }
        if (role == "pirate") {
            [ship setCargoFlag:CARGO_FLAG_PIRATE];
            [ship setBounty:(Ranrot() & 7) + (Ranrot() & 7) + ((randf() < 0.05) ? 63 : 23) withReason:kOOLegalStatusReasonSetup]; // they already have a price on their heads
        }
        if ([ship crew] == nil && ![ship isUnpiloted])
            [ship setCrew:oo::NSArrayFromObjects(std::vector<id> {
                              [OOCharacter randomCharacterWithRole:role
                                                 andOriginalSystem:Ranrot() & 255] })];
        // The following is set inside leaveWitchspace: AI state GLOBAL, STATUS_EXITING_WITCHSPACE, ai message: EXITED_WITCHSPACE, then STATUS_IN_FLIGHT
        [ship leaveWitchspace];
        [ship release];
    }
}

// adds a ship within the collision radius of the other entity
- (ShipEntity*)cxx_spawnShipWithRole:(const std::string&)desc near:(Entity*)entity
{
    if (entity == nil)
        return nil;

    ShipEntity* ship = nil;
    HPVector spawn_pos;
    Quaternion spawn_q;
    GLfloat offset = (randf() + randf()) * entity->collision_radius;

    quaternion_set_random(&spawn_q);
    spawn_pos = HPvector_add([entity position], vectorToHPVector(vector_multiply_scalar(vector_forward_from_quaternion(spawn_q), offset)));

    ship = [self addShipWithRole:desc launchPos:spawn_pos rfactor:0.0];
    [ship setOrientation:spawn_q];

    return ship;
}

- (OOVisualEffectEntity*)cxx_addVisualEffectAt:(HPVector)pos withKey:(const std::string&)key
{
    OOJS_PROFILE_ENTER

    // minimise the time between creating ship & assigning position.

    OOVisualEffectEntity* vis = [self cxx_newVisualEffectWithName:key]; // is retained
    BOOL success = NO;
    if (vis != nil) {
        [vis setPosition:pos];
        [vis setOrientation:OORandomQuaternion()];

        success = [self addEntity:vis]; // retained globally now

        [vis release];
    }
    return success ? vis : (OOVisualEffectEntity*)nil;

    OOJS_PROFILE_EXIT
}

- (ShipEntity*)addShipAt:(HPVector)pos withRole:(const std::string&)role withinRadius:(GLfloat)radius
{
    OOJS_PROFILE_ENTER

    // minimise the time between creating ship & assigning position.
    if (radius == static_cast<GLfloat>(NSNotFound)) {
        GLfloat scalar = 1.0;
        [self cxx_coordinatesForPosition:pos withCoordinateSystem:"abs" returningScalar:&scalar];
        //	randomise
        GLfloat rfactor = scalar;
        if (rfactor > SCANNER_MAX_RANGE)
            rfactor = SCANNER_MAX_RANGE;
        if (rfactor < 1000)
            rfactor = 1000;
        pos.x += rfactor * (randf() - randf());
        pos.y += rfactor * (randf() - randf());
        pos.z += rfactor * (randf() - randf());
    } else {
        pos = HPvector_add(pos, OOHPVectorRandomSpatial(radius));
    }

    ShipEntity* ship = [self cxx_newShipWithRole:role]; // is retained
    BOOL success = NO;

    if (ship != nil) {
        [ship setPosition:pos];
        if ([ship hasRole:@"cargopod"])
            [self fillCargopodWithRandomCargo:ship];
        OOScanClass scanClass = [ship scanClass];
        if (scanClass == CLASS_NOT_SET) {
            scanClass = CLASS_NEUTRAL;
            [ship setScanClass:scanClass];
        }

        if ([ship crew] == nil && ![ship isUnpiloted]) {
            [ship setCrew:oo::NSArrayFromObjects(std::vector<id> {
                              [OOCharacter randomCharacterWithRole:role
                                                 andOriginalSystem:Ranrot() & 255] })];
        }

        [ship setOrientation:OORandomQuaternion()];

        BOOL trader = role == "trader";
        if (trader) {
            // half of traders created anywhere will now have cargo.
            if (randf() > 0.5f) {
                [ship setCargoFlag:(randf() < 0.66f ? CARGO_FLAG_FULL_PLENTIFUL : CARGO_FLAG_FULL_SCARCE)]; // most of them will carry the cargo produced in-system.
            }

            uint8_t pendingEscortCount = [ship pendingEscortCount];
            if (pendingEscortCount > 0) {
                OOGovernmentID government = [self cxx_currentSystemData].get<unsigned char>(oo::StdString(KEY_GOVERNMENT));
                if ((Ranrot() % 7) < government) // remove escorts if we feel safe
                {
                    int nx = pendingEscortCount - 2 * (1 + (Ranrot() & 3)); // remove 2,4,6, or 8 escorts
                    [ship setPendingEscortCount:(nx > 0) ? nx : 0];
                }
            }
        }

        if (HPdistance([self getWitchspaceExitPosition], pos) > SCANNER_MAX_RANGE) {
            // nothing extra to do
            success = [self addEntity:ship]; // STATUS_IN_FLIGHT, AI state GLOBAL - ship is retained globally
        } else // witchspace incoming traders & pirates need extra settings.
        {
            if (trader) {
                [ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
                if ([ship hasRole:@"sunskim-trader"] && randf() < 0.25) {
                    [ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
                    [self makeSunSkimmer:ship andSetAI:YES];
                } else {
                    [ship switchAITo:@"oolite-traderAI.js"];
                }
            } else if (role == "pirate") {
                [ship setBounty:(Ranrot() & 7) + (Ranrot() & 7) + ((randf() < 0.05) ? 63 : 23) withReason:kOOLegalStatusReasonSetup]; // they already have a price on their heads
            }

            // Status changes inside the following call: AI state GLOBAL, then STATUS_EXITING_WITCHSPACE,
            // with the EXITED_WITCHSPACE message sent to the AI. At last we set STATUS_IN_FLIGHT.
            // Includes addEntity, so ship is retained globally.
            success = [ship witchspaceLeavingEffects];
        }

        [ship release];
    }
    return success ? ship : (ShipEntity*)nil;

    OOJS_PROFILE_EXIT
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_addShipsAt:(HPVector)pos withRole:(const std::string&)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup
{
    OOJS_PROFILE_ENTER

    std::vector<oo::ObjCRef<ShipEntity*>> ships;
    ships.reserve(count);
    ShipEntity* ship = nil;
    OOShipGroup* group = nil;

    if (isGroup) {
        group = [OOShipGroup groupWithName:oo::NSStringFrom(oo::str::format("%s group", role.c_str()))];
    }

    while (count--) {
        ship = [self addShipAt:pos withRole:role withinRadius:radius];
        if (ship != nil) {
            // TODO: avoid collisions!!!
            if (isGroup)
                [ship setGroup:group];
            ships.push_back(oo::ObjCRef<ShipEntity*>(ship));
        }
    }

    return ships; // empty where nil was returned

    OOJS_PROFILE_EXIT
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_addShipsToRoute:(const std::string&)route withRole:(const std::string&)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup
{
    std::vector<oo::ObjCRef<ShipEntity*>> ships;
    ships.reserve(count);
    ShipEntity* ship = nil;
    Entity<OOStellarBody>* entity = nil;
    HPVector pos = kZeroHPVector, direction = kZeroHPVector, point0 = kZeroHPVector, point1 = kZeroHPVector;
    double radius = 0;

    if (route == "pw" || route == "sw" || route == "ps") {
        routeFraction = 1.0f - routeFraction;
    }

    // which route is it?
    if (route == "wp" || route == "pw") {
        point0 = [self getWitchspaceExitPosition];
        entity = [self planet];
        if (entity == nil)
            return { };
        point1 = [entity position];
        radius = [entity radius];
    } else if (route == "ws" || route == "sw") {
        point0 = [self getWitchspaceExitPosition];
        entity = [self sun];
        if (entity == nil)
            return { };
        point1 = [entity position];
        radius = [entity radius];
    } else if (route == "sp" || route == "ps") {
        entity = [self sun];
        if (entity == nil)
            return { };
        point0 = [entity position];
        double radius0 = [entity radius];

        entity = [self planet];
        if (entity == nil)
            return { };
        point1 = [entity position];
        radius = [entity radius];

        // shorten the route by scanner range & sun radius, otherwise ships could be created inside it.
        direction = HPvector_normal(HPvector_subtract(point0, point1));
        point0 = HPvector_subtract(point0, HPvector_multiply_scalar(direction, radius0 + SCANNER_MAX_RANGE * 1.1f));
    } else if (route == "st") {
        point0 = [self getWitchspaceExitPosition];
        if ([self station] == nil)
            return { };
        point1 = [[self station] position];
        radius = [[self station] collisionRadius];
    } else
        return { }; // no route specifier? We shouldn't be here!

    // shorten the route by scanner range & radius, otherwise ships could be created inside the route destination.
    direction = HPvector_normal(HPvector_subtract(point1, point0));
    point1 = HPvector_subtract(point1, HPvector_multiply_scalar(direction, radius + SCANNER_MAX_RANGE * 1.1f));

    pos = [self fractionalPositionFrom:point0 to:point1 withFraction:routeFraction];
    if (isGroup) {
        return [self cxx_addShipsAt:pos withRole:role quantity:count withinRadius:(SCANNER_MAX_RANGE / 10.0f) asGroup:YES];
    } else {
        while (count--) {
            ship = [self addShipAt:pos withRole:role withinRadius:0]; // no radius because pos is already randomised with SCANNER_MAX_RANGE.
            if (ship != nil)
                ships.push_back(oo::ObjCRef<ShipEntity*>(ship));
            if (count > 0)
                pos = [self fractionalPositionFrom:point0 to:point1 withFraction:routeFraction];
        }
    }

    return ships; // empty where nil was returned
}

- (BOOL)cxx_roleIsPirateVictim:(const std::string&)role
{
    return [self cxx_role:role isInCategory:"oolite-pirate-victim"];
}

- (BOOL)cxx_role:(const std::string&)role isInCategory:(const std::string&)category
{
    const oo::PList* categoryInfo = roleCategories.get<oo::PList::Array>(category); // the category's roles, each once
    if (categoryInfo == nullptr) {
        return NO;
    }
    for (const oo::PList& member : *categoryInfo->getIf<oo::PList::Array>()) {
        if (const std::string* memberRole = member.getIf<std::string>(); memberRole != nullptr && *memberRole == role)
            return YES;
    }
    return NO;
}

// used to avoid having lost escorts when player advances clock while docked
- (void)forceWitchspaceEntries
{
    unsigned i;
    for (i = 0; i < n_entities; i++) {
        if (sortedEntities[i]->isShip) {
            ShipEntity* my_ship = (ShipEntity*)sortedEntities[i];
            Entity* my_target = [my_ship primaryTarget];
            if ([my_target isWormhole]) {
                [my_ship enterTargetWormhole];
            } else if ([[my_ship getAI] cxx_state] == "ENTER_WORMHOLE") {
                [my_ship enterTargetWormhole];
            }
        }
    }
}

- (void)addWitchspaceJumpEffectForShip:(ShipEntity*)ship
{
    // don't add rings when system is being populated
    if ([PLAYER status] != STATUS_ENTERING_WITCHSPACE && [PLAYER status] != STATUS_EXITING_WITCHSPACE) {
        [self addEntity:[OORingEffectEntity ringFromEntity:ship]];
        [self addEntity:[OORingEffectEntity shrinkingRingFromEntity:ship]];
    }
}

- (GLfloat)safeWitchspaceExitDistance
{
    for (unsigned i = 0; i < n_entities; i++) {
        Entity* e2 = sortedEntities[i];
        if ([e2 isShip] && [(ShipEntity*)e2 hasPrimaryRole:@"buoy-witchpoint"]) {
            return [(ShipEntity*)e2 collisionRadius] + MIN_DISTANCE_TO_BUOY;
        }
    }
    return MIN_DISTANCE_TO_BUOY;
}

- (void)setUpBreakPattern:(HPVector)pos orientation:(Quaternion)q forDocking:(BOOL)forDocking
{
    int i;
    OOBreakPatternEntity* ring = nil;
    id colorDesc = nil;
    OOColor* color = nil;

    [self setViewDirection:VIEW_FORWARD];

    q.w = -q.w; // reverse the quaternion because this is from the player's viewpoint

    Vector v = vector_forward_from_quaternion(q);
    Vector vel = vector_multiply_scalar(v, -BREAK_PATTERN_RING_SPEED);

    // hyperspace colours

    OOColor* col1 = [OOColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5]; // standard tunnel colour
    OOColor* col2 = [OOColor colorWithRed:0.0 green:0.0 blue:1.0 alpha:0.25]; // standard tunnel colour

    colorDesc = ObjectForKeyIn(globalSettings, "hyperspace_tunnel_color_1"); // +colorWithDescription: takes any description object
    if (colorDesc != nil) {
        color = [OOColor colorWithDescription:colorDesc];
        if (color != nil)
            col1 = color;
        else
            OO_LOG_WARN("hyperspaceTunnel.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
    }

    colorDesc = ObjectForKeyIn(globalSettings, "hyperspace_tunnel_color_2");
    if (colorDesc != nil) {
        color = [OOColor colorWithDescription:colorDesc];
        if (color != nil)
            col2 = color;
        else
            OO_LOG_WARN("hyperspaceTunnel.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
    }

    unsigned sides = kOOBreakPatternMaxSides;
    GLfloat startAngle = 0;
    GLfloat aspectRatio = 1;

    if (forDocking) {
        const oo::PList info = oo::PListFrom([[PLAYER dockedStation] shipInfoDictionary]); // the unmigrated ShipEntity's
        sides = info.get<unsigned int>("tunnel_corners", 4);
        startAngle = info.get<float>("tunnel_start_angle", 45.0f);
        aspectRatio = info.get<float>("tunnel_aspect_ratio", 2.67f);
    }

    for (i = 1; i < 11; i++) {
        ring = [OOBreakPatternEntity breakPatternWithPolygonSides:sides startAngle:startAngle aspectRatio:aspectRatio];
        if (!forDocking) {
            [ring setInnerColor:col1 outerColor:col2];
        }

        Vector offset = vector_multiply_scalar(v, i * BREAK_PATTERN_RING_SPACING);
        [ring setPosition:HPvector_add(pos, vectorToHPVector(offset))]; // ahead of the player
        [ring setOrientation:q];
        [ring setVelocity:vel];
        [ring setLifetime:i * BREAK_PATTERN_RING_SPACING];

        // FIXME: better would be to have break pattern timing not depend on
        // these ring objects existing in the first place. - CIM
        if (forDocking && ![[PLAYER dockedStation] hasBreakPattern]) {
            ring->isImmuneToBreakPatternHide = NO;
        } else if (!forDocking && ![self witchspaceBreakPattern]) {
            ring->isImmuneToBreakPatternHide = NO;
        }
        [self addEntity:ring];
        breakPatternCounter++;
    }
}

- (BOOL)witchspaceBreakPattern
{
    return _witchspaceBreakPattern;
}

- (void)setWitchspaceBreakPattern:(BOOL)newValue
{
    _witchspaceBreakPattern = !!newValue;
}

- (BOOL)dockingClearanceProtocolActive
{
    return _dockingClearanceProtocolActive;
}

- (void)setDockingClearanceProtocolActive:(BOOL)newValue
{
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];
    StationEntity* station = nil;

    /* CIM: picking a random ship type which can take the same primary
     * role as the station to determine whether it has no set docking
     * clearance requirements seems unlikely to work entirely
     * correctly. To be fixed. */

    for (const oo::ObjCRef<StationEntity*>& entry : allStations) {
        station = entry.get();
        const std::optional<std::string> stationKey = [registry cxx_randomShipKeyForRole:oo::StdString([station primaryRole])];
        const oo::PList stationInfo = stationKey.has_value() ? [registry cxx_shipInfoForKey:*stationKey] : oo::PList();
        if (stationInfo.find("requires_docking_clearance") == nullptr) {
            [station setRequiresDockingClearance:!!newValue];
        }
    }

    _dockingClearanceProtocolActive = !!newValue;
}

- (void)handleGameOver
{
    if ([[self gameController] playerFileToLoad]) {
        [[self gameController] loadPlayerIfRequired];
    } else {
        [self cxx_setUseAddOns:oo::StdString(SCENARIO_OXP_DEFINITION_ALL) fromSaveGame:NO forceReinit:YES]; // calls reinitAndShowDemo
    }
}

namespace {

std::optional<std::string> OptionalStringIn(const oo::PList& dict, std::string_view key); // defined with the other configuration readers below

// The demo ship entry at <index>, <subindex> of the demo list: null where the old array /
// dictionary lookup chain gave nil.
oo::PList DemoShipEntry(const oo::PList& demoShips, NSUInteger index, NSUInteger subindex)
{
    const oo::PList* subList = demoShips.at(index);
    const oo::PList* entry = (subList != nullptr && subList->isArray()) ? subList->at(subindex) : nullptr;
    return (entry != nullptr && entry->isDict()) ? *entry : oo::PList();
}

// -count of the demo class at <index> (0 where it was nil).
NSUInteger DemoClassCount(const oo::PList& demoShips, NSUInteger index)
{
    const oo::PList* subList = demoShips.at(index);
    return (subList != nullptr) ? subList->count() : 0;
}

// The class of the first ship of the demo class at <index>; "" where it was nil (oo::StdString(nil)).
std::string DemoClassAt(const oo::PList& demoShips, NSUInteger index)
{
    return OptionalStringIn(DemoShipEntry(demoShips, index, 0), kOODemoShipClass).value_or(std::string());
}

// A string setting of the library entry, <fallback> where absent; a null entry answered nil.
std::optional<std::string> LibrarySetting(const oo::PList& settings, std::string_view key, const char* fallback)
{
    if (settings.isNull())
        return std::nullopt;
    const std::optional<std::string> value = OptionalStringIn(settings, key);
    if (value.has_value() || fallback == nullptr)
        return value;
    return std::string(fallback);
}

// OOExpand(text), the unmigrated expander.
std::optional<std::string> ExpandText(const std::string& text)
{
    return oo::OptionalString(OOExpand(oo::NSStringFrom(text)));
}

// The DESC(descKey) format given OOExpand(override): a nil expansion printed "(null)".
std::string CustomLibraryText(const char* descKey, const std::string& override)
{
    const std::optional<std::string> expanded = ExpandText(override);
    return oo::str::formatRuntime(cxx_OOLookUpDescriptionPRIV(descKey), { expanded.has_value() ? oo::str::FormatArg(*expanded) : oo::str::FormatArg::null() });
}

// +arrayWithObjects:field1, field2, field3, nil: the fields up to the first nil.
std::vector<std::string> FieldsUpToNil(std::initializer_list<std::optional<std::string>> fields)
{
    std::vector<std::string> result;
    for (const std::optional<std::string>& field : fields) {
        if (!field.has_value())
            break;
        result.push_back(*field);
    }
    return result;
}

} // namespace

- (void)setupIntroFirstGo:(BOOL)justCobra
{
    PlayerEntity* player = PLAYER;
    ShipEntity* ship = nil;
    Quaternion q2 = { 0.0f, 0.0f, 1.0f, 0.0f }; // w,x,y,z

    // in status demo draw ships and display text
    if (!justCobra) {
        demo_ships = [[OOShipRegistry sharedRegistry] cxx_demoShipKeys];
        // always, even if it's the cobra, because it's repositioned
        [self removeDemoShips];
    }
    if (justCobra) {
        [player setStatus:STATUS_START_GAME];
    }
    [player setShowDemoShips:YES];
    displayGUI = YES;

    if (justCobra) {
        /*- cobra - intro1 -*/
        ship = [self newShipWithName:PLAYER_SHIP_DESC usePlayerProxy:YES];
    } else {
        /*- demo ships - intro2 -*/

        demo_ship_index = 0;
        demo_ship_subindex = 0;

        /* Try to set the initial list position to Cobra III if
         * available, and at least the Ships category. */
        const oo::PList::Array* demoClasses = demo_ships.getIf<oo::PList::Array>();
        if (demoClasses != nullptr) {
            for (NSUInteger k = 0; k < demoClasses->size(); k++) {
                const oo::PList& subList = (*demoClasses)[k];
                if (OptionalStringIn(DemoShipEntry(demo_ships, k, 0), kOODemoShipClass) == "ship") {
                    demo_ship_index = std::find(demoClasses->begin(), demoClasses->end(), subList) - demoClasses->begin(); // -indexOfObject:
                    const oo::PList::Array* shipEntries = subList.getIf<oo::PList::Array>(); // an array: its first entry was found above
                    for (const oo::PList& shipEntry : *shipEntries) {
                        if (OptionalStringIn(shipEntry, kOODemoShipKey) == "cobra3-trader") {
                            demo_ship_subindex = std::find(shipEntries->begin(), shipEntries->end(), shipEntry) - shipEntries->begin(); // -indexOfObject:
                            break;
                        }
                    }
                    break;
                }
            }
        }

        if (!demo_ship)
            ship = [self cxx_newShipWithName:OptionalStringIn(DemoShipEntry(demo_ships, demo_ship_index, demo_ship_subindex), kOODemoShipKey).value_or(std::string()) usePlayerProxy:NO];
        // stop consistency problems on the ship library screen
        [ship removeEquipmentItem:@"EQ_SHIELD_BOOSTER"];
        [ship removeEquipmentItem:@"EQ_SHIELD_ENHANCER"];
    }

    if (ship) {
        [ship setOrientation:q2];
        if (!justCobra) {
            [ship setPositionX:0.0f y:0.0f z:DEMO2_VANISHING_DISTANCE * ship->collision_radius * 0.01];
            [ship setDestination:ship->position]; // ideal position
        } else {
            // main screen Cobra is closer
            [ship setPositionX:0.0f y:0.0f z:3.6 * ship->collision_radius];
        }
        [ship setDemoShip:1.0f];
        [ship setDemoStartTime:universal_time];
        [ship setScanClass:CLASS_NO_DRAW];
        [ship switchAITo:@"nullAI.plist"];
        if ([ship pendingEscortCount] > 0)
            [ship setPendingEscortCount:0];
        [self addEntity:ship]; // STATUS_IN_FLIGHT, AI state GLOBAL
        // now override status
        [ship setStatus:STATUS_COCKPIT_DISPLAY];
        demo_ship = ship;

        [ship release];
    }

    if (!justCobra) {
        //		[gui setText:[demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];
        [self setLibraryTextForDemoShip];
    }

    [self enterGUIViewModeWithMouseInteraction:NO];
    if (!justCobra) {
        demo_stage = DEMO_SHOW_THING;
        demo_stage_time = universal_time + 300.0;
    }
}

- (oo::PList)demoShipData
{
    return DemoShipEntry(demo_ships, demo_ship_index, demo_ship_subindex);
}

- (void)setLibraryTextForDemoShip
{
    OOGUITabSettings tab_stops;
    tab_stops[0] = 0;
    tab_stops[1] = 170;
    tab_stops[2] = 340;
    [gui setTabStops:tab_stops];

    /*	[gui setText:[demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];
            [gui setColor:[OOColor whiteColor] forRow:19]; */

    const oo::PList librarySettings = [self demoShipData];

    OOGUIRow descRow = 7;

    std::optional<std::string> field1;
    std::optional<std::string> field2;
    std::optional<std::string> field3;
    std::optional<std::string> override;

    // clear rows
    for (NSUInteger i = 1; i <= 26; i++) {
        [gui setText:@"" forRow:i];
    }

    /* Row 1: ScanClass, Name, Summary */
    override = LibrarySetting(librarySettings, kOODemoShipClass, "ship");
    field1 = OOShipLibraryCategorySingular(override.value_or(std::string()));

    field2 = oo::OptionalString([demo_ship shipClassName]);

    override = LibrarySetting(librarySettings, kOODemoShipSummary, nullptr);
    if (override.has_value()) {
        field3 = ExpandText(*override);
    } else {
        field3 = std::string();
    }
    [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:1];
    [gui setColor:[OOColor greenColor] forRow:1];

    // ship_data defaults to true for "ship" class, false for everything else
    if (!librarySettings.get<bool>(kOODemoShipShipData, LibrarySetting(librarySettings, kOODemoShipClass, "ship") == "ship")) {
        descRow = 3;
    } else {
        /* Row 2: Speed, Turn Rate, Cargo */

        override = LibrarySetting(librarySettings, kOODemoShipSpeed, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field1 = std::string();
            } else {
                field1 = CustomLibraryText("oolite-ship-library-speed-custom", *override);
            }
        } else {
            field1 = OOShipLibrarySpeed(demo_ship);
        }

        override = LibrarySetting(librarySettings, kOODemoShipTurnRate, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field2 = std::string();
            } else {
                field2 = CustomLibraryText("oolite-ship-library-turn-custom", *override);
            }
        } else {
            field2 = OOShipLibraryTurnRate(demo_ship);
        }

        override = LibrarySetting(librarySettings, kOODemoShipCargo, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field3 = std::string();
            } else {
                field3 = CustomLibraryText("oolite-ship-library-cargo-custom", *override);
            }
        } else {
            field3 = OOShipLibraryCargo(demo_ship);
        }

        [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:3];

        /* Row 3: recharge rate, energy banks, witchspace */
        override = LibrarySetting(librarySettings, kOODemoShipGenerator, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field1 = std::string();
            } else {
                field1 = CustomLibraryText("oolite-ship-library-generator-custom", *override);
            }
        } else {
            field1 = OOShipLibraryGenerator(demo_ship);
        }

        override = LibrarySetting(librarySettings, kOODemoShipShields, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field2 = std::string();
            } else {
                field2 = CustomLibraryText("oolite-ship-library-shields-custom", *override);
            }
        } else {
            field2 = OOShipLibraryShields(demo_ship);
        }

        override = LibrarySetting(librarySettings, kOODemoShipWitchspace, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field3 = std::string();
            } else {
                field3 = CustomLibraryText("oolite-ship-library-witchspace-custom", *override);
            }
        } else {
            field3 = OOShipLibraryWitchspace(demo_ship);
        }

        [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:4];

        /* Row 4: weapons, turrets, size */
        override = LibrarySetting(librarySettings, kOODemoShipWeapons, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field1 = std::string();
            } else {
                field1 = CustomLibraryText("oolite-ship-library-weapons-custom", *override);
            }
        } else {
            field1 = OOShipLibraryWeapons(demo_ship);
        }

        override = LibrarySetting(librarySettings, kOODemoShipTurrets, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field2 = std::string();
            } else {
                field2 = CustomLibraryText("oolite-ship-library-turrets-custom", *override);
            }
        } else {
            field2 = OOShipLibraryTurrets(demo_ship);
        }

        override = LibrarySetting(librarySettings, kOODemoShipSize, nullptr);
        if (override.has_value()) {
            if (override->empty()) {
                field3 = std::string();
            } else {
                field3 = CustomLibraryText("oolite-ship-library-size-custom", *override);
            }
        } else {
            field3 = OOShipLibrarySize(demo_ship);
        }

        [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:5];
    }

    override = LibrarySetting(librarySettings, kOODemoShipDescription, nullptr);
    if (override.has_value()) {
        [gui cxx_addLongText:ExpandText(*override) startingAtRow:descRow align:GUI_ALIGN_LEFT];
    }

    // line 19: ship categories
    field1 = oo::str::format("<-- %s", OOShipLibraryCategoryPlural(DemoClassAt(demo_ships, (demo_ship_index + demo_ships.count() - 1) % demo_ships.count())).c_str());
    field2 = OOShipLibraryCategoryPlural(DemoClassAt(demo_ships, demo_ship_index));
    field3 = oo::str::format("%s -->", OOShipLibraryCategoryPlural(DemoClassAt(demo_ships, (demo_ship_index + 1) % demo_ships.count())).c_str());

    [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:19];
    [gui setColor:[OOColor greenColor] forRow:19];

    // lines 21-25: ship names
    const oo::PList* subListEntry = demo_ships.at(demo_ship_index);
    const oo::PList subList = (subListEntry != nullptr) ? *subListEntry : oo::PList();
    NSUInteger i, start = demo_ship_subindex - (demo_ship_subindex % 5);
    NSUInteger end = start + 4;
    if (end >= subList.count()) {
        end = subList.count() - 1;
    }
    OOGUIRow row = 21;
    field1 = std::string();
    field3 = std::string();
    for (i = start; i <= end; i++) {
        const oo::PList* shipEntry = subList.at(i);
        field2 = (shipEntry != nullptr) ? OptionalStringIn(*shipEntry, kOODemoShipName) : std::nullopt;
        [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:row];
        if (i == demo_ship_subindex) {
            [gui setColor:[OOColor yellowColor] forRow:row];
        } else {
            [gui setColor:[OOColor whiteColor] forRow:row];
        }
        row++;
    }

    field2 = "...";
    if (start > 0) {
        [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:20];
        [gui setColor:[OOColor whiteColor] forRow:20];
    }
    if (end < subList.count() - 1) {
        [gui cxx_setArray:FieldsUpToNil({ field1, field2, field3 }) forRow:26];
        [gui setColor:[OOColor whiteColor] forRow:26];
    }
}

- (void)selectIntro2Previous
{
    demo_stage = DEMO_SHOW_THING;
    NSUInteger subcount = DemoClassCount(demo_ships, demo_ship_index);
    demo_ship_subindex = (demo_ship_subindex + subcount - 2) % subcount;
    demo_stage_time = universal_time - 1.0; // force change
}

- (void)selectIntro2PreviousCategory
{
    demo_stage = DEMO_SHOW_THING;
    demo_ship_index = (demo_ship_index + demo_ships.count() - 1) % demo_ships.count();
    demo_ship_subindex = DemoClassCount(demo_ships, demo_ship_index) - 1;
    demo_stage_time = universal_time - 1.0; // force change
}

- (void)selectIntro2NextCategory
{
    demo_stage = DEMO_SHOW_THING;
    demo_ship_index = (demo_ship_index + 1) % demo_ships.count();
    demo_ship_subindex = DemoClassCount(demo_ships, demo_ship_index) - 1;
    demo_stage_time = universal_time - 1.0; // force change
}

- (void)selectIntro2Next
{
    demo_stage = DEMO_SHOW_THING;
    demo_stage_time = universal_time - 1.0; // force change
}

static BOOL IsCandidateMainStationPredicate(Entity* entity, void* parameter)
{
    return [entity isStation] && !entity->isExplicitlyNotMainStation;
}

static BOOL IsFriendlyStationPredicate(Entity* entity, void* parameter)
{
    return [entity isStation] && ![(ShipEntity*)entity isHostileTo:(Entity*)parameter];
}

- (StationEntity*)station
{
    if (cachedSun != nil && cachedStation == nil) {
        cachedStation = [self findOneEntityMatchingPredicate:IsCandidateMainStationPredicate
                                                   parameter:nil];
    }
    return cachedStation;
}

- (StationEntity*)cxx_stationWithRole:(const std::string&)role andPosition:(HPVector)position
{
    if (role.empty()) {
        return nil;
    }

    float range = 1000000; // allow a little variation in position

    const std::vector<oo::ObjCRef<StationEntity*>> stations = [self cxx_stations];
    StationEntity* station = nil;
    for (const oo::ObjCRef<StationEntity*>& entry : stations) {
        station = entry.get();
        if (HPdistance2(position, [station position]) < range) {
            if (oo::StdString([station primaryRole]) == role) // the unmigrated ShipEntity's role string
            {
                return station;
            }
        }
    }
    return nil;
}

- (StationEntity*)stationFriendlyTo:(ShipEntity*)ship
{
    // In interstellar space we select a random friendly carrier as mainStation.
    // No caching: friendly status can change!
    return [self findOneEntityMatchingPredicate:IsFriendlyStationPredicate parameter:ship];
}

- (OOPlanetEntity*)planet
{
    if (cachedPlanet == nil && allPlanets.size() > 0) {
        cachedPlanet = allPlanets[0].get();
    }
    return cachedPlanet;
}

- (OOSunEntity*)sun
{
    if (cachedSun == nil) {
        cachedSun = [self findOneEntityMatchingPredicate:IsSunPredicate parameter:nil];
    }
    return cachedSun;
}

- (std::vector<oo::ObjCRef<OOPlanetEntity*>>)cxx_planets
{
    return allPlanets;
}

- (std::vector<oo::ObjCRef<StationEntity*>>)cxx_stations
{
    return allStations;
}

- (std::vector<oo::ObjCRef<WormholeEntity*>>)cxx_wormholes
{
    return activeWormholes;
}

- (void)unMagicMainStation
{
    /*	During the demo screens, the player must remain docked in order for the
            UI to work. This means either enforcing invulnerability or launching
            the player when the station is destroyed even if on the "new game Y/N"
            screen.

            The latter is a) weirder and b) harder. If your OXP relies on being
            able to destroy the main station before the game has even started,
            your OXP sucks.
    */
    OOEntityStatus playerStatus = [PLAYER status];
    if (playerStatus == STATUS_START_GAME)
        return;

    StationEntity* theStation = [self station];
    if (theStation != nil)
        theStation->isExplicitlyNotMainStation = YES;
    cachedStation = nil;
}

- (void)resetBeacons
{
    Entity<OOBeaconEntity>*beaconShip = [self firstBeacon], *next = nil;
    while (beaconShip) {
        next = [beaconShip nextBeacon];
        [beaconShip setPrevBeacon:nil];
        [beaconShip setNextBeacon:nil];
        beaconShip = next;
    }

    [self setFirstBeacon:nil];
    [self setLastBeacon:nil];
}

- (Entity<OOBeaconEntity>*)firstBeacon
{
    return [_firstBeacon weakRefUnderlyingObject];
}

- (void)setFirstBeacon:(Entity<OOBeaconEntity>*)beacon
{
    if (beacon != [self firstBeacon]) {
        [beacon setPrevBeacon:nil];
        [beacon setNextBeacon:[self firstBeacon]];
        [[self firstBeacon] setPrevBeacon:beacon];
        [_firstBeacon release];
        _firstBeacon = [beacon weakRetain];
    }
}

- (Entity<OOBeaconEntity>*)lastBeacon
{
    return [_lastBeacon weakRefUnderlyingObject];
}

- (void)setLastBeacon:(Entity<OOBeaconEntity>*)beacon
{
    if (beacon != [self lastBeacon]) {
        [beacon setNextBeacon:nil];
        [beacon setPrevBeacon:[self lastBeacon]];
        [[self lastBeacon] setNextBeacon:beacon];
        [_lastBeacon release];
        _lastBeacon = [beacon weakRetain];
    }
}

- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    if ([beaconShip isBeacon]) {
        [self setLastBeacon:beaconShip];
        if ([self firstBeacon] == nil)
            [self setFirstBeacon:beaconShip];
    } else {
        OO_LOG("universe.beacon.error", "***** ERROR: Universe setNextBeacon '{}'. The ship has no beacon code set.", oo::DescriptionOf(beaconShip));
    }
}

- (void)clearBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    Entity<OOBeaconEntity>* tmp = nil;

    if ([beaconShip isBeacon]) {
        if ([self firstBeacon] == beaconShip) {
            tmp = [[beaconShip nextBeacon] nextBeacon];
            [self setFirstBeacon:[beaconShip nextBeacon]];
            [[beaconShip prevBeacon] setNextBeacon:tmp];
        } else if ([self lastBeacon] == beaconShip) {
            tmp = [[beaconShip prevBeacon] prevBeacon];
            [self setLastBeacon:[beaconShip prevBeacon]];
            [[beaconShip nextBeacon] setPrevBeacon:tmp];
        } else {
            [[beaconShip nextBeacon] setPrevBeacon:[beaconShip prevBeacon]];
            [[beaconShip prevBeacon] setNextBeacon:[beaconShip nextBeacon]];
        }
        [beaconShip setBeaconCode:nil];
    }
}

- (std::map<std::string, oo::ObjCRef<OOWaypointEntity*>, std::less<>>)cxx_currentWaypoints
{
    return waypoints;
}

- (void)cxx_defineWaypoint:(const oo::PList&)definition forKey:(const std::string&)key
{
    OOWaypointEntity* waypoint = nil;
    BOOL preserveCompass = NO;
    const auto existing = waypoints.find(key);
    if (existing != waypoints.end())
        waypoint = existing->second.get();
    if (waypoint != nil) {
        if ([PLAYER compassTarget] == waypoint) {
            preserveCompass = YES;
        }
        [self removeEntity:waypoint];
        waypoints.erase(key);
    }
    if (!definition.isNull()) {
        waypoint = [OOWaypointEntity waypointWithDictionary:definition];
        if (waypoint != nil) {
            [self addEntity:waypoint];
            waypoints[key] = oo::ObjCRef<OOWaypointEntity*>(waypoint);
            if (preserveCompass) {
                [PLAYER setCompassTarget:waypoint];
                [PLAYER setNextBeacon:waypoint];
            }
        }
    }
}

- (GLfloat*)skyClearColor
{
    return skyClearColor;
}

- (void)setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
{
    skyClearColor[0] = red;
    skyClearColor[1] = green;
    skyClearColor[2] = blue;
    skyClearColor[3] = alpha;
    [self setAirResistanceFactor:alpha];
}

- (BOOL)breakPatternOver
{
    return (breakPatternCounter == 0);
}

- (BOOL)breakPatternHide
{
    Entity* player = PLAYER;
    return ((breakPatternCounter > 5) || (!player) || ([player status] == STATUS_DOCKING));
}

#define PROFILE_SHIP_SELECTION 0

- (BOOL)canInstantiateShip:(const std::string&)shipKey
{
    oo::PList shipInfo;
    const oo::PList* conditions = nullptr;
    std::optional<std::string> condition_script;
    shipInfo = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:shipKey];

    condition_script = OptionalStringIn(shipInfo, "condition_script");
    if (condition_script.has_value()) {
        OOJSScript* condScript = [self cxx_getConditionScript:*condition_script];
        if (condScript != nil) // should always be non-nil, but just in case
        {
            JSContext* context = OOJSAcquireContext();
            BOOL OK;
            BOOL allow_instantiation = NO;
            OOJSVal result = OOJSUndefinedValue();
            OOJSVal args[] = { OOJSValueFromNativeObject(context, oo::NSStringFrom(shipKey)) };

            OK = [condScript callMethod:OOJSID("allowSpawnShip")
                              inContext:context
                          withArguments:args
                                  count:sizeof args / sizeof *args
                                 result:&result];

            if (OK)
                allow_instantiation = OOJSValueToBOOL(context, result);

            OOJSFreeValue(context, result);
            OOJSFreeValue(context, args[0]);
            OOJSRelinquishContext(context);

            if (OK && !allow_instantiation) {
                /* if the script exists, the function exists, the function
                 * returns a bool, and that bool is false, block
                 * instantiation. Otherwise allow it as default */
                return NO;
            }
        }
    }

    conditions = shipInfo.get<oo::PList::Array>("conditions");
    if (conditions == nullptr)
        return YES;

    // Check conditions (the legacy script engine is not migrated yet: it gets the array it read before)
    return [PLAYER scriptTestConditions:oo::ObjectFromPList(*conditions)];
}

- (std::optional<std::string>)cxx_randomShipKeyForRoleRespectingConditions:(const std::string&)role
{
    OOJS_PROFILE_ENTER

    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];
    std::optional<std::string> shipKey;
    OOMutableProbabilitySet* pset = nil;

#if PROFILE_SHIP_SELECTION
    static unsigned long profTotal = 0, profSlowPath = 0;
    ++profTotal;
#endif

    // Select a ship, check conditions and return it if possible.
    shipKey = [registry cxx_randomShipKeyForRole:role];
    if (!shipKey.has_value())
        return std::nullopt; // no ship has the role (a nil key passed the check and was returned)
    if ([self canInstantiateShip:*shipKey])
        return shipKey;

    /*	If we got here, condition check failed.
            We now need to keep trying until we either find an acceptable ship or
            run out of candidates.
            This is special-cased because it has more overhead than the more
            common conditionless lookup.
    */

#if PROFILE_SHIP_SELECTION
    ++profSlowPath;
    if ((profSlowPath % 10) == 0) // Only print every tenth slow path, to reduce spamminess.
    {
        OO_LOG("shipRegistry.selection.profile", "Hit slow path in ship selection for role \"{}\", having selected ship \"{}\". Now {} of {} on slow path ({:f}%).", role, shipKey.value_or("(null)"), static_cast<size_t>(profSlowPath), static_cast<size_t>(profTotal), ((double)profSlowPath) / ((double)profTotal) * 100.0f);
    }
#endif

    pset = [[[registry cxx_probabilitySetForRole:role] mutableCopy] autorelease];

    while ([pset count] > 0) {
        // Select a ship, check conditions and return it if possible.
        id shipKeyObject = [pset randomObject]; // the probability set (unmigrated) holds ship keys as objects
        if ([self canInstantiateShip:oo::StdString(shipKeyObject)])
            return oo::StdString(shipKeyObject);

        // Condition failed -> remove ship from consideration.
        [pset removeObject:shipKeyObject];
    }

    // If we got here, some ships existed but all failed conditions test.
    return std::nullopt;

    OOJS_PROFILE_EXIT
}

- (ShipEntity*)cxx_newShipWithRole:(const std::string&)role
{
    OOJS_PROFILE_ENTER

    ShipEntity* ship = nil;
    std::optional<std::string> shipKey;
    oo::PList shipInfo;
    std::optional<std::string> autoAI;

    shipKey = [self cxx_randomShipKeyForRoleRespectingConditions:role];
    if (shipKey.has_value()) {
        ship = [self cxx_newShipWithName:*shipKey];
        if (ship != nil) {
            [ship setPrimaryRole:oo::NSStringFrom(role)];

            shipInfo = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:*shipKey];
            if (FuzzyBooleanIn(shipInfo, "auto_ai", YES)) {
                // Set AI based on role
                autoAI = [self defaultAIForRole:role];
                if (autoAI.has_value()) {
                    [ship setAITo:oo::NSStringFrom(*autoAI)];
                    // Nikos 20090604
                    // Pirate, trader or police with auto_ai? Follow populator rules for them.
                    if (role == "pirate")
                        [ship setBounty:20 + randf() * 50 withReason:kOOLegalStatusReasonSetup];
                    if (role == "trader")
                        [ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
                    if (role == "police")
                        [ship setScanClass:CLASS_POLICE];
                    if (role == "interceptor") {
                        [ship setScanClass:CLASS_POLICE];
                        [ship setPrimaryRole:@"police"]; // to make sure interceptors get the correct pilot later on.
                    }
                }
                if (role == "thargoid")
                    [ship setScanClass:CLASS_THARGOID]; // thargoids are not on the autoAIMap
            }
        }
    }

    return ship;

    OOJS_PROFILE_EXIT
}

- (OOVisualEffectEntity*)cxx_newVisualEffectWithName:(const std::string&)effectKey
{
    OOJS_PROFILE_ENTER

    oo::PList effectDict;
    OOVisualEffectEntity* effect = nil;

    effectDict = [[OOShipRegistry sharedRegistry] cxx_effectInfoForKey:effectKey];
    if (effectDict.isNull())
        return nil;

    @try {
        // -initWithKey:definition: is shared: the key and definition as the objects it took before
        effect = [[OOVisualEffectEntity alloc] initWithKey:oo::NSStringFrom(effectKey) definition:oo::ObjectFromPList(effectDict)];
    }
    @catch (OOException* exception) {
        if (strcmp([exception name], OOLITE_EXCEPTION_DATA_NOT_FOUND) == 0) {
            OO_LOG(cxx_kOOLogException, "***** Oolite Exception : '{}' in [Universe newVisualEffectWithName: {} ] *****", [exception reason], effectKey);
        } else
            @throw exception;
    }

    return effect;

    OOJS_PROFILE_EXIT
}

- (ShipEntity*)cxx_newSubentityWithName:(const std::string&)shipKey andScaleFactor:(float)scale
{
    return [self cxx_newShipWithName:shipKey usePlayerProxy:NO isSubentity:YES andScaleFactor:scale];
}

- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy
{
    return [self cxx_newShipWithName:shipKey usePlayerProxy:usePlayerProxy isSubentity:NO];
}

- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity
{
    return [self cxx_newShipWithName:shipKey usePlayerProxy:usePlayerProxy isSubentity:isSubentity andScaleFactor:1.0f];
}

- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity andScaleFactor:(float)scale
{
    OOJS_PROFILE_ENTER

    oo::PList shipDict;
    ShipEntity* ship = nil;

    shipDict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:shipKey];
    if (shipDict.isNull())
        return nil;

    volatile Class shipClass = nil;
    if (isSubentity) {
        shipClass = [ShipEntity class];
    } else {
        shipClass = [self cxx_shipClassForShipDictionary:shipDict];
        if (usePlayerProxy && shipClass == [ShipEntity class]) {
            shipClass = [ProxyPlayerEntity class];
        }
    }

    @try {
        if (scale != 1.0f) {
            // a copy with the scale, a float as +numberWithFloat: stored it (ADR-0043 item 15)
            (*shipDict.getIf<oo::PList::Dict>())["model_scale_factor"] = oo::PList::singleReal(scale);
        }
        // -initWithKey:definition: is shared: the key and definition as the objects it took before
        ship = [[shipClass alloc] initWithKey:oo::NSStringFrom(shipKey) definition:oo::ObjectFromPList(shipDict)];
    }
    @catch (OOException* exception) {
        if (strcmp([exception name], OOLITE_EXCEPTION_DATA_NOT_FOUND) == 0) {
            OO_LOG(cxx_kOOLogException, "***** Oolite Exception : '{}' in [Universe newShipWithName: {} ] *****", [exception reason], shipKey);
        } else
            @throw exception;
    }

    // Set primary role to same as ship name, if ship name is also a role.
    // Otherwise, if caller doesn't set a role, one will be selected randomly.
    if ([ship hasRole:oo::NSStringFrom(shipKey)])
        [ship setPrimaryRole:oo::NSStringFrom(shipKey)];

    return ship;

    OOJS_PROFILE_EXIT
}

- (DockEntity*)cxx_newDockWithName:(const std::string&)shipDataKey andScaleFactor:(float)scale
{
    OOJS_PROFILE_ENTER

    oo::PList shipDict;
    DockEntity* dock = nil;

    shipDict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:shipDataKey];
    if (shipDict.isNull())
        return nil;

    @try {
        if (scale != 1.0f) {
            // a copy with the scale, a float as +numberWithFloat: stored it (ADR-0043 item 15)
            (*shipDict.getIf<oo::PList::Dict>())["model_scale_factor"] = oo::PList::singleReal(scale);
        }
        // -initWithKey:definition: is shared: the key and definition as the objects it took before
        dock = [[DockEntity alloc] initWithKey:oo::NSStringFrom(shipDataKey) definition:oo::ObjectFromPList(shipDict)];
    }
    @catch (OOException* exception) {
        if (strcmp([exception name], OOLITE_EXCEPTION_DATA_NOT_FOUND) == 0) {
            OO_LOG(cxx_kOOLogException, "***** Oolite Exception : '{}' in [Universe newDockWithName: {} ] *****", [exception reason], shipDataKey);
        } else
            @throw exception;
    }

    // Set primary role to same as name, if ship name is also a role.
    // Otherwise, if caller doesn't set a role, one will be selected randomly.
    if ([dock hasRole:oo::NSStringFrom(shipDataKey)])
        [dock setPrimaryRole:oo::NSStringFrom(shipDataKey)];

    return dock;

    OOJS_PROFILE_EXIT
}

- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey
{
    return [self cxx_newShipWithName:shipKey usePlayerProxy:NO];
}

- (Class)cxx_shipClassForShipDictionary:(const oo::PList&)dict
{
    OOJS_PROFILE_ENTER

    if (dict.isNull())
        return Nil;

    BOOL isStation = NO;
    std::optional<std::string> shipRoles = OptionalStringIn(dict, "roles");

    if (shipRoles.has_value()) {
        isStation = shipRoles->find("station") != std::string::npos || shipRoles->find("carrier") != std::string::npos;
    }

    // Note priority here: is_carrier overrides isCarrier which overrides roles.
    isStation = dict.get<bool>("isCarrier", isStation);
    isStation = dict.get<bool>("is_carrier", isStation);

    return isStation ? [StationEntity class] : [ShipEntity class];

    OOJS_PROFILE_EXIT
}

- (std::optional<std::string>)defaultAIForRole:(const std::string&)role
{
    return OptionalStringIn(autoAIMap, role);
}

- (OOCargoQuantity)cxx_maxCargoForShip:(const std::string&)desc
{
    return [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:desc].get<unsigned int>("max_cargo", 0);
}

/*
 * Price for an item expressed in 10ths of credits (divide by 10 to get credits)
 */
- (OOCreditsQuantity)cxx_getEquipmentPriceForKey:(const std::string&)eq_key
{
    if (const oo::PList::Array* items = equipmentData.getIf<oo::PList::Array>()) {
        for (const oo::PList& itemData : *items) {
            std::optional<std::string> itemType = OptionalStringAt(itemData, EQUIPMENT_KEY_INDEX);

            if (itemType.has_value() && *itemType == eq_key) {
                return itemData.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
            }
        }
    }
    return 0;
}

- (OOCommodities*)commodities
{
    return commodities;
}

/* Converts template cargo pods to real ones */
- (ShipEntity*)reifyCargoPod:(ShipEntity*)cargoObj
{
    if ([cargoObj isTemplateCargoPod]) {
        return [UNIVERSE cargoPodFromTemplate:cargoObj];
    } else {
        return cargoObj;
    }
}

- (ShipEntity*)cargoPodFromTemplate:(ShipEntity*)cargoObj
{
    ShipEntity* container = nil;
    // this is a template container, so we need to make a real one
    const std::optional<std::string> co_type = oo::OptionalString([cargoObj commodityType]);
    OOCargoQuantity co_amount = co_type.has_value() ? [UNIVERSE cxx_getRandomAmountOfCommodity:*co_type] : 0;
    if (randf() < 0.5) // stops OXP monopolising pods for commodities
    {
        container = co_type.has_value() ? [UNIVERSE cxx_newShipWithRole:*co_type] : nil; // newShipWithRole returns retained object
    }
    if (container == nil) {
        container = [UNIVERSE cxx_newShipWithRole:"cargopod"];
    }
    [container setCommodity:oo::NSStringOrNil(co_type) andAmount:co_amount];
    return [container autorelease];
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal
{
    /*	build list of goods allocating 0..100 for each based on how much of
            each quantity there is. Use a ratio of n x 100/64 for plentiful goods;
            reverse the probabilities for scarce goods.
    */
    std::vector<oo::ObjCRef<ShipEntity*>> accumulator;
    accumulator.reserve(how_many);
    NSUInteger i = 0, commodityCount = [commodityMarket count];
    std::vector<OOCargoQuantity> quantities(commodityCount);
    OOCargoQuantity total_quantity = 0;

    const std::vector<std::string> goodsKeys = oo::StringsFrom([commodityMarket goods]); // -goods is shared: an array of the keys

    for (const std::string& goodsKey : goodsKeys) {
        OOCargoQuantity q = [commodityMarket cxx_quantityForGood:goodsKey];
        if (scarce) {
            if (q < 64)
                q = 64 - q;
            else
                q = 0;
        }
        // legal YES restricts (almost) only to legal goods
        // legal NO allows illegal goods, but not necessarily a full hold
        if (legal && [commodityMarket cxx_exportLegalityForGood:goodsKey] > 0) {
            q &= 1; // keep a very small chance, sometimes
        }
        if (q > 64)
            q = 64;
        q *= 100;
        q /= 64;
        quantities[i++] = q;
        total_quantity += q;
    }
    // quantities is now used to determine which good get into the containers
    for (i = 0; i < how_many; i++) {
        NSUInteger co_type = 0;

        int qr = 0;
        if (total_quantity) {
            qr = 1 + (Ranrot() % total_quantity);
            co_type = 0;
            while (qr > 0) {
                OOAssert((NSUInteger)co_type < commodityCount, "Commodity type index out of range.");
                qr -= quantities[co_type++];
            }
            co_type--;
        }

        const std::optional<std::string> goodsKey = (co_type < goodsKeys.size()) ? std::optional<std::string>(goodsKeys[co_type]) : std::nullopt;
        ShipEntity* container = nil;
        if (goodsKey.has_value()) {
            const auto pod = cargoPods.find(*goodsKey);
            if (pod != cargoPods.end())
                container = pod->second.get();
        }

        if (container != nil) {
            accumulator.push_back(oo::ObjCRef<ShipEntity*>(container));
        } else {
            OO_LOG("universe.createContainer.failed", "***** ERROR: failed to find a container to fill with {} ({}).", goodsKey.value_or("(null)"), static_cast<size_t>(co_type));
        }
    }
    return accumulator;
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_getContainersOfCommodity:(const std::string&)commodity_name how_much:(OOCargoQuantity)how_much
{
    std::vector<oo::ObjCRef<ShipEntity*>> accumulator;
    accumulator.reserve(how_much);
    if (![commodities goodDefined:oo::NSStringFrom(commodity_name)]) // OOCommodities is not migrated yet
    {
        return accumulator; // empty array
    }

    ShipEntity* container = nil;
    const auto pod = cargoPods.find(commodity_name);
    if (pod != cargoPods.end())
        container = pod->second.get();
    while (how_much > 0) {
        if (container) {
            accumulator.push_back(oo::ObjCRef<ShipEntity*>(container));
        } else {
            OO_LOG("universe.createContainer.failed", "***** ERROR: failed to find a container to fill with {}", commodity_name);
        }

        how_much--;
    }
    return accumulator;
}

- (void)fillCargopodWithRandomCargo:(ShipEntity*)cargopod
{
    if (cargopod == nil || ![cargopod hasRole:@"cargopod"] || [cargopod cargoType] == CARGO_SCRIPTED_ITEM)
        return;

    if ([cargopod commodityType] == nil || ![cargopod commodityAmount]) {
        const std::optional<std::string> aCommodity = oo::OptionalString([self getRandomCommodity]);
        OOCargoQuantity aQuantity = aCommodity.has_value() ? [self cxx_getRandomAmountOfCommodity:*aCommodity] : 0;
        [cargopod setCommodity:oo::NSStringOrNil(aCommodity) andAmount:aQuantity];
    }
}

- (id)getRandomCommodity // shared selector (proposed ADR-0043)
{
    return [commodities getRandomCommodity];
}

- (OOCargoQuantity)cxx_getRandomAmountOfCommodity:(const std::string&)co_type
{
    OOMassUnit units;

    units = [commodities massUnitForGood:oo::NSStringFrom(co_type)]; // OOCommodities is not migrated yet
    switch (units) {
    case 0: // TONNES
        return 1;
    case 1: // KILOGRAMS
        return 1 + (Ranrot() % 6) + (Ranrot() % 6) + (Ranrot() % 6);
    case 2: // GRAMS
        return 4 + (Ranrot() % 16) + (Ranrot() % 11) + (Ranrot() % 6);
    case UNITS_UNKNOWN: // not a unit (ADR-0036): warned about below, as any other value was
        break;
    }
    OO_LOG("universe.commodityAmount.warning", "Commodity {} has an unrecognised mass unit, assuming tonnes", co_type);
    return 1;
}

- (oo::PList)commodityDataForType:(const std::string&)type
{
    return [commodityMarket cxx_definitionForGood:type];
}

- (std::optional<std::string>)cxx_displayNameForCommodity:(const std::string&)co_type
{
    return [commodityMarket cxx_nameForGood:co_type];
}

- (std::optional<std::string>)cxx_describeCommodity:(const std::string&)co_type amount:(OOCargoQuantity)co_amount
{
    int units;
    std::string unitDesc;
    std::optional<std::string> typeDesc;
    const oo::PList commodity = [self commodityDataForType:co_type];

    if (commodity.isNull())
        return std::string();

    units = [commodityMarket massUnitForGood:oo::NSStringFrom(co_type)]; // shared: an Objective-C string
    if (co_amount == 1) {
        switch (units) {
        case UNITS_KILOGRAMS: // KILOGRAM
            unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-kilogram");
            break;
        case UNITS_GRAMS: // GRAM
            unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-gram");
            break;
        case UNITS_TONS: // TONNE
        default:
            unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-ton");
            break;
        }
    } else {
        switch (units) {
        case UNITS_KILOGRAMS: // KILOGRAMS
            unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-kilograms");
            break;
        case UNITS_GRAMS: // GRAMS
            unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-grams");
            break;
        case UNITS_TONS: // TONNES
        default:
            unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-tons");
            break;
        }
    }

    typeDesc = [commodityMarket cxx_nameForGood:co_type];

    return oo::str::format("%d %s %s", co_amount, unitDesc.c_str(), TextOrNull(typeDesc).c_str());
}

////////////////////////////////////////////////////

- (void)setGameView:(MyOpenGLView*)view
{
    [gameView release];
    gameView = [view retain];
}

- (MyOpenGLView*)gameView
{
    return gameView;
}

- (GameController*)gameController
{
    return [[self gameView] gameController];
}

// The number kinds the old dictionary held: oo_setInteger: a signed integer, oo_setBool: a
// boolean, oo_setFloat: / +numberWithFloat: a single-precision real.
- (oo::PList)cxx_gameSettings
{
    oo::PList::Dict result;

    result["speechOn"] = oo::PList::signedInteger([PLAYER isSpeechOn]);
    result["autosave"] = oo::PList(static_cast<bool>(autoSave));
    result["wireframeGraphics"] = oo::PList(static_cast<bool>(wireframeGraphics));
    result["procedurallyTexturedPlanets"] = oo::PList(static_cast<bool>(doProcedurallyTexturedPlanets));

    result["fovValue"] = oo::PList::singleReal([gameView fov:NO]);

#if OOLITE_WINDOWS
    if ([gameView hdrOutput]) {
        result["hdr-max-brightness"] = oo::PList::singleReal([gameView hdrMaxBrightness]);
        result["hdr-paperwhite-brightness"] = oo::PList::singleReal([gameView hdrPaperWhiteBrightness]);
        result["hdr-tone-mapper"] = oo::PList(cxx_OOStringFromHDRToneMapper([gameView hdrToneMapper]));
    }
#endif

    result["sdr-tone-mapper"] = oo::PList(cxx_OOStringFromSDRToneMapper([gameView sdrToneMapper]));

    result["detailLevel"] = oo::PList(cxx_OOStringFromGraphicsDetail([self detailLevel]));

    const char* desc = "UNDEFINED";
    switch ([[OOMusicController sharedController] mode]) {
    case kOOMusicOff:
        desc = "MUSIC_OFF";
        break;
    case kOOMusicOn:
        desc = "MUSIC_ON";
        break;
    case kOOMusicITunes:
        desc = "MUSIC_ITUNES";
        break;
    }
    result["musicMode"] = oo::PList(desc);

    result["gameWindow"] = oo::PList(oo::PList::Dict {
        { "width", oo::PList::singleReal([gameView backingViewSize].width) },
        { "height", oo::PList::singleReal([gameView backingViewSize].height) },
        { "fullScreen", oo::PList(static_cast<bool>([[self gameController] inFullScreenMode])) },
    });

    result["keyConfig"] = oo::PListFrom([PLAYER keyConfig]); // the unmigrated PlayerEntity's

    return oo::PList(std::move(result));
}

- (void)useGUILightSource:(BOOL)GUILight
{
    if (GUILight != demo_light_on) {
        if (![self useShaders]) {
            if (GUILight) {
                OOGL(glEnable(GL_LIGHT0));
                OOGL(glDisable(GL_LIGHT1));
            } else {
                OOGL(glEnable(GL_LIGHT1));
                OOGL(glDisable(GL_LIGHT0));
            }
        }
        // There should be nothing to do for shaders, they use the same (always on) light source
        // both in flight & in gui mode. According to the standard, shaders should treat lights as
        // always enabled. At least one non-standard shader implementation (windows' X3100 Intel
        // core with GM965 chipset and version 6.14.10.4990 driver) does _not_ use glDisabled lights,
        // making the following line necessary.

        else
            OOGL(glEnable(GL_LIGHT1)); // make sure we have a light, even with shaders (!)

        demo_light_on = GUILight;
    }
}

- (void)lightForEntity:(BOOL)isLit
{
    if (isLit != object_light_on) {
        if ([self useShaders]) {
            if (isLit) {
                OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
                OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
            } else {
                OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_off));
                OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_off));
            }
        } else {
            if (!demo_light_on) {
                if (isLit)
                    OOGL(glEnable(GL_LIGHT1));
                else
                    OOGL(glDisable(GL_LIGHT1));
            } else {
                // If we're in demo/GUI mode we should always have a lit object.
                OOGL(glEnable(GL_LIGHT0));

                // Redundant, see above.
                // if (isLit)  OOGL(glEnable(GL_LIGHT0));
                // else  OOGL(glDisable(GL_LIGHT0));
            }
        }

        object_light_on = isLit;
    }
}

// global rotation matrix definitions
static const OOMatrix fwd_matrix = { { { 1.0f, 0.0f, 0.0f, 0.0f },
    { 0.0f, 1.0f, 0.0f, 0.0f },
    { 0.0f, 0.0f, 1.0f, 0.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f } } };
static const OOMatrix aft_matrix = { { { -1.0f, 0.0f, 0.0f, 0.0f },
    { 0.0f, 1.0f, 0.0f, 0.0f },
    { 0.0f, 0.0f, -1.0f, 0.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f } } };
static const OOMatrix port_matrix = { { { 0.0f, 0.0f, -1.0f, 0.0f },
    { 0.0f, 1.0f, 0.0f, 0.0f },
    { 1.0f, 0.0f, 0.0f, 0.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f } } };
static const OOMatrix starboard_matrix = { { { 0.0f, 0.0f, 1.0f, 0.0f },
    { 0.0f, 1.0f, 0.0f, 0.0f },
    { -1.0f, 0.0f, 0.0f, 0.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f } } };

- (void)getActiveViewMatrix:(OOMatrix*)outMatrix forwardVector:(Vector*)outForward upVector:(Vector*)outUp
{
    assert(outMatrix != NULL && outForward != NULL && outUp != NULL);

    PlayerEntity* player = nil;

    switch (viewDirection) {
    case VIEW_AFT:
        *outMatrix = aft_matrix;
        *outForward = vector_flip(kBasisZVector);
        *outUp = kBasisYVector;
        return;

    case VIEW_PORT:
        *outMatrix = port_matrix;
        *outForward = vector_flip(kBasisXVector);
        *outUp = kBasisYVector;
        return;

    case VIEW_STARBOARD:
        *outMatrix = starboard_matrix;
        *outForward = kBasisXVector;
        *outUp = kBasisYVector;
        return;

    case VIEW_CUSTOM:
        player = PLAYER;
        *outMatrix = [player customViewMatrix];
        *outForward = [player customViewForwardVector];
        *outUp = [player customViewUpVector];
        return;

    case VIEW_FORWARD:
    case VIEW_NONE:
    case VIEW_GUI_DISPLAY:
    case VIEW_BREAK_PATTERN:;
    }

    *outMatrix = fwd_matrix;
    *outForward = kBasisZVector;
    *outUp = kBasisYVector;
}

- (OOMatrix)activeViewMatrix
{
    OOMatrix m;
    Vector f, u;

    [self getActiveViewMatrix:&m forwardVector:&f upVector:&u];
    return m;
}

/* Code adapted from http://www.crownandcutlass.com/features/technicaldetails/frustum.html
 * Original license is: "This page and its contents are Copyright 2000 by Mark Morley
 * Unless otherwise noted, you may use any and all code examples provided herein in any way you want."
 */

- (void)defineFrustum
{
    OOMatrix clip;
    GLfloat rt;

    clip = OOGLGetModelViewProjection();

    /* Extract the numbers for the RIGHT plane */
    frustum[0][0] = clip.m[0][3] - clip.m[0][0];
    frustum[0][1] = clip.m[1][3] - clip.m[1][0];
    frustum[0][2] = clip.m[2][3] - clip.m[2][0];
    frustum[0][3] = clip.m[3][3] - clip.m[3][0];

    /* Normalize the result */
    rt = 1.0f / sqrt(frustum[0][0] * frustum[0][0] + frustum[0][1] * frustum[0][1] + frustum[0][2] * frustum[0][2]);
    frustum[0][0] *= rt;
    frustum[0][1] *= rt;
    frustum[0][2] *= rt;
    frustum[0][3] *= rt;

    /* Extract the numbers for the LEFT plane */
    frustum[1][0] = clip.m[0][3] + clip.m[0][0];
    frustum[1][1] = clip.m[1][3] + clip.m[1][0];
    frustum[1][2] = clip.m[2][3] + clip.m[2][0];
    frustum[1][3] = clip.m[3][3] + clip.m[3][0];

    /* Normalize the result */
    rt = 1.0f / sqrt(frustum[1][0] * frustum[1][0] + frustum[1][1] * frustum[1][1] + frustum[1][2] * frustum[1][2]);
    frustum[1][0] *= rt;
    frustum[1][1] *= rt;
    frustum[1][2] *= rt;
    frustum[1][3] *= rt;

    /* Extract the BOTTOM plane */
    frustum[2][0] = clip.m[0][3] + clip.m[0][1];
    frustum[2][1] = clip.m[1][3] + clip.m[1][1];
    frustum[2][2] = clip.m[2][3] + clip.m[2][1];
    frustum[2][3] = clip.m[3][3] + clip.m[3][1];

    /* Normalize the result */
    rt = 1.0 / sqrt(frustum[2][0] * frustum[2][0] + frustum[2][1] * frustum[2][1] + frustum[2][2] * frustum[2][2]);
    frustum[2][0] *= rt;
    frustum[2][1] *= rt;
    frustum[2][2] *= rt;
    frustum[2][3] *= rt;

    /* Extract the TOP plane */
    frustum[3][0] = clip.m[0][3] - clip.m[0][1];
    frustum[3][1] = clip.m[1][3] - clip.m[1][1];
    frustum[3][2] = clip.m[2][3] - clip.m[2][1];
    frustum[3][3] = clip.m[3][3] - clip.m[3][1];

    /* Normalize the result */
    rt = 1.0 / sqrt(frustum[3][0] * frustum[3][0] + frustum[3][1] * frustum[3][1] + frustum[3][2] * frustum[3][2]);
    frustum[3][0] *= rt;
    frustum[3][1] *= rt;
    frustum[3][2] *= rt;
    frustum[3][3] *= rt;

    /* Extract the FAR plane */
    frustum[4][0] = clip.m[0][3] - clip.m[0][2];
    frustum[4][1] = clip.m[1][3] - clip.m[1][2];
    frustum[4][2] = clip.m[2][3] - clip.m[2][2];
    frustum[4][3] = clip.m[3][3] - clip.m[3][2];

    /* Normalize the result */
    rt = sqrt(frustum[4][0] * frustum[4][0] + frustum[4][1] * frustum[4][1] + frustum[4][2] * frustum[4][2]);
    frustum[4][0] *= rt;
    frustum[4][1] *= rt;
    frustum[4][2] *= rt;
    frustum[4][3] *= rt;

    /* Extract the NEAR plane */
    frustum[5][0] = clip.m[0][3] + clip.m[0][2];
    frustum[5][1] = clip.m[1][3] + clip.m[1][2];
    frustum[5][2] = clip.m[2][3] + clip.m[2][2];
    frustum[5][3] = clip.m[3][3] + clip.m[3][2];

    /* Normalize the result */
    rt = sqrt(frustum[5][0] * frustum[5][0] + frustum[5][1] * frustum[5][1] + frustum[5][2] * frustum[5][2]);
    frustum[5][0] *= rt;
    frustum[5][1] *= rt;
    frustum[5][2] *= rt;
    frustum[5][3] *= rt;
}

- (BOOL)viewFrustumIntersectsSphereAt:(Vector)position withRadius:(GLfloat)radius
{
    // position is the relative position between the camera and the object
    int p;
    for (p = 0; p < 6; p++) {
        if (frustum[p][0] * position.x + frustum[p][1] * position.y + frustum[p][2] * position.z + frustum[p][3] <= -radius) {
            return NO;
        }
    }
    return YES;
}

- (void)drawUniverse
{
    int currentPostFX = [self currentPostFX];
    BOOL hudSeparateRenderPass = [self useShaders] && (currentPostFX == OO_POSTFX_NONE || ((currentPostFX == OO_POSTFX_CLOAK || currentPostFX == OO_POSTFX_CRTBADSIGNAL) && [self colorblindMode] == OO_POSTFX_NONE));
    NSSize viewSize = [gameView backingViewSize];
    OO_LOG("universe.profile.draw", "{}", "Begin draw");

    if (!no_update) {
        if ((int)targetFramebufferSize.width != (int)viewSize.width || (int)targetFramebufferSize.height != (int)viewSize.height) {
            [self resizeTargetFramebufferWithViewSize:viewSize];
        }

        if ([self useShaders]) {
            if ([gameView msaa]) {
                OOGL(glBindFramebuffer(GL_FRAMEBUFFER, msaaFramebufferID));
            } else {
                OOGL(glBindFramebuffer(GL_FRAMEBUFFER, targetFramebufferID));
            }
        }
        @try {
            no_update = YES; // block other attempts to draw

            int i, v_status, vdist;
            Vector view_dir, view_up;
            OOMatrix view_matrix;
            int ent_count = n_entities;
            std::vector<Entity*> my_entities(ent_count);
            int draw_count = 0;
            PlayerEntity* player = PLAYER;
            Entity* drawthing = nil;
            BOOL demoShipMode = [player showDemoShips];

            float aspect = viewSize.height / viewSize.width;

            if (!displayGUI && wasDisplayGUI) {
                // reset light1 position for the shaders
                if (cachedSun)
                    [UNIVERSE setMainLightPosition:HPVectorToVector([cachedSun position])]; // the main light is the sun.
                else
                    [UNIVERSE setMainLightPosition:kZeroVector];
            }
            wasDisplayGUI = displayGUI;
            // use a non-mutable copy so this can't be changed under us.
            for (i = 0; i < ent_count; i++) {
                /* BUG: this list is ordered nearest to furthest from
                 * the player, and we just assume that the camera is
                 * on/near the player. So long as everything uses
                 * depth tests, we'll get away with it; it'll just
                 * occasionally be inefficient. - CIM */
                Entity* e = sortedEntities[i]; // ordered NEAREST -> FURTHEST AWAY
                if ([e isVisible]) {
                    my_entities[draw_count++] = [[e retain] autorelease];
                }
            }

            v_status = [player status];

            cxx_OOCheckOpenGLErrors("Universe before doing anything");

            OOSetOpenGLState(OPENGL_STATE_OPAQUE); // FIXME: should be redundant.

            OOGL(glClear(GL_COLOR_BUFFER_BIT));

            if (!displayGUI) {
                OOGL(glClearColor(skyClearColor[0], skyClearColor[1], skyClearColor[2], skyClearColor[3]));
            } else {
                OOGL(glClearColor(0.0, 0.0, 0.0, 0.0));
                // If set, display background GUI image. Must be done before enabling lights to avoid dim backgrounds
                OOGLResetProjection();
                OOGLFrustum(-0.5, 0.5, -aspect * 0.5, aspect * 0.5, 1.0, MAX_CLEAR_DEPTH);
                [gui drawGUIBackground];
            }

            BOOL fogging, bpHide = [self breakPatternHide];

            drawCounter++;
            float breakPlane = INTERMEDIATE_CLEAR_DEPTH;
            for (int i = 0; i < draw_count; i++) {
                if ([my_entities[i] cameraRangeFront] > breakPlane) {
                    continue;
                }
                if ([my_entities[i] cameraRangeBack] > breakPlane) {
                    breakPlane = [my_entities[i] cameraRangeBack];
                }
            }

            // We need to bring forward the near plane of the frustum on the long distance pass by this factor to avoid clipping objects at the corner of the window
            float distanceFactor = sqrt(1 + ([gameView fov:YES] * [gameView fov:YES] * (1.0 + 1.0 / (aspect * aspect))));

            for (vdist = 0; vdist <= 1; vdist++) {
                float nearPlane = vdist ? 1.0 : INTERMEDIATE_CLEAR_DEPTH;
                float farPlane = vdist ? breakPlane : MAX_CLEAR_DEPTH;
                float ratio = (displayGUI ? 0.5 : [gameView fov:YES]) * nearPlane / distanceFactor; // 0.5 is field of view ratio for GUIs

                OOGLResetProjection();
                if ((displayGUI && 4 * aspect >= 3) || (!displayGUI && 4 * aspect <= 3)) {
                    OOGLFrustum(-ratio, ratio, -aspect * ratio, aspect * ratio, nearPlane / distanceFactor, farPlane);
                } else {
                    OOGLFrustum(-3 * ratio / aspect / 4, 3 * ratio / aspect / 4, -3 * ratio / 4, 3 * ratio / 4, nearPlane / distanceFactor, farPlane);
                }

                [self getActiveViewMatrix:&view_matrix forwardVector:&view_dir upVector:&view_up];

                OOGLResetModelView(); // reset matrix
                OOGLLookAt(kZeroVector, kBasisZVector, kBasisYVector);

                // HACK BUSTED
                OOGLMultModelView(OOMatrixForScale(-1.0, 1.0, 1.0)); // flip left and right
                OOGLPushModelView(); // save this flat viewpoint

                /* OpenGL viewpoints:
                 *
                 * Oolite used to transform the viewpoint by the inverse of the
                 * view position, and then transform the objects by the inverse
                 * of their position, to get the correct view. However, as
                 * OpenGL only uses single-precision floats, this causes
                 * noticeable display inaccuracies relatively close to the
                 * origin.
                 *
                 * Instead, we now calculate the difference between the view
                 * position and the object using high-precision vectors, convert
                 * the difference to a low-precision vector (since if you can
                 * see it, it's close enough for the loss of precision not to
                 * matter) and use that relative vector for the OpenGL transform
                 *
                 * Objects which reset the view matrix in their display need to be
                 * handled a little more carefully than before.
                 */

                OOSetOpenGLState(OPENGL_STATE_OPAQUE);
                // clearing the depth buffer waits until we've set
                // STATE_OPAQUE so that depth writes are definitely
                // available.
                OOGL(glClear(GL_DEPTH_BUFFER_BIT));

                // Set up view transformation matrix
                OOMatrix flipMatrix = kIdentityMatrix;
                flipMatrix.m[2][2] = -1;
                view_matrix = OOMatrixMultiply(view_matrix, flipMatrix);
                Vector viewOffset = [player viewpointOffset];

                OOGLLookAt(view_dir, kZeroVector, view_up);

                if (EXPECT(!displayGUI || demoShipMode)) {
                    if (EXPECT(!demoShipMode)) // we're in flight
                    {
                        // rotate the view
                        OOGLMultModelView([player rotationMatrix]);
                        // translate the view
                        // HPVect: camera-relative position
                        OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
                        // main light position, no shaders, in-flight / shaders, in-flight and docked.
                        if (cachedSun) {
                            [self setMainLightPosition:[cachedSun cameraRelativePosition]];
                        } else {
                            // in witchspace
                            [self setMainLightPosition:HPVectorToVector(HPvector_flip([PLAYER viewpointPosition]))];
                        }
                        OOGL(glLightfv(GL_LIGHT1, GL_POSITION, main_light_position));
                    } else {
                        OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, docked_light_ambient));
                        // main_light_position no shaders, docked/GUI.
                        OOGL(glLightfv(GL_LIGHT0, GL_POSITION, main_light_position));
                        // main light position, no shaders, in-flight / shaders, in-flight and docked.
                        OOGL(glLightfv(GL_LIGHT1, GL_POSITION, main_light_position));
                    }

                    OOGL([self useGUILightSource:demoShipMode]);

                    // HACK: store view matrix for absolute drawing of active subentities (i.e., turrets, flashers).
                    viewMatrix = OOGLGetModelView();

                    int furthest = draw_count - 1;
                    int nearest = 0;
                    BOOL inAtmosphere = airResistanceFactor > 0.01;
                    GLfloat fogFactor = 0.5 / airResistanceFactor;
                    double fog_scale, half_scale;
                    GLfloat flat_ambdiff[4] = { 1.0, 1.0, 1.0, 1.0 }; // for alpha
                    GLfloat mat_no[4] = { 0.0, 0.0, 0.0, 1.0 }; // nothing
                    GLfloat fog_blend;

                    OOGL(glHint(GL_FOG_HINT, [self reducedDetail] ? GL_FASTEST : GL_NICEST));

                    [self defineFrustum]; // camera is set up for this frame

                    OOVerifyOpenGLState();
                    cxx_OOCheckOpenGLErrors("Universe after setting up for opaque pass");
                    OO_LOG("universe.profile.draw", "{}", "Begin opaque pass");

                    //		DRAW ALL THE OPAQUE ENTITIES
                    for (i = furthest; i >= nearest; i--) {
                        drawthing = my_entities[i];
                        OOEntityStatus d_status = [drawthing status];

                        if (bpHide && !drawthing->isImmuneToBreakPatternHide)
                            continue;
                        if ([drawthing lastDrawCounter] == drawCounter)
                            continue;
                        if (vdist == 0 && [drawthing cameraRangeFront] < nearPlane) {
                            continue;
                        }

                        if (!((d_status == STATUS_COCKPIT_DISPLAY) ^ demoShipMode)) // either demo ship mode or in flight
                        {
                            // reset material properties
                            // FIXME: should be part of SetState
                            OOGL(glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff));
                            OOGL(glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, mat_no));

                            OOGLPushModelView();
                            if (EXPECT(drawthing != player)) {
                                // translate the object
                                //  HPVect: camera relative
                                [drawthing updateCameraRelativePosition];
                                OOGLTranslateModelView([drawthing cameraRelativePosition]);
                                // rotate the object
                                OOGLMultModelView([drawthing drawRotationMatrix]);
                            } else {
                                // Load transformation matrix
                                OOGLLoadModelView(view_matrix);
                                // translate the object  from the viewpoint
                                OOGLTranslateModelView(vector_flip(viewOffset));
                            }

                            // atmospheric fog
                            fogging = (inAtmosphere && ![drawthing isStellarObject]);

                            if (fogging) {
                                fog_scale = BILLBOARD_DEPTH * fogFactor;
                                half_scale = fog_scale * 0.50;
                                OOGL(glEnable(GL_FOG));
                                OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
                                OOGL(glFogfv(GL_FOG_COLOR, skyClearColor));
                                OOGL(glFogf(GL_FOG_START, half_scale));
                                OOGL(glFogf(GL_FOG_END, fog_scale));
                                fog_blend = OOClamp_0_1_f((magnitude([drawthing cameraRelativePosition]) - half_scale) / half_scale);
                                [drawthing setAtmosphereFogging:[OOColor colorWithRed:skyClearColor[0] green:skyClearColor[1] blue:skyClearColor[2] alpha:fog_blend]];
                            }

                            [self lightForEntity:demoShipMode || drawthing->isSunlit];

                            // draw the thing
                            [drawthing setLastDrawCounter:drawCounter];
                            [drawthing drawImmediate:false translucent:false];

                            OOGLPopModelView();

                            // atmospheric fog
                            if (fogging) {
                                [drawthing setAtmosphereFogging:[OOColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0]];
                                OOGL(glDisable(GL_FOG));
                            }
                        }

                        if (!((d_status == STATUS_COCKPIT_DISPLAY) ^ demoShipMode)) // either in flight or in demo ship mode
                        {
                            OOGLPushModelView();
                            if (EXPECT(drawthing != player)) {
                                // translate the object
                                //  HPVect: camera relative positions
                                [drawthing updateCameraRelativePosition];
                                OOGLTranslateModelView([drawthing cameraRelativePosition]);
                                // rotate the object
                                OOGLMultModelView([drawthing drawRotationMatrix]);
                            } else {
                                // Load transformation matrix
                                OOGLLoadModelView(view_matrix);
                                // translate the object  from the viewpoint
                                OOGLTranslateModelView(vector_flip(viewOffset));
                            }

                            // experimental - atmospheric fog
                            fogging = (inAtmosphere && ![drawthing isStellarObject]);

                            if (fogging) {
                                fog_scale = BILLBOARD_DEPTH * fogFactor;
                                half_scale = fog_scale * 0.50;
                                OOGL(glEnable(GL_FOG));
                                OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
                                OOGL(glFogfv(GL_FOG_COLOR, skyClearColor));
                                OOGL(glFogf(GL_FOG_START, half_scale));
                                OOGL(glFogf(GL_FOG_END, fog_scale));
                                fog_blend = OOClamp_0_1_f((magnitude([drawthing cameraRelativePosition]) - half_scale) / half_scale);
                                [drawthing setAtmosphereFogging:[OOColor colorWithRed:skyClearColor[0] green:skyClearColor[1] blue:skyClearColor[2] alpha:fog_blend]];
                            }

                            // draw the thing
                            [drawthing setLastDrawCounter:drawCounter];
                            [drawthing drawImmediate:false translucent:true];

                            // atmospheric fog
                            if (fogging) {
                                [drawthing setAtmosphereFogging:[OOColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0]];
                                OOGL(glDisable(GL_FOG));
                            }

                            OOGLPopModelView();
                        }
                    }
                }

                OOGLPopModelView();
            }

            // glare effects covering the entire game window
            OOGLResetProjection();
            OOGLFrustum(-0.5, 0.5, -aspect * 0.5, aspect * 0.5, 1.0, MAX_CLEAR_DEPTH);
            OOSetOpenGLState(OPENGL_STATE_OVERLAY); // FIXME: should be redundant.
            if (EXPECT(!displayGUI)) {
                if (!bpHide && cachedSun) {
                    [cachedSun drawDirectVisionSunGlare];
                    [cachedSun drawStarGlare];
                }
            }

            // actions when the HUD should be rendered separately from the 3d universe
            if (hudSeparateRenderPass) {
                cxx_OOCheckOpenGLErrors("Universe after drawing entities");
                OOSetOpenGLState(OPENGL_STATE_OVERLAY); // FIXME: should be redundant.

                [self prepareToRenderIntoDefaultFramebuffer];
                OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));

                OO_LOG("universe.profile.secondPassDraw", "{}", "Begin second pass draw");
                [self drawTargetTextureIntoDefaultFramebuffer];
                cxx_OOCheckOpenGLErrors("Universe after drawing from custom framebuffer to screen framebuffer");
                OO_LOG("universe.profile.secondPassDraw", "{}", "End second pass drawing");

                OO_LOG("universe.profile.drawHUD", "{}", "Begin HUD drawing");
            }

            /* Reset for HUD drawing */
            cxx_OOCheckOpenGLErrors("Universe after drawing entities");
            OO_LOG("universe.profile.draw", "{}", "Begin HUD");

            GLfloat lineWidth = [gameView backingViewSize].width / 1024.0; // restore line size
            if (lineWidth < 1.0)
                lineWidth = 1.0;
            if (lineWidth > 1.5)
                lineWidth = 1.5; // don't overscale; think of ultra-wide screen setups
            OOGL(GLScaledLineWidth(lineWidth));

            HeadUpDisplay* theHUD = [player hud];

            // If the HUD has a non-nil deferred name string, it means that a HUD switch was requested while it was being rendered.
            // If so, execute the deferred HUD switch now - Nikos 20110628
            if ([theHUD cxx_deferredHudName].has_value()) {
                const std::string deferredName = *[theHUD cxx_deferredHudName]; // a copy: the switch releases the HUD
                [player switchHudTo:oo::NSStringFrom(deferredName)];
                theHUD = [player hud]; // HUD has been changed, so point to its new address
            }

            // Hiding HUD: has been a regular - non-debug - feature as of r2749, about 2 yrs ago! --Kaks 2011.10.14
            static float sPrevHudAlpha = -1.0f;
            if ([theHUD isHidden]) {
                if (sPrevHudAlpha < 0.0f) {
                    sPrevHudAlpha = [theHUD overallAlpha];
                }
                [theHUD setOverallAlpha:0.0f];
            } else if (sPrevHudAlpha >= 0.0f) {
                [theHUD setOverallAlpha:sPrevHudAlpha];
                sPrevHudAlpha = -1.0f;
            }

            switch (v_status) {
            case STATUS_DEAD:
            case STATUS_ESCAPE_SEQUENCE:
            case STATUS_START_GAME:
                // no HUD rendering in these modes
                break;
            default:
                switch ([player guiScreen]) {
                // case GUI_SCREEN_KEYBOARD:
                //  no HUD rendering on this screen
                // break;
                default:
                    [theHUD setLineWidth:lineWidth];
                    [theHUD renderHUD];
                }
            }

            // should come after the HUD to avoid it being overlapped by it
            [self drawMessage];

#if (defined(DEV_RELEASE))
            [self drawWatermarkString:"Development version " OO_VERSION_FULL];
#endif

            OO_LOG("universe.profile.drawHUD", "{}", "End HUD drawing");
            cxx_OOCheckOpenGLErrors("Universe after drawing HUD");

            OOGL(glFlush()); // don't wait around for drawing to complete

            no_update = NO; // allow other attempts to draw

            // frame complete, when it is time to update the fps_counter, updateClocks:delta_t
            // in PlayerEntity.m will take care of resetting the processed frames number to 0.
            if (![[self gameController] isGamePaused]) {
                framesDoneThisUpdate++;
            }
        }
        @catch (OOException* exception) {
            no_update = NO; // make sure we don't get stuck in all subsequent frames.

            if (strncmp([exception name], "Oolite", 6) == 0) {
                [self handleOoliteException:exception];
            } else {
                OO_LOG(cxx_kOOLogException, "***** Exception: {} : {} *****", [exception name], [exception reason]);
                @throw exception;
            }
        }
        @catch (OOFoundationException* exception) {
            no_update = NO; // make sure we don't get stuck in all subsequent frames.

            if ([[exception name] hasPrefix:@"Oolite"]) {
                [self handleOoliteException:[OOException exceptionWithName:[[exception name] UTF8String] reason:[[exception reason] UTF8String]]];
            } else {
                OO_LOG(cxx_kOOLogException, "***** Exception: {} : {} *****", oo::DescriptionOf([exception name]), oo::DescriptionOf([exception reason]));
                @throw exception;
            }
        }
    }

    OO_LOG("universe.profile.draw", "{}", "End drawing");

    // actions when the HUD should be rendered together with the 3d universe
    if (!hudSeparateRenderPass) {
        if ([self useShaders]) {
            [self prepareToRenderIntoDefaultFramebuffer];
            OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));

            OO_LOG("universe.profile.secondPassDraw", "{}", "Begin second pass draw");
            [self drawTargetTextureIntoDefaultFramebuffer];
            OO_LOG("universe.profile.secondPassDraw", "{}", "End second pass drawing");
        }
    }
}

- (void)prepareToRenderIntoDefaultFramebuffer
{
    NSSize viewSize = [gameView backingViewSize];
    if ([self useShaders]) {
        if ([gameView msaa]) {
            // resolve MSAA framebuffer to target framebuffer
            OOGL(glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFramebufferID));
            OOGL(glBindFramebuffer(GL_DRAW_FRAMEBUFFER, targetFramebufferID));
            OOGL(glBlitFramebuffer(0, 0, (GLint)viewSize.width, (GLint)viewSize.height, 0, 0, (GLint)viewSize.width, (GLint)viewSize.height, GL_COLOR_BUFFER_BIT, GL_NEAREST));
        }
    }
}

- (int)framesDoneThisUpdate
{
    return framesDoneThisUpdate;
}

- (void)resetFramesDoneThisUpdate
{
    framesDoneThisUpdate = 0;
}

- (OOMatrix)viewMatrix
{
    return viewMatrix;
}

- (void)drawMessage
{
    OOSetOpenGLState(OPENGL_STATE_OVERLAY);

    OOGL(glDisable(GL_TEXTURE_2D)); // for background sheets

    float overallAlpha = [[PLAYER hud] overallAlpha];
    if (displayGUI) {
        if ([[self gameController] mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_WITH_INTERACTION) {
            cursor_row = [gui drawGUI:1.0 drawCursor:YES];
        } else {
            [gui drawGUI:1.0 drawCursor:NO];
        }
    }

    [message_gui drawGUI:[message_gui alpha] * overallAlpha drawCursor:NO];
    [comm_log_gui drawGUI:[comm_log_gui alpha] * overallAlpha drawCursor:NO];

    OOVerifyOpenGLState();
}

- (void)drawWatermarkString:(const std::string&)watermarkString
{
    NSSize watermarkStringSize = cxx_OORectFromString(watermarkString, 0.0f, 0.0f, NSMakeSize(10, 10)).size;

    OOGL(glColor4f(0.0, 1.0, 0.0, 1.0));
    // position the watermark string on the top right hand corner of the game window and right-align it
    cxx_OODrawString(watermarkString, MAIN_GUI_PIXEL_WIDTH / 2 - watermarkStringSize.width + 80,
        MAIN_GUI_PIXEL_HEIGHT / 2 - watermarkStringSize.height, [gameView display_z], NSMakeSize(10, 10));
}

- (id)entityForUniversalID:(OOUniversalID)u_id
{
    if (u_id == 100)
        return PLAYER; // the player

    if (MAX_ENTITY_UID < u_id) {
        OO_LOG("universe.badUID", "Attempt to retrieve entity for out-of-range UID {}. (This is an internal programming error, please report it.)", static_cast<unsigned>(u_id));
        return nil;
    }

    if ((u_id == NO_TARGET) || (!entity_for_uid[u_id]))
        return nil;

    Entity* ent = entity_for_uid[u_id];
    if ([ent isEffect]) // effects SHOULD NOT HAVE U_IDs!
    {
        return nil;
    }

    if ([ent status] == STATUS_DEAD || [ent status] == STATUS_DOCKED) {
        return nil;
    }

    return ent;
}

static BOOL MaintainLinkedLists(Universe* uni)
{
    OOCParameterAssert(uni != NULL);
    BOOL result = YES;

    // DEBUG check for loops and short lists
    if (uni->n_entities > 0) {
        int n;
        Entity *checkEnt, *last;

        last = nil;

        n = uni->n_entities;
        checkEnt = uni->x_list_start;
        while ((n--) && (checkEnt)) {
            last = checkEnt;
            checkEnt = checkEnt->x_next;
        }
        if ((checkEnt) || (n > 0)) {
#ifndef NDEBUG
            OO_LOG(kOOLogEntityVerificationError, "Broken x_next {} list ({}) ***", oo::DescriptionOf(uni->x_list_start), n);
#endif
            result = NO;
        }

        n = uni->n_entities;
        checkEnt = last;
        while ((n--) && (checkEnt))
            checkEnt = checkEnt->x_previous;
        if ((checkEnt) || (n > 0)) {
#ifndef NDEBUG
            OO_LOG(kOOLogEntityVerificationError, "Broken x_previous {} list ({}) ***", oo::DescriptionOf(uni->x_list_start), n);
#endif
            if (result) {
#ifndef NDEBUG
                OO_LOG(kOOLogEntityVerificationRebuild, "{}", "REBUILDING x_previous list from x_next list");
#endif
                checkEnt = uni->x_list_start;
                checkEnt->x_previous = nil;
                while (checkEnt->x_next) {
                    last = checkEnt;
                    checkEnt = checkEnt->x_next;
                    checkEnt->x_previous = last;
                }
            }
        }

        n = uni->n_entities;
        checkEnt = uni->y_list_start;
        while ((n--) && (checkEnt)) {
            last = checkEnt;
            checkEnt = checkEnt->y_next;
        }
        if ((checkEnt) || (n > 0)) {
#ifndef NDEBUG
            OO_LOG(kOOLogEntityVerificationError, "Broken *** broken y_next {} list ({}) ***", oo::DescriptionOf(uni->y_list_start), n);
#endif
            result = NO;
        }

        n = uni->n_entities;
        checkEnt = last;
        while ((n--) && (checkEnt))
            checkEnt = checkEnt->y_previous;
        if ((checkEnt) || (n > 0)) {
#ifndef NDEBUG
            OO_LOG(kOOLogEntityVerificationError, "Broken y_previous {} list ({}) ***", oo::DescriptionOf(uni->y_list_start), n);
#endif
            if (result) {
#ifndef NDEBUG
                OO_LOG(kOOLogEntityVerificationRebuild, "{}", "REBUILDING y_previous list from y_next list");
#endif
                checkEnt = uni->y_list_start;
                checkEnt->y_previous = nil;
                while (checkEnt->y_next) {
                    last = checkEnt;
                    checkEnt = checkEnt->y_next;
                    checkEnt->y_previous = last;
                }
            }
        }

        n = uni->n_entities;
        checkEnt = uni->z_list_start;
        while ((n--) && (checkEnt)) {
            last = checkEnt;
            checkEnt = checkEnt->z_next;
        }
        if ((checkEnt) || (n > 0)) {
#ifndef NDEBUG
            OO_LOG(kOOLogEntityVerificationError, "Broken z_next {} list ({}) ***", oo::DescriptionOf(uni->z_list_start), n);
#endif
            result = NO;
        }

        n = uni->n_entities;
        checkEnt = last;
        while ((n--) && (checkEnt))
            checkEnt = checkEnt->z_previous;
        if ((checkEnt) || (n > 0)) {
#ifndef NDEBUG
            OO_LOG(kOOLogEntityVerificationError, "Broken z_previous {} list ({}) ***", oo::DescriptionOf(uni->z_list_start), n);
#endif
            if (result) {
#ifndef NDEBUG
                OO_LOG(kOOLogEntityVerificationRebuild, "{}", "REBUILDING z_previous list from z_next list");
#endif
                checkEnt = uni->z_list_start;
                OOCAssert(checkEnt != nil, "Expected z-list to be non-empty."); // Previously an implicit assumption. -- Ahruman 2011-01-25
                checkEnt->z_previous = nil;
                while (checkEnt->z_next) {
                    last = checkEnt;
                    checkEnt = checkEnt->z_next;
                    checkEnt->z_previous = last;
                }
            }
        }
    }

    if (!result) {
#ifndef NDEBUG
        OO_LOG(kOOLogEntityVerificationRebuild, "{}", "Rebuilding all linked lists from scratch");
#endif
        const std::vector<oo::ObjCRef<Entity*>> allEntities = uni->entities; // a snapshot, as the enumeration was
        uni->x_list_start = nil;
        uni->y_list_start = nil;
        uni->z_list_start = nil;

        Entity* ent = nil;
        for (const oo::ObjCRef<Entity*>& entry : allEntities) {
            ent = entry.get();
            ent->x_next = nil;
            ent->x_previous = nil;
            ent->y_next = nil;
            ent->y_previous = nil;
            ent->z_next = nil;
            ent->z_previous = nil;
            [ent addToLinkedLists];
        }
    }

    return result;
}

- (BOOL)addEntity:(Entity*)entity
{
    if (entity) {
        ShipEntity* se = nil;
        OOVisualEffectEntity* ve = nil;
        OOWaypointEntity* wp = nil;

        if (![entity validForAddToUniverse])
            return NO;

        // don't add things twice!
        if (std::find(entities.begin(), entities.end(), entity) != entities.end())
            return YES;

        if (n_entities >= UNIVERSE_MAX_ENTITIES - 1) {
            // throw an exception here...
            OO_LOG("universe.addEntity.failed", "***** Universe cannot addEntity:{} -- Universe is full ({} entities out of {})", oo::DescriptionOf(entity), static_cast<int>(n_entities), static_cast<int>(UNIVERSE_MAX_ENTITIES));
#ifndef NDEBUG
            if (OOLogWillDisplayMessagesInClass(@"universe.maxEntitiesDump"))
                [self debugDumpEntities];
#endif
            return NO;
        }

        if (![entity isEffect]) {
            unsigned limiter = UNIVERSE_MAX_ENTITIES;
            while (entity_for_uid[next_universal_id] != nil) // skip allocated numbers
            {
                next_universal_id++; // increment keeps idkeys unique
                if (next_universal_id >= MAX_ENTITY_UID) {
                    next_universal_id = MIN_ENTITY_UID;
                }
                if (limiter-- == 0) {
                    // Every slot has been tried! This should not happen due to previous test, but there was a problem here in 1.70.
                    OO_LOG("universe.addEntity.failed", "***** Universe cannot addEntity:{} -- Could not find free slot for entity.", oo::DescriptionOf(entity));
                    return NO;
                }
            }
            [entity setUniversalID:next_universal_id];
            entity_for_uid[next_universal_id] = entity;
            if ([entity isShip]) {
                se = (ShipEntity*)entity;
                if ([se isBeacon]) {
                    [self setNextBeacon:se];
                }
                if ([se isStation]) {
                    // check if it is a proper rotating station (ie. roles contains the word "station")
                    if ([(StationEntity*)se isRotatingStation]) {
                        double stationRoll = 0.0;
                        // check for station_roll override
                        id definedRoll = [[se shipInfoDictionary] objectForKey:@"station_roll"];

                        if (definedRoll != nil) {
                            stationRoll = OODoubleFromObject(definedRoll, stationRoll);
                        } else {
                            stationRoll = oo::PListView([self currentSystemData]).get<double>(@"station_roll", STANDARD_STATION_ROLL);
                        }

                        [se setRoll:stationRoll];
                    } else {
                        [se setRoll:0.0];
                    }
                    [(StationEntity*)se setPlanet:[self planet]];
                    if ([se maxFlightSpeed] > 0)
                        se->isExplicitlyNotMainStation = YES; // we never want carriers to become main stations.
                }
                // stations used to have STATUS_ACTIVE, they're all STATUS_IN_FLIGHT now.
                if ([se status] != STATUS_COCKPIT_DISPLAY) {
                    [se setStatus:STATUS_IN_FLIGHT];
                }
            }
        } else {
            [entity setUniversalID:NO_TARGET];
            if ([entity isVisualEffect]) {
                ve = (OOVisualEffectEntity*)entity;
                if ([ve isBeacon]) {
                    [self setNextBeacon:ve];
                }
            } else if ([entity isWaypoint]) {
                wp = (OOWaypointEntity*)entity;
                if ([wp isBeacon]) {
                    [self setNextBeacon:wp];
                }
            }
        }

        // lighting considerations
        entity->isSunlit = YES;
        entity->shadingEntityID = NO_TARGET;

        // add it to the universe
        entities.emplace_back(entity);
        [entity wasAddedToUniverse];

        // maintain sorted list (and for the scanner relative position)
        HPVector entity_pos = entity->position;
        HPVector delta = HPvector_between(entity_pos, PLAYER->position);
        double z_distance = HPmagnitude2(delta);
        entity->zero_distance = z_distance;
        unsigned index = n_entities;
        sortedEntities[index] = entity;
        entity->zero_index = index;
        while ((index > 0) && (z_distance < sortedEntities[index - 1]->zero_distance)) // bubble into place
        {
            sortedEntities[index] = sortedEntities[index - 1];
            sortedEntities[index]->zero_index = index;
            index--;
            sortedEntities[index] = entity;
            entity->zero_index = index;
        }

        // increase n_entities...
        n_entities++;

        // add entity to linked lists
        [entity addToLinkedLists]; // position and universe have been set - so we can do this
        if ([entity canCollide]) // filter only collidables disappearing
        {
            doLinkedListMaintenanceThisUpdate = YES;
        }

        if ([entity isWormhole]) {
            activeWormholes.emplace_back((WormholeEntity*)entity);
        } else if ([entity isPlanet]) {
            allPlanets.emplace_back((OOPlanetEntity*)entity);
        } else if ([entity isShip]) {
            [[se getAI] setOwner:se];
            [[se getAI] setState:@"GLOBAL"];
            if ([entity isStation]) {
                AddIfAbsent(allStations, (StationEntity*)entity);
            }
        }

        return YES;
    }
    return NO;
}

- (BOOL)removeEntity:(Entity*)entity
{
    if (entity != nil && ![entity isPlayer]) {
        /*	Ensure entity won't actually be dealloced until the end of this
                update (or the next update if none is in progress), because
                there may be things pointing to it but not retaining it.
        */
        AddIfAbsent(entitiesDeadThisUpdate, entity);
        if ([entity isStation]) {
            std::erase(allStations, entity);
            if ([PLAYER getTargetDockStation] == entity) {
                [PLAYER setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
            }
        }
        return [self doRemoveEntity:entity];
    }
    return NO;
}

- (void)ensureEntityReallyRemoved:(Entity*)entity
{
    if ([entity universalID] != NO_TARGET) {
        OO_LOG("universe.unremovedEntity", "Entity {} dealloced without being removed from universe! (This is an internal programming error, please report it.)", oo::DescriptionOf(entity));
        [self doRemoveEntity:entity];
    }
}

- (void)removeAllEntitiesExceptPlayer
{
    BOOL updating = no_update;
    no_update = YES; // no drawing while we do this!

#ifndef NDEBUG
    Entity* p0 = entities[0].get();
    if (!(p0->isPlayer)) {
        OO_LOG(cxx_kOOLogInconsistentState, "{}", "***** First entity is not the player in Universe.removeAllEntitiesExceptPlayer - exiting.");
        exit(EXIT_FAILURE);
    }
#endif

    // preserve wormholes
    std::vector<oo::ObjCRef<WormholeEntity*>> savedWormholes = activeWormholes;

    while (entities.size() > 1) {
        Entity* ent = entities[1].get();
        if (ent->isStation) // clear out queues
            [(StationEntity*)ent clear];
        if (EXPECT(![ent isVisualEffect])) {
            [self removeEntity:ent];
        } else {
            // this will ensure the effectRemoved script event will run
            [(OOVisualEffectEntity*)ent remove];
        }
    }

    activeWormholes = std::move(savedWormholes); // will be cleared out by populateSpaceFromActiveWormholes

    // maintain sorted list
    n_entities = 1;

    cachedSun = nil;
    cachedPlanet = nil;
    cachedStation = nil;
    closeSystems.reset();

    [self resetBeacons];
    waypoints.clear();

    no_update = updating; // restore drawing
}

- (void)removeDemoShips
{
    int i;
    int ent_count = n_entities;
    if (ent_count > 0) {
        Entity* ent;
        for (i = 0; i < ent_count; i++) {
            ent = sortedEntities[i];
            if ([ent status] == STATUS_COCKPIT_DISPLAY && ![ent isPlayer]) {
                [self removeEntity:ent];
            }
        }
    }
    demo_ship = nil;
}

- (ShipEntity*)cxx_makeDemoShipWithRole:(const std::string&)role spinning:(BOOL)spinning
{
    if ([PLAYER dockedStation] == nil)
        return nil;

    [self removeDemoShips]; // get rid of any pre-existing models on display

    [PLAYER setShowDemoShips:YES];
    Quaternion q2 = { (GLfloat)M_SQRT1_2, (GLfloat)M_SQRT1_2, (GLfloat)0.0, (GLfloat)0.0 };

    ShipEntity* ship = [self cxx_newShipWithRole:role]; // retain count = 1
    if (ship) {
        double cr = [ship collisionRadius];
        [ship setOrientation:q2];
        [ship setPositionX:0.0f y:0.0f z:3.6f * cr];
        [ship setScanClass:CLASS_NO_DRAW];
        [ship switchAITo:@"nullAI.plist"];
        [ship setPendingEscortCount:0];

        [UNIVERSE addEntity:ship]; // STATUS_IN_FLIGHT, AI state GLOBAL

        if (spinning) {
            [ship setDemoShip:1.0f];
        } else {
            [ship setDemoShip:0.0f];
        }
        [ship setStatus:STATUS_COCKPIT_DISPLAY];
        // stop problems on the ship library screen
        // demo ships shouldn't have this equipment
        [ship removeEquipmentItem:@"EQ_SHIELD_BOOSTER"];
        [ship removeEquipmentItem:@"EQ_SHIELD_ENHANCER"];
    }

    return [ship autorelease];
}

- (BOOL)isVectorClearFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2
{
    if (!e1)
        return NO;

    HPVector f1;
    HPVector p1 = e1->position;
    HPVector v1 = p2;
    v1.x -= p1.x;
    v1.y -= p1.y;
    v1.z -= p1.z; // vector from entity to p2

    double nearest = sqrt(v1.x * v1.x + v1.y * v1.y + v1.z * v1.z) - dist; // length of vector

    if (nearest < 0.0)
        return YES; // within range already!

    int i;
    int ent_count = n_entities;
    std::vector<Entity*> my_entities(ent_count);
    for (i = 0; i < ent_count; i++)
        my_entities[i] = [sortedEntities[i] retain]; //	retained

    if (v1.x || v1.y || v1.z)
        f1 = HPvector_normal(v1); // unit vector in direction of p2 from p1
    else
        f1 = make_HPvector(0, 0, 1);

    for (i = 0; i < ent_count; i++) {
        Entity* e2 = my_entities[i];
        if ((e2 != e1) && ([e2 canCollide])) {
            HPVector epos = e2->position;
            epos.x -= p1.x;
            epos.y -= p1.y;
            epos.z -= p1.z; // epos now holds vector from p1 to this entities position

            double d_forward = HPdot_product(epos, f1); // distance along f1 which is nearest to e2's position

            if ((d_forward > 0) && (d_forward < nearest)) {
                double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
                HPVector p0 = e1->position;
                p0.x += d_forward * f1.x;
                p0.y += d_forward * f1.y;
                p0.z += d_forward * f1.z;
                // p0 holds nearest point on current course to center of incident object
                HPVector epos = e2->position;
                p0.x -= epos.x;
                p0.y -= epos.y;
                p0.z -= epos.z;
                // compare with center of incident object
                double dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
                if (dist2 < cr * cr) {
                    for (i = 0; i < ent_count; i++)
                        [my_entities[i] release]; //	released
                    return NO;
                }
            }
        }
    }
    for (i = 0; i < ent_count; i++)
        [my_entities[i] release]; //	released
    return YES;
}

- (Entity*)hazardOnRouteFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2
{
    if (!e1)
        return nil;

    HPVector f1;
    HPVector p1 = e1->position;
    HPVector v1 = p2;
    v1.x -= p1.x;
    v1.y -= p1.y;
    v1.z -= p1.z; // vector from entity to p2

    double nearest = HPmagnitude(v1) - dist; // length of vector

    if (nearest < 0.0)
        return nil; // within range already!

    Entity* result = nil;
    int i;
    int ent_count = n_entities;
    std::vector<Entity*> my_entities(ent_count);
    for (i = 0; i < ent_count; i++)
        my_entities[i] = [sortedEntities[i] retain]; //	retained

    if (v1.x || v1.y || v1.z)
        f1 = HPvector_normal(v1); // unit vector in direction of p2 from p1
    else
        f1 = make_HPvector(0, 0, 1);

    for (i = 0; (i < ent_count) && (!result); i++) {
        Entity* e2 = my_entities[i];
        if ((e2 != e1) && ([e2 canCollide])) {
            HPVector epos = e2->position;
            epos.x -= p1.x;
            epos.y -= p1.y;
            epos.z -= p1.z; // epos now holds vector from p1 to this entities position

            double d_forward = HPdot_product(epos, f1); // distance along f1 which is nearest to e2's position

            if ((d_forward > 0) && (d_forward < nearest)) {
                double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
                HPVector p0 = e1->position;
                p0.x += d_forward * f1.x;
                p0.y += d_forward * f1.y;
                p0.z += d_forward * f1.z;
                // p0 holds nearest point on current course to center of incident object
                HPVector epos = e2->position;
                p0.x -= epos.x;
                p0.y -= epos.y;
                p0.z -= epos.z;
                // compare with center of incident object
                double dist2 = HPmagnitude2(p0);
                if (dist2 < cr * cr)
                    result = e2;
            }
        }
    }
    for (i = 0; i < ent_count; i++)
        [my_entities[i] release]; //	released
    return result;
}

- (HPVector)getSafeVectorFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2
{
    // heuristic three

    if (!e1) {
        OO_LOG(cxx_kOOLogParameterError, "{}", "***** No entity set in Universe getSafeVectorFromEntity:toDistance:fromPoint:");
        return kZeroHPVector;
    }

    HPVector f1;
    HPVector result = p2;
    int i;
    int ent_count = n_entities;
    std::vector<Entity*> my_entities(ent_count);
    for (i = 0; i < ent_count; i++)
        my_entities[i] = [sortedEntities[i] retain]; // retained
    HPVector p1 = e1->position;
    HPVector v1 = p2;
    v1.x -= p1.x;
    v1.y -= p1.y;
    v1.z -= p1.z; // vector from entity to p2

    double nearest = sqrt(v1.x * v1.x + v1.y * v1.y + v1.z * v1.z) - dist; // length of vector

    if (v1.x || v1.y || v1.z)
        f1 = HPvector_normal(v1); // unit vector in direction of p2 from p1
    else
        f1 = make_HPvector(0, 0, 1);

    for (i = 0; i < ent_count; i++) {
        Entity* e2 = my_entities[i];
        if ((e2 != e1) && ([e2 canCollide])) {
            HPVector epos = e2->position;
            epos.x -= p1.x;
            epos.y -= p1.y;
            epos.z -= p1.z;
            double d_forward = HPdot_product(epos, f1);
            if ((d_forward > 0) && (d_forward < nearest)) {
                double cr = 1.20 * (e2->collision_radius + e1->collision_radius); //  20% safety margin

                HPVector p0 = e1->position;
                p0.x += d_forward * f1.x;
                p0.y += d_forward * f1.y;
                p0.z += d_forward * f1.z;
                // p0 holds nearest point on current course to center of incident object

                HPVector epos = e2->position;
                p0.x -= epos.x;
                p0.y -= epos.y;
                p0.z -= epos.z;
                // compare with center of incident object

                double dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;

                if (dist2 < cr * cr) {
                    result = e2->position; // center of incident object
                    nearest = d_forward;

                    if (dist2 == 0.0) {
                        // ie. we're on a line through the object's center !
                        // jitter the position somewhat!
                        result.x += ((int)(Ranrot() % 1024) - 512) / 512.0; //   -1.0 .. +1.0
                        result.y += ((int)(Ranrot() % 1024) - 512) / 512.0; //   -1.0 .. +1.0
                        result.z += ((int)(Ranrot() % 1024) - 512) / 512.0; //   -1.0 .. +1.0
                    }

                    HPVector nearest_point = p1;
                    nearest_point.x += d_forward * f1.x;
                    nearest_point.y += d_forward * f1.y;
                    nearest_point.z += d_forward * f1.z;
                    // nearest point now holds nearest point on line to center of incident object

                    HPVector outward = nearest_point;
                    outward.x -= result.x;
                    outward.y -= result.y;
                    outward.z -= result.z;
                    if (outward.x || outward.y || outward.z)
                        outward = HPvector_normal(outward);
                    else
                        outward.y = 1.0;
                    // outward holds unit vector through the nearest point on the line from the center of incident object

                    HPVector backward = p1;
                    backward.x -= result.x;
                    backward.y -= result.y;
                    backward.z -= result.z;
                    if (backward.x || backward.y || backward.z)
                        backward = HPvector_normal(backward);
                    else
                        backward.z = -1.0;
                    // backward holds unit vector from center of the incident object to the center of the ship

                    HPVector dd = result;
                    dd.x -= p1.x;
                    dd.y -= p1.y;
                    dd.z -= p1.z;
                    double current_distance = HPmagnitude(dd);

                    // sanity check current_distance
                    if (current_distance < cr * 1.25) // 25% safety margin
                        current_distance = cr * 1.25;
                    if (current_distance > cr * 5.0) // up to 2 diameters away
                        current_distance = cr * 5.0;

                    // choose a point that's three parts backward and one part outward

                    result.x += 0.25 * (outward.x * current_distance) + 0.75 * (backward.x * current_distance); // push 'out' by this amount
                    result.y += 0.25 * (outward.y * current_distance) + 0.75 * (backward.y * current_distance);
                    result.z += 0.25 * (outward.z * current_distance) + 0.75 * (backward.z * current_distance);
                }
            }
        }
    }
    for (i = 0; i < ent_count; i++)
        [my_entities[i] release]; //	released
    return result;
}

- (ShipEntity*)cxx_addWreckageFrom:(ShipEntity*)ship withRole:(const std::string&)wreckRole at:(HPVector)rpos scale:(GLfloat)scale lifetime:(GLfloat)lifetime
{
    ShipEntity* wreck = [UNIVERSE cxx_newShipWithRole:wreckRole]; // retain count = 1
    Quaternion q;
    if (wreck) {
        GLfloat expected_mass = 0.1f * [ship mass] * (0.75 + 0.5 * randf());
        GLfloat wreck_mass = [wreck mass];
        GLfloat scale_factor = powf(expected_mass / wreck_mass, 0.33333333f) * scale; // cube root of volume ratio
        [wreck rescaleBy:scale_factor writeToCache:NO];

        [wreck setPosition:rpos];

        [wreck setVelocity:[ship velocity]];

        quaternion_set_random(&q);
        [wreck setOrientation:q];

        [wreck setTemperature:1000.0]; // take 1000e heat damage per second
        [wreck setHeatInsulation:1.0e7]; // very large! so it won't cool down
        [wreck setEnergy:lifetime];

        [wreck setIsWreckage:YES];

        [UNIVERSE addEntity:wreck]; // STATUS_IN_FLIGHT, AI state GLOBAL
        [wreck performTumble];
        //	[wreck rescaleBy: 1.0/scale_factor];
        [wreck release];
    }
    return wreck;
}

- (void)addLaserHitEffectsAt:(HPVector)pos against:(ShipEntity*)target damage:(float)damage color:(OOColor*)color
{
    // low energy, start getting small surface explosions
    if ([target showDamage] && [target energy] < [target maxEnergy] / 2) {
        const char* key = (randf() < 0.5) ? "oolite-hull-spark" : "oolite-hull-spark-b";
        const oo::PList settings = [UNIVERSE cxx_explosionSetting:key];
        OOExplosionCloudEntity* burst = [OOExplosionCloudEntity explosionCloudFromEntity:target withSettings:settings];
        [burst setPosition:pos];
        [self addEntity:burst];
        if ([target energy] * randf() < damage) {
            ShipEntity* wreck = [self addWreckageFrom:target withRole:@"oolite-wreckage-chunk" at:pos scale:0.05 lifetime:(125.0 + (randf() * 200.0))];
            if (wreck) {
                Vector direction = HPVectorToVector(HPvector_normal(HPvector_subtract(pos, [target position])));
                [wreck setVelocity:vector_add([wreck velocity], vector_multiply_scalar(direction, 10 + 20 * randf()))];
            }
        }
    } else {
        [self addEntity:[OOFlashEffectEntity laserFlashWithPosition:pos velocity:[target velocity] color:color]];
    }
}

- (ShipEntity*)firstShipHitByLaserFromShip:(ShipEntity*)srcEntity inDirection:(OOWeaponFacing)direction offset:(Vector)offset gettingRangeFound:(GLfloat*)range_ptr
{
    if (srcEntity == nil)
        return nil;

    ShipEntity* hit_entity = nil;
    ShipEntity* hit_subentity = nil;
    HPVector p0 = [srcEntity position];
    Quaternion q1 = [srcEntity normalOrientation];
    ShipEntity* parent = [srcEntity parentEntity];

    if (parent) {
        // we're a subentity!
        BoundingBox bbox = [srcEntity boundingBox];
        HPVector midfrontplane = make_HPvector(0.5 * (bbox.max.x + bbox.min.x), 0.5 * (bbox.max.y + bbox.min.y), bbox.max.z);
        p0 = [srcEntity absolutePositionForSubentityOffset:midfrontplane];
        q1 = [parent orientation];
        if ([parent isPlayer])
            q1.w = -q1.w;
    }

    double nearest = [srcEntity weaponRange];
    int i;
    int ent_count = n_entities;
    int ship_count = 0;
    std::vector<ShipEntity*> my_entities(ent_count);

    for (i = 0; i < ent_count; i++) {
        Entity* ent = sortedEntities[i];
        if (ent != srcEntity && ent != parent && [ent isShip] && [ent canCollide]) {
            my_entities[ship_count++] = [(ShipEntity*)ent retain];
        }
    }

    Vector u1, f1, r1;
    basis_vectors_from_quaternion(q1, &r1, &u1, &f1);
    p0 = HPvector_add(p0, vectorToHPVector(OOVectorMultiplyMatrix(offset, OOMatrixFromBasisVectors(r1, u1, f1))));

    switch (direction) {
    case WEAPON_FACING_FORWARD:
    case WEAPON_FACING_NONE:
        break;

    case WEAPON_FACING_AFT:
        quaternion_rotate_about_axis(&q1, u1, M_PI);
        break;

    case WEAPON_FACING_PORT:
        quaternion_rotate_about_axis(&q1, u1, M_PI / 2.0);
        break;

    case WEAPON_FACING_STARBOARD:
        quaternion_rotate_about_axis(&q1, u1, -M_PI / 2.0);
        break;
    }

    basis_vectors_from_quaternion(q1, &r1, NULL, &f1);
    HPVector p1 = HPvector_add(p0, vectorToHPVector(vector_multiply_scalar(f1, nearest))); // endpoint

    for (i = 0; i < ship_count; i++) {
        ShipEntity* e2 = my_entities[i];

        // check outermost bounding sphere
        GLfloat cr = e2->collision_radius;
        Vector rpos = HPVectorToVector(HPvector_subtract(e2->position, p0));
        Vector v_off = make_vector(dot_product(rpos, r1), dot_product(rpos, u1), dot_product(rpos, f1));
        if (v_off.z > 0.0 && v_off.z < nearest + cr && // ahead AND within range
            v_off.x < cr && v_off.x > -cr && v_off.y < cr && v_off.y > -cr && // AND not off to one side or another
            v_off.x * v_off.x + v_off.y * v_off.y < cr * cr) // AND not off to both sides
        {
            ShipEntity* entHit = nil;
            GLfloat hit = [(ShipEntity*)e2 doesHitLine:p0 v1:p1 hitEntity:&entHit]; // octree detection

            if (hit > 0.0 && hit < nearest) {
                if ([entHit isSubEntity]) {
                    hit_subentity = entHit;
                }
                hit_entity = e2;
                nearest = hit;
                p1 = HPvector_add(p0, vectorToHPVector(vector_multiply_scalar(f1, nearest)));
            }
        }
    }

    if (hit_entity) {
        // I think the above code does not guarantee that the closest hit_subentity belongs to the closest hit_entity.
        if (hit_subentity && [hit_subentity owner] == hit_entity)
            [hit_entity setSubEntityTakingDamage:hit_subentity];

        if (range_ptr != NULL) {
            *range_ptr = nearest;
        }
    }

    for (i = 0; i < ship_count; i++)
        [my_entities[i] release]; //	released

    return hit_entity;
}

- (Entity*)firstEntityTargetedByPlayer
{
    PlayerEntity* player = PLAYER;
    Entity* hit_entity = nil;
    OOScalar nearest2 = SCANNER_MAX_RANGE - 100; // 100m shorter than range at which target is lost
    nearest2 *= nearest2;
    int i;
    int ent_count = n_entities;
    int ship_count = 0;
    std::vector<Entity*> my_entities(ent_count);

    for (i = 0; i < ent_count; i++) {
        if (([sortedEntities[i] isShip] && ![sortedEntities[i] isPlayer]) || [sortedEntities[i] isWormhole]) {
            my_entities[ship_count++] = [sortedEntities[i] retain];
        }
    }

    Quaternion q1 = [player normalOrientation];
    Vector u1, f1, r1;
    basis_vectors_from_quaternion(q1, &r1, &u1, &f1);
    Vector offset = [player weaponViewOffset];

    HPVector p1 = HPvector_add([player position], vectorToHPVector(OOVectorMultiplyMatrix(offset, OOMatrixFromBasisVectors(r1, u1, f1))));

    // Note: deliberately tied to view direction, not weapon facing. All custom views count as forward for targeting.
    switch (viewDirection) {
    case VIEW_AFT:
        quaternion_rotate_about_axis(&q1, u1, M_PI);
        break;
    case VIEW_PORT:
        quaternion_rotate_about_axis(&q1, u1, 0.5 * M_PI);
        break;
    case VIEW_STARBOARD:
        quaternion_rotate_about_axis(&q1, u1, -0.5 * M_PI);
        break;
    default:
        break;
    }
    basis_vectors_from_quaternion(q1, &r1, NULL, &f1);

    for (i = 0; i < ship_count; i++) {
        Entity* e2 = my_entities[i];
        if ([e2 canCollide] && [e2 scanClass] != CLASS_NO_DRAW) {
            Vector rp = HPVectorToVector(HPvector_subtract([e2 position], p1));
            OOScalar dist2 = magnitude2(rp);
            if (dist2 < nearest2) {
                OOScalar df = dot_product(f1, rp);
                if (df > 0.0 && df * df < nearest2) {
                    OOScalar du = dot_product(u1, rp);
                    OOScalar dr = dot_product(r1, rp);
                    OOScalar cr = [e2 collisionRadius];
                    if (du * du + dr * dr < cr * cr) {
                        hit_entity = e2;
                        nearest2 = dist2;
                    }
                }
            }
        }
    }
    // check for MASC'M
    if (hit_entity != nil && [hit_entity isShip]) {
        ShipEntity* ship = (ShipEntity*)hit_entity;
        if ([ship isJammingScanning] && ![player hasMilitaryScannerFilter]) {
            hit_entity = nil;
        }
    }

    for (i = 0; i < ship_count; i++) {
        [my_entities[i] release];
    }

    return hit_entity;
}

- (Entity*)firstEntityTargetedByPlayerPrecisely
{
    OOWeaponFacing targetFacing;
    Vector laserPortOffset = kZeroVector;
    PlayerEntity* player = PLAYER;

    switch (viewDirection) {
    case VIEW_FORWARD:
        targetFacing = WEAPON_FACING_FORWARD;
        laserPortOffset = oo::PListView([player forwardWeaponOffset]).at<Vector>(0);
        break;

    case VIEW_AFT:
        targetFacing = WEAPON_FACING_AFT;
        laserPortOffset = oo::PListView([player aftWeaponOffset]).at<Vector>(0);
        break;

    case VIEW_PORT:
        targetFacing = WEAPON_FACING_PORT;
        laserPortOffset = oo::PListView([player portWeaponOffset]).at<Vector>(0);
        break;

    case VIEW_STARBOARD:
        targetFacing = WEAPON_FACING_STARBOARD;
        laserPortOffset = oo::PListView([player starboardWeaponOffset]).at<Vector>(0);
        break;

    default:
        // Match behaviour of -firstEntityTargetedByPlayer.
        targetFacing = WEAPON_FACING_FORWARD;
        laserPortOffset = oo::PListView([player forwardWeaponOffset]).at<Vector>(0);
    }

    return [self firstShipHitByLaserFromShip:PLAYER inDirection:targetFacing offset:laserPortOffset gettingRangeFound:NULL];
}

- (std::vector<oo::ObjCRef<Entity*>>)cxx_entitiesWithinRange:(double)range ofEntity:(Entity*)entity
{
    if (entity == nil)
        return { };

    return [self cxx_findShipsMatchingPredicate:YESPredicate
                                      parameter:NULL
                                        inRange:range
                                       ofEntity:entity];
}

// The role predicates read an Objective-C string (-hasRole: / -hasPrimaryRole: are the unmigrated ShipEntity's).
- (unsigned)cxx_countShipsWithRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity
{
    return [self countShipsMatchingPredicate:HasRolePredicate
                                   parameter:oo::NSStringFrom(role)
                                     inRange:range
                                    ofEntity:entity];
}

- (unsigned)cxx_countShipsWithRole:(const std::string&)role
{
    return [self cxx_countShipsWithRole:role inRange:-1 ofEntity:nil];
}

- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity
{
    return [self countShipsMatchingPredicate:HasPrimaryRolePredicate
                                   parameter:oo::NSStringFrom(role)
                                     inRange:range
                                    ofEntity:entity];
}

// HasScanClassPredicate reads the scan class as a number object's -intValue.
- (unsigned)countShipsWithScanClass:(OOScanClass)scanClass inRange:(double)range ofEntity:(Entity*)entity
{
    return [self countShipsMatchingPredicate:HasScanClassPredicate
                                   parameter:oo::ObjectFromPList(oo::PList(std::int64_t(scanClass)))
                                     inRange:range
                                    ofEntity:entity];
}

- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role
{
    return [self cxx_countShipsWithPrimaryRole:role inRange:-1 ofEntity:nil];
}

- (unsigned)countEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                 parameter:(void*)parameter
                                   inRange:(double)range
                                  ofEntity:(Entity*)e1
{
    unsigned i, found = 0;
    HPVector p1;
    double distance, cr;

    if (predicate == NULL)
        predicate = YESPredicate;

    if (e1 != nil)
        p1 = e1->position;
    else
        p1 = kZeroHPVector;

    for (i = 0; i < n_entities; i++) {
        Entity* e2 = sortedEntities[i];
        if (e2 != e1 && predicate(e2, parameter)) {
            if (range < 0)
                distance = -1; // Negative range means infinity
            else {
                cr = range + e2->collision_radius;
                distance = HPdistance2(e2->position, p1) - cr * cr;
            }
            if (distance < 0) {
                found++;
            }
        }
    }

    return found;
}

- (unsigned)countShipsMatchingPredicate:(EntityFilterPredicate)predicate
                              parameter:(void*)parameter
                                inRange:(double)range
                               ofEntity:(Entity*)entity
{
    if (predicate != NULL) {
        BinaryOperationPredicateParameter param = {
            IsShipPredicate, NULL,
            predicate, parameter
        };

        return [self countEntitiesMatchingPredicate:ANDPredicate
                                          parameter:&param
                                            inRange:range
                                           ofEntity:entity];
    } else {
        return [self countEntitiesMatchingPredicate:IsShipPredicate
                                          parameter:NULL
                                            inRange:range
                                           ofEntity:entity];
    }
}

OOINLINE BOOL EntityInRange(HPVector p1, Entity* e2, float range)
{
    if (range < 0)
        return YES;
    float cr = range + e2->collision_radius;
    return HPdistance2(e2->position, p1) < cr * cr;
}

// NOTE: OOJSSystem relies on this returning entities in distance-from-player order.
// This can be easily changed by removing the [reference isPlayer] conditions in FindJSVisibleEntities().
- (std::vector<oo::ObjCRef<Entity*>>)cxx_findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                                             parameter:(void*)parameter
                                                               inRange:(double)range
                                                              ofEntity:(Entity*)e1
{
    OOJS_PROFILE_ENTER

    unsigned i;
    HPVector p1;
    std::vector<oo::ObjCRef<Entity*>> result;

    OOJSPauseTimeLimiter();

    if (predicate == NULL)
        predicate = YESPredicate;

    result.reserve(n_entities);

    if (e1 != nil)
        p1 = [e1 position];
    else
        p1 = kZeroHPVector;

    for (i = 0; i < n_entities; i++) {
        Entity* e2 = sortedEntities[i];

        if (e1 != e2 && EntityInRange(p1, e2, range) && predicate(e2, parameter)) {
            result.emplace_back(e2);
        }
    }

    OOJSResumeTimeLimiter();

    return result;

    OOJS_PROFILE_EXIT
}

- (id)findOneEntityMatchingPredicate:(EntityFilterPredicate)predicate
                           parameter:(void*)parameter
{
    unsigned i;
    Entity* candidate = nil;

    OOJSPauseTimeLimiter();

    if (predicate == NULL)
        predicate = YESPredicate;

    for (i = 0; i < n_entities; i++) {
        candidate = sortedEntities[i];
        if (predicate(candidate, parameter))
            return candidate;
    }

    OOJSResumeTimeLimiter();

    return nil;
}

- (std::vector<oo::ObjCRef<Entity*>>)cxx_findShipsMatchingPredicate:(EntityFilterPredicate)predicate
                                                          parameter:(void*)parameter
                                                            inRange:(double)range
                                                           ofEntity:(Entity*)entity
{
    if (predicate != NULL) {
        BinaryOperationPredicateParameter param = {
            IsShipPredicate, NULL,
            predicate, parameter
        };

        return [self cxx_findEntitiesMatchingPredicate:ANDPredicate
                                             parameter:&param
                                               inRange:range
                                              ofEntity:entity];
    } else {
        return [self cxx_findEntitiesMatchingPredicate:IsShipPredicate
                                             parameter:NULL
                                               inRange:range
                                              ofEntity:entity];
    }
}

- (std::vector<oo::ObjCRef<Entity*>>)cxx_findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate
                                                                  parameter:(void*)parameter
                                                                    inRange:(double)range
                                                                   ofEntity:(Entity*)entity
{
    if (predicate != NULL) {
        BinaryOperationPredicateParameter param = {
            IsVisualEffectPredicate, NULL,
            predicate, parameter
        };

        return [self cxx_findEntitiesMatchingPredicate:ANDPredicate
                                             parameter:&param
                                               inRange:range
                                              ofEntity:entity];
    } else {
        return [self cxx_findEntitiesMatchingPredicate:IsVisualEffectPredicate
                                             parameter:NULL
                                               inRange:range
                                              ofEntity:entity];
    }
}

- (id)nearestEntityMatchingPredicate:(EntityFilterPredicate)predicate
                           parameter:(void*)parameter
                    relativeToEntity:(Entity*)entity
{
    unsigned i;
    HPVector p1;
    float rangeSq = INFINITY;
    id result = nil;

    if (predicate == NULL)
        predicate = YESPredicate;

    if (entity != nil)
        p1 = [entity position];
    else
        p1 = kZeroHPVector;

    for (i = 0; i < n_entities; i++) {
        Entity* e2 = sortedEntities[i];
        float distanceToReferenceEntitySquared = (float)HPdistance2(p1, [e2 position]);

        if (entity != e2 && distanceToReferenceEntitySquared < rangeSq && predicate(e2, parameter)) {
            result = e2;
            rangeSq = distanceToReferenceEntitySquared;
        }
    }

    return [[result retain] autorelease];
}

- (id)nearestShipMatchingPredicate:(EntityFilterPredicate)predicate
                         parameter:(void*)parameter
                  relativeToEntity:(Entity*)entity
{
    if (predicate != NULL) {
        BinaryOperationPredicateParameter param = {
            IsShipPredicate, NULL,
            predicate, parameter
        };

        return [self nearestEntityMatchingPredicate:ANDPredicate
                                          parameter:&param
                                   relativeToEntity:entity];
    } else {
        return [self nearestEntityMatchingPredicate:IsShipPredicate
                                          parameter:NULL
                                   relativeToEntity:entity];
    }
}

- (OOTimeAbsolute)getTime
{
    return universal_time;
}

- (OOTimeDelta)getTimeDelta
{
    return time_delta;
}

- (void)findCollisionsAndShadows
{
    unsigned i;

    [universeRegion clearEntityList];

    for (i = 0; i < n_entities; i++) {
        [universeRegion checkEntity:sortedEntities[i]]; // sorts out which region it's in
    }

    if (![[self gameController] isGamePaused]) {
        [universeRegion findCollisions];
    }

    // do check for entities that can't see the sun!
    [universeRegion findShadowedEntities];
}

- (id)collisionDescription // shared selector (proposed ADR-0043): an Objective-C string, as CollisionRegion's
{
    if (universeRegion != nil)
        return [universeRegion collisionDescription];
    else
        return @"-";
}

- (void)dumpCollisions
{
    dumpCollisionInfo = YES;
}

- (OOViewID)viewDirection
{
    return viewDirection;
}

- (void)setViewDirection:(OOViewID)vd
{
    std::optional<std::string> ms;
    BOOL guiSelected = NO;

    if ((viewDirection == vd) && (vd != VIEW_CUSTOM) && (!displayGUI))
        return;

    switch (vd) {
    case VIEW_FORWARD:
        ms = cxx_OOLookUpDescriptionPRIV("forward-view-string");
        break;

    case VIEW_AFT:
        ms = cxx_OOLookUpDescriptionPRIV("aft-view-string");
        break;

    case VIEW_PORT:
        ms = cxx_OOLookUpDescriptionPRIV("port-view-string");
        break;

    case VIEW_STARBOARD:
        ms = cxx_OOLookUpDescriptionPRIV("starboard-view-string");
        break;

    case VIEW_CUSTOM:
        ms = oo::OptionalString([PLAYER customViewDescription]);
        break;

    case VIEW_GUI_DISPLAY:
        [self setDisplayText:YES];
        [self setMainLightPosition:(Vector) { DEMO_LIGHT_POSITION }];
        guiSelected = YES;
        break;

    default:
        guiSelected = YES;
        break;
    }

    if (guiSelected) {
        [[self gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
    } else {
        displayGUI = NO; // switch off any text displays
        [[self gameController] setMouseInteractionModeForFlight];
    }

    if (viewDirection != vd || viewDirection == VIEW_CUSTOM) {
#if (ALLOW_CUSTOM_VIEWS_WHILE_PAUSED)
        BOOL gamePaused = [[self gameController] isGamePaused];
#else
        BOOL gamePaused = NO;
#endif
        // view notifications for when the player switches to/from gui!
        // if (EXPECT(viewDirection == VIEW_GUI_DISPLAY || vd == VIEW_GUI_DISPLAY )) [PLAYER noteViewDidChangeFrom:viewDirection toView:vd];
        viewDirection = vd;
        if (ms.has_value() && !gamePaused) {
            [self cxx_addMessage:ms forCount:3];
        } else if (gamePaused) {
            [message_gui clear];
        }
    }
}

- (void)enterGUIViewModeWithMouseInteraction:(BOOL)mouseInteraction
{
    OOViewID vd = viewDirection;
    [self setViewDirection:VIEW_GUI_DISPLAY];
    if (viewDirection != vd) {
        PlayerEntity* player = PLAYER;
        JSContext* context = OOJSAcquireContext();
        ShipScriptEvent(context, player, "viewDirectionChanged", OOJSValueFromViewID(context, viewDirection), OOJSValueFromViewID(context, vd));
        OOJSRelinquishContext(context);
    }
    [[self gameController] setMouseInteractionModeForUIWithMouseInteraction:mouseInteraction];
}

namespace {

std::optional<std::string> OptionalStringAt(const oo::PList& array, std::size_t index); // defined with the configuration readers below
std::optional<std::string> OptionalStringIn(const oo::PList& dict, std::string_view key);
std::string ExpandKey(const std::string& key); // defined with the shipyard helpers below

// -[currentMessage isEqual:text]: both present and equal (a nil receiver or argument answered NO).
bool SameMessage(const std::optional<std::string>& current, const std::optional<std::string>& text)
{
    return current.has_value() && text.has_value() && *current == *text;
}

} // namespace

// Resolved names are cached by key; a nil key (an array entry that is neither a string nor a
// number) is cached as "", as the cache took a nil key.
- (std::optional<std::string>)soundNameForCustomSoundKey:(const std::string&)soundKey
{
    std::optional<std::string> key = soundKey;
    std::optional<std::string> result;
    std::set<std::string> seen;
    const oo::PList* object = customSounds.find(*key);

    if (object != nullptr && object->isArray() && object->count() > 0) {
        key = OptionalStringAt(*object, Ranrot() % object->count());
    } else {
        object = nullptr;
    }

    result = oo::OptionalString([[OOCacheManager sharedCache] cxx_objectForKey:key.value_or(std::string()) inCache:"resolved custom sounds"]);
    if (!result.has_value()) {
        // Resolve sound, allowing indirection within customsounds.plist
        result = key;
        if (object == nullptr || (result.has_value() && oo::str::hasPrefix(*result, "[") && oo::str::hasSuffix(*result, "]"))) {
            for (;;) {
                seen.insert(*result);
                object = customSounds.find(*result);
                if (object != nullptr && object->isArray() && object->count() > 0) {
                    result = OptionalStringAt(*object, Ranrot() % object->count());
                    if (key.has_value() && oo::str::hasPrefix(*key, "[") && oo::str::hasSuffix(*key, "]"))
                        key = result;
                } else {
                    if (object != nullptr && object->isString())
                        result = *object->getIf<std::string>();
                    else
                        result = std::nullopt;
                }
                if (!result.has_value() || !oo::str::hasPrefix(*result, "[") || !oo::str::hasSuffix(*result, "]"))
                    break;
                if (seen.contains(*result)) {
                    OO_LOG_ERR("sound.customSounds.recursion", "recursion in customsounds.plist for '{}' (at '{}'), no sound will be played.", key.value_or("(null)"), *result);
                    result = std::nullopt;
                    break;
                }
            }
        }

        if (!result.has_value())
            result = std::string("__oolite-no-sound");
        [[OOCacheManager sharedCache] cxx_setObject:oo::NSStringFrom(*result) forKey:key.value_or(std::string()) inCache:"resolved custom sounds"];
    }

    if (*result == "__oolite-no-sound") {
        OO_LOG("sound.customSounds", "Could not resolve sound name in customsounds.plist for '{}', no sound will be played.", key.value_or("(null)"));
        result = std::nullopt;
    }
    return result;
}

- (oo::PList)cxx_screenTextureDescriptorForKey:(const std::string&)key
{
    const oo::PList* entry = screenBackgrounds.find(key);
    oo::PList value = (entry != nullptr) ? *entry : oo::PList();
    while (value.isArray()) {
        const oo::PList* chosen = value.at(Ranrot() % value.count());
        oo::PList next = (chosen != nullptr) ? *chosen : oo::PList();
        value = std::move(next);
    }

    if (value.isString())
        value = oo::PList(oo::PList::Dict { { "name", value } });
    else if (!value.isDict())
        value = oo::PList();

    // Start loading the texture, and return nil if it doesn't exist.
    if (![[self gui] cxx_preloadGUITexture:value])
        value = oo::PList();

    return value;
}

// Unloaded backgrounds (null) stay unloaded, as messaging nil changed nothing.
- (void)cxx_setScreenTextureDescriptorForKey:(const std::string&)key descriptor:(const oo::PList&)desc
{
    oo::PList::Dict* backgrounds = screenBackgrounds.getIf<oo::PList::Dict>();
    if (backgrounds == nullptr)
        return;
    if (desc.isNull()) {
        backgrounds->erase(key);
    } else {
        (*backgrounds)[key] = desc;
    }
}

- (void)clearPreviousMessage
{
    currentMessage.reset();
}

- (void)setMessageGuiBackgroundColor:(OOColor*)some_color
{
    [message_gui setBackgroundColor:some_color];
}

- (void)cxx_displayMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    if (!SameMessage(currentMessage, text) || universal_time >= messageRepeatTime) {
        currentMessage = text;
        messageRepeatTime = universal_time + 6.0;
        [self showGUIMessage:text withScroll:YES andColor:[message_gui textColor] overDuration:count];
    }
}

- (void)cxx_displayCountdownMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    if (!SameMessage(currentMessage, text) && universal_time >= countdown_messageRepeatTime) {
        currentMessage = text;
        countdown_messageRepeatTime = universal_time + count;
        [self showGUIMessage:text withScroll:NO andColor:[message_gui textColor] overDuration:count];
    }
}

// The deferred call's argument is the dictionary -addDelayedMessage: reads (a missing text leaves
// the message out: the delayed call then shows nothing; setting a nil text raised).
- (void)cxx_addDelayedMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count afterDelay:(double)delay
{
    oo::PList::Dict msgDict;
    if (text.has_value())
        msgDict["message"] = oo::PList(*text);
    msgDict["duration"] = oo::PList(count);
    OOScheduleDeferredCall(self, @selector(addDelayedMessage:), oo::ObjectFromPList(oo::PList(std::move(msgDict))), delay);
}

- (void)addDelayedMessage:(id)textdict // called by name (ADR-0043 item 21): the deferred call above
{
    std::optional<std::string> msg;
    OOTimeDelta msg_duration;
    const oo::PList message = oo::PListFrom(textdict);

    msg = OptionalStringIn(message, "message");
    if (!msg.has_value())
        return;
    msg_duration = message.get<oo::NonNegative<double>>("duration", 3.0);

    [self cxx_addMessage:msg forCount:msg_duration];
}

- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    [self cxx_addMessage:text forCount:count forceDisplay:NO];
}

- (void)speakWithSubstitutions:(const std::optional<std::string>&)text
{
#if OOLITE_SPEECH_SYNTH
    // speech synthesis

    PlayerEntity* player = PLAYER;
    if ([player isSpeechOn] > OOSPEECHSETTINGS_OFF) {
        std::optional<std::string> systemSaid;
        std::optional<std::string> h_systemSaid;

        const std::optional<std::string> systemName = [self cxx_getSystemName:systemID];

        systemSaid = systemName;

        const std::optional<std::string> h_systemName = [self cxx_getSystemName:[player targetSystemID]];
        h_systemSaid = h_systemName;

        std::optional<std::string> spokenText = text;
        if (!speechArray.isNull()) {
            const oo::PList::Array* pairs = speechArray.getIf<oo::PList::Array>();
            if (pairs != nullptr)
                for (const oo::PList& thePair : *pairs) {
                    const std::optional<std::string> original_phrase = OptionalStringAt(thePair, 0);

                    NSUInteger replacementIndex;
#if OOLITE_MAC_COCOA_UI
                    replacementIndex = 1;
#elif OOLITE_ESPEAK
                    replacementIndex = thePair.count() > 2 ? 2 : 1;
#endif

                    const std::optional<std::string> replacement_phrase = OptionalStringAt(thePair, replacementIndex);
                    // An empty or missing phrase replaced nothing (a missing replacement or a nil text stayed nil).
                    if (replacement_phrase != "_" && spokenText.has_value() && original_phrase.has_value() && !original_phrase->empty() && replacement_phrase.has_value()) {
                        spokenText = oo::str::replaceOccurrences(*spokenText, *original_phrase, *replacement_phrase);
                    }
                }
            if (spokenText.has_value() && systemName.has_value() && !systemName->empty())
                spokenText = oo::str::replaceOccurrences(*spokenText, *systemName, systemSaid.value_or(std::string()));
            if (spokenText.has_value() && h_systemName.has_value() && !h_systemName->empty())
                spokenText = oo::str::replaceOccurrences(*spokenText, *h_systemName, h_systemSaid.value_or(std::string()));
        }
        [self stopSpeaking];
        if (spokenText.has_value())
            [self cxx_startSpeakingString:*spokenText]; // a nil text said nothing
    }
#endif // OOLITE_SPEECH_SYNTH
}

- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count forceDisplay:(BOOL)forceDisplay
{
    if (!SameMessage(currentMessage, text) || forceDisplay || universal_time >= messageRepeatTime) {
        if ([PLAYER isSpeechOn] == OOSPEECHSETTINGS_ALL) {
            [self speakWithSubstitutions:text];
        }

        [self showGUIMessage:text withScroll:YES andColor:[message_gui textColor] overDuration:count];

        [PLAYER doScriptEvent:OOJSID("consoleMessageReceived") withArgument:oo::NSStringOrNil(text)];

        currentMessage = text;
        messageRepeatTime = universal_time + 6.0;
    }
}

- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    [self cxx_addCommsMessage:text forCount:count andShowComms:_autoCommLog logOnly:NO];
}

- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly
{
    if ([PLAYER showDemoShips])
        return;

    const std::optional<std::string> expandedMessage = oo::OptionalString(OOExpand(oo::NSStringOrNil(text)));

    if (!SameMessage(currentMessage, expandedMessage) || universal_time >= messageRepeatTime) {
        PlayerEntity* player = PLAYER;

        if (!logOnly) {
            if ([player isSpeechOn] >= OOSPEECHSETTINGS_COMMS) {
                // EMMSTRAN: should say "Incoming message from ..." when prefixed with sender name.
                const std::string format = ExpandKey("speech-synthesis-incoming-message-@");
                [self speakWithSubstitutions:oo::str::formatRuntime(format, { expandedMessage.has_value() ? oo::str::FormatArg(*expandedMessage) : oo::str::FormatArg::null() })];
            }

            [self showGUIMessage:expandedMessage withScroll:YES andColor:[message_gui textCommsColor] overDuration:count];

            currentMessage = expandedMessage;
            messageRepeatTime = universal_time + 6.0;
        }

        // the printed lines go to the player's (unmigrated) comm log as they went before
        std::vector<std::string> printedLines;
        [comm_log_gui cxx_printLongText:expandedMessage align:GUI_ALIGN_LEFT color:nil fadeTime:0.0 key:std::nullopt addToArray:&printedLines];
        for (const std::string& line : printedLines)
            [[player commLog] addObject:oo::NSStringFrom(line)];

        if (showComms)
            [self showCommsLog:6.0];
    }
}

- (void)showCommsLog:(OOTimeDelta)how_long
{
    [comm_log_gui setAlpha:1.0];
    if (![self permanentCommLog])
        [comm_log_gui fadeOutFromTime:[self getTime] overDuration:how_long];
}

- (void)showGUIMessage:(const std::optional<std::string>&)text withScroll:(BOOL)scroll andColor:(OOColor*)selectedColor overDuration:(OOTimeDelta)how_long
{
    if (scroll) {
        [message_gui cxx_printLongText:text align:GUI_ALIGN_CENTER color:selectedColor fadeTime:how_long key:std::nullopt addToArray:nullptr];
    } else {
        [message_gui cxx_printLineNoScroll:text align:GUI_ALIGN_CENTER color:selectedColor fadeTime:how_long key:std::nullopt addToArray:nullptr];
    }
    [message_gui setAlpha:1.0f];
}

- (void)repopulateSystem
{
    if (EXPECT_NOT([PLAYER status] == STATUS_START_GAME)) {
        return; // no need to be adding ships as this is not a "real" game
    }
    JSContext* context = OOJSAcquireContext();
    [PLAYER doWorldScriptEvent:(system_repopulator.has_value() ? cxx_OOJSIDFromString(*system_repopulator) : JS_ATOM_NULL) inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
    OOJSRelinquishContext(context);
    next_repopulation = SYSTEM_REPOPULATION_INTERVAL;
}

- (void)update:(OOTimeDelta)inDeltaT
{
    volatile OOTimeDelta delta_t = inDeltaT * [self timeAccelerationFactor];
    NSUInteger sessionID = _sessionID;
    OO_LOG("universe.profile.update", "{}", "Begin update");
    if (EXPECT(!no_update)) {
        next_repopulation -= delta_t;
        if (next_repopulation < 0) {
            [self repopulateSystem];
        }

        unsigned i, ent_count = n_entities;
        std::vector<Entity*> my_entities(ent_count);

        [self verifyEntitySessionIDs];

        // use a retained copy so this can't be changed under us.
        for (i = 0; i < ent_count; i++) {
            my_entities[i] = [sortedEntities[i] retain]; // explicitly retain each one
        }

        const char* volatile update_stage = "initialisation";
#ifndef NDEBUG
        id volatile update_stage_param = nil;
#endif

        @try {
            PlayerEntity* player = PLAYER;

            skyClearColor[0] = 0.0;
            skyClearColor[1] = 0.0;
            skyClearColor[2] = 0.0;
            skyClearColor[3] = 0.0;

            time_delta = delta_t;
            universal_time += delta_t;

            if (EXPECT_NOT([player showDemoShips] && [player guiScreen] == GUI_SCREEN_SHIPLIBRARY)) {
                update_stage = "demo management";

                if (universal_time >= demo_stage_time) {
                    if (ent_count > 1) {
                        Vector vel;
                        Quaternion q2 = kIdentityQuaternion;

                        quaternion_rotate_about_y(&q2, M_PI);

                        switch (demo_stage) {
                        case DEMO_FLY_IN:
                            [demo_ship setPosition:[demo_ship destination]]; // ideal position
                            demo_stage = DEMO_SHOW_THING;
                            demo_stage_time = universal_time + 300.0;
                            break;
                        case DEMO_SHOW_THING:
                            vel = make_vector(0, 0, DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius * 6.0);
                            [demo_ship setVelocity:vel];
                            demo_stage = DEMO_FLY_OUT;
                            demo_stage_time = universal_time + 0.25;
                            break;
                        case DEMO_FLY_OUT:
                            // change the demo_ship here
                            [self removeEntity:demo_ship];
                            demo_ship = nil;

                            demo_ship_subindex = (demo_ship_subindex + 1) % DemoClassCount(demo_ships, demo_ship_index);
                            demo_ship = [self cxx_newShipWithName:OptionalStringIn([self demoShipData], kOODemoShipKey).value_or(std::string()) usePlayerProxy:NO]; // a missing key asked for "", as nil did

                            if (demo_ship != nil) {
                                [demo_ship removeEquipmentItem:@"EQ_SHIELD_BOOSTER"];
                                [demo_ship removeEquipmentItem:@"EQ_SHIELD_ENHANCER"];

                                [demo_ship switchAITo:@"nullAI.plist"];
                                [demo_ship setOrientation:q2];
                                [demo_ship setScanClass:CLASS_NO_DRAW];
                                [demo_ship setStatus:STATUS_COCKPIT_DISPLAY]; // prevents it getting escorts on addition
                                [demo_ship setDemoShip:1.0f];
                                [demo_ship setDemoStartTime:universal_time];
                                if ([self addEntity:demo_ship]) {
                                    [demo_ship release]; // We now own a reference through the entity list.
                                    [demo_ship setStatus:STATUS_COCKPIT_DISPLAY];
                                    demo_start_z = DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius;
                                    [demo_ship setPositionX:0.0f y:0.0f z:demo_start_z];
                                    [demo_ship setDestination:make_HPvector(0.0f, 0.0f, demo_start_z * 0.01f)]; // ideal position
                                    [demo_ship setVelocity:kZeroVector];
                                    [demo_ship setScanClass:CLASS_NO_DRAW];
                                    //										[gui setText:shipName != nil ? shipName : [demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];

                                    [self setLibraryTextForDemoShip];

                                    demo_stage = DEMO_FLY_IN;
                                    demo_start_time = universal_time;
                                    demo_stage_time = demo_start_time + DEMO2_FLY_IN_STAGE_TIME;
                                } else {
                                    demo_ship = nil;
                                }
                            }
                            break;
                        }
                    }
                } else if (demo_stage == DEMO_FLY_IN) {
                    GLfloat delta = (universal_time - demo_start_time) / DEMO2_FLY_IN_STAGE_TIME;
                    [demo_ship setPositionX:0.0f y:[demo_ship destination].y * delta z:demo_start_z + ([demo_ship destination].z - demo_start_z) * delta];
                }
            }

            update_stage = "update:entity";
            std::vector<oo::ObjCRef<Entity*>> zombies; // each once, in the order found
            OO_LOG("universe.profile.update", "{}", const_cast<const char*>(update_stage));
            for (i = 0; i < ent_count; i++) {
                Entity* thing = my_entities[i];
#ifndef NDEBUG
                update_stage_param = thing;
                update_stage = "update:entity [%@]";
#endif
                // Game Over code depends on regular delta_t updates to the dead player entity. Ignore the player entity, even when dead.
                if (EXPECT_NOT([thing status] == STATUS_DEAD && std::find(entitiesDeadThisUpdate.begin(), entitiesDeadThisUpdate.end(), thing) == entitiesDeadThisUpdate.end() && ![thing isPlayer])) {
                    AddIfAbsent(zombies, thing);
                    continue;
                }

                [thing update:delta_t];
                if (EXPECT_NOT(sessionID != _sessionID)) {
                    // Game was reset (in player update); end this update: cycle.
                    break;
                }

#ifndef NDEBUG
                update_stage = "update:list maintenance [%@]";
#endif

                // maintain distance-from-player list
                GLfloat z_distance = thing->zero_distance;

                int index = thing->zero_index;
                while (index > 0 && z_distance < sortedEntities[index - 1]->zero_distance) {
                    sortedEntities[index] = sortedEntities[index - 1]; // bubble up the list, usually by just one position
                    sortedEntities[index - 1] = thing;
                    thing->zero_index = index - 1;
                    sortedEntities[index]->zero_index = index;
                    index--;
                }

                // update deterministic AI
                if ([thing isShip]) {
#ifndef NDEBUG
                    update_stage = "update:think [%@]";
#endif
                    AI* theShipsAI = [(ShipEntity*)thing getAI];
                    if (theShipsAI) {
                        double thinkTime = [theShipsAI nextThinkTime];
                        if ((universal_time > thinkTime) || (thinkTime == 0.0)) {
                            [theShipsAI setNextThinkTime:universal_time + [theShipsAI thinkTimeInterval]];
                            [theShipsAI think];
                        }
                    }
                }
            }
#ifndef NDEBUG
            update_stage_param = nil;
#endif

            if (!zombies.empty()) {
                update_stage = "shootin' zombies";
                Entity* zombie = nil;
                for (const oo::ObjCRef<Entity*>& entry : zombies) {
                    zombie = entry.get();
                    OO_LOG_ERR("universe.zombie", "Found dead entity {} in active entity list, removing. This is an internal error, please report it.", oo::DescriptionOf(zombie));
                    [self removeEntity:zombie];
                }
            }

            // Maintain x/y/z order lists
            update_stage = "updating linked lists";
            OO_LOG("universe.profile.update", "{}", const_cast<const char*>(update_stage));
            for (i = 0; i < ent_count; i++) {
                [my_entities[i] updateLinkedLists];
            }

            // detect collisions and light ships that can see the sun

            update_stage = "collision and shadow detection";
            OO_LOG("universe.profile.update", "{}", const_cast<const char*>(update_stage));
            [self filterSortedLists];
            [self findCollisionsAndShadows];

            // do any required check and maintenance of linked lists

            if (doLinkedListMaintenanceThisUpdate) {
                MaintainLinkedLists(self);
                doLinkedListMaintenanceThisUpdate = NO;
            }
        }
        @catch (OOException* exception) {
            if (strncmp([exception name], "Oolite", 6) == 0) {
                [self handleOoliteException:exception];
            } else {
                std::string stage = update_stage;
#ifndef NDEBUG
                if (update_stage_param != nil)
                    stage = oo::str::formatRuntime(stage, { oo::DescriptionOf(update_stage_param) });
#endif
                OO_LOG(cxx_kOOLogException, "***** Exception during [{}] in [Universe update:] : {} : {} *****", stage, [exception name], [exception reason]);
                @throw exception;
            }
        }
        @catch (OOFoundationException* exception) {
            if ([[exception name] hasPrefix:@"Oolite"]) {
                [self handleOoliteException:[OOException exceptionWithName:[[exception name] UTF8String] reason:[[exception reason] UTF8String]]];
            } else {
                std::string stage = update_stage;
#ifndef NDEBUG
                if (update_stage_param != nil)
                    stage = oo::str::formatRuntime(stage, { oo::DescriptionOf(update_stage_param) });
#endif
                OO_LOG(cxx_kOOLogException, "***** Exception during [{}] in [Universe update:] : {} : {} *****", stage, oo::DescriptionOf([exception name]), oo::DescriptionOf([exception reason]));
                @throw exception;
            }
        }

        // dispose of the non-mutable copy and everything it references neatly
        update_stage = "clean up";
        OO_LOG("universe.profile.update", "{}", const_cast<const char*>(update_stage));
        for (i = 0; i < ent_count; i++) {
            [my_entities[i] release]; // explicitly release each one
        }
        /* Garbage collection is going to result in a significant
         * pause when it happens. Doing it here is better than doing
         * it in the middle of the update when it might slow a
         * function into the timelimiter through no fault of its
         * own. JS_MaybeGC will only run a GC when it's
         * necessary. Merely checking is not significant in terms of
         * time. - CIM: 4/8/2013
         */
        update_stage = "JS Garbage Collection";
        OO_LOG("universe.profile.update", "{}", const_cast<const char*>(update_stage));
        [[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:NO];

    } else {
        // always perform player's dead updates: allows deferred JS resets.
        if ([PLAYER status] == STATUS_DEAD)
            [PLAYER update:delta_t];
    }

    // The dead stay alive until the autorelease pool drains, as the autoreleased set kept them.
    AutoreleaseAll(entitiesDeadThisUpdate);
    entitiesDeadThisUpdate.reserve(n_entities);

#if NEW_PLANETS
    [self prunePreloadingPlanetMaterials];
#endif

    OO_LOG("universe.profile.update", "{}", "Update complete");
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (double)timeAccelerationFactor
{
    return timeAccelerationFactor;
}

- (void)setTimeAccelerationFactor:(double)newTimeAccelerationFactor
{
    if (newTimeAccelerationFactor < TIME_ACCELERATION_FACTOR_MIN || newTimeAccelerationFactor > TIME_ACCELERATION_FACTOR_MAX) {
        newTimeAccelerationFactor = TIME_ACCELERATION_FACTOR_DEFAULT;
    }
    timeAccelerationFactor = newTimeAccelerationFactor;
}
#else
- (double)timeAccelerationFactor
{
    return 1.0;
}

- (void)setTimeAccelerationFactor:(double)newTimeAccelerationFactor
{
}
#endif

- (BOOL)ECMVisualFXEnabled
{
    return ECMVisualFXEnabled;
}

- (void)setECMVisualFXEnabled:(BOOL)isEnabled
{
    ECMVisualFXEnabled = isEnabled;
}

- (void)filterSortedLists
{
    /*
    Eric, 17-10-2010: raised the area to be not filtered out, from the combined collision size to 2x this size.
    This allows this filtered list to be used also for proximity_alert and not only for collisions. Before the
    proximity_alert could only trigger when already very near a collision. To late for ships to react.
    This does raise the number of entities in the collision chain with as result that the number of pairs to compair
    becomes significant larger. However, almost all of these extra pairs are dealt with by a simple distance check.
    I currently see no noticeable negative effect while playing, but this change might still give some trouble I missed.
    */
    Entity *e0, *next, *prev;
    OOHPScalar start, finish, next_start, next_finish, prev_start, prev_finish;

    // using the z_list - set or clear collisionTestFilter and clear collision_chain
    e0 = z_list_start;
    while (e0) {
        e0->collisionTestFilter = [e0 canCollide] ? 0 : 3;
        e0->collision_chain = nil;
        e0 = e0->z_next;
    }
    // done.

    /* We need to check the lists in both ascending and descending order
     * to catch some cases with interposition of entities. We set cTF =
     * 1 on the way up, and |= 2 on the way down. Therefore it's only 3
     * at the end of the list if it was caught both ways on the same
     * list. - CIM: 7/11/2012 */

    // start with the z_list
    e0 = z_list_start;
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.z - 2.0f * e0->collision_radius;
        finish = start + 4.0f * e0->collision_radius;
        next = e0->z_next;
        while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            next = next->z_next;
        if (next) {
            next_start = next->position.z - 2.0f * next->collision_radius;
            if (next_start < finish) {
                // e0 and next overlap
                while ((next) && (next_start < finish)) {
                    // skip forward to the next gap or the end of the list
                    next_finish = next_start + 4.0f * next->collision_radius;
                    if (next_finish > finish)
                        finish = next_finish;
                    e0 = next;
                    next = e0->z_next;
                    while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        next = next->z_next;
                    if (next)
                        next_start = next->position.z - 2.0f * next->collision_radius;
                }
                // now either (next == nil) or (next_start >= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter = 1;
            }
        } else // (next == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter = 1;
        }
        e0 = next;
    }
    // list filtered upwards, now filter downwards
    // e0 currently = end of z list
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.z + 2.0f * e0->collision_radius;
        finish = start - 4.0f * e0->collision_radius;
        prev = e0->z_previous;
        while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            prev = prev->z_previous;
        if (prev) {
            prev_start = prev->position.z + 2.0f * prev->collision_radius;
            if (prev_start > finish) {
                // e0 and next overlap
                while ((prev) && (prev_start > finish)) {
                    // skip forward to the next gap or the end of the list
                    prev_finish = prev_start - 4.0f * prev->collision_radius;
                    if (prev_finish < finish)
                        finish = prev_finish;
                    e0 = prev;
                    prev = e0->z_previous;
                    while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        prev = prev->z_previous;
                    if (prev)
                        prev_start = prev->position.z + 2.0f * prev->collision_radius;
                }
                // now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter |= 2;
            }
        } else // (prev == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter |= 2;
        }
        e0 = prev;
    }
    // done! list filtered

    // then with the y_list, z_list singletons now create more gaps..
    e0 = y_list_start;
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.y - 2.0f * e0->collision_radius;
        finish = start + 4.0f * e0->collision_radius;
        next = e0->y_next;
        while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            next = next->y_next;
        if (next) {

            next_start = next->position.y - 2.0f * next->collision_radius;
            if (next_start < finish) {
                // e0 and next overlap
                while ((next) && (next_start < finish)) {
                    // skip forward to the next gap or the end of the list
                    next_finish = next_start + 4.0f * next->collision_radius;
                    if (next_finish > finish)
                        finish = next_finish;
                    e0 = next;
                    next = e0->y_next;
                    while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        next = next->y_next;
                    if (next)
                        next_start = next->position.y - 2.0f * next->collision_radius;
                }
                // now either (next == nil) or (next_start >= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter = 1;
            }
        } else // (next == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter = 1;
        }
        e0 = next;
    }
    // list filtered upwards, now filter downwards
    // e0 currently = end of y list
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.y + 2.0f * e0->collision_radius;
        finish = start - 4.0f * e0->collision_radius;
        prev = e0->y_previous;
        while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            prev = prev->y_previous;
        if (prev) {
            prev_start = prev->position.y + 2.0f * prev->collision_radius;
            if (prev_start > finish) {
                // e0 and next overlap
                while ((prev) && (prev_start > finish)) {
                    // skip forward to the next gap or the end of the list
                    prev_finish = prev_start - 4.0f * prev->collision_radius;
                    if (prev_finish < finish)
                        finish = prev_finish;
                    e0 = prev;
                    prev = e0->y_previous;
                    while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        prev = prev->y_previous;
                    if (prev)
                        prev_start = prev->position.y + 2.0f * prev->collision_radius;
                }
                // now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter |= 2;
            }
        } else // (prev == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter |= 2;
        }
        e0 = prev;
    }
    // done! list filtered

    // finish with the x_list
    e0 = x_list_start;
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.x - 2.0f * e0->collision_radius;
        finish = start + 4.0f * e0->collision_radius;
        next = e0->x_next;
        while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            next = next->x_next;
        if (next) {
            next_start = next->position.x - 2.0f * next->collision_radius;
            if (next_start < finish) {
                // e0 and next overlap
                while ((next) && (next_start < finish)) {
                    // skip forward to the next gap or the end of the list
                    next_finish = next_start + 4.0f * next->collision_radius;
                    if (next_finish > finish)
                        finish = next_finish;
                    e0 = next;
                    next = e0->x_next;
                    while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        next = next->x_next;
                    if (next)
                        next_start = next->position.x - 2.0f * next->collision_radius;
                }
                // now either (next == nil) or (next_start >= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter = 1;
            }
        } else // (next == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter = 1;
        }
        e0 = next;
    }
    // list filtered upwards, now filter downwards
    // e0 currently = end of x list
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.x + 2.0f * e0->collision_radius;
        finish = start - 4.0f * e0->collision_radius;
        prev = e0->x_previous;
        while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            prev = prev->x_previous;
        if (prev) {
            prev_start = prev->position.x + 2.0f * prev->collision_radius;
            if (prev_start > finish) {
                // e0 and next overlap
                while ((prev) && (prev_start > finish)) {
                    // skip forward to the next gap or the end of the list
                    prev_finish = prev_start - 4.0f * prev->collision_radius;
                    if (prev_finish < finish)
                        finish = prev_finish;
                    e0 = prev;
                    prev = e0->x_previous;
                    while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        prev = prev->x_previous;
                    if (prev)
                        prev_start = prev->position.x + 2.0f * prev->collision_radius;
                }
                // now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter |= 2;
            }
        } else // (prev == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter |= 2;
        }
        e0 = prev;
    }
    // done! list filtered

    // repeat the y_list - so gaps from the x_list influence singletons
    e0 = y_list_start;
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.y - 2.0f * e0->collision_radius;
        finish = start + 4.0f * e0->collision_radius;
        next = e0->y_next;
        while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            next = next->y_next;
        if (next) {
            next_start = next->position.y - 2.0f * next->collision_radius;
            if (next_start < finish) {
                // e0 and next overlap
                while ((next) && (next_start < finish)) {
                    // skip forward to the next gap or the end of the list
                    next_finish = next_start + 4.0f * next->collision_radius;
                    if (next_finish > finish)
                        finish = next_finish;
                    e0 = next;
                    next = e0->y_next;
                    while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        next = next->y_next;
                    if (next)
                        next_start = next->position.y - 2.0f * next->collision_radius;
                }
                // now either (next == nil) or (next_start >= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter = 1;
            }
        } else // (next == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter = 1;
        }
        e0 = next;
    }
    // e0 currently = end of y list
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.y + 2.0f * e0->collision_radius;
        finish = start - 4.0f * e0->collision_radius;
        prev = e0->y_previous;
        while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            prev = prev->y_previous;
        if (prev) {
            prev_start = prev->position.y + 2.0f * prev->collision_radius;
            if (prev_start > finish) {
                // e0 and next overlap
                while ((prev) && (prev_start > finish)) {
                    // skip forward to the next gap or the end of the list
                    prev_finish = prev_start - 4.0f * prev->collision_radius;
                    if (prev_finish < finish)
                        finish = prev_finish;
                    e0 = prev;
                    prev = e0->y_previous;
                    while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        prev = prev->y_previous;
                    if (prev)
                        prev_start = prev->position.y + 2.0f * prev->collision_radius;
                }
                // now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
            } else {
                // e0 is a singleton
                e0->collisionTestFilter |= 2;
            }
        } else // (prev == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter |= 2;
        }
        e0 = prev;
    }
    // done! list filtered

    // finally, repeat the z_list - this time building collision chains...
    e0 = z_list_start;
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.z - 2.0f * e0->collision_radius;
        finish = start + 4.0f * e0->collision_radius;
        next = e0->z_next;
        while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            next = next->z_next;
        if (next) {
            next_start = next->position.z - 2.0f * next->collision_radius;
            if (next_start < finish) {
                // e0 and next overlap
                while ((next) && (next_start < finish)) {
                    // chain e0 to next in collision
                    e0->collision_chain = next;
                    // skip forward to the next gap or the end of the list
                    next_finish = next_start + 4.0f * next->collision_radius;
                    if (next_finish > finish)
                        finish = next_finish;
                    e0 = next;
                    next = e0->z_next;
                    while ((next) && (next->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        next = next->z_next;
                    if (next)
                        next_start = next->position.z - 2.0f * next->collision_radius;
                }
                // now either (next == nil) or (next_start >= finish)-which would imply a gap!
                e0->collision_chain = nil; // end the collision chain
            } else {
                // e0 is a singleton
                e0->collisionTestFilter = 1;
            }
        } else // (next == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter = 1;
        }
        e0 = next;
    }
    // e0 currently = end of z list
    while (e0) {
        // here we are either at the start of the list or just past a gap
        start = e0->position.z + 2.0f * e0->collision_radius;
        finish = start - 4.0f * e0->collision_radius;
        prev = e0->z_previous;
        while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated from the list of possible colliders - so skip it
            prev = prev->z_previous;
        if (prev) {
            prev_start = prev->position.z + 2.0f * prev->collision_radius;
            if (prev_start > finish) {
                // e0 and next overlap
                while ((prev) && (prev_start > finish)) {
                    // e0 probably already in collision chain at this point, but if it
                    // isn't we have to insert it
                    if (prev->collision_chain != e0) {
                        if (prev->collision_chain == nil) {
                            // easy, just add it onto the start of the chain
                            prev->collision_chain = e0;
                        } else {
                            /* not nil and not e0 shouldn't be possible, I think.
                             * if it is, that implies that e0->collision_chain is nil, though
                             * so: */
                            if (e0->collision_chain == nil) {
                                e0->collision_chain = prev->collision_chain;
                                prev->collision_chain = e0;
                            } else {
                                /* This shouldn't happen... If it does, we accept
                                 * missing collision checks and move on */
                                OO_LOG("general.error.inconsistentState", "Unexpected state in collision chain builder prev={}, prev->c={}, e0={}, e0->c={}", oo::DescriptionOf(prev), oo::DescriptionOf(prev->collision_chain), oo::DescriptionOf(e0), oo::DescriptionOf(e0->collision_chain));
                            }
                        }
                    }
                    // skip forward to the next gap or the end of the list
                    prev_finish = prev_start - 4.0f * prev->collision_radius;
                    if (prev_finish < finish)
                        finish = prev_finish;
                    e0 = prev;
                    prev = e0->z_previous;
                    while ((prev) && (prev->collisionTestFilter == 3)) // next has been eliminated - so skip it
                        prev = prev->z_previous;
                    if (prev)
                        prev_start = prev->position.z + 2.0f * prev->collision_radius;
                }
                // now either (prev == nil) or (prev_start <= finish)-which would imply a gap!

                // all the collision chains are already terminated somewhere
                // at this point so no need to set e0->collision_chain = nil
            } else {
                // e0 is a singleton
                e0->collisionTestFilter |= 2;
            }
        } else // (prev == nil)
        {
            // at the end of the list so e0 is a singleton
            e0->collisionTestFilter |= 2;
        }
        e0 = prev;
    }
    // done! list filtered
}

- (void)setGalaxyTo:(OOGalaxyID)g
{
    [self setGalaxyTo:g andReinit:NO];
}

- (void)setGalaxyTo:(OOGalaxyID)g andReinit:(BOOL)forced
{
    int i;

    if (galaxyID != g || forced) {
        galaxyID = g;

        // systems
        @autoreleasepool {
            for (i = 0; i < 256; i++) {
                system_names[i] = SystemPropertyString([systemManager cxx_getProperty:"name" forSystem:i inGalaxy:g]);
            }
        }
    }
}

- (void)setSystemTo:(OOSystemID)s
{
    oo::PList systemData;
    PlayerEntity* player = PLAYER;
    OOEconomyID economy;
    std::optional<std::string> scriptName;

    [self setGalaxyTo:[player galaxyNumber]];

    systemID = s;
    targetSystemID = s;

    systemData = [self cxx_generateSystemData:targetSystemID];
    economy = systemData.get<unsigned char>(oo::StdString(KEY_ECONOMY));
    scriptName = OptionalStringIn(systemData, "market_script");

    DESTROY(commodityMarket);
    // OOCommodities is not migrated yet: the script name goes as the string (or nil) it read before.
    commodityMarket = [[commodities generateMarketForSystemWithEconomy:economy andScript:oo::NSStringOrNil(scriptName)] retain];
}

- (OOSystemID)currentSystemID
{
    return systemID;
}

namespace {

// Makes each assignment of a Universe's _descriptions distinguishable (see -cxx_descriptionsGeneration).
unsigned sDescriptionsGeneration = 0;

// +dictionaryWithContentsOfFile: of the dictionary class: the file's property list if it is a
// dictionary, else (missing, unreadable, unparsable, another kind) a null PList. As ResourceManager.mm.
oo::PList DictionaryWithContentsOfFile(const std::string& path)
{
    const auto data = oo::fs::readFile(oo::fs::pathFromUTF8(path));
    if (!data)
        return oo::PList();
    auto plist = oo::parsePropertyListData(data->stringView());
    if (!plist || !plist->isDict())
        return oo::PList();
    return std::move(*plist);
}

/*	A string element of an array, nullopt where oo_stringAtIndex: gave nil (past the end, or
        neither a string nor a number; a number reads as its -stringValue).
*/
std::optional<std::string> OptionalStringAt(const oo::PList& array, std::size_t index)
{
    const oo::PList* value = array.at(index);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return array.at<std::string>(index);
}

/*	A string from a configuration dictionary, nullopt where oo_stringForKey: gave nil (the key is
        absent, or its value is neither a string nor a number; a number reads as its -stringValue).
*/
std::optional<std::string> OptionalStringIn(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

/*	The object -objectForKey: gave for a configuration value (nil when absent), for callees that
        still take Objective-C objects (+[OOColor colorWithDescription:]).
*/
id ObjectForKeyIn(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return (value != nullptr) ? oo::ObjectFromPList(*value) : nil;
}

// get<Vector> / get<HPVector>: OOVectorFromObject / OOHPVectorFromObject (not migrated yet) of the
// value; the zero vector for a null configuration (messaging nil).
Vector VectorIn(const oo::PList& dict, std::string_view key, Vector fallback)
{
    if (dict.isNull())
        return kZeroVector;
    return OOVectorFromObject(ObjectForKeyIn(dict, key), fallback);
}

HPVector HPVectorIn(const oo::PList& dict, std::string_view key, HPVector fallback)
{
    if (dict.isNull())
        return kZeroHPVector;
    return OOHPVectorFromObject(ObjectForKeyIn(dict, key), fallback);
}

// What %@ printed for a string that may be nil.
std::string TextOrNull(const std::optional<std::string>& text)
{
    return text.has_value() ? *text : std::string("(null)");
}

// An equipment entry's extra-info dictionary: the dictionary, or nullptr where the old read gave nil.
const oo::PList* EquipmentExtraInfo(const oo::PList& item)
{
    return item.at<oo::PList::Dict>(EQUIPMENT_EXTRA_INFO_INDEX);
}

// -[nil oo_unsignedLongLongForKey:defaultValue:] was 0, not the fallback.
unsigned long long ExtraInfoValue(const oo::PList* extra, std::string_view key, unsigned long long fallback)
{
    return (extra != nullptr) ? extra->get<unsigned long long>(key, fallback) : 0;
}

// equipment.plist order: explicit sort_order, then tech level, then price (ties keep file order).
bool equipmentSort(const oo::PList& one, const oo::PList& two)
{
    unsigned long long comp1 = ExtraInfoValue(EquipmentExtraInfo(one), "sort_order", 1000);
    unsigned long long comp2 = ExtraInfoValue(EquipmentExtraInfo(two), "sort_order", 1000);
    if (comp1 != comp2)
        return comp1 < comp2;

    comp1 = one.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
    comp2 = two.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
    if (comp1 != comp2)
        return comp1 < comp2;

    comp1 = one.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
    comp2 = two.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
    return comp1 < comp2;
}

// As equipmentSort, but purchase_sort_order (falling back to sort_order) first.
bool equipmentSortOutfitting(const oo::PList& one, const oo::PList& two)
{
    const oo::PList* extra1 = EquipmentExtraInfo(one);
    const oo::PList* extra2 = EquipmentExtraInfo(two);
    unsigned long long comp1 = ExtraInfoValue(extra1, "purchase_sort_order", ExtraInfoValue(extra1, "sort_order", 1000));
    unsigned long long comp2 = ExtraInfoValue(extra2, "purchase_sort_order", ExtraInfoValue(extra2, "sort_order", 1000));
    if (comp1 != comp2)
        return comp1 < comp2;

    comp1 = one.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
    comp2 = two.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
    if (comp1 != comp2)
        return comp1 < comp2;

    comp1 = one.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
    comp2 = two.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
    return comp1 < comp2;
}

// A string field of equipment entry j (nullopt where the old nested read gave nil).
std::optional<std::string> EquipmentItemString(const oo::PList& equipment, std::size_t j, std::size_t index)
{
    const oo::PList* item = equipment.at<oo::PList::Array>(j);
    return (item != nullptr) ? OptionalStringAt(*item, index) : std::nullopt;
}

// The populator blocks' order: ascending priority (100 when absent).
bool populatorPrioritySort(const oo::PList& one, const oo::PList& two)
{
    int pri_one = one.get<int>("priority", 100);
    int pri_two = two.get<int>("priority", 100);
    return pri_one < pri_two;
}

/*	oo_fuzzyBooleanForKey:defaultValue: on a configuration: NO for a null one (messaging nil), else
        OOFuzzyBooleanFromObject (not migrated yet) of the value as the object it was (nil when absent),
        which draws the same random number it drew before.
*/
BOOL FuzzyBooleanIn(const oo::PList& dict, std::string_view key, float fallback)
{
    if (dict.isNull())
        return NO;
    const oo::PList* value = dict.find(key);
    return OOFuzzyBooleanFromObject((value != nullptr) ? oo::ObjectFromPList(*value) : nil, fallback);
}

/*	A system property the old code handed on as a string object (a system name, inhabitants): the
        string, nullopt where the property was absent (nil). Planetinfo names and inhabitants are
        strings; a number reads as its -stringValue.
*/
std::optional<std::string> SystemPropertyString(const oo::PList& property)
{
    if (const std::string* string = property.getIf<std::string>())
        return *string;
    if (property.isNumber())
        return oo::plist_get::numberStringValue(property);
    return std::nullopt;
}

} // namespace

- (const oo::PList*)cxx_descriptions
{
    if (_descriptions.isNull()) {
        // Load internal descriptions.plist for use in early init, OXP verifier etc.
        // It will be replaced by merged version later if running the game normally.
        _descriptions = DictionaryWithContentsOfFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(*[ResourceManager cxx_builtInPath], "Config"), "descriptions.plist"));
        _descriptionsGeneration = ++sDescriptionsGeneration;

        [self verifyDescriptions];
    }
    return &_descriptions;
}

- (unsigned)cxx_descriptionsGeneration
{
    return _descriptionsGeneration;
}

namespace {

void VerifyDesc(const std::string& key, const oo::PList& desc);

void VerifyDescString(const std::string& key, const std::string& desc)
{
    if (desc.find("%n") != std::string::npos) {
        OO_LOG("descriptions.verify.percentN", "***** FATAL: descriptions.plist entry \"{}\" contains the dangerous control sequence %n.", key);
        exit(EXIT_FAILURE);
    }
}

void VerifyDescArray(const std::string& key, const oo::PList& desc)
{
    for (const oo::PList& subDesc : *desc.getIf<oo::PList::Array>()) {
        VerifyDesc(key, subDesc);
    }
}

void VerifyDesc(const std::string& key, const oo::PList& desc)
{
    if (desc.isString()) {
        VerifyDescString(key, *desc.getIf<std::string>());
    } else if (desc.isArray()) {
        VerifyDescArray(key, desc);
    } else if (desc.isNumber()) {
        // No verification needed.
    } else {
        OO_LOG_ERR("descriptions.verify.badType", "***** FATAL: descriptions.plist entry for \"{}\" is neither a string nor an array.", key);
        exit(EXIT_FAILURE);
    }
}

} // namespace

- (void)verifyDescriptions
{
    /*
            Ensure that no descriptions.plist entries contain the %n format code,
            which can be used to smash the stack and potentially call arbitrary
            functions.

            %n is deliberately not supported in Foundation/CoreFoundation under
            Mac OS X, but unfortunately GNUstep implements it.
            -- Ahruman 2011-05-05
    */

    if (_descriptions.isNull()) {
        OO_LOG("descriptions.verify", "{}", "***** FATAL: Tried to verify descriptions, but descriptions was nil - unable to load any descriptions.plist file.");
        exit(EXIT_FAILURE);
    }
    // Byte order of the key (was hash order): it decides only which bad entry is reported first.
    if (const oo::PList::Dict* entries = _descriptions.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *entries) {
            VerifyDesc(key, value);
        }
    }
}

- (void)loadDescriptions
{
    _descriptions = [ResourceManager cxx_dictionaryFromFilesNamed:"descriptions.plist" inFolder:std::string("Config") andMerge:YES];
    _descriptionsGeneration = ++sDescriptionsGeneration;
    [self verifyDescriptions];
}

- (oo::PList)cxx_explosionSetting:(const std::string&)explosion
{
    const oo::PList* setting = explosionSettings.get<oo::PList::Dict>(explosion);
    return (setting != nullptr) ? *setting : oo::PList();
}

- (oo::PList)cxx_scenarios
{
    return _scenarios;
}

- (void)loadScenarios
{
    _scenarios = [ResourceManager cxx_arrayFromFilesNamed:"scenarios.plist" inFolder:std::string("Config") andMerge:YES];
}

- (oo::PList)cxx_characters
{
    return characters;
}

- (oo::PList)cxx_missiontext
{
    return missiontext;
}

- (std::optional<std::string>)cxx_descriptionForKey:(const std::string&)key
{
    return [self chooseStringForKey:key inDictionary:*[self cxx_descriptions]];
}

- (std::optional<std::string>)cxx_descriptionForArrayKey:(const std::string&)key index:(unsigned)index
{
    const oo::PList* array = [self cxx_descriptions]->get<oo::PList::Array>(key);
    if (array == nullptr || array->count() <= index)
        return std::nullopt; // Catches a missing array
    return OptionalStringAt(*array, index);
}

- (BOOL)descriptionBooleanForKey:(const std::string&)key
{
    return [self cxx_descriptions]->get<bool>(key);
}

- (OOSystemDescriptionManager*)systemManager
{
    return systemManager;
}

- (std::optional<std::string>)cxx_keyForPlanetOverridesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return oo::str::format("%d %d", g, s);
}

- (std::optional<std::string>)keyForInterstellarOverridesForSystems:(OOSystemID)s1 s2:(OOSystemID)s2 inGalaxy:(OOGalaxyID)g
{
    return oo::str::format("interstellar: %d %d %d", g, s1, s2);
}

- (oo::PList)cxx_generateSystemData:(OOSystemID)s
{
    return [self cxx_generateSystemData:s useCache:YES];
}

// cache isn't handled this way any more
- (oo::PList)cxx_generateSystemData:(OOSystemID)s useCache:(BOOL)useCache
{
    OOJS_PROFILE_ENTER

    // TODO: At the moment this method is only called for systems in the
    // same galaxy. At some point probably needs generalising to have a
    // galaxynumber parameter.
    const std::string systemKey = oo::str::format("%u %u", [PLAYER galaxyNumber], s);

    return [systemManager cxx_getPropertiesForSystemKey:systemKey];

    OOJS_PROFILE_EXIT
}

- (oo::PList)cxx_currentSystemData
{
    OOJS_PROFILE_ENTER

    if (![self inInterstellarSpace]) {
        return [self cxx_generateSystemData:systemID];
    } else {
        static oo::PList interstellarDict; // null until built
        if (interstellarDict.isNull()) {
            const std::string interstellarName = cxx_OOLookUpDescriptionPRIV("interstellar-space");
            const std::string notApplicable = cxx_OOLookUpDescriptionPRIV("not-applicable");
            // signed integers, as +numberWithInt: made them
            const oo::PList minusOne = oo::PList::signedInteger(-1);
            const oo::PList zero = oo::PList::signedInteger(0);
            interstellarDict = oo::PList(oo::PList::Dict {
                { oo::StdString(KEY_NAME), oo::PList(interstellarName) },
                { oo::StdString(KEY_GOVERNMENT), minusOne },
                { oo::StdString(KEY_ECONOMY), minusOne },
                { oo::StdString(KEY_TECHLEVEL), minusOne },
                { oo::StdString(KEY_POPULATION), zero },
                { oo::StdString(KEY_PRODUCTIVITY), zero },
                { oo::StdString(KEY_RADIUS), zero },
                { oo::StdString(KEY_INHABITANTS), oo::PList(notApplicable) },
                { oo::StdString(KEY_DESCRIPTION), oo::PList(notApplicable) } });
        }

        return interstellarDict;
    }

    OOJS_PROFILE_EXIT
}

- (BOOL)inInterstellarSpace
{
    return [self sun] == nil;
}

// layer 2
// used by legacy script engine and sun going nova
- (void)cxx_setSystemDataKey:(const std::string&)key value:(id)object fromManifest:(const std::optional<std::string>&)manifest
{
    [self cxx_setSystemDataForGalaxy:galaxyID planet:systemID key:key value:object fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
}

- (void)cxx_setSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key value:(id)object fromManifest:(const std::optional<std::string>&)manifest forLayer:(OOSystemLayer)layer
{
    static BOOL sysdataLocked = NO;
    if (sysdataLocked) {
        OO_LOG_ERR("script.error", "{}", "System properties cannot be set during 'systemInformationChanged' events to avoid infinite loops.");
        return;
    }

    BOOL sameGalaxy = (gnum == [PLAYER currentGalaxyID]);
    BOOL sameSystem = (sameGalaxy && pnum == [self currentSystemID]);

    // trying to set  unsettable properties?
    if (key == oo::StdString(KEY_RADIUS) && sameGalaxy && sameSystem) // buggy if we allow this key to be set while in the system
    {
        OO_LOG_ERR("script.error", "System property '{}' cannot be set while in the system.", key);
        return;
    }

    if (key == "coordinates") // setting this in game would be very confusing
    {
        OO_LOG_ERR("script.error", "System property '{}' cannot be set.", key);
        return;
    }

    const std::string overrideKey = oo::str::format("%u %u", gnum, pnum);
    oo::PList sysInfo;

    // short range map fix
    [gui refreshStarChart];

    if (object != nil) {
        // long range map fixes
        if (key == oo::StdString(KEY_NAME)) {
            // -lowercaseString / -capitalizedString of the name (a script string)
            const std::string name = oo::str::capitalized(oo::str::lowercase(oo::StdString(object)));
            object = oo::NSStringFrom(name);
            if (sameGalaxy) {
                system_names[pnum] = name;
            }
        } else if (key == "sun_radius") {
            if ([object doubleValue] < 1000.0 || [object doubleValue] > 10000000.0) {
                object = oo::NSStringFrom([object doubleValue] < 1000.0 ? "1000.0" : "10000000.0"); // works!
            }
        } else if (oo::str::hasPrefix(key, "corona_")) {
            object = oo::NSStringFrom(oo::str::format("%f", OOClamp_0_1_f([object floatValue])));
        }
    }

    // the value read once (nil -> a null PList, which removes the property as nil did)
    [systemManager cxx_setProperty:key forSystemKey:overrideKey andLayer:layer toValue:oo::PListFrom(object) fromManifest:manifest];

    // Apply changes that can be effective immediately, issue warning if they can't be changed just now
    if (sameSystem) {
        sysInfo = [systemManager cxx_getPropertiesForCurrentSystem];

        OOSunEntity* the_sun = [self sun];
        /* KEY_ECONOMY used to be here, but resetting the main station
         * market while the player is in the system is likely to cause
         * more trouble than it's worth. Let them leave and come back
         * - CIM */
        if (key == oo::StdString(KEY_TECHLEVEL)) {
            if ([self station]) {
                [[self station] setEquivalentTechLevel:[object intValue]];
                [[self station] setLocalShipyard:[self shipsForSaleForSystem:systemID
                                                                      withTL:[object intValue]
                                                                      atTime:[PLAYER clockTime]]];
            }
        } else if (key == "sun_color" || key == "star_count_multiplier" || key == "nebula_count_multiplier" || oo::str::hasPrefix(key, "sky_")) {
            SkyEntity* the_sky = nil;
            int i;

            for (i = n_entities - 1; i > 0; i--)
                if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[SkyEntity class]]))
                    the_sky = (SkyEntity*)sortedEntities[i];

            if (the_sky != nil) {
                [the_sky changeProperty:key withDictionary:sysInfo];

                if (key == "sun_color") {
                    OOColor* color = [the_sky skyColor];
                    if (the_sun != nil) {
                        [the_sun setSunColor:color];
                        [the_sun getDiffuseComponents:sun_diffuse];
                        [the_sun getSpecularComponents:sun_specular];
                    }
                    for (i = n_entities - 1; i > 0; i--)
                        if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[DustEntity class]]))
                            [(DustEntity*)sortedEntities[i] setDustColor:[color blendedColorWithFraction:0.5 ofColor:[OOColor whiteColor]]];
                }
            }
        } else if (the_sun != nil && (oo::str::hasPrefix(key, "sun_") || oo::str::hasPrefix(key, "corona_"))) {
            [the_sun changeSunProperty:key withDictionary:sysInfo];
        } else if (key == "texture") {
            [[self planet] setUpPlanetFromTexture:oo::OptionalString(object)];
        } else if (key == "texture_hsb_color") {
            [[self planet] setUpPlanetFromTexture:[[self planet] textureFileName]];
        } else if (key == "air_color") {
            [[self planet] setAirColor:[OOColor brightColorWithDescription:object]];
        } else if (key == "illumination_color") {
            [[self planet] setIlluminationColor:[OOColor colorWithDescription:object]];
        } else if (key == "air_color_mix_ratio") {
            [[self planet] setAirColorMixRatio:sysInfo.get<float>(key)];
        }
    }

    sysdataLocked = YES;
    // the same arguments (a nil value ends the list, as it did)
    [PLAYER doScriptEvent:OOJSID("systemInformationChanged") withArguments:oo::ObjectFromPList(oo::PList(oo::PList::Array { oo::PList::signedInteger(gnum), oo::PList::signedInteger(pnum), oo::PList(key), oo::PListObject(object) }))];
    sysdataLocked = NO;
}

- (oo::PList)generateSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum
{
    const std::optional<std::string> systemKey = [self cxx_keyForPlanetOverridesForSystem:pnum inGalaxy:gnum];
    return [systemManager cxx_getPropertiesForSystemKey:*systemKey];
}

// Byte order of the key (was the dictionary's -allKeys, hash order).
- (std::vector<std::string>)cxx_systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum
{
    std::vector<std::string> keys;
    const oo::PList systemData = [self generateSystemDataForGalaxy:gnum planet:pnum];
    if (const oo::PList::Dict* entries = systemData.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *entries)
            keys.push_back(key);
    }
    return keys;
}

/* Only called from OOJSSystemInfo. */
- (id)cxx_systemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key
{
    return oo::ObjectFromPList([systemManager cxx_getProperty:key forSystem:pnum inGalaxy:gnum]);
}

- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys
{
    return [self cxx_getSystemName:sys forGalaxy:galaxyID];
}

- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gnum
{
    return SystemPropertyString([systemManager cxx_getProperty:"name" forSystem:sys inGalaxy:gnum]);
}

- (OOGovernmentID)getSystemGovernment:(OOSystemID)sys
{
    return [[systemManager getProperty:@"government" forSystem:sys inGalaxy:galaxyID] unsignedCharValue];
}

- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys
{
    return [self cxx_getSystemInhabitants:sys plural:YES];
}

- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys plural:(BOOL)plural
{
    std::optional<std::string> ret;
    if (!plural) {
        ret = SystemPropertyString([systemManager cxx_getProperty:oo::StdString(KEY_INHABITANT) forSystem:sys inGalaxy:galaxyID]);
    }
    if (ret.has_value()) // the singular form might be absent.
    {
        return ret;
    } else {
        return SystemPropertyString([systemManager cxx_getProperty:oo::StdString(KEY_INHABITANTS) forSystem:sys inGalaxy:galaxyID]);
    }
}

- (NSPoint)coordinatesForSystem:(OOSystemID)s
{
    return [systemManager getCoordinatesForSystem:s inGalaxy:galaxyID];
}

- (OOSystemID)cxx_findSystemFromName:(const std::string&)sysName
{
    const std::string match = oo::str::lowercase(sysName);
    int i;
    for (i = 0; i < 256; i++) {
        // a missing name matched nothing
        if (system_names[i].has_value() && oo::str::lowercase(*system_names[i]) == match) {
            return i;
        }
    }
    return -1; // no match found!
}

- (OOSystemID)findSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g
{
    OO_LOG("deprecated.function", "{}", "findSystemAtCoords");
    return [self findSystemNumberAtCoords:coords withGalaxy:g includingHidden:YES];
}

- (oo::PList)cxx_nearbyDestinationsWithinRange:(double)range
{
    oo::PList::Array result;

    range = OOClamp_0_max_d(range, MAX_JUMP_RANGE); // limit to systems within 7LY
    NSPoint here = [PLAYER galaxy_coordinates];

    for (unsigned short i = 0; i < 256; i++) {
        NSPoint there = [self coordinatesForSystem:i];
        double dist = distanceBetweenPlanetPositions(here.x, here.y, there.x, there.y);
        if (dist <= range && (i != systemID || [self inInterstellarSpace])) // if we are in interstellar space, it's OK to include the system we (mis)jumped from
        {
            // the number kinds it held: a double, a signed integer
            result.push_back(oo::PList(oo::PList::Dict {
                { "distance", oo::PList(dist) },
                { "sysID", oo::PList::signedInteger(i) },
                { "nova", oo::PList([self cxx_generateSystemData:i].get<std::string>("sun_gone_nova", "0")) } }));
        }
    }

    return oo::PList(std::move(result));
}

- (OOSystemID)findNeighbouringSystemToCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g
{

    double distance;
    int n, i, j;
    double min_dist = 10000.0;

    // make list of connected systems
    BOOL connected[256];
    for (i = 0; i < 256; i++)
        connected[i] = NO;
    connected[0] = YES; // system zero is always connected (true for galaxies 0..7)
    for (n = 0; n < 3; n++) // repeat three times for surety
    {
        for (i = 0; i < 256; i++) // flood fill out from system zero
        {
            NSPoint ipos = [systemManager getCoordinatesForSystem:i inGalaxy:g];
            for (j = 0; j < 256; j++) {
                NSPoint jpos = [systemManager getCoordinatesForSystem:j inGalaxy:g];
                double dist = distanceBetweenPlanetPositions(ipos.x, ipos.y, jpos.x, jpos.y);
                if (dist <= MAX_JUMP_RANGE) {
                    connected[j] |= connected[i];
                    connected[i] |= connected[j];
                }
            }
        }
    }
    OOSystemID system = 0;
    for (i = 0; i < 256; i++) {
        NSPoint ipos = [systemManager getCoordinatesForSystem:i inGalaxy:g];
        distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, ipos.x, ipos.y);
        if ((connected[i]) && (distance < min_dist) && (distance != 0.0)) {
            min_dist = distance;
            system = i;
        }
    }

    return system;
}

/* This differs from the above function in that it can return a system
 * exactly at the specified coordinates */
- (OOSystemID)findConnectedSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g
{

    double distance;
    int n, i, j;
    double min_dist = 10000.0;

    // make list of connected systems
    BOOL connected[256];
    for (i = 0; i < 256; i++)
        connected[i] = NO;
    connected[0] = YES; // system zero is always connected (true for galaxies 0..7)
    for (n = 0; n < 3; n++) // repeat three times for surety
    {
        for (i = 0; i < 256; i++) // flood fill out from system zero
        {
            NSPoint ipos = [systemManager getCoordinatesForSystem:i inGalaxy:g];
            for (j = 0; j < 256; j++) {
                NSPoint jpos = [systemManager getCoordinatesForSystem:j inGalaxy:g];
                double dist = distanceBetweenPlanetPositions(ipos.x, ipos.y, jpos.x, jpos.y);
                if (dist <= MAX_JUMP_RANGE) {
                    connected[j] |= connected[i];
                    connected[i] |= connected[j];
                }
            }
        }
    }
    OOSystemID system = 0;
    for (i = 0; i < 256; i++) {
        NSPoint ipos = [systemManager getCoordinatesForSystem:i inGalaxy:g];
        distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, ipos.x, ipos.y);
        if ((connected[i]) && (distance < min_dist)) {
            min_dist = distance;
            system = i;
        }
    }

    return system;
}

- (OOSystemID)findSystemNumberAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g includingHidden:(BOOL)hidden
{
    /*
            NOTE: this previously used NSNotFound as the default value, but
            returned an int, which would truncate on 64-bit systems. I assume
            no-one was using it in a context where the default value was returned.
            -- Ahruman 2012-08-25
    */
    OOSystemID system = kOOMinimumSystemID;
    unsigned distance, dx, dy;
    OOSystemID i;
    unsigned min_dist = 10000;

    for (i = 0; i < 256; i++) {
        if (!hidden) {
            const oo::PList systemInfo = [systemManager cxx_getPropertiesForSystem:i inGalaxy:g];
            NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
            if (concealment >= OO_SYSTEMCONCEALMENT_NOTHING) {
                // system is not known
                continue;
            }
        }
        NSPoint ipos = [systemManager getCoordinatesForSystem:i inGalaxy:g];
        dx = ABS(coords.x - ipos.x);
        dy = ABS(coords.y - ipos.y);

        if (dx > dy)
            distance = (dx + dx + dy) / 2;
        else
            distance = (dx + dy + dy) / 2;

        if (distance < min_dist) {
            min_dist = distance;
            system = i;
        }
        // with coincident systems choose only if ABOVE
        if ((distance == min_dist) && (coords.y > ipos.y)) {
            system = i;
        }
        // or if EQUAL but already selected
        else if ((distance == min_dist) && (coords.y == ipos.y) && (i == [PLAYER targetSystemID])) {
            system = i;
        }
    }
    return system;
}

- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix
{
    return [self cxx_findSystemCoordinatesWithPrefix:p_fix exactMatch:NO];
}

- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix exactMatch:(BOOL)exactMatch
{
    std::string system_name;
    NSPoint system_coords = NSMakePoint(-1.0, -1.0);
    int i;
    int result = -1;
    for (i = 0; i < 256; i++) {
        system_found[i] = NO;
        if (!system_names[i].has_value())
            continue; // a missing name matched nothing
        system_name = oo::str::lowercase(*system_names[i]);
        if ((exactMatch && system_name == p_fix) || (!exactMatch && oo::str::hasPrefix(system_name, p_fix))) {
            /* Only used in player-based search routines */
            const oo::PList systemInfo = [systemManager cxx_getPropertiesForSystem:i inGalaxy:galaxyID];
            NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
            if (concealment >= OO_SYSTEMCONCEALMENT_NONAME) {
                // system is not known
                continue;
            }

            system_found[i] = YES;
            if (result < 0) {
                system_coords = [systemManager getCoordinatesForSystem:i inGalaxy:galaxyID];
                result = i;
            }
        }
    }
    return system_coords;
}

- (BOOL*)systemsFound
{
    return (BOOL*)system_found;
}

- (std::optional<std::string>)cxx_systemNameIndex:(OOSystemID)index
{
    return system_names[index & 255];
}

- (oo::PList)cxx_routeFromSystem:(OOSystemID)start toSystem:(OOSystemID)goal optimizedBy:(OORouteType)optimizeBy
{
    /*
     time_cost = distance * distance
     jump_cost = jumps * max_total_distance + distance = max_total_tistance + distance

     max_total_distance is 7 * 256

     max_time_cost = max_planets * max_time_cost = 256 * (7 * 7)
     max_jump_cost = max_planets * max_jump_cost = 256 * (7 * 256 + 7)
     */

    // no interstellar space for start and/or goal please
    if (start == -1 || goal == -1)
        return oo::PList();

#ifdef CACHE_ROUTE_FROM_SYSTEM_RESULTS

    static oo::PList c_route;
    static OOSystemID c_start, c_goal;
    static OORouteType c_optimizeBy;

    if (!c_route.isNull() && c_start == start && c_goal == goal && c_optimizeBy == optimizeBy) {
        return c_route;
    }

#endif

    unsigned i, j;

    if (start > 255 || goal > 255)
        return oo::PList();

    std::vector<OOSystemID> neighbours[256];
    BOOL concealed[256];
    for (i = 0; i < 256; i++) {
        const oo::PList systemInfo = [systemManager cxx_getPropertiesForSystem:i inGalaxy:galaxyID];
        NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
        if (concealment >= OO_SYSTEMCONCEALMENT_NOTHING) {
            // system is not known
            neighbours[i].clear();
            concealed[i] = YES;
        } else {
            neighbours[i] = [self neighboursToSystem:i];
            concealed[i] = NO;
        }
    }

    RouteElement* cheapest[256] = { 0 };

    double maxCost = optimizeBy == OPTIMIZED_BY_TIME ? 256 * (7 * 7) : 256 * (7 * 256 + 7);

    std::vector<oo::ObjCRef<RouteElement*>> curr;
    curr.reserve(256);
    curr.push_back(oo::ObjCRef<RouteElement*>(cheapest[start] = [RouteElement elementWithLocation:start parent:-1 cost:0 distance:0 time:0 jumps:0]));

    std::vector<oo::ObjCRef<RouteElement*>> next;
    next.reserve(256);
    while (curr.size() != 0) {
        for (i = 0; i < curr.size(); i++) {
            RouteElement* elemI = curr[i].get();
            const std::vector<OOSystemID>& ns = neighbours[[elemI location]];
            for (j = 0; j < ns.size(); j++) {
                RouteElement* ce = cheapest[[elemI location]];
                OOSystemID n = ns[j];
                if (concealed[n]) {
                    continue;
                }
                OOSystemID c = [ce location];

                NSPoint cpos = [systemManager getCoordinatesForSystem:c inGalaxy:galaxyID];
                NSPoint npos = [systemManager getCoordinatesForSystem:n inGalaxy:galaxyID];

                double lastDistance = distanceBetweenPlanetPositions(npos.x, npos.y, cpos.x, cpos.y);
                double lastTime = lastDistance * lastDistance;

                double distance = [ce distance] + lastDistance;
                double time = [ce time] + lastTime;
                double cost = [ce cost] + (optimizeBy == OPTIMIZED_BY_TIME ? lastTime : 7 * 256 + lastDistance);
                int jumps = [ce jumps] + 1;

                if (cost < maxCost && (cheapest[n] == nil || [cheapest[n] cost] > cost)) {
                    RouteElement* e = [RouteElement elementWithLocation:n parent:c cost:cost distance:distance time:time jumps:jumps];
                    cheapest[n] = e;
                    next.push_back(oo::ObjCRef<RouteElement*>(e));

                    if (n == goal && cost < maxCost)
                        maxCost = cost;
                }
            }
        }
        curr = next;
        next.clear();
    }

    if (!cheapest[goal])
        return oo::PList();

    oo::PList::Array route; // system IDs as signed integers, as +numberWithInt: made them
    RouteElement* e = cheapest[goal];
    for (;;) {
        route.insert(route.begin(), oo::PList::signedInteger([e location]));
        if ([e parent] == -1)
            break;
        e = cheapest[[e parent]];
    }

#ifdef CACHE_ROUTE_FROM_SYSTEM_RESULTS
    c_start = start;
    c_goal = goal;
    c_optimizeBy = optimizeBy;
    c_route = oo::PList(oo::PList::Dict { { "route", oo::PList(std::move(route)) }, { "distance", oo::PList((double)[cheapest[goal] distance]) } });

    return c_route;
#else
    return oo::PList(oo::PList::Dict {
        { "route", oo::PList(std::move(route)) },
        { "distance", oo::PList((double)[cheapest[goal] distance]) },
        { "time", oo::PList((double)[cheapest[goal] time]) },
        { "jumps", oo::PList::signedInteger([cheapest[goal] jumps]) } });
#endif
}

- (std::vector<OOSystemID>)neighboursToSystem:(OOSystemID)s
{
    if (s == systemID && closeSystems.has_value()) {
        return *closeSystems;
    }
    std::vector<OOSystemID> neighbours = [systemManager cxx_getNeighbourIDsForSystem:s inGalaxy:galaxyID];

    if (s == systemID) {
        closeSystems = neighbours;
        return *closeSystems;
    }
    return neighbours;
}

/*
        Planet texture preloading.

        In order to hide the cost of synthesizing textures, we want to start
        rendering them asynchronously as soon as there's a hint they may be needed
        soon: when a system is selected on one of the charts, and when beginning a
        jump. However, it would be a Bad Idea™ to allow an arbitrary number of
        planets to be queued, since you can click on lots of systems quite
        quickly on the long-range chart.

        To rate-limit this, we track the materials that are being preloaded and
        only queue the ones for a new system if there are no more than two in the
        queue. (Currently, each system will have at most two materials, the main
        planet and the main planet's atmosphere, but it may be worth adding the
        ability to declare planets in planetinfo.plist instead of using scripts so
        that they can also benefit from preloading.)

        The preloading materials list is pruned before preloading, and also once
        per frame so textures can fall out of the regular cache.
        -- Ahruman 2009-12-19

        DISABLED due to crashes on some Windows systems. Textures generated here
        remain in the sRecentTextures cache when released, suggesting a retain
        imbalance somewhere. Cannot reproduce under Mac OS X. Needs further
        analysis before reenabling.
        http://www.aegidian.org/bb/viewtopic.php?f=3&t=12109
        -- Ahruman 2012-06-29
*/
- (void)preloadPlanetTexturesForSystem:(OOSystemID)s
{
// #if NEW_PLANETS
#if 0
	[self prunePreloadingPlanetMaterials];
	
	if (_preloadingPlanetMaterials.size() < 3)
	{
		
		OOPlanetEntity *planet = [[OOPlanetEntity alloc] initAsMainPlanetForSystem:s];
		OOMaterial *surface = [planet material];
		// can be nil if texture mis-defined
		if (surface != nil)
		{
			// if it's already loaded, no need to continue
			if (![surface isFinishedLoading])
			{
				_preloadingPlanetMaterials.push_back(oo::ObjCRef<OOMaterial *>(surface));
		
				// In some instances (retextured planets atm), the main planet might not have an atmosphere defined.
				// Trying to add nil to _preloadingPlanetMaterials will prematurely terminate the calling function.(!) --Kaks 20100107
				OOMaterial *atmo = [planet atmosphereMaterial];
				if (atmo != nil)  _preloadingPlanetMaterials.push_back(oo::ObjCRef<OOMaterial *>(atmo));
			}
		}
		
		[planet release];
	}
#endif
}

- (oo::PList)cxx_globalSettings
{
    return globalSettings;
}

- (oo::PList)cxx_equipmentData
{
    return equipmentData;
}

- (oo::PList)cxx_equipmentDataOutfitting
{
    return equipmentDataOutfitting;
}

- (OOCommodityMarket*)commodityMarket
{
    return commodityMarket;
}

- (std::optional<std::string>)timeDescription:(double)interval
{
    double r_time = interval;
    std::string result;

    if (r_time > 86400) {
        int days = floor(r_time / 86400);
        r_time -= 86400 * days;
        result = oo::str::format("%s %d day%s", result.c_str(), days, (days > 1) ? "s" : "");
    }
    if (r_time > 3600) {
        int hours = floor(r_time / 3600);
        r_time -= 3600 * hours;
        result = oo::str::format("%s %d hour%s", result.c_str(), hours, (hours > 1) ? "s" : "");
    }
    if (r_time > 60) {
        int mins = floor(r_time / 60);
        r_time -= 60 * mins;
        result = oo::str::format("%s %d minute%s", result.c_str(), mins, (mins > 1) ? "s" : "");
    }
    if (r_time > 0) {
        int secs = floor(r_time);
        result = oo::str::format("%s %d second%s", result.c_str(), secs, (secs > 1) ? "s" : "");
    }
    return oo::str::trim(result, oo::str::CharacterSet::whitespace());
}

- (std::optional<std::string>)cxx_shortTimeDescription:(double)interval
{
    double r_time = interval;
    std::string result;
    int parts = 0;

    if (interval <= 0.0)
        return cxx_OOLookUpDescriptionPRIV("contracts-no-time");

    if (r_time > 86400) {
        int days = floor(r_time / 86400);
        r_time -= 86400 * days;
        result = oo::str::format("%s %d %s", result.c_str(), days, cxx_OOLookUpPluralDescriptionPRIV("contracts-day-word", days).c_str());
        parts++;
    }
    if (r_time > 3600) {
        int hours = floor(r_time / 3600);
        r_time -= 3600 * hours;
        result = oo::str::format("%s %d %s", result.c_str(), hours, cxx_OOLookUpPluralDescriptionPRIV("contracts-hour-word", hours).c_str());
        parts++;
    }
    if (parts < 2 && r_time > 60) {
        int mins = floor(r_time / 60);
        r_time -= 60 * mins;
        result = oo::str::format("%s %d %s", result.c_str(), mins, cxx_OOLookUpPluralDescriptionPRIV("contracts-minute-word", mins).c_str());
        parts++;
    }
    if (parts < 2 && r_time > 0) {
        int secs = floor(r_time);
        result = oo::str::format("%s %d %s", result.c_str(), secs, cxx_OOLookUpPluralDescriptionPRIV("contracts-second-word", secs).c_str());
    }
    return oo::str::trim(result, oo::str::CharacterSet::whitespace());
}

- (void)makeSunSkimmer:(ShipEntity*)ship andSetAI:(BOOL)setAI
{
    if (setAI)
        [ship switchAITo:@"oolite-traderAI.js"]; // perfectly acceptable for both route 2 & 3
    [ship setFuel:(Ranrot() & 31)];
    // slow ships need extra insulation or they will burn up when sunskimming. (Tested at biggest sun in G3: Aenqute)
    float minInsulation = 1000 / [ship maxFlightSpeed] + 1;
    if ([ship heatInsulation] < minInsulation)
        [ship setHeatInsulation:minInsulation];
}

- (Random_Seed)marketSeed
{
    Random_Seed ret = [systemManager getRandomSeedForCurrentSystem];

    // adjust basic seed by market random factor
    // which for (very bad) historical reasons is 0x80

    ret.f ^= 0x80; // XOR back to front
    ret.e ^= ret.f; // XOR
    ret.d ^= ret.e; // XOR
    ret.c ^= ret.d; // XOR
    ret.b ^= ret.c; // XOR
    ret.a ^= ret.b; // XOR

    return ret;
}

- (void)cxx_loadStationMarkets:(const oo::PList&)marketData
{
    if (marketData.isNull()) {
        return;
    }

    const oo::PList::Array* savedMarkets = marketData.getIf<oo::PList::Array>();
    if (savedMarkets == nullptr)
        return;
    for (const oo::PList& savedMarket : *savedMarkets) {
        HPVector pos = HPVectorIn(savedMarket, "position", kZeroHPVector);
        for (const oo::ObjCRef<StationEntity*>& entry : [self cxx_stations]) // a snapshot
        {
            StationEntity* station = entry.get();
            // must be deterministic and secondary
            if ([station allowsSaving] && station != [UNIVERSE station]) {
                // allow a km of drift just in case
                if (HPdistance2(pos, [station position]) < 1000000) {
                    const oo::PList* market = savedMarket.get<oo::PList::Array>("market");
                    [station cxx_setLocalMarket:(market != nullptr) ? *market : oo::PList()];
                    break;
                }
            }
        }
    }
}

// Saved in the savegame: the market rows as OOCommodityMarket saves them, the position as the
// doubles ArrayFromHPVector stored.
- (oo::PList)cxx_getStationMarkets
{
    oo::PList::Array markets;

    OOCommodityMarket* stationMarket = nil;

    for (const oo::ObjCRef<StationEntity*>& entry : [self cxx_stations]) // a snapshot
    {
        StationEntity* station = entry.get();
        // must be deterministic and secondary
        if ([station allowsSaving] && station != [UNIVERSE station]) {
            stationMarket = [station localMarket];
            if (stationMarket != nil) {
                const HPVector position = [station position];
                markets.push_back(oo::PList(oo::PList::Dict {
                    { "market", [stationMarket cxx_saveStationAmounts] },
                    { "position", oo::PList(oo::PList::Array { oo::PList((double)position.x), oo::PList((double)position.y), oo::PList((double)position.z) }) } }));
            }
        }
    }

    return oo::PList(std::move(markets));
}

namespace {

/*	-removeObjectAtIndex: on the shipyard's candidate keys: an index past the end raised
        OORangeException (the conditions test below can remove the same slot twice).
*/
void RemoveKeyAt(std::vector<std::string>& keys, unsigned index)
{
    if (index >= keys.size()) {
        [OOException raise:OORangeException format:"Index %lu is out of range %lu (in 'removeObjectAtIndex:')", (unsigned long)index, (unsigned long)keys.size()];
    }
    keys.erase(keys.begin() + index);
}

// -containsObject: on an equipment list: -isEqual: of two strings.
bool ContainsKey(const oo::PList::Array& list, const std::string& key)
{
    return std::find(list.begin(), list.end(), oo::PList(key)) != list.end();
}

// -removeObject: on the optional equipment: every equal entry goes; nil removed nothing.
void RemoveOption(std::vector<std::optional<std::string>>& options, const std::optional<std::string>& key)
{
    if (key.has_value())
        std::erase(options, key);
}

// -setObject:forKey: on the offered ship's dictionary.
void SetInDict(oo::PList& dict, std::string_view key, const std::string& value)
{
    if (oo::PList::Dict* entries = dict.getIf<oo::PList::Dict>())
        (*entries)[std::string(key)] = oo::PList(value);
}

/*	OOExpandKey(key, <name>): OOExpand's macro hands the expander a one-entry argument dictionary
        keyed by the variable's name; a number keeps the number type OO_CAST_PARAMETER boxed it as.
*/
std::string ExpandKeyWith(const std::string& key, const char* name, const oo::PList& value)
{
    return oo::StdString(OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), oo::NSStringFrom(key),
        oo::ObjectFromPList(oo::PList(oo::PList::Dict { { name, value } })), nil, nil, kOOExpandKey));
}

// OOExpandKey(key) with no arguments: no argument dictionary.
std::string ExpandKey(const std::string& key)
{
    return oo::StdString(OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), oo::NSStringFrom(key), nil, nil, nil, kOOExpandKey));
}

// -compare: of the two offers' price numbers (unsigned long long).
int comparePrice(const oo::PList& offer1, const oo::PList& offer2)
{
    const unsigned long long price1 = offer1.get<unsigned long long>(oo::StdString(SHIPYARD_KEY_PRICE));
    const unsigned long long price2 = offer2.get<unsigned long long>(oo::StdString(SHIPYARD_KEY_PRICE));
    return (price1 < price2) ? -1 : (price1 > price2) ? 1
                                                      : 0;
}

/*	The offered ships' lowercased names as -compare: ordered them, then the price. A missing name
        compares the same (messaging nil); ship definitions always carry one.
*/
int compareName(const oo::PList& offer1, const oo::PList& offer2)
{
    const oo::PList* ship1 = offer1.get<oo::PList::Dict>(oo::StdString(SHIPYARD_KEY_SHIP));
    const oo::PList* ship2 = offer2.get<oo::PList::Dict>(oo::StdString(SHIPYARD_KEY_SHIP));
    const std::optional<std::string> name1 = (ship1 != nullptr) ? OptionalStringIn(*ship1, oo::StdString(KEY_NAME)) : std::nullopt;
    const std::optional<std::string> name2 = (ship2 != nullptr) ? OptionalStringIn(*ship2, oo::StdString(KEY_NAME)) : std::nullopt;

    const int result = (name1.has_value() && name2.has_value()) ? oo::str::compare(oo::str::lowercase(*name1), oo::str::lowercase(*name2)) : 0;
    if (result != 0)
        return result;
    else
        return comparePrice(offer1, offer2);
}

} // namespace

- (oo::PList)cxx_shipsForSaleForSystem:(OOSystemID)s withTL:(OOTechLevelID)specialTL atTime:(OOTimeAbsolute)current_time
{
    RANROTSeed saved_seed = RANROTGetFullSeed();
    Random_Seed ship_seed = [self marketSeed];

    std::map<std::string, oo::PList> resultDictionary; // by ship ID

    float tech_price_boost = (ship_seed.a + ship_seed.b) / 256.0;
    unsigned i;
    PlayerEntity* player = PLAYER;
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];
    RANROTSeed personalitySeed = RanrotSeedFromRandomSeed(ship_seed);

    for (i = 0; i < 256; i++) {
        long long reference_time = 0x1000000 * floor(current_time / 0x1000000);

        long long c_time = ship_seed.a * 0x10000 + ship_seed.b * 0x100 + ship_seed.c;
        double ship_sold_time = reference_time + c_time;

        if (ship_sold_time < 0)
            ship_sold_time += 0x1000000; // wraparound

        double days_until_sale = (ship_sold_time - current_time) / 86400.0;

        std::vector<std::string> keysForShips = [registry cxx_playerShipKeys];
        unsigned si;
        for (si = 0; si < keysForShips.size(); si++) {
            // eliminate any ships that fail a 'conditions test'
            const std::string key = keysForShips[si];
            const oo::PList dict = [registry cxx_shipyardInfoForKey:key];
            const oo::PList* conditions = dict.get<oo::PList::Array>("conditions");

            if (![player scriptTestConditions:(conditions != nullptr) ? oo::ObjectFromPList(*conditions) : nil]) {
                RemoveKeyAt(keysForShips, si--);
            }
            std::optional<std::string> condition_script = OptionalStringIn(dict, "condition_script");
            if (condition_script.has_value()) {
                OOJSScript* condScript = [self cxx_getConditionScript:*condition_script];
                if (condScript != nil) // should always be non-nil, but just in case
                {
                    JSContext* context = OOJSAcquireContext();
                    BOOL OK;
                    BOOL allow_purchase = NO;
                    OOJSVal result = OOJSUndefinedValue();
                    OOJSVal args[] = { OOJSValueFromNativeObject(context, oo::NSStringFrom(key)) };

                    OK = [condScript callMethod:OOJSID("allowOfferShip")
                                      inContext:context
                                  withArguments:args
                                          count:sizeof args / sizeof *args
                                         result:&result];

                    if (OK)
                        allow_purchase = OOJSValueToBOOL(context, result);

                    OOJSFreeValue(context, result);
                    OOJSFreeValue(context, args[0]);
                    OOJSRelinquishContext(context);

                    if (OK && !allow_purchase) {
                        /* if the script exists, the function exists, the function
                         * returns a bool, and that bool is false, block
                         * purchase. Otherwise allow it as default */
                        RemoveKeyAt(keysForShips, si--);
                    }
                }
            }
        }

        const oo::PList systemInfo = [self cxx_generateSystemData:s];
        OOTechLevelID techlevel;
        if (specialTL != NSNotFound) {
            // if we are passed a tech level use that
            techlevel = specialTL;
        } else {
            // otherwise use default for system
            techlevel = systemInfo.get<unsigned int>(oo::StdString(KEY_TECHLEVEL));
        }
        unsigned ship_index = (ship_seed.d * 0x100 + ship_seed.e) % keysForShips.size();
        const std::string ship_key = keysForShips[ship_index];
        const oo::PList ship_info = [registry cxx_shipyardInfoForKey:ship_key];
        OOTechLevelID ship_techlevel = ship_info.get<int>(oo::StdString(KEY_TECHLEVEL));

        double chance = 1.0 - pow(1.0 - ship_info.get<double>(oo::StdString(KEY_CHANCE)), MAX((OOTechLevelID)1, techlevel - ship_techlevel));

        // seed random number generator
        int superRand1 = ship_seed.a * 0x10000 + ship_seed.c * 0x100 + ship_seed.e;
        uint32_t superRand2 = ship_seed.b * 0x10000 + ship_seed.d * 0x100 + ship_seed.f;
        ranrot_srand(superRand2);

        const oo::PList shipBaseDict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:ship_key];

        if ((days_until_sale > 0.0) && (days_until_sale < 30.0) && (ship_techlevel <= techlevel) && (randf() < chance) && !shipBaseDict.isNull()) {
            oo::PList shipDict = shipBaseDict;
            std::string shortShipDescription;
            std::optional<std::string> shipName = OptionalStringIn(shipDict, "display_name");
            if (!shipName.has_value())
                shipName = OptionalStringIn(shipDict, oo::StdString(KEY_NAME));
            OOCreditsQuantity price = ship_info.get<unsigned int>(oo::StdString(KEY_PRICE));
            OOCreditsQuantity base_price = price;
            const oo::PList* standardEquipment = ship_info.get<oo::PList::Dict>(oo::StdString(KEY_STANDARD_EQUIPMENT));
            const oo::PList* standardExtras = (standardEquipment != nullptr) ? standardEquipment->get<oo::PList::Array>(oo::StdString(KEY_EQUIPMENT_EXTRAS)) : nullptr;
            oo::PList::Array extras = (standardExtras != nullptr) ? *standardExtras->getIf<oo::PList::Array>() : oo::PList::Array();
            std::optional<std::string> fwdWeaponString = (standardEquipment != nullptr) ? OptionalStringIn(*standardEquipment, oo::StdString(KEY_EQUIPMENT_FORWARD_WEAPON)) : std::nullopt;
            std::optional<std::string> aftWeaponString = (standardEquipment != nullptr) ? OptionalStringIn(*standardEquipment, oo::StdString(KEY_EQUIPMENT_AFT_WEAPON)) : std::nullopt;

            const oo::PList* optionalEquipment = ship_info.get<oo::PList::Array>(oo::StdString(KEY_OPTIONAL_EQUIPMENT));
            std::vector<std::optional<std::string>> options;
            if (optionalEquipment != nullptr) {
                for (std::size_t k = 0; k < optionalEquipment->count(); k++)
                    options.push_back(OptionalStringAt(*optionalEquipment, k));
            }
            OOCargoQuantity maxCargo = shipDict.get<unsigned int>("max_cargo");

            // more info for potential purchasers - how to reveal this I'm not yet sure...
            // std::optional<std::string> brochure_desc = [self brochureDescriptionWithDictionary:shipDict standardEquipment:extras optionalEquipment:options];
            // OO_LOG("shipyard.brochure", "{} Brochure description : \"{}\"", oo::DescriptionOf([ship name]), brochure_desc);

            shortShipDescription += TextOrNull(shipName) + ":";

            OOWeaponFacingSet availableFacings = ship_info.get<unsigned int>(oo::StdString(KEY_WEAPON_FACINGS), VALID_WEAPON_FACINGS) & VALID_WEAPON_FACINGS;

            OOWeaponType fwdWeapon = OOWeaponTypeFromEquipmentIdentifierSloppy(oo::NSStringOrNil(fwdWeaponString));
            OOWeaponType aftWeapon = OOWeaponTypeFromEquipmentIdentifierSloppy(oo::NSStringOrNil(aftWeaponString));
            // port and starboard weapons are not modified in the shipyard
            //  apply fwd and aft weapons to the ship
            if (fwdWeapon && fwdWeaponString)
                SetInDict(shipDict, oo::StdString(KEY_EQUIPMENT_FORWARD_WEAPON), *fwdWeaponString);
            if (aftWeapon && aftWeaponString)
                SetInDict(shipDict, oo::StdString(KEY_EQUIPMENT_AFT_WEAPON), *aftWeaponString);

            int passengerBerthCount = 0;
            BOOL customised = NO;
            BOOL weaponCustomized = NO;

            std::optional<std::string> fwdWeaponDesc;

            std::string shortExtrasKey = "shipyard-first-extra";

            // for testing condition scripts
            ShipEntity* testship = [[ProxyPlayerEntity alloc] initWithKey:oo::NSStringFrom(ship_key) definition:oo::ObjectFromPList(shipDict)];
            // customise the ship (if chance = 1, then ship will get all possible add ons)
            while ((randf() < chance) && (options.size())) {
                chance *= chance; // decrease the chance of a further customisation (unless it is 1, which might be a bug)
                int optionIndex = Ranrot() % options.size();
                const std::optional<std::string> equipmentKey = options[optionIndex];
                OOEquipmentType* item = equipmentKey.has_value() ? [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(*equipmentKey)] : nil;

                if (item != nil) {
                    OOTechLevelID eqTechLevel = [item techLevel];
                    OOCreditsQuantity eqPrice = [item price] / 10; // all amounts are x/10 due to being represented in tenths of credits.
                    std::optional<std::string> eqShortDesc = oo::OptionalString([item name]);

                    if ([item techLevel] > techlevel) {
                        // Cap maximum tech level.
                        eqTechLevel = MIN(eqTechLevel, 15U);

                        // Higher tech items are rarer!
                        if (randf() * (eqTechLevel - techlevel) < 1.0) {
                            // All included equip has a 10% discount.
                            eqPrice *= (tech_price_boost + eqTechLevel - techlevel) * 90 / 100;
                        } else
                            break; // Bar this upgrade.
                    }

                    if ([item incompatibleEquipment] != nil) {
                        BOOL incompatible = NO;
                        const std::vector<std::string> incompatibleKeys = oo::StringsFrom([item incompatibleEquipment]);

                        for (const std::string& key : incompatibleKeys) {
                            if (ContainsKey(extras, key)) {
                                RemoveOption(options, equipmentKey);
                                incompatible = YES;
                                break;
                            }
                        }
                        if (incompatible)
                            break;

                        // make sure the incompatible equipment is not choosen later on.
                        for (const std::string& key : incompatibleKeys) {
                            RemoveOption(options, key);
                        }
                    }

                    /* Check condition scripts */
                    std::optional<std::string> condition_script = oo::OptionalString([item conditionScript]);
                    if (condition_script.has_value()) {
                        OOJSScript* condScript = [self cxx_getConditionScript:*condition_script];
                        if (condScript != nil) // should always be non-nil, but just in case
                        {
                            JSContext* JScontext = OOJSAcquireContext();
                            BOOL OK;
                            BOOL allow_addition = NO;
                            OOJSVal result = OOJSUndefinedValue();
                            OOJSVal args[] = { OOJSValueFromNativeObject(JScontext, oo::NSStringFrom(*equipmentKey)), OOJSValueFromNativeObject(JScontext, testship), OOJSValueFromNativeObject(JScontext, @"newShip") };

                            OK = [condScript callMethod:OOJSID("allowAwardEquipment")
                                              inContext:JScontext
                                          withArguments:args
                                                  count:sizeof args / sizeof *args
                                                 result:&result];

                            if (OK)
                                allow_addition = OOJSValueToBOOL(JScontext, result);

                            OOJSFreeValue(JScontext, result);
                            OOJSFreeValue(JScontext, args[0]);
                            OOJSFreeValue(JScontext, args[1]);
                            OOJSFreeValue(JScontext, args[2]);
                            OOJSRelinquishContext(JScontext);

                            if (OK && !allow_addition) {
                                /* if the script exists, the function exists, the function
                                 * returns a bool, and that bool is false, block
                                 * addition. Otherwise allow it as default */
                                break;
                            }
                        }
                    }

                    if ([item requiresEquipment] != nil) {
                        BOOL missing = NO;

                        for (const std::string& key : oo::StringsFrom([item requiresEquipment])) {
                            if (!ContainsKey(extras, key)) {
                                missing = YES;
                            }
                        }
                        if (missing)
                            break;
                    }

                    if ([item requiresAnyEquipment] != nil) {
                        BOOL missing = YES;

                        for (const std::string& key : oo::StringsFrom([item requiresAnyEquipment])) {
                            if (ContainsKey(extras, key)) {
                                missing = NO;
                            }
                        }
                        if (missing)
                            break;
                    }

                    // Special case, NEU has to be compatible with EEU inside equipment.plist
                    // but we can only have either one or the other on board.
                    if (*equipmentKey == "EQ_NAVAL_ENERGY_UNIT") {
                        if (ContainsKey(extras, "EQ_ENERGY_UNIT")) {
                            RemoveOption(options, equipmentKey);
                            break;
                        }
                    }

                    if (oo::str::hasPrefix(*equipmentKey, "EQ_WEAPON")) {
                        OOWeaponType new_weapon = OOWeaponTypeFromEquipmentIdentifierSloppy(oo::NSStringFrom(*equipmentKey));
                        // fit best weapon forward
                        if (availableFacings & WEAPON_FACING_FORWARD && [new_weapon weaponThreatAssessment] > [fwdWeapon weaponThreatAssessment]) {
                            // again remember to divide price by 10 to get credits from tenths of credit
                            price -= (fwdWeaponString ? [self cxx_getEquipmentPriceForKey:*fwdWeaponString] : 0) * 90 / 1000; // 90% credits
                            price += eqPrice;
                            fwdWeaponString = equipmentKey;
                            fwdWeapon = new_weapon;
                            SetInDict(shipDict, oo::StdString(KEY_EQUIPMENT_FORWARD_WEAPON), *fwdWeaponString);
                            weaponCustomized = YES;
                            fwdWeaponDesc = eqShortDesc;
                        } else {
                            // if less good than current forward, try fitting is to rear
                            if (availableFacings & WEAPON_FACING_AFT && (isWeaponNone(aftWeapon) || [new_weapon weaponThreatAssessment] > [aftWeapon weaponThreatAssessment])) {
                                price -= (aftWeaponString ? [self cxx_getEquipmentPriceForKey:*aftWeaponString] : 0) * 90 / 1000; // 90% credits
                                price += eqPrice;
                                aftWeaponString = equipmentKey;
                                aftWeapon = new_weapon;
                                SetInDict(shipDict, oo::StdString(KEY_EQUIPMENT_AFT_WEAPON), *aftWeaponString);
                            } else {
                                RemoveOption(options, equipmentKey); // dont try again
                            }
                        }

                    } else {
                        if (*equipmentKey == "EQ_PASSENGER_BERTH") {
                            if ((maxCargo >= PASSENGER_BERTH_SPACE) && (randf() < chance)) {
                                maxCargo -= PASSENGER_BERTH_SPACE;
                                price += eqPrice;
                                extras.push_back(oo::PList(*equipmentKey));
                                passengerBerthCount++;
                                customised = YES;
                            } else {
                                // remove the option if there's no space left
                                RemoveOption(options, equipmentKey);
                            }
                        } else {
                            price += eqPrice;
                            extras.push_back(oo::PList(*equipmentKey));
                            if ([item isVisible]) {
                                shortShipDescription += ExpandKeyWith(shortExtrasKey, "item", eqShortDesc ? oo::PList(*eqShortDesc) : oo::PList());
                                shortExtrasKey = "shipyard-additional-extra";
                            }
                            customised = YES;
                            RemoveOption(options, equipmentKey); // dont add twice
                        }
                    }
                } else {
                    RemoveOption(options, equipmentKey);
                }
            } // end adding optional equipment
            [testship release];
            // i18n: Some languages require that no conversion to lower case string takes place.
            BOOL lowercaseIgnore = [self cxx_descriptions]->get<bool>("lowercase_ignore");

            if (passengerBerthCount) {
                std::string npb = (passengerBerthCount > 1) ? oo::str::format("%d ", passengerBerthCount) : std::string();
                std::string ppb = cxx_OOLookUpPluralDescriptionPRIV("passenger-berth", passengerBerthCount);
                std::string extraPassengerBerthsDescription = oo::str::formatRuntime(cxx_OOLookUpDescriptionPRIV("extra-@-@-(passenger-berths)"), { npb, ppb });
                shortShipDescription += ExpandKeyWith(shortExtrasKey, "item", oo::PList(extraPassengerBerthsDescription));
                shortExtrasKey = "shipyard-additional-extra";
            }

            if (!customised) {
                shortShipDescription += ExpandKey("shipyard-standard-customer-model");
            }

            if (weaponCustomized) {
                std::optional<std::string> weapon = fwdWeaponDesc;
                if (!lowercaseIgnore && weapon.has_value())
                    weapon = oo::str::lowercase(*weapon);
                shortShipDescription += ExpandKeyWith("shipyard-forward-weapon-upgraded", "weapon", weapon ? oo::PList(*weapon) : oo::PList());
            }
            if (price > base_price) {
                price = base_price + cunningFee(price - base_price, 0.05);
            }

            shortShipDescription += ExpandKeyWith("shipyard-price", "price", oo::PList(price));

            std::string shipID = oo::str::format("%06x-%06x", superRand1, superRand2);

            uint16_t personality = RanrotWithSeed(&personalitySeed) & ENTITY_PERSONALITY_MAX;

            oo::PList::Dict ship_info_dictionary;
            ship_info_dictionary[oo::StdString(SHIPYARD_KEY_ID)] = oo::PList(shipID);
            ship_info_dictionary[oo::StdString(SHIPYARD_KEY_SHIPDATA_KEY)] = oo::PList(ship_key);
            ship_info_dictionary[oo::StdString(SHIPYARD_KEY_SHIP)] = shipDict;
            ship_info_dictionary[oo::StdString(KEY_SHORT_DESCRIPTION)] = oo::PList(shortShipDescription);
            ship_info_dictionary[oo::StdString(SHIPYARD_KEY_PRICE)] = oo::PList(price);
            ship_info_dictionary[oo::StdString(KEY_EQUIPMENT_EXTRAS)] = oo::PList(extras);
            ship_info_dictionary[oo::StdString(SHIPYARD_KEY_PERSONALITY)] = oo::PList(personality);

            resultDictionary[shipID] = oo::PList(std::move(ship_info_dictionary)); // should order them fairly randomly
        }

        // next contract
        rotate_seed(&ship_seed);
        rotate_seed(&ship_seed);
        rotate_seed(&ship_seed);
        rotate_seed(&ship_seed);
    }

    oo::PList::Array resultArray;
    for (auto& entry : resultDictionary)
        resultArray.push_back(std::move(entry.second));
    std::stable_sort(resultArray.begin(), resultArray.end(), [](const oo::PList& a, const oo::PList& b) { return compareName(a, b) < 0; });

    // remove identically priced ships of the same name
    i = 1;

    while (i < resultArray.size()) {
        if (compareName(resultArray[i - 1], resultArray[i]) == 0) {
            resultArray.erase(resultArray.begin() + i);
        } else {
            i++;
        }
    }

    RANROTSetFullSeed(saved_seed);

    return oo::PList(std::move(resultArray));
}

- (OOCreditsQuantity)cxx_tradeInValueForCommanderDictionary:(const oo::PList&)dict
{
    // get basic information about the craft
    OOCreditsQuantity base_price = 0ULL;
    std::optional<std::string> ship_desc = OptionalStringIn(dict, "ship_desc");
    const oo::PList shipyard_info = ship_desc.has_value() ? [[OOShipRegistry sharedRegistry] cxx_shipyardInfoForKey:*ship_desc] : oo::PList();
    // This checks a rare, but possible case. If the ship for which we are trying to calculate a trade in value
    // does not have a shipyard dictionary entry, report it and set its base price to 0 -- Nikos 20090613.
    if (shipyard_info.isNull()) {
        OO_LOG_ERR("universe.tradeInValueForCommanderDictionary.valueCalculationError", "Shipyard dictionary entry for ship {} required for trade in value calculation, but does not exist. Setting ship value to 0.", ship_desc.value_or("(null)"));
    } else {
        base_price = shipyard_info.get<unsigned long long>(oo::StdString(SHIPYARD_KEY_PRICE), 0ULL);
    }

    if (base_price == 0ULL)
        return base_price;

    // A missing key was priced as nothing ([UNIVERSE getEquipmentPriceForKey:nil]).
    auto priceOf = [](const std::optional<std::string>& key) -> OOCreditsQuantity {
        return key.has_value() ? [UNIVERSE cxx_getEquipmentPriceForKey:*key] : 0;
    };

    OOCreditsQuantity scrap_value = 351; // translates to 250 cr.

    OOWeaponType ship_fwd_weapon = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(OptionalStringIn(dict, "forward_weapon"))];
    OOWeaponType ship_aft_weapon = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(OptionalStringIn(dict, "aft_weapon"))];
    OOWeaponType ship_port_weapon = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(OptionalStringIn(dict, "port_weapon"))];
    OOWeaponType ship_starboard_weapon = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(OptionalStringIn(dict, "starboard_weapon"))];
    unsigned ship_missiles = dict.get<unsigned int>("missiles");
    unsigned ship_max_passengers = dict.get<unsigned int>("max_passengers");
    std::vector<std::string> ship_extra_equipment;
    if (const oo::PList* extraEquipment = dict.get<oo::PList::Dict>("extra_equipment")) {
        for (const auto& entry : *extraEquipment->getIf<oo::PList::Dict>())
            ship_extra_equipment.push_back(entry.first);
    }

    const oo::PList* basicInfoEntry = shipyard_info.get<oo::PList::Dict>(oo::StdString(KEY_STANDARD_EQUIPMENT));
    const oo::PList basic_info = (basicInfoEntry != nullptr) ? *basicInfoEntry : oo::PList();
    unsigned base_missiles = basic_info.get<unsigned int>(oo::StdString(KEY_EQUIPMENT_MISSILES));
    OOCreditsQuantity base_missiles_value = base_missiles * [UNIVERSE cxx_getEquipmentPriceForKey:"EQ_MISSILE"] / 10;
    std::optional<std::string> base_weapon_key = OptionalStringIn(basic_info, oo::StdString(KEY_EQUIPMENT_FORWARD_WEAPON));
    OOCreditsQuantity base_weapons_value = priceOf(base_weapon_key) / 10;
    std::vector<std::optional<std::string>> base_extra_equipment;
    if (const oo::PList* baseExtras = basic_info.get<oo::PList::Array>(oo::StdString(KEY_EQUIPMENT_EXTRAS))) {
        for (std::size_t k = 0; k < baseExtras->count(); k++)
            base_extra_equipment.push_back(OptionalStringAt(*baseExtras, k));
    }
    std::string weapon_key;

    // was aft_weapon defined as standard equipment ?
    base_weapon_key = OptionalStringIn(basic_info, oo::StdString(KEY_EQUIPMENT_AFT_WEAPON));
    if (base_weapon_key.has_value())
        base_weapons_value += priceOf(base_weapon_key) / 10;

    OOCreditsQuantity ship_main_weapons_value = 0;
    OOCreditsQuantity ship_other_weapons_value = 0;
    OOCreditsQuantity ship_missiles_value = 0;

    // calculate the actual value for the missiles present on board.
    const oo::PList* missileRoles = dict.get<oo::PList::Array>("missile_roles");
    if (missileRoles != nullptr) {
        unsigned i;
        for (i = 0; i < ship_missiles; i++) {
            std::optional<std::string> missile_desc = OptionalStringAt(*missileRoles, i);
            if (missile_desc.has_value() && *missile_desc != "NONE") {
                ship_missiles_value += [UNIVERSE cxx_getEquipmentPriceForKey:*missile_desc] / 10;
            }
        }
    } else
        ship_missiles_value = ship_missiles * [UNIVERSE cxx_getEquipmentPriceForKey:"EQ_MISSILE"] / 10;

    // needs to be a signed value, we can then subtract from the base price, if less than standard equipment.
    long long extra_equipment_value = ship_max_passengers * [UNIVERSE cxx_getEquipmentPriceForKey:"EQ_PASSENGER_BERTH"] / 10;

    // add on missile values
    extra_equipment_value += ship_missiles_value - base_missiles_value;

    // work out weapon values
    if (ship_fwd_weapon) {
        weapon_key = oo::StdString(OOEquipmentIdentifierFromWeaponType(ship_fwd_weapon));
        ship_main_weapons_value = [UNIVERSE cxx_getEquipmentPriceForKey:weapon_key] / 10;
    }
    if (ship_aft_weapon) {
        weapon_key = oo::StdString(OOEquipmentIdentifierFromWeaponType(ship_aft_weapon));
        if (base_weapon_key.has_value()) // aft weapon was defined as a base weapon
        {
            ship_main_weapons_value += [UNIVERSE cxx_getEquipmentPriceForKey:weapon_key] / 10; // take weapon downgrades into account
        } else {
            ship_other_weapons_value += [UNIVERSE cxx_getEquipmentPriceForKey:weapon_key] / 10;
        }
    }
    if (ship_port_weapon) {
        weapon_key = oo::StdString(OOEquipmentIdentifierFromWeaponType(ship_port_weapon));
        ship_other_weapons_value += [UNIVERSE cxx_getEquipmentPriceForKey:weapon_key] / 10;
    }
    if (ship_starboard_weapon) {
        weapon_key = oo::StdString(OOEquipmentIdentifierFromWeaponType(ship_starboard_weapon));
        ship_other_weapons_value += [UNIVERSE cxx_getEquipmentPriceForKey:weapon_key] / 10;
    }

    // add on extra weapons, take away the value of the base weapons
    extra_equipment_value += ship_other_weapons_value;
    extra_equipment_value += ship_main_weapons_value - base_weapons_value;

    NSInteger i;
    std::optional<std::string> eq_key;

    // shipyard.plist settings might have duplicate keys.
    // cull possible duplicates from inside base equipment
    // (the search range 0..i-2, as NSMakeRange(0, i-1) gave it, never looks at the entry just before)
    for (i = (NSInteger)base_extra_equipment.size() - 1; i > 0; i--) {
        eq_key = base_extra_equipment[i];
        const auto searchEnd = base_extra_equipment.begin() + (i - 1);
        if (eq_key.has_value() && std::find(base_extra_equipment.begin(), searchEnd, eq_key) != searchEnd)
            base_extra_equipment.erase(base_extra_equipment.begin() + i);
    }

    // do we at least have the same equipment as a standard ship?
    for (i = (NSInteger)base_extra_equipment.size() - 1; i >= 0; i--) {
        eq_key = base_extra_equipment[i];
        if (eq_key.has_value() && std::find(ship_extra_equipment.begin(), ship_extra_equipment.end(), *eq_key) != ship_extra_equipment.end())
            std::erase(ship_extra_equipment, *eq_key);
        else // if the ship has less equipment than standard, deduct the missing equipent's price
            extra_equipment_value -= (priceOf(eq_key) / 10);
    }

    // remove portable equipment from the totals
    OOEquipmentType* item = nil;

    for (i = (NSInteger)ship_extra_equipment.size() - 1; i >= 0; i--) {
        item = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(ship_extra_equipment[i])];
        if ([item isPortableBetweenShips])
            ship_extra_equipment.erase(ship_extra_equipment.begin() + i);
    }

    // add up what we've got left.
    for (i = (NSInteger)ship_extra_equipment.size() - 1; i >= 0; i--)
        extra_equipment_value += ([UNIVERSE cxx_getEquipmentPriceForKey:ship_extra_equipment[i]] / 10);

    // 10% discount for second hand value, steeper reduction if worse than standard.
    extra_equipment_value *= extra_equipment_value < 0 ? 1.4 : 0.9;

    // we'll return at least the scrap value
    // TODO: calculate scrap value based on the size of the ship.
    if ((long long)scrap_value > (long long)base_price + extra_equipment_value)
        return scrap_value;

    return base_price + extra_equipment_value;
}

- (std::optional<std::string>)brochureDescriptionWithDictionary:(const oo::PList&)dict standardEquipment:(const std::vector<std::string>&)extras optionalEquipment:(const std::vector<std::string>&)options
{
    std::vector<std::string> mut_extras = extras;
    std::string allOptions;
    for (std::size_t k = 0; k < options.size(); k++) {
        if (k > 0)
            allOptions += " ";
        allOptions += options[k];
    }

    std::string desc = "The " + TextOrNull(OptionalStringIn(dict, oo::StdString(KEY_NAME))) + ".";

    // cargo capacity and expansion
    OOCargoQuantity max_cargo = dict.get<unsigned int>("max_cargo");
    if (max_cargo) {
        OOCargoQuantity extra_cargo = dict.get<unsigned int>("extra_cargo", 15);
        desc += oo::str::format(" Cargo capacity %dt", max_cargo);
        BOOL canExpand = (allOptions.find("EQ_CARGO_BAY") != std::string::npos);
        if (canExpand)
            desc += oo::str::format(" (expandable to %dt at most starports)", max_cargo + extra_cargo);
        desc += ".";
    }

    // speed
    float top_speed = dict.get<int>("max_flight_speed");
    desc += oo::str::format(" Top speed %.3fLS.", 0.001 * top_speed);

    // passenger berths
    if (mut_extras.size()) {
        unsigned n_berths = 0;
        unsigned i;
        for (i = 0; i < mut_extras.size(); i++) {
            if (mut_extras[i] == "EQ_PASSENGER_BERTH") {
                n_berths++;
                mut_extras.erase(mut_extras.begin() + i--);
            }
        }
        if (n_berths) {
            if (n_berths == 1)
                desc += " Includes luxury accomodation for a single passenger.";
            else
                desc += oo::str::format(" Includes luxury accomodation for %d passengers.", n_berths);
        }
    }

    // standard fittings
    if (mut_extras.size()) {
        desc += "\nComes with";
        unsigned i, j;
        for (i = 0; i < mut_extras.size(); i++) {
            const std::string& item_key = mut_extras[i];
            std::optional<std::string> item_desc;
            for (j = 0; ((j < equipmentData.count()) && (!item_desc)); j++) {
                std::optional<std::string> eq_type = EquipmentItemString(equipmentData, j, EQUIPMENT_KEY_INDEX);
                if (eq_type == item_key)
                    item_desc = EquipmentItemString(equipmentData, j, EQUIPMENT_SHORT_DESC_INDEX);
            }
            if (item_desc) {
                switch (mut_extras.size() - i) {
                case 1:
                    desc += " " + *item_desc + " fitted as standard.";
                    break;
                case 2:
                    desc += " " + *item_desc + " and";
                    break;
                default:
                    desc += " " + *item_desc + ",";
                    break;
                }
            }
        }
    }

    // optional fittings
    if (options.size()) {
        desc += "\nCan additionally be outfitted with";
        unsigned i, j;
        for (i = 0; i < options.size(); i++) {
            const std::string& item_key = options[i];
            std::optional<std::string> item_desc;
            for (j = 0; ((j < equipmentData.count()) && (!item_desc)); j++) {
                std::optional<std::string> eq_type = EquipmentItemString(equipmentData, j, EQUIPMENT_KEY_INDEX);
                if (eq_type == item_key)
                    item_desc = EquipmentItemString(equipmentData, j, EQUIPMENT_SHORT_DESC_INDEX);
            }
            if (item_desc) {
                switch (options.size() - i) {
                case 1:
                    desc += " " + *item_desc + " at suitably equipped starports.";
                    break;
                case 2:
                    desc += " " + *item_desc + " and/or";
                    break;
                default:
                    desc += " " + *item_desc + ",";
                    break;
                }
            }
        }
    }

    return desc;
}

- (HPVector)getWitchspaceExitPosition
{
    return kZeroHPVector;
}

- (Quaternion)getWitchspaceExitRotation
{
    // this should be fairly close to {0,0,0,1}
    Quaternion q_result;

    // CIM: seems to be no reason why this should be a per-system constant
    //  - trying it without resetting the RNG for now
    //	seed_RNG_only_for_planet_description(system_seed);

    q_result.x = (gen_rnd_number() - 128) / 1024.0;
    q_result.y = (gen_rnd_number() - 128) / 1024.0;
    q_result.z = (gen_rnd_number() - 128) / 1024.0;
    q_result.w = 1.0;
    quaternion_normalize(&q_result);

    return q_result;
}

// FIXME: should use vector functions
- (HPVector)getSunSkimStartPositionForShip:(ShipEntity*)ship
{
    if (!ship) {
        OO_LOG(cxx_kOOLogParameterError, "{}", "***** No ship set in Universe getSunSkimStartPositionForShip:");
        return kZeroHPVector;
    }
    OOSunEntity* the_sun = [self sun];
    // get vector from sun position to ship
    if (!the_sun) {
        OO_LOG(cxx_kOOLogInconsistentState, "{}", "***** No sun set in Universe getSunSkimStartPositionForShip:");
        return kZeroHPVector;
    }
    HPVector v0 = the_sun->position;
    HPVector v1 = ship->position;
    v1.x -= v0.x;
    v1.y -= v0.y;
    v1.z -= v0.z; // vector from sun to ship
    if (v1.x || v1.y || v1.z)
        v1 = HPvector_normal(v1);
    else
        v1.z = 1.0;
    double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
    v1.x *= radius;
    v1.y *= radius;
    v1.z *= radius;
    v1.x += v0.x;
    v1.y += v0.y;
    v1.z += v0.z;

    return v1;
}

// FIXME: should use vector functions
- (HPVector)getSunSkimEndPositionForShip:(ShipEntity*)ship
{
    OOSunEntity* the_sun = [self sun];
    if (!ship) {
        OO_LOG(cxx_kOOLogParameterError, "{}", "***** No ship set in Universe getSunSkimEndPositionForShip:");
        return kZeroHPVector;
    }
    // get vector from sun position to ship
    if (!the_sun) {
        OO_LOG(cxx_kOOLogInconsistentState, "{}", "***** No sun set in Universe getSunSkimEndPositionForShip:");
        return kZeroHPVector;
    }
    HPVector v0 = the_sun->position;
    HPVector v1 = ship->position;
    v1.x -= v0.x;
    v1.y -= v0.y;
    v1.z -= v0.z;
    if (v1.x || v1.y || v1.z)
        v1 = HPvector_normal(v1);
    else
        v1.z = 1.0;
    HPVector v2 = make_HPvector(randf() - 0.5, randf() - 0.5, randf() - 0.5); // random vector
    if (v2.x || v2.y || v2.z)
        v2 = HPvector_normal(v2);
    else
        v2.x = 1.0;
    HPVector v3 = HPcross_product(v1, v2); // random vector at 90 degrees to v1 and v2 (random Vector)
    if (v3.x || v3.y || v3.z)
        v3 = HPvector_normal(v3);
    else
        v3.y = 1.0;
    double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
    v1.x *= radius;
    v1.y *= radius;
    v1.z *= radius;
    v1.x += v0.x;
    v1.y += v0.y;
    v1.z += v0.z;
    v1.x += 15000 * v3.x;
    v1.y += 15000 * v3.y;
    v1.z += 15000 * v3.z; // point 15000m at a tangent to sun from v1
    v1.x -= v0.x;
    v1.y -= v0.y;
    v1.z -= v0.z;
    if (v1.x || v1.y || v1.z)
        v1 = HPvector_normal(v1);
    else
        v1.z = 1.0;
    v1.x *= radius;
    v1.y *= radius;
    v1.z *= radius;
    v1.x += v0.x;
    v1.y += v0.y;
    v1.z += v0.z;

    return v1;
}

- (std::vector<oo::ObjCRef<Entity<OOBeaconEntity>*>>)cxx_listBeaconsWithCode:(const std::string&)code
{
    std::vector<oo::ObjCRef<Entity<OOBeaconEntity>*>> result;
    Entity<OOBeaconEntity>* beacon = [self firstBeacon];

    while (beacon != nil) {
        const std::optional<std::string> beaconCode = oo::OptionalString([beacon beaconCode]);
        if (BeaconCodeMatches(beaconCode, code)) {
            result.emplace_back(beacon);
        }
        beacon = [beacon nextBeacon];
    }

    // ORDER-SENSITIVE (decision D): beacons whose codes compare the same keep their list order.
    std::stable_sort(result.begin(), result.end(), [](const oo::ObjCRef<Entity<OOBeaconEntity>*>& a, const oo::ObjCRef<Entity<OOBeaconEntity>*>& b) {
        return [a.get() compareBeaconCodeWith:b.get()] == NSOrderedAscending;
    });
    return result;
}

- (void)cxx_allShipsDoScriptEvent:(OOJSPropID)event andReactToAIMessage:(const std::optional<std::string>&)message
{
    int i;
    int ent_count = n_entities;
    int ship_count = 0;
    std::vector<ShipEntity*> my_ships(ent_count);
    for (i = 0; i < ent_count; i++) {
        if (sortedEntities[i]->isShip) {
            my_ships[ship_count++] = [(ShipEntity*)sortedEntities[i] retain]; // retained
        }
    }

    for (i = 0; i < ship_count; i++) {
        ShipEntity* se = my_ships[i];
        [se doScriptEvent:event];
        if (message.has_value())
            [[se getAI] reactToMessage:oo::NSStringFrom(*message) context:@"global message"];
        [se release]; //	released
    }
}

///////////////////////////////////////

- (GuiDisplayGen*)gui
{
    return gui;
}

- (GuiDisplayGen*)commLogGUI
{
    return comm_log_gui;
}

- (GuiDisplayGen*)messageGUI
{
    return message_gui;
}

- (void)clearGUIs
{
    [gui clear];
    [message_gui clear];
    [comm_log_gui clear];
    [comm_log_gui printLongText:DESC(@"communications-log-string")
                          align:GUI_ALIGN_CENTER
                          color:[OOColor yellowColor]
                       fadeTime:0
                            key:nil
                     addToArray:nil];
}

- (void)resetCommsLogColor
{
    [comm_log_gui setTextColor:[OOColor whiteColor]];
}

- (void)setDisplayText:(BOOL)value
{
    displayGUI = !!value;
}

- (BOOL)displayGUI
{
    return displayGUI;
}

- (void)setDisplayFPS:(BOOL)value
{
    displayFPS = !!value;
}

- (BOOL)displayFPS
{
    return displayFPS;
}

- (void)setAutoSave:(BOOL)value
{
    autoSave = !!value;
    oo::Defaults::standard().setBool("autosave", autoSave);
}

- (BOOL)autoSave
{
    return autoSave;
}

- (void)setAutoSaveNow:(BOOL)value
{
    autoSaveNow = !!value;
}

- (BOOL)autoSaveNow
{
    return autoSaveNow;
}

- (void)setWireframeGraphics:(BOOL)value
{
    wireframeGraphics = !!value;
    oo::Defaults::standard().setBool("wireframe-graphics", wireframeGraphics);
}

- (BOOL)wireframeGraphics
{
    return wireframeGraphics;
}

- (BOOL)reducedDetail
{
    return detailLevel == DETAIL_LEVEL_MINIMUM;
}

/* Only to be called directly at initialisation */
- (void)setDetailLevelDirectly:(OOGraphicsDetail)value
{
    if (value >= DETAIL_LEVEL_MAXIMUM) {
        value = DETAIL_LEVEL_MAXIMUM;
    } else if (value <= DETAIL_LEVEL_MINIMUM) {
        value = DETAIL_LEVEL_MINIMUM;
    }
    if (![[OOOpenGLExtensionManager sharedManager] shadersSupported]) {
        value = DETAIL_LEVEL_MINIMUM;
    }
    detailLevel = value;
}

- (void)setDetailLevel:(OOGraphicsDetail)value
{
    OOGraphicsDetail old = detailLevel;
    [self setDetailLevelDirectly:value];
    oo::Defaults::standard().setInteger("detailLevel", detailLevel);
    // if changed then reset graphics state
    // (some items now require this even if shader on/off mode unchanged)
    if (old != detailLevel) {
        OO_LOG("rendering.detail-level", "Detail level set to {}.", oo::DescriptionOf(OOStringFromGraphicsDetail(detailLevel)));
        [[OOGraphicsResetManager sharedManager] resetGraphicsState];
    }
}

- (OOGraphicsDetail)detailLevel
{
    return detailLevel;
}

- (BOOL)useShaders
{
    return detailLevel >= DETAIL_LEVEL_SHADERS;
}

- (void)handleOoliteException:(OOException*)exception
{
    if (exception != nil) {
        if (strcmp([exception name], OOLITE_EXCEPTION_FATAL) == 0) {
            PlayerEntity* player = PLAYER;
            [player setStatus:STATUS_HANDLING_ERROR];

            OO_LOG(cxx_kOOLogException, "***** Handling Fatal : {} : {} *****", [exception name], [exception reason]);
            std::string exception_msg = oo::str::format("Exception : %s : %s Please take a screenshot and/or press esc or Q to quit.", [exception name], [exception reason]);
            [self cxx_addMessage:exception_msg forCount:30.0];
            [[self gameController] setGamePaused:YES];
        } else {
            OO_LOG(cxx_kOOLogException, "***** Handling Non-fatal : {} : {} *****", [exception name], [exception reason]);
        }
    }
}

- (GLfloat)airResistanceFactor
{
    return airResistanceFactor;
}

- (void)setAirResistanceFactor:(GLfloat)newFactor
{
    airResistanceFactor = OOClamp_0_1_f(newFactor);
}

// speech routines
#if OOLITE_MAC_COCOA_UI

- (void)cxx_startSpeakingString:(const std::string&)text
{
    [speechSynthesizer startSpeakingString:oo::NSStringFrom(oo::str::format("[[volm %.3f]]%s", 0.3333333f * [OOSound masterVolume], text.c_str()))];
}

- (void)stopSpeaking
{
    if ([speechSynthesizer respondsToSelector:@selector(stopSpeakingAtBoundary:)]) {
        [speechSynthesizer stopSpeakingAtBoundary:NSSpeechWordBoundary];
    } else {
        [speechSynthesizer stopSpeaking];
    }
}

- (BOOL)isSpeaking
{
    return [speechSynthesizer isSpeaking];
}

#elif OOLITE_ESPEAK

- (void)cxx_startSpeakingString:(const std::string&)text
{
    // the UTF-8 bytes of the text
    const char* stringToSay = text.c_str();
    espeak_Synth(stringToSay, strlen(stringToSay) + 1 /* inc. NULL */, 0, POS_CHARACTER, 0, espeakCHARS_UTF8 | espeakPHONEMES | espeakENDPAUSE, NULL, NULL);
}

- (void)stopSpeaking
{
    espeak_Cancel();
}

- (BOOL)isSpeaking
{
    return espeak_IsPlaying();
}

- (std::optional<std::string>)cxx_voiceName:(unsigned int)index
{
    if (index >= espeak_voice_count)
        return std::string("-");
    return std::string(espeak_voices[index]->name);
}

- (unsigned int)cxx_voiceNumber:(const std::string&)name
{
    const char* const label = name.c_str();

    unsigned int index = -1;
    while (espeak_voices[++index] && strcmp(espeak_voices[index]->name, label))
        /**/;
    return (index < espeak_voice_count) ? index : UINT_MAX;
}

- (unsigned int)nextVoice:(unsigned int)index
{
    if (++index >= espeak_voice_count)
        index = 0;
    return index;
}

- (unsigned int)prevVoice:(unsigned int)index
{
    if (--index >= espeak_voice_count)
        index = espeak_voice_count - 1;
    return index;
}

- (unsigned int)setVoice:(unsigned int)index withGenderM:(BOOL)isMale
{
    if (index == UINT_MAX)
        index = [self cxx_voiceNumber:cxx_OOLookUpDescriptionPRIV("espeak-default-voice")];

    if (index < espeak_voice_count) {
        espeak_VOICE voice = { espeak_voices[index]->name, NULL, NULL, (unsigned char)(isMale ? 1 : 2) };
        espeak_SetVoiceByProperties(&voice);
    }

    return index;
}

#else

- (void)cxx_startSpeakingString:(const std::string&)text
{
}

- (void)stopSpeaking
{
}

- (BOOL)isSpeaking
{
    return NO;
}
#endif

- (BOOL)pauseMessageVisible
{
    return _pauseMessage;
}

- (void)setPauseMessageVisible:(BOOL)value
{
    _pauseMessage = value;
}

- (BOOL)permanentMessageLog
{
    return _permanentMessageLog;
}

- (void)setPermanentMessageLog:(BOOL)value
{
    _permanentMessageLog = value;
}

- (BOOL)autoMessageLogBg
{
    return _autoMessageLogBg;
}

- (void)setAutoMessageLogBg:(BOOL)value
{
    _autoMessageLogBg = !!value;
}

- (BOOL)permanentCommLog
{
    return _permanentCommLog;
}

- (void)setPermanentCommLog:(BOOL)value
{
    _permanentCommLog = value;
}

- (void)setAutoCommLog:(BOOL)value
{
    _autoCommLog = value;
}

- (BOOL)blockJSPlayerShipProps
{
    return gOOJSPlayerIfStale != nil;
}

- (void)setBlockJSPlayerShipProps:(BOOL)value
{
    if (value) {
        gOOJSPlayerIfStale = PLAYER;
    } else {
        gOOJSPlayerIfStale = nil;
    }
}

- (void)setUpSettings
{
    [self resetBeacons];

    next_universal_id = 100; // start arbitrarily above zero
    memset(entity_for_uid, 0, sizeof entity_for_uid);

    [self setMainLightPosition:kZeroVector];

    [gui autorelease];
    gui = [[GuiDisplayGen alloc] init];
    [gui setTextColor:[OOColor colorWithDescription:[[gui userSettings] objectForKey:kGuiDefaultTextColor]]];

    // message_gui and comm_log_gui defaults are set up inside [hud resetGuis:] ( via [player deferredInit], called from the code that calls this method).
    [message_gui autorelease];
    message_gui = [[GuiDisplayGen alloc]
        initWithPixelSize:NSMakeSize(480, 160)
                  columns:1
                     rows:9
                rowHeight:19
                 rowStart:20
                    title:nil];

    [comm_log_gui autorelease];
    comm_log_gui = [[GuiDisplayGen alloc]
        initWithPixelSize:NSMakeSize(360, 120)
                  columns:1
                     rows:10
                rowHeight:12
                 rowStart:12
                    title:nil];

    //

    time_delta = 0.0;
#ifdef OO_DEBUG_MONITOR_ENABLED
    [self setTimeAccelerationFactor:TIME_ACCELERATION_FACTOR_DEFAULT];
#endif
    universal_time = 0.0;
    messageRepeatTime = 0.0;
    countdown_messageRepeatTime = 0.0;

#if OOLITE_SPEECH_SYNTH
    speechArray = [ResourceManager cxx_arrayFromFilesNamed:"speech_pronunciation_guide.plist" inFolder:std::string("Config") andMerge:YES];
#endif

    [commodities autorelease];
    commodities = [[OOCommodities alloc] init];

    [self loadDescriptions];

    characters = [ResourceManager cxx_dictionaryFromFilesNamed:"characters.plist" inFolder:std::string("Config") andMerge:YES];

    customSounds = [ResourceManager cxx_dictionaryFromFilesNamed:"customsounds.plist" inFolder:std::string("Config") andMerge:YES];

    globalSettings = [ResourceManager cxx_dictionaryFromFilesNamed:"global-settings.plist" inFolder:std::string("Config") mergeMode:MERGE_SMART cache:YES];

    [systemManager autorelease];
    systemManager = [[ResourceManager systemDescriptionManager] retain];

    screenBackgrounds = [ResourceManager cxx_dictionaryFromFilesNamed:"screenbackgrounds.plist" inFolder:std::string("Config") andMerge:YES];

    // role-categories.plist and pirate-victim-roles.plist
    roleCategories = [ResourceManager cxx_roleCategoriesDictionary];

    autoAIMap = [ResourceManager cxx_dictionaryFromFilesNamed:"autoAImap.plist" inFolder:std::string("Config") andMerge:YES];

    [equipmentData autorelease];
    [equipmentDataOutfitting autorelease];
    NSArray* equipmentTemp = [ResourceManager arrayFromFilesNamed:@"equipment.plist" inFolder:@"Config" andMerge:YES];
    equipmentData = [[equipmentTemp sortedArrayUsingFunction:OOSortFunction(equipmentSort) context:NULL] retain];
    equipmentDataOutfitting = [[equipmentTemp sortedArrayUsingFunction:OOSortFunction(equipmentSortOutfitting) context:NULL] retain];

    [OOEquipmentType loadEquipment];

    explosionSettings = [ResourceManager cxx_dictionaryFromFilesNamed:"explosions.plist" inFolder:std::string("Config") andMerge:YES];
}

- (void)setUpCargoPods
{
    std::map<std::string, oo::ObjCRef<ShipEntity*>, std::less<>> tmp;
    for (const std::string& type : oo::StringsFrom([commodities goods])) // OOCommodities is not migrated yet
    {
        ShipEntity* container = [self cxx_newShipWithRole:"oolite-template-cargopod"];
        [container setScanClass:CLASS_CARGO];
        [container setCommodity:oo::NSStringFrom(type) andAmount:1];
        if (container != nil)
            tmp[type] = oo::adoptObjC(container); // a nil container was an exception before
    }
    cargoPods = std::move(tmp);
}

- (void)verifyEntitySessionIDs
{
#ifndef NDEBUG
    std::vector<oo::ObjCRef<Entity*>> badEntities;
    Entity* entity = nil;

    unsigned i;
    for (i = 0; i < n_entities; i++) {
        entity = sortedEntities[i];
        if ([entity sessionID] != _sessionID) {
            OO_LOG_ERR("universe.sessionIDs.verify.failed", "Invalid entity {} (came from session {}, current session is {}).", oo::DescriptionOf([entity shortDescription]), static_cast<size_t>([entity sessionID]), static_cast<size_t>(_sessionID));
            badEntities.emplace_back(entity);
        }
    }

    for (const oo::ObjCRef<Entity*>& entry : badEntities) {
        [self removeEntity:entry.get()];
    }
#endif
}

// FIXME: needs less redundancy?
- (BOOL)reinitAndShowDemo:(BOOL)showDemo
{
    no_update = YES;
    PlayerEntity* player = PLAYER;
    assert(player != nil);

    if (JSResetFlags != 0) // JS reset failed, remember previous settings
    {
        showDemo = (JSResetFlags & 2) > 0; // binary 10, a.k.a. 1 << 1
    } else {
        JSResetFlags = (showDemo << 1);
    }

    [self removeAllEntitiesExceptPlayer];
    [OOTexture clearCache];

    _sessionID++; // Must be after removing old entities and before adding new ones.

    [ResourceManager cxx_setUseAddOns:useAddOns]; // also logs the paths
    //[ResourceManager loadScripts]; // initialised inside [player setUp]!

    // NOTE: Anything in the sharedCache is now trashed and must be
    //       reloaded. Ideally anything using the sharedCache should
    //       be aware of cache flushes so it can automatically
    //       reinitialize itself - mwerle 20081107.
    [OOShipRegistry reload];
    [[self gameController] setGamePaused:NO];
    [[self gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
    [PLAYER setSpeed:0.0];

    [self loadDescriptions];
    [self loadScenarios];

    missiontext = [ResourceManager cxx_dictionaryFromFilesNamed:"missiontext.plist" inFolder:std::string("Config") andMerge:YES];

    if (showDemo) {
        demo_ships = [[OOShipRegistry sharedRegistry] cxx_demoShipKeys];
        demo_ship_index = 0;
        demo_ship_subindex = 0;
    }

    breakPatternCounter = 0;

    cachedSun = nil;
    cachedPlanet = nil;
    cachedStation = nil;

    [self setUpSettings];

    // reset these in case OXP set has changed

    // set up cargopod templates
    [self setUpCargoPods];

    if (![player setUpAndConfirmOK:YES]) {
        // reinitAndShowDemo rescheduled inside setUpAndConfirmOK...
        return NO; // Abort!
    }

    // we can forget the previous settings now.
    JSResetFlags = 0;

    [self addEntity:player];
    demo_ship = nil;
    [[self gameController] setPlayerFileToLoad:nil]; // reset Quicksave

    [self setUpInitialUniverse];
    autoSaveNow = NO; // don't autosave immediately after restarting a game

    [[self station] initialiseLocalMarket];

    if (showDemo) {
        [player setStatus:STATUS_START_GAME];
        // re-read keyconfig.plist just in case we've loaded a keyboard
        // configuration expansion
        [player initControls];
    } else {
        [player setDockedAtMainStation];
    }

    [player completeSetUp];
    if (showDemo) {
        [player setGuiToIntroFirstGo:YES];
    } else {
        // no need to do these if showing the demo as the only way out
        // now is to load a game
        [self populateNormalSpace];

        [player startUpComplete];
    }

    if (!showDemo) {
        [player setGuiToStatusScreen];
        [player doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")];
    }

    [self verifyEntitySessionIDs];

    no_update = NO;
    return YES;
}

- (void)setUpInitialUniverse
{
    PlayerEntity* player = PLAYER;

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"Wormhole and character reset");
    AutoreleaseAll(activeWormholes); // the old list was autoreleased
    activeWormholes.reserve(16);
    AutoreleaseAll(characterPool); // the old pool was autoreleased
    characterPool.reserve(256);
    OO_DEBUG_POP_PROGRESS();

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"Galaxy reset");
    [self setGalaxyTo:[player galaxyNumber] andReinit:YES];
    systemID = [player systemID];
    OO_DEBUG_POP_PROGRESS();

    OO_DEBUG_PUSH_PROGRESS(@"%@", @"Player init: setUpShipFromDictionary");
    [player setUpShipFromDictionary:[[OOShipRegistry sharedRegistry] shipInfoForKey:[player shipDataKey]]]; // the standard cobra at this point
    [player baseMass]; // bootstrap the base mass used in all fuel charge calculations.
    OO_DEBUG_POP_PROGRESS();

    // Player init above finishes initialising all standard player ship properties. Now that the base mass is set, we can run setUpSpace!
    [self setUpSpace];

    [self setDockingClearanceProtocolActive:
            oo::PListView([self currentSystemData]).get<BOOL>(@"stations_require_docking_clearance", YES)];

    [self enterGUIViewModeWithMouseInteraction:NO];
    [player setPosition:[[self station] position]];
    [player setOrientation:kIdentityQuaternion];
}

- (float)randomDistanceWithinScanner
{
    return SCANNER_MAX_RANGE * ((Ranrot() & 255) / 256.0 - 0.5);
}

- (Vector)randomPlaceWithinScannerFrom:(Vector)pos alongRoute:(Vector)route withOffset:(double)offset
{
    pos.x += offset * route.x + [self randomDistanceWithinScanner];
    pos.y += offset * route.y + [self randomDistanceWithinScanner];
    pos.z += offset * route.z + [self randomDistanceWithinScanner];

    return pos;
}

- (HPVector)fractionalPositionFrom:(HPVector)point0 to:(HPVector)point1 withFraction:(double)routeFraction
{
    if (routeFraction == static_cast<double>(NSNotFound))
        routeFraction = randf();

    point1 = OOHPVectorInterpolate(point0, point1, routeFraction);

    point1.x += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
    point1.y += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
    point1.z += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);

    return point1;
}

- (BOOL)doRemoveEntity:(Entity*)entity
{
    // remove reference to entity in linked lists
    if ([entity canCollide]) // filter only collidables disappearing
    {
        doLinkedListMaintenanceThisUpdate = YES;
    }

    [entity removeFromLinkedLists];

    // moved forward ^^
    // remove from the reference dictionary
    int old_id = [entity universalID];
    entity_for_uid[old_id] = nil;
    [entity setUniversalID:NO_TARGET];
    [entity wasRemovedFromUniverse];

    // maintain sorted lists
    int index = entity->zero_index;

    int n = 1;
    if (index >= 0) {
        if (sortedEntities[index] != entity) {
            OO_LOG(cxx_kOOLogInconsistentState, "DEBUG: Universe removeEntity:{} ENTITY IS NOT IN THE RIGHT PLACE IN THE ZERO_DISTANCE SORTED LIST -- FIXING...", oo::DescriptionOf(entity));
            unsigned i;
            index = -1;
            for (i = 0; (i < n_entities) && (index == -1); i++)
                if (sortedEntities[i] == entity)
                    index = i;
            if (index == -1)
                OO_LOG(cxx_kOOLogInconsistentState, "DEBUG: Universe removeEntity:{} ENTITY IS NOT IN THE ZERO_DISTANCE SORTED LIST -- CONTINUING...", oo::DescriptionOf(entity));
        }
        if (index != -1) {
            while ((unsigned)index < n_entities) {
                while (((unsigned)index + n < n_entities) && (sortedEntities[index + n] == entity)) {
                    n++; // ie there's a duplicate entry for this entity
                }

                /*
                        BUG: when n_entities == UNIVERSE_MAX_ENTITIES, this read
                        off the end of the array and copied (Entity *)n_entities =
                        0x800 into the list. The subsequent update of zero_index
                        derferenced 0x800 and crashed.
                        FIX: add an extra unused slot to sortedEntities, which is
                        always nil.
                        EFFICIENCY CONCERNS: this could have been an alignment
                        issue since UNIVERSE_MAX_ENTITIES == 2048, but it isn't
                        really. sortedEntities is part of the object, not malloced,
                        it isn't aligned, and the end of it is only live in
                        degenerate cases.
                        -- Ahruman 2012-07-11
                */
                sortedEntities[index] = sortedEntities[index + n]; // copy entity[index + n] -> entity[index] (preserves sort order)
                if (sortedEntities[index]) {
                    sortedEntities[index]->zero_index = index; // give it its correct position
                }
                index++;
            }
            if (n > 1)
                OO_LOG(cxx_kOOLogInconsistentState, "DEBUG: Universe removeEntity: REMOVED {} EXTRA COPIES OF {} FROM THE ZERO_DISTANCE SORTED LIST", n - 1, oo::DescriptionOf(entity));
            while (n--) {
                n_entities--;
                sortedEntities[n_entities] = nil;
            }
        }
        entity->zero_index = -1; // it's GONE!
    }

    // remove from the definitive list
    if (std::find(entities.begin(), entities.end(), entity) != entities.end()) {
        // FIXME: better approach needed for core break patterns - CIM
        if ([entity isBreakPattern] && ![entity isVisualEffect]) {
            breakPatternCounter--;
        }

        if ([entity isShip]) {
            ShipEntity* se = (ShipEntity*)entity;
            [self clearBeacon:se];
        }
        if ([entity isWaypoint]) {
            OOWaypointEntity* wp = (OOWaypointEntity*)entity;
            [self clearBeacon:wp];
        }
        if ([entity isVisualEffect]) {
            OOVisualEffectEntity* ve = (OOVisualEffectEntity*)entity;
            [self clearBeacon:ve];
        }

        if ([entity isWormhole]) {
            std::erase(activeWormholes, entity);
        } else if ([entity isPlanet]) {
            std::erase(allPlanets, entity);
        }

        std::erase(entities, entity);
        return YES;
    }

    return NO;
}

static void PreloadOneSound(const std::string& soundName)
{
    if (!oo::str::hasPrefix(soundName, "[") && !oo::str::hasSuffix(soundName, "]")) {
        [ResourceManager cxx_ooSoundNamed:soundName inFolder:std::string("Sounds")];
    }
}

// ORDER-SENSITIVE (decision D): the keys in byte order (was the dictionary's hash order).
- (void)preloadSounds
{
    // Preload sounds to avoid loading stutter.
    if (const oo::PList::Dict* sounds = customSounds.getIf<oo::PList::Dict>()) {
        for (const auto& [key, object] : *sounds) {
            if (object.isString()) {
                PreloadOneSound(*object.getIf<std::string>());
            } else if (object.isArray() && object.count() > 0) {
                for (const oo::PList& soundName : *object.getIf<oo::PList::Array>()) {
                    if (soundName.isString()) {
                        PreloadOneSound(*soundName.getIf<std::string>());
                    }
                }
            }
        }
    }

    // Afterburner sound doesn't go through customsounds.plist.
    PreloadOneSound("afterburner1.ogg");
}

- (void)populateSpaceFromActiveWormholes
{
    while (!activeWormholes.empty()) {
        @autoreleasepool {
            @try {
                WormholeEntity* whole = activeWormholes[0].get();
                // If the wormhole has been scanned by the player then the
                // PlayerEntity will take care of it
                if (![whole isScanned] && NSEqualPoints([PLAYER galaxy_coordinates], [whole destinationCoordinates])) {
                    // this is a wormhole to this system
                    [whole disgorgeShips];
                }
                RemoveFirstWormhole(activeWormholes); // empty it out
            }
            @catch (OOException* exception) {
                OO_LOG(cxx_kOOLogException, "Squashing exception during wormhole unpickling ({}: {}).", [exception name], [exception reason]);
            }
            @catch (OOFoundationException* exception) {
                OO_LOG(cxx_kOOLogException, "Squashing exception during wormhole unpickling ({}: {}).", oo::DescriptionOf([exception name]), oo::DescriptionOf([exception reason]));
            }
        }
    }
}

- (std::optional<std::string>)chooseStringForKey:(const std::string&)key inDictionary:(const oo::PList&)dictionary
{
    const oo::PList* object = dictionary.find(key);
    if (object == nullptr)
        return std::nullopt;
    if (object->isString())
        return *object->getIf<std::string>();
    else if (object->isArray() && object->count() > 0)
        return OptionalStringAt(*object, Ranrot() % object->count());
    return std::nullopt;
}

#if OO_LOCALIZATION_TOOLS

#if DEBUG_GRAPHVIZ
- (void)dumpDebugGraphViz
{
    if (oo::Defaults::standard().boolForKey("universe-dump-debug-graphviz")) {
        [self dumpSystemDescriptionGraphViz];
    }
}

namespace {

/*	EscapedGraphVizString(OOStringifySystemDescriptionLine(line, keyMap, NO)): the stringifier is
        the unmigrated OOConvertSystemDescriptions' (oo-xh1g), given Objective-C objects at the call;
        a nil line or result escaped to nil, which %@ printed as "(null)".
*/
std::string StringifiedLabel(id line, id keyMap)
{
    // oo-xh1g: stringify takes std::string / oo::PList; nil line still prints as "(null)".
    if (line == nil)
        return "(null)";
    return cxx_EscapedGraphVizString(OOStringifySystemDescriptionLine(oo::StdString(line), oo::PListFrom(keyMap), NO));
}

} // namespace

- (void)dumpSystemDescriptionGraphViz
{
    std::string graphViz;
    const oo::PList* systemDescriptions = nullptr;
    const oo::PList* thisDesc = nullptr;
    NSUInteger i, count, j, subCount;
    std::string descLine;
    const oo::PList* curses = nullptr;
    std::string label;
    oo::PList keyMap;

    keyMap = [ResourceManager cxx_dictionaryFromFilesNamed:"sysdesc_key_table.plist"
                                                  inFolder:std::string("Config")
                                                  andMerge:NO];
    const id keyMapObject = oo::ObjectFromPList(keyMap); // for the unmigrated stringifier

    graphViz = "// System description grammar:\n\n"
               "digraph system_descriptions\n"
               "{\n"
               "\tgraph [charset=\"UTF-8\", label=\"System description grammar\", labelloc=t, labeljust=l rankdir=LR compound=true nodesep=0.02 ranksep=1.5 concentrate=true fontname=Helvetica]\n"
               "\tedge [arrowhead=dot]\n"
               "\tnode [shape=none height=0.2 width=3 fontname=Helvetica]\n\t\n";

    systemDescriptions = [self cxx_descriptions]->get<oo::PList::Array>("system_description");
    count = (systemDescriptions != nullptr) ? systemDescriptions->count() : 0;

    // Add system-description-string as special node (it's the one thing that ties [14] to everything else).
    descLine = cxx_OOLookUpDescriptionPRIV("system-description-string");
    graphViz += oo::str::format("\tsystem_description_string [label=\"%s\" shape=ellipse]\n", StringifiedLabel(oo::NSStringFrom(descLine), keyMapObject).c_str());
    [self addNumericRefsInString:descLine
                      toGraphViz:graphViz
                        fromNode:"system_description_string"
                       nodeCount:count];
    graphViz += "\t\n";

    // Add special nodes for formatting codes
    graphViz += "\tpercent_I [label=\"%I\\nInhabitants\" shape=diamond]\n"
                "\tpercent_H [label=\"%H\\nSystem name\" shape=diamond]\n"
                "\tpercent_RN [label=\"%R/%N\\nRandom name\" shape=diamond]\n"
                "\tpercent_J [label=\"%J\\nNumbered system name\" shape=diamond]\n"
                "\tpercent_G [label=\"%G\\nNumbered system name in chart number\" shape=diamond]\n\t\n";

    // Toss in the Thargoid curses, too
    graphViz += "\tsubgraph cluster_thargoid_curses\n\t{\n\t\tlabel = \"Thargoid curses\"\n";
    curses = [self cxx_descriptions]->get<oo::PList::Array>("thargoid_curses");
    subCount = (curses != nullptr) ? curses->count() : 0;
    for (j = 0; j < subCount; ++j) {
        graphViz += oo::str::format("\t\tthargoid_curse_%zu [label=\"%s\"]\n", j, StringifiedLabel(oo::NSStringOrNil(OptionalStringAt(*curses, j)), keyMapObject).c_str());
    }
    graphViz += "\t}\n";
    for (j = 0; j < subCount; ++j) {
        [self addNumericRefsInString:OptionalStringAt(*curses, j).value_or(std::string())
                          toGraphViz:graphViz
                            fromNode:oo::str::format("thargoid_curse_%zu", j)
                           nodeCount:count];
    }
    graphViz += "\t\n";

    // The main show: the bits of systemDescriptions itself.
    // Define the nodes
    for (i = 0; i < count; ++i) {
        // Build label, using sysdesc_key_table.plist if available
        const oo::PList* keyLabel = keyMap.find(oo::str::format("%zu", i));
        if (keyLabel == nullptr)
            label = oo::str::format("[%zu]", i);
        else
            label = oo::str::format("[%zu] (%s)", i, oo::DescriptionOf(oo::ObjectFromPList(*keyLabel)).c_str());

        graphViz += oo::str::format("\tsubgraph cluster_%zu\n\t{\n\t\tlabel=\"%s\"\n", i, cxx_EscapedGraphVizString(label).c_str());

        thisDesc = systemDescriptions->at<oo::PList::Array>(i);
        subCount = (thisDesc != nullptr) ? thisDesc->count() : 0;
        for (j = 0; j < subCount; ++j) {
            graphViz += oo::str::format("\t\tn%zu_%zu [label=\"\\\"%s\\\"\"]\n", i, j, StringifiedLabel(oo::NSStringOrNil(OptionalStringAt(*thisDesc, j)), keyMapObject).c_str());
        }

        graphViz += "\t}\n";
    }
    graphViz += "\t\n";

    // Define the edges
    for (i = 0; i != count; ++i) {
        thisDesc = systemDescriptions->at<oo::PList::Array>(i);
        subCount = (thisDesc != nullptr) ? thisDesc->count() : 0;
        for (j = 0; j != subCount; ++j) {
            descLine = OptionalStringAt(*thisDesc, j).value_or(std::string());
            [self addNumericRefsInString:descLine
                              toGraphViz:graphViz
                                fromNode:oo::str::format("n%zu_%zu", i, j)
                               nodeCount:count];
        }
    }

    // Write file
    graphViz += "\t}\n";
    [ResourceManager cxx_writeDiagnosticData:oo::Data(graphViz.data(), graphViz.size()) toFileNamed:"SystemDescription.dot"];
}
#endif // DEBUG_GRAPHVIZ

// A missing line is "" here (the old nil receiver answered zeroed ranges and never ended the scan).
- (void)addNumericRefsInString:(const std::string&)string toGraphViz:(std::string&)graphViz fromNode:(const std::string&)fromNode nodeCount:(NSUInteger)nodeCount
{
    std::size_t start, end, remaining = 0;
    unsigned i;

    for (;;) {
        const std::size_t open = string.find('[', remaining);
        if (open == std::string::npos)
            break;
        start = open + 1;
        remaining = start;

        const std::size_t close = string.find(']', remaining);
        if (close == std::string::npos)
            break;
        end = close;
        remaining = end;

        const std::string index = string.substr(start, end - start);
        i = oo::str::intValue(index);

        // Each node gets a colour for its incoming edges. The multiplication and mod shuffle them to avoid adjacent nodes having similar colours.
        graphViz += oo::str::format("\t%s -> n%u_0 [color=\"%f,0.75,0.8\" lhead=cluster_%u]\n", fromNode.c_str(), i, ((float)(i * 511 % nodeCount)) / ((float)nodeCount), i);
    }

    if (string.find("%I") != std::string::npos) {
        graphViz += oo::str::format("\t%s -> percent_I [color=\"0,0,0.25\"]\n", fromNode.c_str());
    }
    if (string.find("%H") != std::string::npos) {
        graphViz += oo::str::format("\t%s -> percent_H [color=\"0,0,0.45\"]\n", fromNode.c_str());
    }
    if (string.find("%R") != std::string::npos || string.find("%N") != std::string::npos) {
        graphViz += oo::str::format("\t%s -> percent_RN [color=\"0,0,0.65\"]\n", fromNode.c_str());
    }

    // TODO: test graphViz output for "%Jxxx" and "%Gxxxxxx"
    if (string.find("%J") != std::string::npos) {
        graphViz += oo::str::format("\t%s -> percent_J [color=\"0,0,0.75\"]\n", fromNode.c_str());
    }

    if (string.find("%G") != std::string::npos) {
        graphViz += oo::str::format("\t%s -> percent_G [color=\"0,0,0.85\"]\n", fromNode.c_str());
    }
}

- (void)runLocalizationTools
{
    // Handle command line options to transform system_description array for easier localization

    BOOL compileSysDesc = NO, exportSysDesc = NO, xml = NO;

    for (const std::string& arg : oo::process::arguments()) {
        if (arg == "--compile-sysdesc")
            compileSysDesc = YES;
        else if (arg == "--export-sysdesc")
            exportSysDesc = YES;
        else if (arg == "--xml")
            xml = YES;
        else if (arg == "--openstep")
            xml = NO;
    }

    if (compileSysDesc)
        CompileSystemDescriptions(xml);
    if (exportSysDesc)
        ExportSystemDescriptions(xml);
}
#endif

#if NEW_PLANETS
// See notes at preloadPlanetTexturesForSystem:.
- (void)prunePreloadingPlanetMaterials
{
    [[OOAsyncWorkManager sharedAsyncWorkManager] completePendingTasks];

    NSUInteger i = _preloadingPlanetMaterials.size();
    while (i--) {
        if ([_preloadingPlanetMaterials[i].get() isFinishedLoading]) {
            _preloadingPlanetMaterials.erase(_preloadingPlanetMaterials.begin() + i);
        }
    }
}
#endif

- (void)loadConditionScripts
{
    conditionScripts.clear();
    // get list of names from cache manager (the cache is not migrated yet: its arrays of names arrive as strings)
    [self addConditionScripts:oo::StringsFrom([[OOCacheManager sharedCache] cxx_objectForKey:"equipment conditions" inCache:"condition scripts"])];

    [self addConditionScripts:oo::StringsFrom([[OOCacheManager sharedCache] cxx_objectForKey:"ship conditions" inCache:"condition scripts"])];

    [self addConditionScripts:oo::StringsFrom([[OOCacheManager sharedCache] cxx_objectForKey:"demoship conditions" inCache:"condition scripts"])];
}

- (void)addConditionScripts:(const std::vector<std::string>&)scripts
{
    for (const std::string& scriptname : scripts) {
        if (!conditionScripts.contains(scriptname)) {
            OOJSScript* script = [OOScript cxx_jsScriptFromFileNamed:scriptname properties:oo::PList()];
            if (script != nil) {
                conditionScripts[scriptname] = oo::ObjCRef<OOJSScript*>(script);
            }
        }
    }
}

- (OOJSScript*)cxx_getConditionScript:(const std::string&)scriptname
{
    const auto found = conditionScripts.find(scriptname);
    return (found != conditionScripts.end()) ? found->second.get() : nil;
}

@end

@implementation OOSound (OOCustomSounds)

+ (id)cxx_soundWithCustomSoundKey:(const std::string&)key
{
    const std::optional<std::string> fileName = [UNIVERSE soundNameForCustomSoundKey:key];
    if (!fileName.has_value())
        return nil;
    return [ResourceManager cxx_ooSoundNamed:*fileName inFolder:std::string("Sounds")];
}

- (id)initWithCustomSoundKey:(id)key // shared selector (proposed ADR-0043): an Objective-C string, as OOSoundSource's
{
    [self release];
    return [[OOSound cxx_soundWithCustomSoundKey:oo::StdString(key)] retain];
}

@end

@implementation OOSoundSource (OOCustomSounds)

+ (id)sourceWithCustomSoundKey:(const std::string&)key
{
    return [[[self alloc] initWithCustomSoundKey:oo::NSStringFrom(key)] autorelease];
}

- (id)initWithCustomSoundKey:(id)key // shared selector (proposed ADR-0043): an Objective-C string, as OOSound's
{
    OOSound* theSound = [OOSound cxx_soundWithCustomSoundKey:oo::StdString(key)];
    if (theSound != nil) {
        self = [self initWithSound:theSound];
    } else {
        [self release];
        self = nil;
    }
    return self;
}

- (void)cxx_playCustomSoundWithKey:(const std::string&)key
{
    OOSound* theSound = [OOSound cxx_soundWithCustomSoundKey:key];
    if (theSound != nil)
        [self playSound:theSound];
}

@end

std::string cxx_OOLookUpDescriptionPRIV(const std::string& key)
{
    std::optional<std::string> result = [UNIVERSE cxx_descriptionForKey:key];
    if (!result.has_value())
        result = key;
    return *result;
}

// There's a hint of gettext about this...
std::string cxx_OOLookUpPluralDescriptionPRIV(const std::string& key, NSInteger count)
{
    const oo::PList* descriptions = [UNIVERSE cxx_descriptions];
    const oo::PList* conditions = (descriptions != nullptr) ? descriptions->get<oo::PList::Array>("plural-rules") : nullptr;

    // are we using an older descriptions.plist (1.72.x) ?
    std::optional<std::string> tmp = [UNIVERSE cxx_descriptionForKey:key];
    if (tmp.has_value()) {
        static std::set<std::string> warned;

        if (!warned.contains(*tmp)) {
            OO_LOG_WARN("localization.plurals", "'{}' found in descriptions.plist, should be '{}%0'. Localization data needs updating.", key, key);
            warned.insert(*tmp);
        }
    }

    if (conditions == nullptr) {
        if (!tmp.has_value()) // this should mean that descriptions.plist is from 1.73 or above.
            return cxx_OOLookUpDescriptionPRIV(oo::str::format("%s%%%d", key.c_str(), (int)(count != 1)));
        // still using an older descriptions.plist
        return *tmp;
    }
    int unsigned i;
    long int index;

    for (index = i = 0; i < conditions->count(); ++index, ++i) {
        const std::optional<std::string> condition = OptionalStringAt(*conditions, i);
        if (!condition.has_value())
            break;
        const char* cond = condition->c_str();

        long int input = count;
        BOOL flag = NO; // we XOR test results with this

        while (isspace(*cond))
            ++cond;

        for (;;) {
            while (isspace(*cond))
                ++cond;

            char command = *cond++;

            switch (command) {
            case 0:
                goto passed; // end of string

            case '~':
                flag = !flag;
                continue;
            }

            long int param = strtol(cond, (char**)&cond, 10);

            switch (command) {
            case '#':
                index = param;
                continue;

            case '%':
                if (param < 2)
                    break; // ouch - fail this!
                input %= param;
                continue;

            case '=':
                if (flag ^ (input == param))
                    continue;
                break;
            case '!':
                if (flag ^ (input != param))
                    continue;
                break;

            case '<':
                if (flag ^ (input < param))
                    continue;
                break;
            case '>':
                if (flag ^ (input > param))
                    continue;
                break;
            }
            // if we arrive here, we have an unknown test or a test has failed
            break;
        }
    }

passed:
    return cxx_OOLookUpDescriptionPRIV(oo::str::format("%s%%%ld", key.c_str(), index));
}
