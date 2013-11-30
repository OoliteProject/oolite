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


#import "OOExhaustPlumeEntity.h"
#import "OOCollectionExtractors.h"
#import "ShipEntity.h"
#import "Universe.h"
#import "OOMacroOpenGL.h"
#import "PlayerEntity.h"

#import "OOTexture.h"
#import "OOGraphicsResetManager.h"


#define kOverallAlpha		1.0f
#define kTimeStep			0.05f
#define kFadeLevel1  0.4f
#define kFadeLevel2  0.2f
#define kFadeLevel3  0.02f
#define kScaleLevel1  1.0f
#define kScaleLevel2  0.8f
#define kScaleLevel3  0.6f

static OOTexture *sPlumeTexture = nil;


@interface OOExhaustPlumeEntity (Private)

- (void) saveToLastFrame;
- (Frame) frameAtTime:(double) t_frame fromFrame:(Frame) frame_zero;	// t_frame is relative to now ie. -0.5 = half a second ago.

@end


@implementation OOExhaustPlumeEntity

+ (id) exhaustForShip:(ShipEntity *)ship withDefinition:(NSArray *)definition
{
	return [[[self alloc] initForShip:ship withDefinition:definition] autorelease];
}


- (id) initForShip:(ShipEntity *)ship withDefinition:(NSArray *)definition
{
	if ([definition count] == 0)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		[self setOwner:ship];
		HPVector pos = { [definition oo_floatAtIndex:0], [definition oo_floatAtIndex:1], [definition oo_floatAtIndex:2] };
		[self setPosition:pos];
		Vector scale = { [definition oo_floatAtIndex:3], [definition oo_floatAtIndex:4], [definition oo_floatAtIndex:5] };
		[self setScale:scale];
	}
	
	return self;
}


- (Vector) scale
{
	return _exhaustScale;
}


- (void) setScale:(Vector)scale
{
	_exhaustScale = scale;
	if (scale.z < 0.5 || scale.z > 2.0)
	{
		_exhaustScale.z = 1.0;
	}
}


- (BOOL)isExhaust
{
	return YES;
}


- (double)findCollisionRadius
{
	return 0;	// FIXME: something sensible. Where does plume length come from anyway?
}


