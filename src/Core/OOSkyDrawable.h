/*

OOSkyDrawable.h

Drawable for the sky (i.e., the surrounding space, not planetary atmosphere).


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

#pragma once

#include "OODrawable.h"
#include "OOOpenGL.h"
#include "OOGraphicsResetManager.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"

class OOColor;
class OOSkyQuadSet;
struct OOSkyQuadDesc;


/*	Phase 3 (bead oo-4jjl, proposed ADR-0056 amendments oo-smy, oo-zffj, oo-mw4u and oo-4jjl): a
	drawable with no facade. Its one caller, SkyEntity, makes it with oo::makeRef and hands it to
	the entity (the root facade until bead oo-hahfg). It is a graphics reset client through the C++ client
	interface (amendment oo-jpd8 item 3), which this bead added.
*/
class OOSkyDrawable : public OODrawable, public OOGraphicsResetClient
{
public:
	// -initWithColor1:Color2:Color3:Color4:starCount:nebulaCount:nebulaHueFix:clusterFactor:alpha:scale:
	OOSkyDrawable(OOColor *color1,
				  OOColor *color2,
				  OOColor *color3,
				  OOColor *color4,
				  unsigned starCount,
				  unsigned nebulaCount,
				  bool nebulaHueFix,
				  float nebulaClusterFactor,
				  float nebulaAlpha,
				  float nebulaScale);
	~OOSkyDrawable() override;

	void renderOpaqueParts() override;
	bool hasOpaqueParts() override;
	GLfloat maxDrawDistance() override;
#ifndef NDEBUG
	std::vector<oo::Ref<OOTexture>> allTextures() override;
	size_t totalSize() override;
	size_t objectSize() const override	{ return sizeof *this; }
#endif

	// OOGraphicsResetClient
	void resetGraphicsState() override;

private:
	friend struct OOSkyDrawableTestAccess;

	void setUpStars(OOColor *color1, OOColor *color2);
	void setUpNebulae(OOColor *color1,
					  OOColor *color2,
					  float nebulaClusterFactor,
					  bool nebulaHueFix,
					  float nebulaAlpha,
					  float nebulaScale);

	void loadStarTextures();
	void loadNebulaTextures();

	void addQuads(OOSkyQuadDesc *quads, unsigned count);

	void ensureTexturesLoaded();

	// The unit test's stand-in for setUpStars(), which needs the game's star textures (decision
	// oo-jsx0h); null in the game.
	static void (*sSetUpStarsStandIn)(OOSkyDrawable *sky, OOColor *color1, OOColor *color2);

	unsigned				_starCount = {};
	unsigned				_nebulaCount = {};

	std::vector<oo::Ref<OOSkyQuadSet>>	_quadSets;	// no `= {}` (GCC, incomplete T; bead oo-1q4);	// one per texture (Foundation sweep, proposed ADR-0043)

	GLint					_displayListName = {};
};
