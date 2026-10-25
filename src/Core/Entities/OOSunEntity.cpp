/*

OOSunEntity.m

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

#include "OOSunEntity.h"
#include "OOJSSun.h"
#include "OOPlanetEntity.h"
#include "OOOpenGLExtensionManager.h"
#include "OOMacroOpenGL.h"

#include "Universe.h"
#include "AI.h"
#include "MyOpenGLView.h"
#include "ShipEntityAI.h"
#include "OOColor.h"
#include "OOCharacter.h"
#include "OOStringParsing.h"
#include "PlayerEntity.h"
#include "OODebugFlags.h"
#include "OOStringExpander.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"

#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

bool OOSunEntity::setSunColor(OOColor *sun_colorIn)
{
	if (sun_colorIn == nullptr) return NO;

	OO_ENTER_OPENGL();

	float		hue, sat, bri, alf;
	oo::Ref<OOColor>	color;

	// blend some white into the sun color to brighten it up
	const oo::Ref<OOColor> sun_color = sun_colorIn->blendedColorWithFraction(0.3, OOColor::whiteColor().get());

	sun_color->getHue(&hue, &sat, &bri, &alf);
	hue /= 360;
	
/*
	// FIXME: do away with hue_drift altogether?
	// The following two lines are functionally identical to 1.73:
	randf();randf();	// avoid ranrot dirft!
	float hue_drift = 0.0f;
*/
	
	// anything more than a minimal hue drift will wipe out the original colour.
	float hue_drift = 0.0038f * fabsf(randf() - randf());
	
	// set the lighting color for the sun
	GLfloat		r,g,b,a;
	sun_color->getRed(&r, &g, &b, &a);
	
	GLfloat		sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// real ambient light inside gl_LightModel.ambient
	sun_diffuse[0] = 0.5f * (1.0f + r);	// paler
	sun_diffuse[1] = 0.5f * (1.0f + g);	// paler
	sun_diffuse[2] = 0.5f * (1.0f + b);	// paler
	sun_diffuse[3] = 1.0;
	sun_specular[0] = r;
	sun_specular[1] = g;
	sun_specular[2] = b;
	sun_specular[3] = 1.0;
	
	OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
	OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
	OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
	
	// main disc less saturation (partially taken care of by the ACES tonemapper) more brightness
	color = OOColor::colorWithHue(hue, sat * 0.75f, 1.0f, 1.0f);
	// our OpenGL color values are unclamped, so we can multiply the color components by
	// any value we want, in order to make the sun a truly bright object in the sky
	color = OOColor::colorWithRed(color->redComponent() * _sunBrightnessFactor, color->greenComponent() * _sunBrightnessFactor, color->blueComponent() * _sunBrightnessFactor, color->alphaComponent());
	color->getRed(&discColor[0], &discColor[1], &discColor[2], &discColor[3]);
	
	/*	Two inner corona layers with low alpha and saturation are additively
		blended with main corona. This produces something vaguely like a bloom
		effect.
	*/
	hue += hue_drift * 3;
	// saturation = 1 would shift white to red
	color = OOColor::colorWithHue(hue, OOClamp_0_1_f(sat*1.0f), bri * 0.75f, 0.45f);
	color = OOColor::colorWithRed(color->redComponent() * _sunBrightnessFactor, color->greenComponent() * _sunBrightnessFactor, color->blueComponent() * _sunBrightnessFactor, color->alphaComponent());
	color->getRed(&outerCoronaColor[0], &outerCoronaColor[1], &outerCoronaColor[2], &outerCoronaColor[3]);
	
	return YES;
}


