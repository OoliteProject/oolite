/*

OOExhaustPlumeEntity.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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


#define kOverallAlpha		0.5f
#define kTimeStep			0.05


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
		Vector pos = { [definition oo_floatAtIndex:0], [definition oo_floatAtIndex:1], [definition oo_floatAtIndex:2] };
		[self setPosition:pos];
		Vector scale = { [definition oo_floatAtIndex:3], [definition oo_floatAtIndex:4], [definition oo_floatAtIndex:5] };
		_exhaustScale = scale;
	}
	
	return self;
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

// Moved this check to be earlier - CIM
	GLfloat speed = [ship speedFactor];
	// don't draw if not moving.
	if (EXPECT_NOT(speed <= 0.001f)) return;


	OOTimeAbsolute now = [UNIVERSE getTime];
	if ([UNIVERSE getTime] > _trackTime + kTimeStep)
	{
		[self saveToLastFrame];
		_trackTime = now;
	}

	GLfloat ex_emissive[4]	= {0.6f, 0.8f, 1.0f, 0.9f * kOverallAlpha};   // pale blue
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
	
	GLfloat hyper_fade = 8.0f / (8.0f + speed * speed * speed);
	
	GLfloat flare_factor = speed * ex_emissive[3] * hyper_fade;
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
	
	Vector currentPos = ship->position;
	Vector vfwd = [ship forwardVector];
	GLfloat	spd = 0.5 * [ship flightSpeed];
	vfwd = vector_multiply_scalar(vfwd, spd);
	Vector master_i = [ship rightVector];
	Vector vi,vj,vk;
	vi = master_i;
	vj = [ship upVector];
	vk = [ship forwardVector];
	zero.position = make_vector(currentPos.x + vi.x * position.x + vj.x * position.y + vk.x * position.z,
								currentPos.y + vi.y * position.x + vj.y * position.y + vk.y * position.z,
								currentPos.z + vi.z * position.x + vj.z * position.y + vk.z * position.z);
	
	GLfloat i01 = -0.03 * hyper_fade;
	GLfloat i03 = -0.12;
	GLfloat i06 = -0.25;
	GLfloat i08 = -0.32;
	GLfloat i10 = -0.40;
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
	
	ex_emissive[3] = flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = red_factor;		// diminish red part towards rear of exhaust
	_vertices[iv++] = f03.position.x + b03.x;// + zero.k.x * flare_factor * 4.0;
	_vertices[iv++] = f03.position.y + b03.y;// + zero.k.y * flare_factor * 4.0;
	_vertices[iv++] = f03.position.z + b03.z;// + zero.k.z * flare_factor * 4.0;
	_exhaustBaseColors[ci++] = ex_emissive[0];
	_exhaustBaseColors[ci++] = ex_emissive[1];
	_exhaustBaseColors[ci++] = ex_emissive[2];
	_exhaustBaseColors[ci++] = ex_emissive[3];
	
	ex_emissive[3] = 0.9 * flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.9 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.9 * red_factor;		// diminish red part towards rear of exhaust
	Vector k1 = f01.k;
	Vector j1 = cross_product(master_i, k1);
	Vector i1 = cross_product(j1, k1);
	
	f01.position = vector_subtract(zero.position, vk); // 1m out from zero
	
	i1.x *= _exhaustScale.x;	i1.y *= _exhaustScale.x;	i1.z *= _exhaustScale.x;
	j1.x *= _exhaustScale.y;	j1.y *= _exhaustScale.y;	j1.z *= _exhaustScale.y;
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
	
	ex_emissive[3] = 0.6 * flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.6 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.6 * red_factor;		// diminish red part towards rear of exhaust
	k1 = f03.k;
	i1 = vector_multiply_scalar(cross_product(j1, k1), _exhaustScale.x);
	j1 = vector_multiply_scalar(cross_product(master_i, k1), _exhaustScale.y);
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
	
	ex_emissive[3] = 0.4 * flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.4 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.4 * red_factor;		// diminish red part towards rear of exhaust
	k1 = f06.k;
	i1 = vector_multiply_scalar(cross_product(j1, k1), 0.8f * _exhaustScale.x);
	j1 = vector_multiply_scalar(cross_product(master_i, k1), 0.8f * _exhaustScale.y);
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
	
	ex_emissive[3] = 0.2 * flare_factor * kOverallAlpha;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.2 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.2 * red_factor;		// diminish red part towards rear of exhaust
	k1 = f08.k;
	i1 = vector_multiply_scalar(cross_product(j1, k1), 0.5f * _exhaustScale.x);
	j1 = vector_multiply_scalar(cross_product(master_i, k1), 0.5f * _exhaustScale.y);
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


GLuint tfan1[10] =    {	0,	1,	2,	3,	4,	5,	6,	7,	8,	1 };		// initial fan 0..9
GLuint qstrip1[18] =  {	1,	9,	2,	10,	3,	11,	4,	12,	5,	13,	6,	14,	7,	15,	8,	16,	1,	9 };		// first quadstrip 10..27
GLuint qstrip2[18] =  {	9,	17,	10,	18,	11,	19,	12,	20,	13,	21,	14,	22,	15,	23,	16,	24,	9,	17 };	// second quadstrip 28..45
GLuint qstrip3[18] =  {	17,	25,	18,	26,	19,	27,	20,	28,	21,	29,	22,	30,	23,	31,	24,	32,	17,	25 };	// third quadstrip 46..63
GLuint tfan2[10] =    {	33,	25,	26,	27,	28,	29,	30,	31,	32,	25 };	// final fan 64..73


- (void) drawSubEntity:(BOOL) immediate:(BOOL) translucent
{
	if (!translucent)  return;
	
	ShipEntity *ship = [self owner];
	if ([ship speedFactor] <= 0.0)  return;	// don't draw if there's no fire!
	
	OO_ENTER_OPENGL();
	
	OOGL(glPopMatrix());	// restore absolute positioning
	OOGL(glPushMatrix());	// avoid stack underflow
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	OOGL(glEnable(GL_BLEND));
	OOGL(glDepthMask(GL_FALSE));
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glDisable(GL_CULL_FACE));		// face culling
	OOGL(glShadeModel(GL_SMOOTH));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glVertexPointer(3, GL_FLOAT, 0, _vertices));
	OOGL(glEnableClientState(GL_COLOR_ARRAY));
	OOGL(glColorPointer(4, GL_FLOAT, 0, _exhaustBaseColors));
	OOGL(glDisableClientState(GL_NORMAL_ARRAY));
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	OOGL(glDisableClientState(GL_EDGE_FLAG_ARRAY));
	
	OOGL(glDrawElements(GL_TRIANGLE_FAN, 10, GL_UNSIGNED_INT, tfan1));
	OOGL(glDrawElements(GL_QUAD_STRIP, 18, GL_UNSIGNED_INT, qstrip1));
	OOGL(glDrawElements(GL_QUAD_STRIP, 18, GL_UNSIGNED_INT, qstrip2));
	OOGL(glDrawElements(GL_QUAD_STRIP, 18, GL_UNSIGNED_INT, qstrip3));
	OOGL(glDrawElements(GL_TRIANGLE_FAN, 10, GL_UNSIGNED_INT, tfan2));
	
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	
	OOGL(glPopAttrib());
}


#define PREV(n) ((n + kExhaustFrameCount - 1) % kExhaustFrameCount)
#define NEXT(n) ((n + 1) % kExhaustFrameCount)


- (void) saveToLastFrame
{
	ShipEntity *ship = [self owner];
	
	// Absolute position of self
	Vector framePos = OOVectorMultiplyMatrix([self position], [ship drawTransformationMatrix]);
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
	
	Vector posn;
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
	Vector framePos = OOVectorMultiplyMatrix([self position], [[self owner] drawTransformationMatrix]);
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

@end


@implementation Entity (OOExhaustPlume)

- (BOOL)isExhaust
{
	return NO;
}

@end
