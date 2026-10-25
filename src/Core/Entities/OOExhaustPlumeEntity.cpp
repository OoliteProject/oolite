/*

OOExhaustPlumeEntity.m


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


#include "OOExhaustPlumeEntity.h"

#include "oofnd/PListGet.hpp"
#include "ShipEntity.h"
#include "Universe.h"
#include "OOMacroOpenGL.h"
#include "PlayerEntity.h"
#include "MyOpenGLView.h"

#include "OOTexture.h"
#include "OOGraphicsResetManager.h"
#include "OOJSExhaustPlume.h"


#define kOverallAlpha		1.0f
#define kTimeStep			0.05f
#define kFadeLevel1  0.4f
#define kFadeLevel2  0.2f
#define kFadeLevel3  0.02f
#define kScaleLevel1  1.0f
#define kScaleLevel2  0.8f
#define kScaleLevel3  0.6f

static OOTexture *sPlumeTexture = nil;


namespace {

// The plume texture's graphics reset client, which the façade class was until bead oo-9ht.110
// (ADR-0056 amendment oo-9ht.107 item 5): registered once, with the texture, and never destroyed.
class PlumeTextureResetClient : public OOGraphicsResetClient
{
public:
	void resetGraphicsState() override  { OOExhaustPlumeEntity::resetGraphicsState(); }
};

}	// namespace


oo::Ref<OOExhaustPlumeEntity> OOExhaustPlumeEntity::exhaustForShip(::ShipEntity *ship, const std::vector<std::string> &definition, float scale)
{
	oo::Ref<OOExhaustPlumeEntity> exhaust = oo::makeRef<OOExhaustPlumeEntity>();
	if (!exhaust->initForShip(ship, definition, (float)scale))  return nullptr;
	return exhaust;
}


bool OOExhaustPlumeEntity::initForShip(::ShipEntity *ship, const std::vector<std::string> &tokens, float scaleFactor)
{
	if (tokens.size() == 0)
	{
		return false;
	}

	// [super init] could not fail: the constructor ran Entity's -init body.
	{
		setOwner(ship);
		oo::PList::Array tokenList(tokens.begin(), tokens.end());
		const oo::PList definition(std::move(tokenList));	// at<float>: the conversion -oo_floatAtIndex: made
		HPVector pos = { definition.at<float>(0)*scaleFactor, definition.at<float>(1)*scaleFactor, definition.at<float>(2)*scaleFactor };
		setPosition(pos);
		// scale.z is special and *not* multiplied by scaleFactor
		Vector scale = { definition.at<float>(3)*scaleFactor, definition.at<float>(4)*scaleFactor, definition.at<float>(5) };
		setScale(scale);
	}

	return true;
}


Vector OOExhaustPlumeEntity::scale()
{
	return _exhaustScale;
}


void OOExhaustPlumeEntity::setScale(Vector scale)
{
	_exhaustScale = scale;
	if (scale.z < 0.5 || scale.z > 2.0)
	{
		_exhaustScale.z = 1.0;
	}
}


bool OOExhaustPlumeEntity::isExhaust()
{
	return YES;
}


double OOExhaustPlumeEntity::findCollisionRadius()
{
	return collision_radius;
}


void OOExhaustPlumeEntity::update(OOTimeDelta /*delta_t*/)
{
// Profiling: this function and subfunctions are expensive - CIM

	// don't draw if there's no ship, or if we're just jumping out of witchspace/docked at a station!
	::ShipEntity  *ship = oo::ToShip(owner());
// also don't draw if the ship isn't visible
	if (EXPECT_NOT(ship == nil || !(ship != nullptr ? ship->isVisible() : false) || ((ship != nullptr ? ship->getIsPlayer() : false) && (ship != nullptr ? ship->suppressFlightNotifications() : false)))) return;

	OOTimeAbsolute now = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	if ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) > _trackTime + kTimeStep)
	{
		saveToLastFrame();
		_trackTime = now;
	}

	//GLfloat ex_emissive[4]	= {0.7f, 0.9, 1.0f, 0.9f * kOverallAlpha};   // pale blue - old definition
	collision_radius = 0;
	GLfloat length;
	HPVector vertex;
	GLfloat ex_emissive[4];
	if (::OOColor *emissive = (ship != nullptr ? ship->exhaustEmissiveColor() : (OOColor *)nullptr))  emissive->getRed(&ex_emissive[0], &ex_emissive[1], &ex_emissive[2], &ex_emissive[3]);	// a nil colour left them as they were
	const GLfloat s1[8] = { 0.0, M_SQRT1_2, 1.0, M_SQRT1_2, 0.0, -M_SQRT1_2, -1.0, -M_SQRT1_2};
	const GLfloat c1[8] = { 1.0, M_SQRT1_2, 0.0, -M_SQRT1_2, -1.0, -M_SQRT1_2, 0.0, M_SQRT1_2};
	
	Quaternion shipQrotation = (ship != nullptr ? ship->normalOrientation() : Quaternion{});
	
	Frame zero =
	{
		.timeframe = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0),
		.position = {},
		.orientation = shipQrotation,
		.k = (ship != nullptr ? ship->forwardVector() : Vector{})
	};
	int dam = (ship != nullptr ? ship->damage() : int{});

	GLfloat speed = (ship != nullptr ? ship->speedFactor() : 0.0f);
	// don't draw if not moving.
	if (EXPECT_NOT(speed <= 0.001f)) return;
	
	GLfloat hyper_fade = 8.0f / (8.0f + speed * speed * speed);
	
	GLfloat flare_factor = fmaxf(speed,1.0) * ex_emissive[3] * hyper_fade;
	GLfloat red_factor = speed * ex_emissive[0] * (ranrot_rand() % 11) * 0.1f;	// random fluctuations
	GLfloat green_factor = speed * ex_emissive[1] * hyper_fade;
	
	if (speed > 1.0f)	// afterburner!
	{
		red_factor = 1.5;
	}
	
	if ((int)(ranrot_rand() % 50) < dam - 50)   // flicker the damaged engines
		red_factor = 0.0;
	if ((int)(ranrot_rand() % 40) < dam - 60)
		green_factor = 0.0;
	if ((int)(ranrot_rand() % 25) < dam - 75)
		flare_factor = 0.0;
	
	HPVector currentPos = ship->position;
	Vector vfwd = (ship != nullptr ? ship->forwardVector() : Vector{});
	GLfloat	spd = 0.5f * (ship != nullptr ? ship->getFlightSpeed() : 0.0f);
	vfwd = vector_multiply_scalar(vfwd, spd);
	Vector master_i = (ship != nullptr ? ship->rightVector() : Vector{});
	Vector vi,vj,vk;
	vi = master_i;
	vj = (ship != nullptr ? ship->upVector() : Vector{});
	vk = (ship != nullptr ? ship->forwardVector() : Vector{});
	zero.position = make_HPvector(currentPos.x + vi.x * position.x + vj.x * position.y + vk.x * position.z,
								currentPos.y + vi.y * position.x + vj.y * position.y + vk.y * position.z,
								currentPos.z + vi.z * position.x + vj.z * position.y + vk.z * position.z);
	
	GLfloat speedScale = fminf(1.0f,speed * 5.0f);

	GLfloat exhaust_factor = _exhaustScale.z;
	GLfloat i01 = -0.00f * hyper_fade;
	GLfloat i03 = -0.12f * exhaust_factor;
	GLfloat i06 = -0.25f * exhaust_factor;
	GLfloat i08 = -0.32f * exhaust_factor;
	GLfloat i10 = -0.40f * exhaust_factor;
	GLfloat q01 = i01/i10;	// factor for trail
	GLfloat q03 = i03/i10;
	GLfloat q06 = i06/i10;
	GLfloat q08 = i08/i10;
	GLfloat r01 = 1.0f - q01;	// factor for jet
	GLfloat r03 = 1.0f - q03;
	GLfloat r06 = 1.0f - q06;
	GLfloat r08 = 1.0f - q08;
	Frame	f01 = frameAtTime(i01, zero);
	Vector	b01 = make_vector(r01 * i01 * vfwd.x, r01 * i01 * vfwd.y, r01 * i01 * vfwd.z);
	Frame	f03 = frameAtTime(i03, zero);
	Vector	b03 = make_vector(r03 * i03 * vfwd.x, r03 * i03 * vfwd.y, r03 * i03 * vfwd.z);
	Frame	f06 = frameAtTime(i06, zero);
	Vector	b06 = make_vector(r06 * i06 * vfwd.x, r06 * i06 * vfwd.y, r06 * i06 * vfwd.z);
	Frame	f08 = frameAtTime(i08, zero);
	Vector	b08 = make_vector(r08 * i08 * vfwd.x, r08 * i08 * vfwd.y, r08 * i08 * vfwd.z);
	Frame	f10 = frameAtTime(i10, zero);
	
	int ci = 0;
	int iv = 0;
	int i;
	float r1;