void OOSunEntity::initSunWithColor(OOColor *sun_color, const oo::PList &dict)
{
	int			i;

	// self = [super init]: the constructor ran Entity's -init body.
	
	collision_radius = 100000.0; //  100km across
	
	scanClass = CLASS_NO_DRAW;
	
	{
		oo::Defaults &prefs = oo::Defaults::standard();
		const oo::PList sbf = prefs.object("sbf");
		_sunBrightnessFactor = oo::PListGet<float>::from(sbf.isNull() ? nullptr : &sbf, 80.0f);
		const oo::PList scaf = prefs.object("scaf");
		_sunCoronaAlphaFactor = oo::PListGet<float>::from(scaf.isNull() ? nullptr : &scaf, 0.005f);
	}
	
	setSunColor(sun_color);

	// A nil dictionary read nil for the name (messaging nil), not the default.
	setName(dict ? cxx_OOExpand(dict.get<std::string>(std::string(KEY_SUNNAME), "[oolite-default-star-name]")) : std::nullopt);

	corona_blending=OOClamp_0_1_f(dict.get<float>("corona_hues", 1.0f));
	corona_speed_factor=dict.get<float>("corona_shimmer", -1.0);
	if(corona_speed_factor<0)
	{
		// from .22222 to 2
		corona_speed_factor = 1.0 / (0.5 + 2.0 * (randf() + randf()));
	}
	else
	{
		//on average:  0 = .25 , 1 = 2.25  -  the same sun should give the same random component
		corona_speed_factor=OOClamp_0_1_f(corona_speed_factor) * 2.0 + randf() * randf();
	}
#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "corona_shimmer = {:f}", corona_speed_factor);
#endif

	corona_stage = 0.0;
	for (i = 0; i < SUN_CORONA_SAMPLES; i++)
		rvalue[i] = randf();
	
	// set up the radius properties
	changeSunProperty("sun_radius", dict);
	
	unsigned k = 0;
	for (unsigned i=0 ; i < 360 ; i++)
	{
		unsigned j = (i+1)%360;
// disc
		sunTriangles[k++] = 0;
		sunTriangles[k++] = 1+i;
		sunTriangles[k++] = 1+j;
	}
	for (unsigned i=0 ; i < 360 ; i++)
	{
		unsigned j = (i+1)%360;
// ring 1
		sunTriangles[k++] = 1+i;
		sunTriangles[k++] = 1+j;
		sunTriangles[k++] = 361+i;
		sunTriangles[k++] = 1+j;
		sunTriangles[k++] = 361+i;
		sunTriangles[k++] = 361+j;
// ring 2
		sunTriangles[k++] = 361+i;
		sunTriangles[k++] = 361+j;
		sunTriangles[k++] = 721+i;
		sunTriangles[k++] = 361+j;
		sunTriangles[k++] = 721+i;
		sunTriangles[k++] = 721+j;
// ring 3
		sunTriangles[k++] = 721+i;
		sunTriangles[k++] = 721+j;
		sunTriangles[k++] = 1081+i;
		sunTriangles[k++] = 721+j;
		sunTriangles[k++] = 1081+i;
		sunTriangles[k++] = 1081+j;
// ring 4
		sunTriangles[k++] = 1081+i;
		sunTriangles[k++] = 1081+j;
		sunTriangles[k++] = 1441+i;
		sunTriangles[k++] = 1081+j;
		sunTriangles[k++] = 1441+i;
		sunTriangles[k++] = 1441+j;
	}
}


std::optional<std::string> OOSunEntity::descriptionComponents() const
{
	// The getters read these members (or answer from them).
	OOSunEntity *sun = const_cast<OOSunEntity *>(this);
	std::string result = oo::str::format("ID: %u position: %s radius: %.3fkm", universalID, cxx_HPVectorDescription(position).c_str(), 0.001 * sun->radius());
	if (sun->goneNova())
	{
		result += " (gone nova)";
	}
	else if (sun->willGoNova())
	{
		result += " (will go nova)";
	}

	return result;
}


bool OOSunEntity::canCollide()
{
	return YES;
}


#ifndef NDEBUG
bool OOSunEntity::checkCloseCollisionWith(Entity *other)
{
	if (gDebugFlags & DEBUG_COLLISIONS)
	{
		OO_LOG("sun.collide", "{}", "SUN Collision!");
	}
	
	return Entity::checkCloseCollisionWith(other);
}
#endif


