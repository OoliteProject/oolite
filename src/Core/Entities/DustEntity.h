/*

DustEntity.h

Entity representing a number of dust particles.

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

#pragma once

#include "Entity.h"
#include "OOOpenGLExtensionManager.h"
#include "OOTexture.h"
#include "OOGraphicsResetManager.h"

#include "oofnd/StdLib.hpp"

#if OO_SHADERS
#include "OOShaderProgram.h"
#include "OOShaderUniform.h"
#endif

#define DUST_SCALE			2000
#define DUST_N_PARTICLES	600

/*	C++ only since bead oo-9ht.77 deleted its Objective-C facade (proposed ADR-0056 amendment
	oo-0mxi): the universe makes it with oo::makeRef<DustEntity>() and init(), hands it to
	Objective-C with oo::NewEntityFacade, and finds it with dynamic_cast. It is its own graphics
	reset client (OOGraphicsResetClient), and the dust shader's uniforms are bound to its members
	(bead oo-t0e2m: OOShaderUniform's C++ target binding).
*/
class DustEntity : public Entity, public OOGraphicsResetClient
{
public:
	DustEntity() = default;
	~DustEntity() override;

	/*	-init's body after [super init] (the constructor ran Entity's), run once right after
		construction: it registers this with the graphics reset manager.
	*/
	void init();

	void setDustColor(OOColor *color);
	OOColor *dustColor();

	bool canCollide() override;
	void updateCameraRelativePosition() override;
	void update(OOTimeDelta delta_t) override;

#if OO_SHADERS
	OOShaderProgram *getShader();
	Vector offsetPlayerPosition();	// the dust shader's uOffsetPlayerPosition (bead oo-t0e2m)
#endif
	Vector warpVector();			// the dust shader's uWarp (bead oo-t0e2m)

	void drawImmediate(bool immediate, bool translucent) override;

	// OOGraphicsResetClient.
	void resetGraphicsState() override;

#ifndef NDEBUG
	std::optional<std::string> descriptionForObjDump() override;
#endif

private:
#if OO_SHADERS
	void checkShaderMode();
#endif

	oo::Ref<OOColor>	dust_color;
	Vector				vertices[DUST_N_PARTICLES * 2] = {};
	GLushort			indices[DUST_N_PARTICLES * 2] = {};
	GLfloat				color_fv[4] = {};
	oo::Ref<OOTexture>	texture;
	bool				hasPointSprites = {};
	bool				drawDust = {};
	
#if OO_SHADERS
	GLfloat				warpinessAttr[DUST_N_PARTICLES * 2] = {};
	oo::Ref<OOShaderProgram>	shader;
	std::vector<oo::Ref<OOShaderUniform>>	uniforms;
	uint8_t				shaderMode = {};
#endif
};