//	f01.position = vector_subtract(zero.position, vk); // 1m out from zero
	f01.position = zero.position;

	ex_emissive[3] = flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = red_factor;		// diminish red part towards rear of exhaust
	vertex = HPvector_add(f01.position, vectorToHPVector(b01));
	collision_radius = HPmagnitude(HPvector_subtract(vertex, currentPos));
	_vertices[iv++] = vertex.x;// + zero.k.x * flare_factor * 4.0;
	_vertices[iv++] = vertex.y;// + zero.k.y * flare_factor * 4.0;
	_vertices[iv++] = vertex.z;// + zero.k.z * flare_factor * 4.0;
	_exhaustBaseColors[ci++] = ex_emissive[0];
	_exhaustBaseColors[ci++] = ex_emissive[1];
	_exhaustBaseColors[ci++] = ex_emissive[2];
	_exhaustBaseColors[ci++] = ex_emissive[3];


	Vector k1 = f01.k;
	Vector j1 = cross_product(master_i, k1);
	Vector i1 = vector_multiply_scalar(cross_product(j1, k1), _exhaustScale.x * speedScale);
	j1 = vector_multiply_scalar(j1, _exhaustScale.y * speedScale);

	for (i = 0; i < 8; i++)
	{
		vertex = HPvector_add(f01.position,
							  vectorToHPVector(vector_add(b01,
														  vector_add(vector_multiply_scalar(i1,s1[i]),
																	 vector_multiply_scalar(j1,c1[i])))));
		length = HPmagnitude(HPvector_subtract(vertex, currentPos));
		if (length > collision_radius)
		{
			collision_radius = length;
		}
		_vertices[iv++] = vertex.x;
		_vertices[iv++] = vertex.y;
		_vertices[iv++] = vertex.z;
		_exhaustBaseColors[ci++] = ex_emissive[0];
		_exhaustBaseColors[ci++] = ex_emissive[1];
		_exhaustBaseColors[ci++] = ex_emissive[2];
		_exhaustBaseColors[ci++] = ex_emissive[3];
	}

	ex_emissive[3] = kFadeLevel1 * flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = kFadeLevel1 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = kFadeLevel1 * red_factor;		// diminish red part towards rear of exhaust

	k1 = f03.k;
	i1 = vector_multiply_scalar(cross_product(j1, k1), _exhaustScale.x * kScaleLevel1 * speedScale);
	j1 = vector_multiply_scalar(cross_product(master_i, k1), _exhaustScale.y * kScaleLevel1 * speedScale);
	for (i = 0; i < 8; i++)
	{
		r1 = randf();
		vertex = HPvector_add(f03.position,
							  vectorToHPVector(vector_add(b03,
									   vector_add(vector_multiply_scalar(i1,s1[i]),
												  vector_add(vector_multiply_scalar(j1,c1[i]),
															 vector_multiply_scalar(k1,r1))))));
		length = HPmagnitude(HPvector_subtract(vertex, currentPos));
		if (length > collision_radius)
		{
			collision_radius = length;
		}
		_vertices[iv++] = vertex.x;
		_vertices[iv++] = vertex.y;
		_vertices[iv++] = vertex.z;
		_exhaustBaseColors[ci++] = ex_emissive[0];
		_exhaustBaseColors[ci++] = ex_emissive[1];
		_exhaustBaseColors[ci++] = ex_emissive[2];
		_exhaustBaseColors[ci++] = ex_emissive[3];
	}
	
	ex_emissive[3] = kFadeLevel2 * flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = kFadeLevel2 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = kFadeLevel2 * red_factor;		// diminish red part towards rear of exhaust

	k1 = f06.k;
	i1 = vector_multiply_scalar(cross_product(j1, k1), 0.8f * _exhaustScale.x * kScaleLevel2 * speedScale);
	j1 = vector_multiply_scalar(cross_product(master_i, k1), 0.8f * _exhaustScale.y * kScaleLevel2 * speedScale);
	for (i = 0; i < 8; i++)
	{
		r1 = randf();
		vertex = HPvector_add(f06.position,
							  vectorToHPVector(vector_add(b06,
									   vector_add(vector_multiply_scalar(i1,s1[i]),
												  vector_add(vector_multiply_scalar(j1,c1[i]),
															 vector_multiply_scalar(k1,r1))))));
		length = HPmagnitude(HPvector_subtract(vertex, currentPos));
		if (length > collision_radius)
		{
			collision_radius = length;
		}
		_vertices[iv++] = vertex.x;
		_vertices[iv++] = vertex.y;
		_vertices[iv++] = vertex.z;
		_exhaustBaseColors[ci++] = ex_emissive[0];
		_exhaustBaseColors[ci++] = ex_emissive[1];
		_exhaustBaseColors[ci++] = ex_emissive[2];
		_exhaustBaseColors[ci++] = ex_emissive[3];
	}
	
	ex_emissive[3] = kFadeLevel3 * flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = kFadeLevel3 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = kFadeLevel3 * red_factor;		// diminish red part towards rear of exhaust
	k1 = f08.k;
	i1 = vector_multiply_scalar(cross_product(j1, k1), 0.5f * _exhaustScale.x * kScaleLevel3 * speedScale);
	j1 = vector_multiply_scalar(cross_product(master_i, k1), 0.5f * _exhaustScale.y * kScaleLevel3 * speedScale);
	for (i = 0; i < 8; i++)
	{
		r1 = randf();
		vertex = HPvector_add(f08.position,
							  vectorToHPVector(vector_add(b08,
									   vector_add(vector_multiply_scalar(i1,s1[i]),
												  vector_add(vector_multiply_scalar(j1,c1[i]),
															 vector_multiply_scalar(k1,r1))))));
		length = HPmagnitude(HPvector_subtract(vertex, currentPos));
		if (length > collision_radius)
		{
			collision_radius = length;
		}
		_vertices[iv++] = vertex.x;
		_vertices[iv++] = vertex.y;
		_vertices[iv++] = vertex.z;
		_exhaustBaseColors[ci++] = ex_emissive[0];
		_exhaustBaseColors[ci++] = ex_emissive[1];
		_exhaustBaseColors[ci++] = ex_emissive[2];
		_exhaustBaseColors[ci++] = ex_emissive[3];
	}
	
	ex_emissive[3] = 0.0;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.0;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.0;	// diminish red part towards rear of exhaust
	length = HPmagnitude(HPvector_subtract(vertex, currentPos));
	if (length > collision_radius)
	{
		collision_radius = length;
	}
	_vertices[iv++] = f10.position.x;
	_vertices[iv++] = f10.position.y;
	_vertices[iv++] = f10.position.z;
	_exhaustBaseColors[ci++] = ex_emissive[0];
	_exhaustBaseColors[ci++] = ex_emissive[1];
	_exhaustBaseColors[ci++] = ex_emissive[2];
	_exhaustBaseColors[ci++] = ex_emissive[3];
	
	(void)iv; (void)ci;	// Suppress Clang static analyzer warnings.
}