void OOSunEntity::update(OOTimeDelta delta_t)
{
	Entity::update(delta_t);
	
	::PlayerEntity	*player = PLAYER;
	assert(player != nil);
	rotMatrix = OOMatrixForBillboard(position, (player != nullptr ? player->viewpointPosition() : HPVector{}));
	
	if (throw_sparks && _novaExpansionRate > 0.0f)	// going NOVA!
	{
		if (_novaCountdown >= 0.0)	// countdown
		{
			_novaCountdown -= delta_t;
			if (corona_speed_factor < 5.0)
			{
				corona_speed_factor += 0.75 * delta_t;
			}
		}
		else
		{
			if (_novaExpansionTimer <= 60.0)	// expand for a minute
			{
				double sky_bri = 1.0 - 1.5 * _novaExpansionTimer;
				if (sky_bri < 0)
				{
					if (UNIVERSE != nullptr)  UNIVERSE->setSkyColorRed(0.0f,		// back to black
									   0.0f,
										0.0f,
									   0.0f);
				}
				else
				{
					if (UNIVERSE != nullptr)  UNIVERSE->setSkyColorRed(sky_bri,	// whiteout
									   sky_bri,
										sky_bri,
									   1.0f);
				}
				if (sky_bri == 1.0)
				{	
					// This sun has now gone nova!
					if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataKey("sun_gone_nova", oo::PList(static_cast<bool>(YES)), "org.oolite.oolite");	// +numberWithBool:
					if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataKey("corona_flare", oo::PList::singleReal(0.3), "org.oolite.oolite");	// +numberWithFloat:
					if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataKey("corona_hues", oo::PList::singleReal(0.05), "org.oolite.oolite");
					// Novas are stored under the core manifest if the
					// player was there at the time. Default layer 2
					// is fine.
					OO_LOG("sun.nova.start", "DEBUG: NOVA original radius {:.1f}", collision_radius);
				}
				discColor[0] = 1.0 * _sunBrightnessFactor;	discColor[1] = 1.0 * _sunBrightnessFactor;	discColor[2] = 1.0 * _sunBrightnessFactor;
				_novaExpansionTimer += delta_t;
				if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataKey("sun_radius", oo::PList::singleReal(collision_radius + delta_t * _novaExpansionRate), "org.oolite.oolite");	// +numberWithFloat:
			}
			else
			{
				OO_LOG("sun.nova.end", "DEBUG: NOVA final radius {:.1f}", collision_radius);
				
				// reset at the new size
				resetNova();
				throw_sparks = YES;	// keep throw_sparks at YES to indicate the higher temperature
			}
		}
	}
	
	// update corona
	if (!(UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false))
	{
		corona_stage += corona_speed_factor * delta_t;
		while (corona_stage > 1.0)
		{
			int i;
			corona_stage -= 1.0;
			for (i = 0; i < 360; i++)
			{
				rvalue[i] = rvalue[360 + i];
				rvalue[360 + i] = randf();
			}
		}
	}

}



void OOSunEntity::drawImmediate(bool /*immediate*/, bool translucent)
{
	if (!(UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))
	{
		if (translucent)
		{
			// nothing...
		}
		else
		{
			drawOpaqueParts();
			/* Despite the side effects, we have to draw the translucent
			 * parts on the opaque pass. Planets, at long range, aren't
			 * depth-buffered. So if the translucent parts are drawn on the
			 * translucent pass, they appear in front of planets they are
			 * actually behind. Telabe in G3 is a good one to test with if
			 * you have any clever ideas.
			 *
			 * - CIM 8/7/2013 */
			drawTranslucentParts();
		}
	}
}


void OOSunEntity::updateCameraRelativePosition()
{
	HPVector cr_temp = HPvector_subtract(absolutePositionForSubentity(),(PLAYER != nullptr ? PLAYER->viewpointPosition() : HPVector{}));
	/* Special calculation as suns viewed over ~1E9 - and the bigger
	 * ones are still just about visible at this range - get floating
	 * point errors messing up the display */
	if (EXPECT_NOT(HPmagnitude2(cr_temp) > 1E18))
	{
		cr_temp = HPvector_multiply_scalar(cr_temp,1E9/HPmagnitude(cr_temp));
	}
	cameraRelativePosition = HPVectorToVector(cr_temp);
}