- (void) update:(OOTimeDelta) delta_t
{
// Profiling: this function and subfunctions are expensive - CIM

	// don't draw if there's no ship, or if we're just jumping out of witchspace/docked at a station!
	ShipEntity  *ship = [self owner];
// also don't draw if the ship isn't visible
	if (EXPECT_NOT(ship == nil || ![ship isVisible] || ([ship isPlayer] && [ship suppressFlightNotifications]))) return;

	OOTimeAbsolute now = [UNIVERSE getTime];
	if ([UNIVERSE getTime] > _trackTime + kTimeStep)
	{
		[self saveToLastFrame];
		_trackTime = now;
	}

	//GLfloat ex_emissive[4]	= {0.7f, 0.9, 1.0f, 0.9f * kOverallAlpha};   // pale blue - old definition
	GLfloat ex_emissive[4];
	[[ship exhaustEmissiveColor] getRed:&ex_emissive[0] green:&ex_emissive[1] blue:&ex_emissive[2] alpha:&ex_emissive[3]];
	const GLfloat s1[8] = { 0.0, M_SQRT1_2, 1.0, M_SQRT1_2, 0.0, -M_SQRT1_2, -1.0, -M_SQRT1_2};
	const GLfloat c1[8] = { 1.0, M_SQRT1_2, 0.0, -M_SQRT1_2, -1.0, -M_SQRT1_2, 0.0, M_SQRT1_2};
	
	Quaternion shipQrotation = [ship normalOrientation];
	
	Frame zero =
	{
		.timeframe = [UNIVERSE getTime],
		.orientation = shipQrotation,
		.k = [ship forwardVector]
	};
	int dam = [ship damage];

	GLfloat speed = [ship speedFactor];
	// don't draw if not moving.
	if (EXPECT_NOT(speed <= 0.001f)) return;
	
	GLfloat hyper_fade = 8.0f / (8.0f + speed * speed * speed);
	
	GLfloat flare_factor = fmaxf(speed,1.0) * ex_emissive[3] * hyper_fade;
	GLfloat red_factor = speed * ex_emissive[0] * (ranrot_rand() % 11) * 0.1;	// random fluctuations
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
	Vector vfwd = [ship forwardVector];
	GLfloat	spd = 0.5 * [ship flightSpeed];
	vfwd = vector_multiply_scalar(vfwd, spd);
	Vector master_i = [ship rightVector];
	Vector vi,vj,vk;
	vi = master_i;
	vj = [ship upVector];
	vk = [ship forwardVector];
	zero.position = make_HPvector(currentPos.x + vi.x * position.x + vj.x * position.y + vk.x * position.z,
								currentPos.y + vi.y * position.x + vj.y * position.y + vk.y * position.z,
								currentPos.z + vi.z * position.x + vj.z * position.y + vk.z * position.z);
	
	GLfloat speedScale = fminf(1.0,speed*5.0);

	GLfloat exhaust_factor = _exhaustScale.z;
	GLfloat i01 = -0.00 * hyper_fade;
	GLfloat i03 = -0.12 * exhaust_factor;
	GLfloat i06 = -0.25 * exhaust_factor;
	GLfloat i08 = -0.32 * exhaust_factor;
	GLfloat i10 = -0.40 * exhaust_factor;
	GLfloat q01 = i01/i10;	// factor for trail
	GLfloat q03 = i03/i10;
	GLfloat q06 = i06/i10;
	GLfloat q08 = i08/i10;
	GLfloat r01 = 1.0 - q01;	// factor for jet
	GLfloat r03 = 1.0 - q03;
	GLfloat r06 = 1.0 - q06;
	GLfloat r08 = 1.0 - q08;
	Frame	f01 = [self frameAtTime: i01 fromFrame: zero];
	Vector	b01 = make_vector(r01 * i01 * vfwd.x, r01 * i01 * vfwd.y, r01 * i01 * vfwd.z);
	Frame	f03 = [self frameAtTime: i03 fromFrame: zero];
	Vector	b03 = make_vector(r03 * i03 * vfwd.x, r03 * i03 * vfwd.y, r03 * i03 * vfwd.z);
	Frame	f06 = [self frameAtTime: i06 fromFrame: zero];
	Vector	b06 = make_vector(r06 * i06 * vfwd.x, r06 * i06 * vfwd.y, r06 * i06 * vfwd.z);
	Frame	f08 = [self frameAtTime: i08 fromFrame: zero];
	Vector	b08 = make_vector(r08 * i08 * vfwd.x, r08 * i08 * vfwd.y, r08 * i08 * vfwd.z);
	Frame	f10 = [self frameAtTime: i10 fromFrame: zero];
	
	int ci = 0;
	int iv = 0;
	int i;
	float r1;

//	f01.position = vector_subtract(zero.position, vk); // 1m out from zero
	f01.position = zero.position;

	ex_emissive[3] = flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = red_factor;		// diminish red part towards rear of exhaust
	_vertices[iv++] = f01.position.x + b01.x;// + zero.k.x * flare_factor * 4.0;
	_vertices[iv++] = f01.position.y + b01.y;// + zero.k.y * flare_factor * 4.0;
	_vertices[iv++] = f01.position.z + b01.z;// + zero.k.z * flare_factor * 4.0;
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
		_vertices[iv++] = f01.position.x + b01.x + s1[i] * i1.x + c1[i] * j1.x;
		_vertices[iv++] = f01.position.y + b01.y + s1[i] * i1.y + c1[i] * j1.y;
		_vertices[iv++] = f01.position.z + b01.z + s1[i] * i1.z + c1[i] * j1.z;
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
		_vertices[iv++] = f03.position.x + b03.x + s1[i] * i1.x + c1[i] * j1.x + r1 * k1.x;
		_vertices[iv++] = f03.position.y + b03.y + s1[i] * i1.y + c1[i] * j1.y + r1 * k1.y;
		_vertices[iv++] = f03.position.z + b03.z + s1[i] * i1.z + c1[i] * j1.z + r1 * k1.z;
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
		_vertices[iv++] = f06.position.x + b06.x + s1[i] * i1.x + c1[i] * j1.x + r1 * k1.x;
		_vertices[iv++] = f06.position.y + b06.y + s1[i] * i1.y + c1[i] * j1.y + r1 * k1.y;
		_vertices[iv++] = f06.position.z + b06.z + s1[i] * i1.z + c1[i] * j1.z + r1 * k1.z;
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
		_vertices[iv++] = f08.position.x + b08.x + s1[i] * i1.x + c1[i] * j1.x + r1 * k1.x;
		_vertices[iv++] = f08.position.y + b08.y + s1[i] * i1.y + c1[i] * j1.y + r1 * k1.y;
		_vertices[iv++] = f08.position.z + b08.z + s1[i] * i1.z + c1[i] * j1.z + r1 * k1.z;
		_exhaustBaseColors[ci++] = ex_emissive[0];
		_exhaustBaseColors[ci++] = ex_emissive[1];
		_exhaustBaseColors[ci++] = ex_emissive[2];
		_exhaustBaseColors[ci++] = ex_emissive[3];
	}
	
	ex_emissive[3] = 0.0;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.0;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.0;	// diminish red part towards rear of exhaust
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