static GLuint tfan1[10] =    {	0,	1,	2,	3,	4,	5,	6,	7,	8,	1 };		// initial fan 0..9

// normal polys
static GLuint tstr1[9] = {  1, 5, 9, 13, 17, 21, 25, 29, 33 };
static GLuint tstr2[9] = {  2, 6, 10, 14, 18, 22, 26, 30, 33 };
static GLuint tstr3[9] = {  3, 7, 11, 15, 19, 23, 27, 31, 33 };
static GLuint tstr4[9] = {  4, 8, 12, 16, 20, 24, 28, 32, 33 };

// aft-view special polys
static GLuint afttstr1[4] = {  1, 5, 25, 29 };
static GLuint afttstr2[4] = {  2, 6, 26, 30 };
static GLuint afttstr3[4] = {  3, 7, 27, 31 };
static GLuint afttstr4[4] = {  4, 8, 28, 32 };


static GLfloat pA[6] = { 0.01, 0.0, 2.0, 4.0, 6.0, 10.0 }; // phase adjustments


void OOExhaustPlumeEntity::drawSubEntityImmediate(bool /*immediate*/, bool translucent)
{
	if (!translucent)  return;

	::ShipEntity *ship = oo::ToShip(owner());
	if ((ship != nullptr ? ship->speedFactor() : 0.0f) <= 0.001f)  return;	// don't draw if not moving according to 'update' calculation

	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	
	OOGLPopModelView();
	OOGLPushModelView();
//	GLTranslateOOVector(vector_flip([self cameraRelativePosition]));
	HPVector cam = (PLAYER != nullptr ? PLAYER->viewpointPosition() : HPVector{});
	for (unsigned n=0;n<34*3;n++)
	{
		switch (n%3) 
		{
		case 0: // x coordinates
			_glVertices[n] = (GLfloat)(_vertices[n] - cam.x);
			break;
		case 1: // y coordinates
			_glVertices[n] = (GLfloat)(_vertices[n] - cam.y);
			break;
		case 2: // z coordinates
			_glVertices[n] = (GLfloat)(_vertices[n] - cam.z);
			break;
		}
	}
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	OOGL(glDisable(GL_LIGHTING));
	OOGL(glEnable(GL_BLEND));
	OOGL(glDepthMask(GL_FALSE));
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	OOGL(glEnable(GL_TEXTURE_2D));
	if (OOTexture *plume = texture())  plume->apply();	// a message to nil did nothing

//	OOGL(glDisable(GL_CULL_FACE));		// face culling
	OOGL(glShadeModel(GL_SMOOTH));
	
	OOGL(glEnableClientState(GL_COLOR_ARRAY));
	OOGL(glVertexPointer(3, GL_FLOAT, 0, _glVertices));
	OOGL(glColorPointer(4, GL_FLOAT, 0, _exhaustBaseColors));

	double intpart, dphase = 1.0-modf((double)(UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0)*2.5,&intpart);
	GLfloat phase = (GLfloat)dphase;

	GLfloat texCoords[68] = {
		0.5, phase+pA[0],

		0.1, phase+pA[1], 0.1, phase+pA[1], 
		0.1, phase+pA[1], 0.1, phase+pA[1], 
		0.9, phase+pA[1], 0.9, phase+pA[1], 
		0.9, phase+pA[1], 0.9, phase+pA[1],

		0.1, phase+pA[2], 0.1, phase+pA[2], 
		0.1, phase+pA[2], 0.1, phase+pA[2], 
		0.9, phase+pA[2], 0.9, phase+pA[2], 
		0.9, phase+pA[2], 0.9, phase+pA[2],

		0.1, phase+pA[3], 0.1, phase+pA[3], 
		0.1, phase+pA[3], 0.1, phase+pA[3], 
		0.9, phase+pA[3], 0.9, phase+pA[3], 
		0.9, phase+pA[3], 0.9, phase+pA[3],

		0.1, phase+pA[4], 0.1, phase+pA[4], 
		0.1, phase+pA[4], 0.1, phase+pA[4], 
		0.9, phase+pA[4], 0.9, phase+pA[4], 
		0.9, phase+pA[4], 0.9, phase+pA[4],

		0.5, phase+pA[5],
	};
	OOGL(glTexCoordPointer(2, GL_FLOAT, 0, texCoords));

	// reduced detail for internal view to avoid rendering artefacts
	if (oo::EntityIsPlayer(owner()) && (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) != VIEW_CUSTOM)
	{
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_INT, afttstr1));
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_INT, afttstr2));
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_INT, afttstr3));
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_INT, afttstr4));
	} 
	else
	{
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 9, GL_UNSIGNED_INT, tstr1));
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 9, GL_UNSIGNED_INT, tstr2));
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 9, GL_UNSIGNED_INT, tstr3));
		OOGL(glDrawElements(GL_TRIANGLE_STRIP, 9, GL_UNSIGNED_INT, tstr4));
	}

	/* Need a different texture and color array for this segment */
	GLfloat fanTextures[18] = {
		0.5f, 0.0f+phase,
		0.2f, 0.0f+phase,
		0.2f, 0.1f+phase,
		0.2f, 0.2f+phase,
		0.2f, 0.3f+phase,
		0.2f, 0.4f+phase,
		0.2f, 0.3f+phase,
		0.2f, 0.2f+phase,
		0.2f, 0.1f+phase
	};
	OOGL(glTexCoordPointer(2, GL_FLOAT, 0, fanTextures));
	
	GLfloat fanColors[36];
	GLfloat fr = _exhaustBaseColors[0], fg = _exhaustBaseColors[1], fb = _exhaustBaseColors[2];
	unsigned i = 0;
	fanColors[i++] = fr;
	fanColors[i++] = fg;
	fanColors[i++] = fb;
	fanColors[i++] = 1.0;
	for (;i<36;)
	{
		fanColors[i++] = fr;
		fanColors[i++] = fg;
		fanColors[i++] = fb;
		fanColors[i++] = 0.5;
	}
	OOGL(glColorPointer(4, GL_FLOAT, 0, fanColors));

	OOGL(glDrawElements(GL_TRIANGLE_FAN, 10, GL_UNSIGNED_INT, tfan1));

	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	OOGL(glDisable(GL_TEXTURE_2D));

	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	

	OOGL(glPopAttrib());
	
	OOVerifyOpenGLState();
}