void OOSunEntity::drawOpaqueParts()
{
	float sqrt_zero_distance = sqrt(cam_zero_distance);
	float effective_radius = collision_radius;
	float effective_cor16k = cor16k;

	/* At very long ranges the floating point inaccuracies make a
	 * complete mess of the calculations, so if the sun is more than
	 * 1E9 away, draw it closer but smaller. Painter's algorithm
	 * should stop oddities with planets transiting it */
	float large_distance_compensator = sqrt_zero_distance / 1000000000.0f; //1E9
	if (large_distance_compensator > 1.0f)
	{
		sqrt_zero_distance /= large_distance_compensator;
		effective_radius /= large_distance_compensator;
		effective_cor16k /= large_distance_compensator;
	}

	OO_ENTER_OPENGL();
	
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);

	if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false))
	{	
		int subdivideLevel = 2;		// 4 is probably the maximum!
		float drawFactor = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getViewSize() : NSSize{}).width / 100.0;
		float drawRatio2 = drawFactor * effective_radius / sqrt_zero_distance; // equivalent to size on screen in pixels
	
		if (cam_zero_distance > 0.0f)
		{
			subdivideLevel = 2 + floorf(drawRatio2);
			if (subdivideLevel > 4)
				subdivideLevel = 4;
		}
	
	/*
	 
	The depth test gets disabled in parts of this and instead
	we rely on the painters algorithm instead.
	 
	The depth buffer isn't granular enough to cope with huge objects at vast
	distances.
	 
	*/
		BOOL ignoreDepthBuffer = cam_zero_distance > effective_radius * effective_radius * 25;
	
		int steps = 2 * (MAX_SUBDIVIDE - subdivideLevel);

		// Close enough not to draw flat?
		if (ignoreDepthBuffer)  OOGL(glDisable(GL_DEPTH_TEST));
		
		OOGL(glColor3fv(discColor));
		// FIXME: use vertex arrays
		OOGL(glDisable(GL_BLEND));
		OOGLBEGIN(GL_TRIANGLE_FAN);
		GLDrawBallBillboard(effective_radius, steps, sqrt_zero_distance);
		OOGLEND();
		OOGL(glEnable(GL_BLEND));

		if (ignoreDepthBuffer)  OOGL(glEnable(GL_DEPTH_TEST)); 
	
	}
	else
	{
		calculateGLArrays(effective_radius,
						  effective_cor16k,
					  sqrt_zero_distance);
		OOGL(glDisable(GL_BLEND));
		OOGL(glVertexPointer(3, GL_FLOAT, 0, sunVertices));
		
		OOGL(glEnableClientState(GL_COLOR_ARRAY));
		OOGL(glColorPointer(4, GL_FLOAT, 0, sunColors));
		
		OOGL(glDrawElements(GL_TRIANGLES, 3*360, GL_UNSIGNED_INT, sunTriangles));

		OOGL(glDisableClientState(GL_COLOR_ARRAY));
		OOGL(glEnable(GL_BLEND));

		
	}
	
	OOVerifyOpenGLState();
	cxx_OOCheckOpenGLErrors([&]() -> std::string { return "SunEntity after drawing " + oo::EntityDescription(this); });
}


void OOSunEntity::drawTranslucentParts()
{
	if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false)) 
	{
		return;
	}
	
	OO_ENTER_OPENGL();
	
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);

	OOGL(glVertexPointer(3, GL_FLOAT, 0, sunVertices));

	OOGL(glEnableClientState(GL_COLOR_ARRAY));
	OOGL(glColorPointer(4, GL_FLOAT, 0, sunColors));
	OOGL(glDrawElements(GL_TRIANGLES, 24*360, GL_UNSIGNED_INT, sunTriangles+(3*360)));

	OOGL(glDisableClientState(GL_COLOR_ARRAY));


}