- (void) drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
	if (!translucent)  return;
	
	ShipEntity *ship = [self owner];
	if ([ship speedFactor] <= 0.001f)  return;	// don't draw if not moving according to 'update' calculation

	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	
	OOGL(glPopMatrix());	// restore absolute positioning
	OOGL(glPushMatrix());	// avoid stack underflow
//	GLTranslateOOVector(vector_flip([self cameraRelativePosition]));
	HPVector cam = [PLAYER viewpointPosition];
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
	[[self texture] apply];

//	OOGL(glDisable(GL_CULL_FACE));		// face culling
	OOGL(glShadeModel(GL_SMOOTH));
	
	OOGL(glEnableClientState(GL_COLOR_ARRAY));
	OOGL(glVertexPointer(3, GL_FLOAT, 0, _glVertices));
	OOGL(glColorPointer(4, GL_FLOAT, 0, _exhaustBaseColors));

	double intpart, dphase = 1.0-modf((double)[UNIVERSE getTime]*2.5,&intpart);
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
	if ([[self owner] isPlayer] && [UNIVERSE viewDirection] != VIEW_CUSTOM)
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
		0.5, 0.0+phase,
		0.2, 0.0+phase,
		0.2, 0.1+phase,
		0.2, 0.2+phase,
		0.2, 0.3+phase,
		0.2, 0.4+phase,
		0.2, 0.3+phase,
		0.2, 0.2+phase,
		0.2, 0.1+phase
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


- (void) saveToLastFrame
{
	ShipEntity *ship = [self owner];
	
	// Absolute position of self
	// normally this would use the transformation matrix, but that
	// introduces inaccuracies
	// so just use the rotation matrix, then translate using HPVectors
	HPVector framePos = OOHPVectorMultiplyMatrix([self position], [ship drawRotationMatrix]);
	framePos = HPvector_add(framePos,[ship position]);
	Frame frame = { [UNIVERSE getTime], framePos, [ship normalOrientation], [ship upVector] };
	
	_track[_nextFrame] = frame;
	_nextFrame = (_nextFrame + 1) % kExhaustFrameCount;
}


- (Frame) frameAtTime:(double)t_frame fromFrame:(Frame) frame_zero	// t_frame is relative to now ie. -0.5 = half a second ago.
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
	qrot.w =	f0 * frame_zero.orientation.w + f1 * frame_one.orientation.w;
	qrot.x =	f0 * frame_zero.orientation.x + f1 * frame_one.orientation.x;
	qrot.y =	f0 * frame_zero.orientation.y + f1 * frame_one.orientation.y;
	qrot.z =	f0 * frame_zero.orientation.z + f1 * frame_one.orientation.z;
	
	Frame result;
	result.position = posn;
	result.orientation = qrot;
	result.timeframe = moment_in_time;
	result.k = vector_forward_from_quaternion(qrot);
	return result;
}


- (void) resetPlume
{
	/*ShipEntity *ship = [self owner];
	
	// Absolute position of self
	Vector framePos = OOVectorMultiplyMatrix([self position], [ship drawTransformationMatrix]);
	Frame frame = { [UNIVERSE getTime], framePos, [ship normalOrientation], [ship upVector] };
	
	_track[_nextFrame] = frame;
	_nextFrame = (_nextFrame + 1) % kExhaustFrameCount;*/
	_nextFrame = 0;
	HPVector framePos = OOHPVectorMultiplyMatrix([self position], [[self owner] drawTransformationMatrix]);
	uint8_t i;
	for (i = 0; i < kExhaustFrameCount; i++)
	{
		_track[i].timeframe = 0.0;
		_track[i].position = framePos;
		_track[i].orientation = kIdentityQuaternion;
		_track[i].k = kZeroVector;
	}
}


- (void) rescaleBy:(GLfloat)factor
{
	_exhaustScale = vector_multiply_scalar(_exhaustScale, factor);
}


- (OOTexture *) texture
{
	return [OOExhaustPlumeEntity plumeTexture];
}


+ (void) setUpTexture
{
	if (sPlumeTexture == nil)
	{
		sPlumeTexture = [[OOTexture textureWithName:@"oolite-exhaust-blur.png"
										  inFolder:@"Textures"
										   options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask | kOOTextureRepeatT | kOOTextureRepeatS
										anisotropy:kOOTextureDefaultAnisotropy / 2.0
										   lodBias:0.0] retain];
		[[OOGraphicsResetManager sharedManager] registerClient:(id<OOGraphicsResetClient>)[OOExhaustPlumeEntity class]];

	}
}


+ (OOTexture *) plumeTexture
{
	if (sPlumeTexture == nil)  [self setUpTexture];
	return sPlumeTexture;
}


+ (void) resetGraphicsState
{
	[sPlumeTexture release];
	sPlumeTexture = nil;
}


@end


@implementation Entity (OOExhaustPlume)

- (BOOL)isExhaust
{
	return NO;
}

@end