#define PREV(n) ((n + kExhaustFrameCount - 1) % kExhaustFrameCount)
#define NEXT(n) ((n + 1) % kExhaustFrameCount)


void OOExhaustPlumeEntity::saveToLastFrame()
{
	::ShipEntity *ship = oo::ToShip(owner());
	
	// Absolute position of self
	// normally this would use the transformation matrix, but that
	// introduces inaccuracies
	// so just use the rotation matrix, then translate using HPVectors
	HPVector framePos = OOHPVectorMultiplyMatrix(getPosition(), (ship != nullptr ? ship->drawRotationMatrix() : OOMatrix{}));
	framePos = HPvector_add(framePos,(ship != nullptr ? ship->getPosition() : HPVector{}));
	Frame frame = { (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0), framePos, (ship != nullptr ? ship->normalOrientation() : Quaternion{}), (ship != nullptr ? ship->upVector() : Vector{}) };
	
	_track[_nextFrame] = frame;
	_nextFrame = (_nextFrame + 1) % kExhaustFrameCount;
}


Frame OOExhaustPlumeEntity::frameAtTime(double t_frame, Frame frame_zero)	// t_frame is relative to now ie. -0.5 = half a second ago.
{
	if (t_frame >= 0.0)  return frame_zero;
	
	Frame frame_one;
	
	int t1 = PREV(_nextFrame);
	double moment_in_time = frame_zero.timeframe + t_frame;
	double period, f0;
	
	if (moment_in_time > _trackTime)					// between the last saved frame and now
	{
		frame_one = _track[t1];	// last saved moment
		period = (moment_in_time - t_frame) - _trackTime;
		f0 = 1.0 + t_frame/period;
	}
	else if (moment_in_time < _track[_nextFrame].timeframe)	// more than kExhaustFrameCount frames back
	{
		return _track[_nextFrame];
	}
	else
	{
		while (moment_in_time < _track[t1].timeframe)
		{
			t1 = PREV(t1);
		}
		int t0 = NEXT(t1);
		
		frame_zero = _track[t0];
		frame_one = _track[t1];
		period = frame_zero.timeframe - frame_one.timeframe;
		f0 = (moment_in_time - _track[t1].timeframe)/period;
	}
	
	// interpolate
	double f1 = 1.0 - f0;
	
	HPVector posn;
	posn.x =	f0 * frame_zero.position.x + f1 * frame_one.position.x;
	posn.y =	f0 * frame_zero.position.y + f1 * frame_one.position.y;
	posn.z =	f0 * frame_zero.position.z + f1 * frame_one.position.z;
	Quaternion qrot;
	qrot.w =	(float)f0 * frame_zero.orientation.w + (float)f1 * frame_one.orientation.w;
	qrot.x =	(float)f0 * frame_zero.orientation.x + (float)f1 * frame_one.orientation.x;
	qrot.y =	(float)f0 * frame_zero.orientation.y + (float)f1 * frame_one.orientation.y;
	qrot.z =	(float)f0 * frame_zero.orientation.z + (float)f1 * frame_one.orientation.z;
	
	Frame result;
	result.position = posn;
	result.orientation = qrot;
	result.timeframe = moment_in_time;
	result.k = vector_forward_from_quaternion(qrot);
	return result;
}