void OOSunEntity::calculateGLArrays(GLfloat inner_radius, GLfloat width, GLfloat z_distance)
{
//	if (EXPECT_NOT(inner_radius >= z_distance))  return;	// inside the sphere
	
	GLfloat activity[8] = {0.84, 0.74, 0.64, 0.54, 
												 0.3 , 0.4 , 0.7 , 0.8};
	
	GLfloat				si, ci;
	GLfloat				rv0, rv1, rv2, c0, c1, c2;
	GLfloat				pt0, pt1; 
	
	unsigned short		i, j, k;
	GLfloat				theta = 0.0f, delta;
	delta = M_PI / 180.0f;	// Convert step from degrees to radians
	pt0=(1.0 - corona_stage) * corona_blending;
	pt1=corona_stage * corona_blending;

	sunVertices[0] = 0.0;
	sunVertices[1] = 0.0;
	sunVertices[2] = 0.0;
	k = 3;
	for (j = 0 ; j <= 4 ; j++)
	{
		GLfloat r = inner_radius;
		switch (j) {
		case 4:
			r += width;
			break;
		case 3:
			r += width/1.5f;
			break;
		case 2:
			r += width/3.0f;
			break;
		case 1:
				r += width/15.0f;
			break;
		}
		theta = 0.0;
		for (i = 0 ; i < 360 ; i++)
		{
			GLfloat rm = 1.0;
			if (j >= 1 && j < 4)
			{
				rm = 1.0 + ((0.04/j)*(pt0 * (rvalue[i]+rvalue[i+1]+rvalue[i+2]) + pt1 * (rvalue[i+360]+rvalue[i+361]+rvalue[i+362])))/3;
			}
			GLfloat z = r * r * rm * rm / z_distance;
			si = sinf(theta);
			ci = cosf(theta);
			theta += delta;
			sunVertices[k++] = si * r * rm;
			sunVertices[k++] = ci * r * rm;
			sunVertices[k++] = -z;
		}
	}

	GLfloat blackColor[4] = {0.0,0.0,0.0,0.0};
	GLfloat *color = blackColor;
	GLfloat alpha = 0.0;

	k=0;
	sunColors[k++] = discColor[0];
	sunColors[k++] = discColor[1];
	sunColors[k++] = discColor[2];
	sunColors[k++] = discColor[3] * _sunCoronaAlphaFactor;
	
	for (j = 0 ; j <= 4 ; j++)
	{
		switch (j) {
		case 4:
			color = blackColor;
			alpha = 0.0;
			break;
		case 3:
			color = outerCoronaColor;
			alpha = 0.1;
			break;
		case 2:
			color = outerCoronaColor;
			alpha = 0.6;
			break;
		case 1:
			color = discColor;
			alpha = 0.95;
			break;
		case 0:
			color = discColor;
			alpha = 1.0;
			break;
		}
		for (i = 0 ; i < 360 ; i++)
		{
			if (j == 0) 
			{
				sunColors[k++] = color[0];
				sunColors[k++] = color[1];
				sunColors[k++] = color[2];
				sunColors[k++] = alpha * _sunCoronaAlphaFactor;
			}
			else
			{
				rv0 = pt0 * rvalue[i] + pt1 * rvalue[i + 360];
				rv1 = pt0 * rvalue[i + 1] + pt1 * rvalue[i + 361];
				rv2 = pt0 * rvalue[i + 2] + pt1 * rvalue[i + 362];
				c0 = color[0] * (activity[j-1] + rv0*activity[j+3]);
				c1 = color[1] * (activity[j-1] + rv1*activity[j+3]);
				c2 = color[2] * (activity[j-1] + rv2*activity[j+3]);
				if (c1 > c2 && c1 > c0)
				{
					c1 = fmaxf(c0,c2);
				}

				sunColors[k++] = c0;
				sunColors[k++] = c1;
				sunColors[k++] = c2;
				sunColors[k++] = alpha * _sunCoronaAlphaFactor;
			}	
		}
	}
}