void OOExhaustPlumeEntity::resetPlume()
{
	/*ShipEntity *ship = [self owner];
	
	// Absolute position of self
	Vector framePos = OOVectorMultiplyMatrix([self position], [ship drawTransformationMatrix]);
	Frame frame = { (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0), framePos, [ship normalOrientation], [ship upVector] };
	
	_track[_nextFrame] = frame;
	_nextFrame = (_nextFrame + 1) % kExhaustFrameCount;*/
	_nextFrame = 0;
	HPVector framePos = OOHPVectorMultiplyMatrix(getPosition(), (owner() != nullptr ? owner()->drawTransformationMatrix() : OOMatrix{}));	// a message to nil's zero matrix
	uint8_t i;
	for (i = 0; i < kExhaustFrameCount; i++)
	{
		_track[i].timeframe = 0.0;
		_track[i].position = framePos;
		_track[i].orientation = kIdentityQuaternion;
		_track[i].k = kZeroVector;
	}
}


void OOExhaustPlumeEntity::rescaleBy(GLfloat factor)
{
	_exhaustScale = vector_multiply_scalar(_exhaustScale, factor);
}


void OOExhaustPlumeEntity::rescaleBy(GLfloat /*factor*/, bool /*writeToCache*/)
{
	/* Do nothing; this is only needed because of OOEntityWithDrawable
	   implementation requirements */
}


OOTexture *OOExhaustPlumeEntity::texture()
{
	return OOExhaustPlumeEntity::plumeTexture();
}


void OOExhaustPlumeEntity::setUpTexture()
{
	if (sPlumeTexture == nil)
	{
		sPlumeTexture = OOTexture::textureWithName("oolite-exhaust-blur.png", "Textures", kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask | kOOTextureRepeatT | kOOTextureRepeatS, kOOTextureDefaultAnisotropy / 2.0, 0.0).leakRef();
		OOGraphicsResetManager::sharedManager()->registerCxxClient(new PlumeTextureResetClient);

	}
}


OOTexture *OOExhaustPlumeEntity::plumeTexture()
{
	if (sPlumeTexture == nil)  setUpTexture();
	return sPlumeTexture;
}


void OOExhaustPlumeEntity::resetGraphicsState()
{
	oo::release(sPlumeTexture);
	sPlumeTexture = nullptr;
}


// The binding's bodies (OOJSExhaustPlume.mm), which the façade forwarded to until bead oo-9ht.110.
void OOExhaustPlumeEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSExhaustPlumeGetJSClass(outClass, outPrototype);
}


std::optional<std::string> OOExhaustPlumeEntity::jsClassName()
{
	return ::OOJSExhaustPlumeJSClassName();
}


bool OOExhaustPlumeEntity::isVisibleToScripts()
{
	return ::OOJSExhaustPlumeIsVisibleToScripts();
}