void OOSunEntity::drawDirectVisionSunGlare()
{
#if SUN_DIRECT_VISION_GLARE
	OO_ENTER_OPENGL();
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	GLfloat sunGlareAngularSize = atan(radius()/HPdistance((PLAYER != nullptr ? PLAYER->viewpointPosition() : HPVector{}), getPosition())) * SUN_GLARE_MULT_FACTOR + (SUN_GLARE_ADD_FACTOR);

	GLfloat	directVisionSunGlare = (PLAYER != nullptr ? PLAYER->lookingAtSunWithThresholdAngleCos(cosf(sunGlareAngularSize)) : 0.0f);
	if (directVisionSunGlare)
	{
		NSSize	siz =	UNIVERSE->getGui()->size();
		::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
		GLfloat aspectRatio = ((gameView != nullptr ? gameView->getViewSize() : NSSize{}).width / (gameView != nullptr ? gameView->getViewSize() : NSSize{}).height);
		GLfloat z  = (gameView != nullptr ? gameView->getDisplay_z() : 0.0f) / (aspectRatio > 4.0f/3.0f ? aspectRatio : 1.0f / aspectRatio);
		GLfloat atmosphericReductionFactor =  1.0f - (PLAYER != nullptr ? PLAYER->insideAtmosphereFraction() : 0.0f);
		// 182: square of ratio of radius to sun-witchpoint distance
		// in default Lave
		GLfloat distanceReductionFactor = OOClamp_0_1_f((radius() * radius() * 182.0) / HPdistance2((PLAYER != nullptr ? PLAYER->getPosition() : HPVector{}), getPosition()));
		GLfloat	sunGlareFilterMultiplierLocal = (PLAYER != nullptr ? PLAYER->getSunGlareFilter() : 0.0f);
		GLfloat directVisionSunGlareColor[4] = {discColor[0], discColor[1], discColor[2], directVisionSunGlare *
													atmosphericReductionFactor * distanceReductionFactor * 
													(1.0f - sunGlareFilterMultiplierLocal) * 0.0085f};
													
		OOGL(glColor4fv(directVisionSunGlareColor));
		
		OOGLBEGIN(GL_QUADS);
		glVertex3f(siz.width, siz.height, z);
		glVertex3f(siz.width, -siz.height, z);
		glVertex3f(-siz.width, -siz.height, z);
		glVertex3f(-siz.width, siz.height, z);
		OOGLEND();
	}
#endif
}


void OOSunEntity::drawStarGlare()
{
	OO_ENTER_OPENGL();

	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	float sqrt_zero_distance = sqrtf(cam_zero_distance);
	float alt = sqrt_zero_distance - collision_radius;
	if (EXPECT_NOT(alt < 0))
	{
		return;
	}
	float corona = cor16k/SUN_GLARE_CORONA_FACTOR;
	if (corona > alt)
	{
		float alpha = (1-(alt/corona));
		float alphaMult = _sunCoronaAlphaFactor * alpha;
		alpha *= alphaMult;
		GLfloat glareColor[4] = {discColor[0], discColor[1], discColor[2], alpha};
		NSSize		siz =	UNIVERSE->getGui()->size();
		::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
		GLfloat aspectRatio = ((gameView != nullptr ? gameView->getViewSize() : NSSize{}).width / (gameView != nullptr ? gameView->getViewSize() : NSSize{}).height);
		GLfloat z  = (gameView != nullptr ? gameView->getDisplay_z() : 0.0f) / (aspectRatio > 4.0f/3.0f ? aspectRatio : 1.0f / aspectRatio);
		OOGL(glColor4fv(glareColor));

		OOGLBEGIN(GL_QUADS);
		glVertex3f(siz.width, siz.height, z);
		glVertex3f(siz.width, -siz.height, z);
		glVertex3f(-siz.width, -siz.height, z);
		glVertex3f(-siz.width, siz.height, z);
		OOGLEND();

	}
}



bool OOSunEntity::changeSunProperty(const std::string &key, const oo::PList &dict)
{
	// the value's -doubleValue / -floatValue (0 when absent, as nil answered): get<> with fallback 0 is
	// the same for a string or a number
	static GLfloat oldRadius = 0.0;
	if (key == "sun_radius")
	{
		oldRadius =	dict.get<double>(key, 0.0);	// clamp corona_flare in case planetinfo.plist / savegame contains the wrong value
		setRadius(oldRadius, dict.get<float>("corona_flare", 0.0f));
	}
	else if (key == std::string(KEY_SUNNAME))
	{
		// the Foundation get<> read nil unless a string or a number's text
		const oo::PList *name = dict.find(key);
		setName((name != nullptr && (name->isString() || name->isNumber())) ? std::optional<std::string>(dict.get<std::string>(key)) : std::nullopt);
	}
	else if (key == "corona_flare")
	{
		setRadius(collision_radius, dict.get<float>(key, 0.0f));
	}
	else if (key == "corona_shimmer")
	{
		corona_speed_factor=OOClamp_0_1_f(dict.get<float>(key, 0.0f)) * 2.0 + randf() * randf();
	}
	else if (key == "corona_hues")
	{
		corona_blending=OOClamp_0_1_f(dict.get<float>(key, 0.0f));
	}
	else if (key == "sun_gone_nova")
	{

		if (dict.get<bool>(key))
		{
			setGoingNova(YES, 0);
		}
		else
		{
			setGoingNova(NO, 0);
			// oldRadius is always the radius we had before going nova...
			setRadius(oldRadius, dict.get<float>("corona_flare", 0.0f));

		}
	}
	else
	{
		OO_LOG_WARN("script.warning", "Change to property '{}' not applied, will apply only after leaving this system.", key);
		return NO;
	}
	return YES;
}


OOStellarBodyType OOSunEntity::planetType()
{
	return STELLAR_TYPE_SUN;
}


void OOSunEntity::getDiffuseComponents(GLfloat components[4])
{
	OOCParameterAssert(components != NULL);
	memcpy(components, sun_diffuse, sizeof sun_diffuse);
}


void OOSunEntity::getSpecularComponents(GLfloat components[4])
{
	OOCParameterAssert(components != NULL);
	memcpy(components, sun_specular, sizeof sun_specular);
}


double OOSunEntity::radius()
{
	return collision_radius;
}


void OOSunEntity::setRadius(GLfloat rad, GLfloat corona)
{
	collision_radius = rad;
	if (corona < 0.01f) {
		corona = 0.01f;
	}
	cor16k = rad * 8 * corona;

	GLfloat corouter = rad * (1+(8*corona));

	lim16k = corouter * corouter * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
}


void OOSunEntity::setPosition(HPVector posn)
{
	Entity::setPosition(posn);
	if (UNIVERSE != nullptr)  UNIVERSE->setMainLightPosition(HPVectorToVector(posn));
}


bool OOSunEntity::willGoNova()
{
	return throw_sparks;
}


bool OOSunEntity::goneNova()
{
	return throw_sparks && _novaCountdown <= 0;
}


void OOSunEntity::setGoingNova(bool yesno, double interval)
{
	throw_sparks = yesno;
	if (throw_sparks)
	{
		_novaCountdown = fmax(interval, 0.0);
		OO_LOG("script.debug.setSunNovaIn", "NOVA activated! time until Nova : {:.1f} s", _novaCountdown);
	}
	
	_novaExpansionTimer = 0;
	_novaExpansionRate = 10000;
}


void OOSunEntity::resetNova()
{
	_novaExpansionTimer = 0.0;
	_novaExpansionRate = 0.0f;
	_novaCountdown = 0.0;
}


bool OOSunEntity::isSun()
{
	return YES;
}


bool OOSunEntity::isVisible()
{
	return YES;
}


std::optional<std::string> OOSunEntity::name()
{
	return _name;
}


void OOSunEntity::setName(const std::optional<std::string> &name)
{
	_name = name;
}


// The binding's bodies (OOJSSun.mm), which the facade forwarded to until bead oo-9ht.111.
void OOSunEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSSunGetJSClass(outClass, outPrototype);
}


std::optional<std::string> OOSunEntity::jsClassName()
{
	return ::OOJSSunJSClassName();
}


bool OOSunEntity::isVisibleToScripts()
{
	return ::OOJSSunIsVisibleToScripts();
}


// OOStellarBody.h: the sun (bead oo-9ht.111) and the planet (bead oo-9ht.129) asked directly, any
// other body by selector.
double OOStellarBodyRadius(Entity *body)
{
	if (body == nullptr)  return 0.0;
	if (OOSunEntity *sun = dynamic_cast<OOSunEntity *>(body))  return sun->radius();
	if (OOPlanetEntity *planet = dynamic_cast<OOPlanetEntity *>(body))  return planet->radius();
	return 0.0;	// any other body: none in the game; its object did not answer -radius (bead oo-dpyk8)
}


OOStellarBodyType OOStellarBodyPlanetType(Entity *body)
{
	if (body == nullptr)  return (OOStellarBodyType)0;
	if (OOSunEntity *sun = dynamic_cast<OOSunEntity *>(body))  return sun->planetType();
	if (OOPlanetEntity *planet = dynamic_cast<OOPlanetEntity *>(body))  return planet->planetType();
	return (OOStellarBodyType)0;	// any other body: none in the game; its object did not answer -planetType (bead oo-dpyk8)
}
