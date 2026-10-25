/*

OOTrumble.m

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

#include "OOTrumble.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOTexture.h"
#include "ResourceManager.h"
#include "OOSound.h"
#include "OOStringParsing.h"
#include "OOMaths.h"
#include "oofnd/String.hpp"
#include "MyOpenGLView.h"


static void InitTrumbleSounds(void);
static void PlayTrumbleIdle(void);
static void PlayTrumbleSqueal(void);


OOTrumble::OOTrumble()
{
	int i;
	for (i = 0; i < 4; i++)
	{
		colorPoint1[i] = 1.0;
		colorPoint2[i] = 1.0;
	}
}

OOTrumble::OOTrumble(::PlayerEntity* p1)
{
	setupForPlayer(p1, "a1");
}

OOTrumble::OOTrumble(::PlayerEntity* p1, const std::string & digramString)
{
	setupForPlayer(p1, digramString);
}

void OOTrumble::setupForPlayer(::PlayerEntity* p1, const std::string & digramString)
{
	// set digram (UTF-16 units, as -characterAtIndex: read them; a missing string read as 0s)
	//
	const std::u16string digramUnits = oo::utf8ToUtf16(digramString);
	digram[0] = (digramUnits.size() > 0) ? digramUnits[0] : 0;
	digram[1] = (digramUnits.size() > 1) ? digramUnits[1] : 0;
	
	// set player
	//
	player = p1;
	
	// set color points
	int r0 = (int)digram[0];
	int r1 = (int)digram[1];
	int pointscheme[6] = { 1, 1, 0, 0, 1, 1};
	int ps = r0 >> 2;	// first digram determines pattern of points
	pointscheme[0] = (ps >> 3) & 1;
	pointscheme[1] = (ps >> 2) & 1;
	pointscheme[2] = (ps >> 1) & 1;
	pointscheme[3] = ps & 1;
	pointscheme[4] = (ps >> 2) & 1;
	pointscheme[5] = (ps >> 3) & 1;
	
	GLfloat c1[4] = { 1.0, 1.0, 1.0, 1.0};
	GLfloat c2[4] = { 1.0, 0.0, 0.0, 1.0};

	// I am missing something. Please clarify the intent of the following statement.
	// The next statement shift the result of adding two masked values
	//	max_size = 0.90 + 0.50 * (((r0 & 0x38) + (r1 & 0x38)) >> 3) / 63.0;	// inheritable
	// The next statement adds masked(r0) to shifted(masked(r1)
	// 	max_size = 0.90 + 0.50 * ((r0 & 0x38) + ((r1 & 0x38) >> 3)) / 63.0;	// inheritable
	// Sorry, but I cannot determine what you intended to do here.
	//
	// GILES: It's the second one, we're just determining a pseudo random max_size from the first digram
	max_size = 0.90 + 0.50 * ((r0 & 0x38) + ((r1 & 0x38) >> 3)) / 63.0;	// inheritable

	// seed the random number generator
	//
	ranrot_srand(r0 + r1 *  256);
	
	// set random colors
	int col1 = r0 & 7;
	int col2 = r1 & 7;
	while (((col1 == 7)||(col1 == 0)) && ((col2 == 7)||(col2 == 0)))	// monochrome not allowed
	{
		if (col1 == col2)
			col1 = ranrot_rand() & 7;
		else
			col2 = ranrot_rand() & 7;
	}
	c1[0] = (GLfloat)(col1 & 1);
	c1[1] = (GLfloat)((col1 >> 1) & 1);
	c1[2] = (GLfloat)((col1 >> 2) & 1);
	c2[0] = (GLfloat)(col2 & 1);
	c2[1] = (GLfloat)((col2 >> 1) & 1);
	c2[2] = (GLfloat)((col2 >> 2) & 1);
	if (col1 == 0)
	{
		c1[0] = 0.5 + 0.1 * c2[1];	c1[1] = 0.5 + 0.1 * c2[2];	c1[2] = 0.5;
	}
	if (col1 == 7)
	{
		c1[0] = 1.0 - 0.1 * c2[1];	c1[1] = 1.0 - 0.1 * c2[2];	c1[2] = 0.9;
	}
	if (col2 == 0)
	{
		c2[0] = 0.5 + 0.1 * c1[2];	c2[1] = 0.5 + 0.1 * c1[0];	c2[2] = 0.5;
	}
	if (col2 == 7)
	{
		c2[0] = 1.0 - 0.1 * c1[2];	c2[1] = 1.0 - 0.1 * c1[0];	c2[2] = 0.9;
	}
	
	//	position and motion
	//
	position.x = (ranrot_rand() & 15)* 28 - 210;
	position.y = (ranrot_rand() & 15)* 28 - 210;
	//
	randomizeMotionX();
	randomizeMotionY();
	
	//	rotation
	//
	rotation = TRUMBLE_MAX_ROTATION * (randf() - randf());
	rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * (randf() - randf());
	
	//
	int i;
	for (i = 0; i < 4; i++)
	{
		colorPoint1[i] = c1[i];
		colorPoint2[i] = c2[i];
	}
	//
	for (i = 0; i < 6; i++)
	{
		pointColor[i] = colorPoint1;
		if (pointscheme[i] == 0)
			pointColor[i] = colorPoint1;
		if (pointscheme[i] == 1)
			pointColor[i] = colorPoint2;
	}
	//
	for (i = 0; i < 4; i++)
	{
		colorEyes[i] = 0.2 * (2.0 * pointColor[3][i] + 2.0 * pointColor[1][i] + 1.0);	// eyes - paler than average
		colorBase[i] = 0.5 * (pointColor[2][i] + pointColor[3][i]);	// mouth
	}
	//
	size = 0.5 * (1.0 + randf());
	calcGrowthRate();
	hunger = 0.0;
	discomfort = 0.0;
	//
	eye_position = NSMakePoint( 0.0, 0.075 * (randf() - randf()));
	eyeFrame = TRUMBLE_EYES_OPEN;
	//
	mouth_position = NSMakePoint( 0.0, 0.035 * (randf() - randf()));
	mouthFrame = TRUMBLE_MOUTH_NORMAL;
	//
	animation = TRUMBLE_ANIM_IDLE;
	nextAnimation = TRUMBLE_ANIM_IDLE;
	animationTime = 0.0;
	animationDuration = 1.5 + randf() * 3.0;	// time until next animation
	//
	texture = oo::Ref<OOTexture>(OOTexture::textureWithName("trumblekit.png", "Textures", kOOTextureDefaultOptions | kOOTextureNoShrink, 0.0f, kOOTextureDefaultLODBias));
	
	InitTrumbleSounds();
	
	readyToSpawn = NO;
}

void OOTrumble::spawnFrom(OOTrumble* parentTrumble)
{
	if (parentTrumble)
	{
		// mutate..
		uint16_t mutation1 = ranrot_rand() & ranrot_rand() & ranrot_rand() & 0xff;	// each bit has a 1/8 chance of being set
		uint16_t mutation2 = ranrot_rand() & ranrot_rand() & ranrot_rand() & 0xff;	// each bit has a 1/8 chance of being set
		uint16_t* parentdigram = parentTrumble->getDigram();
		uint16_t newdigram[2];
		newdigram[0] = parentdigram[0] ^ mutation1;
		newdigram[1] = parentdigram[1] ^ mutation2;
		//
		setupForPlayer(player, oo::utf16ToUtf8(std::u16string(newdigram, newdigram + 2)));
		//
		size = parentTrumble->getSize() * 0.4;
		if (size < 0.5)
			size = 0.5;	// minimum size
		position = parentTrumble->getPosition();
		rotation = parentTrumble->getRotation();
		movement = parentTrumble->getMovement();
		movement.y += 8.0;	// emerge!
	}
	else
	{
		size = 0.5;	// minimum size
		position.x = (ranrot_rand() & 15)* 28 - 210;
		position.y = (ranrot_rand() & 15)* 28 - 210;
		randomizeMotionX();
		randomizeMotionY();
		rotation = TRUMBLE_MAX_ROTATION * (randf() - randf());
		rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * (randf() - randf());
	}
	hunger = 0.25;
	calcGrowthRate();
	discomfort = 0.0;
	actionSleep();
}

void OOTrumble::calcGrowthRate()
{
	float rsize = size / max_size;
	growth_rate = TRUMBLE_GROWTH_RATE * (1.0 - rsize);
}


uint16_t * OOTrumble::getDigram()
{
	return digram;
}

NSPoint OOTrumble::getPosition()
{
	return position;
}

NSPoint OOTrumble::getMovement()
{
	return movement;
}

GLfloat OOTrumble::getRotation()
{
	return rotation;
}

GLfloat OOTrumble::getSize()
{
	return size;
}

GLfloat OOTrumble::getHunger()
{
	return hunger;
}

GLfloat OOTrumble::getDiscomfort()
{
	return discomfort;
}



// AI methods here
void OOTrumble::actionIdle()
{
	nextAnimation = TRUMBLE_ANIM_IDLE;
	animationDuration = 1.5 + 3.0 * randf();	// time until next animation
}

void OOTrumble::actionBlink()
{
	nextAnimation = TRUMBLE_ANIM_BLINK;
	animationDuration = 0.5 + 0.5 * randf();	// time until next animation
}

void OOTrumble::actionSnarl()
{
	nextAnimation = TRUMBLE_ANIM_SNARL;
	animationDuration = 4.0 + 1.0 * randf();	// time until next animation
}

void OOTrumble::actionProot()
{
	nextAnimation = TRUMBLE_ANIM_PROOT;
	animationDuration = 1.5 + 0.5 * randf();	// time until next animation
}

void OOTrumble::actionShudder()
{
	nextAnimation = TRUMBLE_ANIM_SHUDDER;
	animationDuration = 2.25 + randf() * 1.5;	// time until next animation
}

void OOTrumble::actionStoned()
{
	nextAnimation = TRUMBLE_ANIM_STONED;
	animationDuration = 1.5 + randf() * 3.0;	// time until next animation
}

void OOTrumble::actionPop()
{
	nextAnimation = TRUMBLE_ANIM_DIE;
	animationDuration = 1.5 + randf() * 3.0;	// time until next animation
}

void OOTrumble::actionSleep()
{
	nextAnimation = TRUMBLE_ANIM_SLEEP;
	animationDuration = 12.0 + 12.0 * randf();	// time until next animation
}

void OOTrumble::actionSpawn()
{
	nextAnimation = TRUMBLE_ANIM_SPAWN;
	animationDuration = 9.0 + 3.0 * randf();	// time until next animation
}


void OOTrumble::randomizeMotionX()
{
	movement.x = 36 * (randf() - 0.5);
	movement.x += (movement.x > 0)? 2.0: -2.0;
	rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * (randf() - randf());
}

void OOTrumble::randomizeMotionY()
{
	movement.y = 36 * (randf() - 0.5);
	movement.y += (movement.y > 0)? 2.0: -2.0;
	rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * (randf() - randf());
}

void OOTrumble::drawTrumble(double z)
{
	/*
	draws a trumble body as a fan of triangles...
	2-------3-------4
	| \	    |     / |
	|   \   |   /   |
	|     \ | /     |
	1-------0-------5
	
	*/
	GLfloat wd = 96 * size;
	GLfloat ht = 96 * size;
	OOGL(glShadeModel(GL_SMOOTH));
	OOGL(glEnable(GL_TEXTURE_2D));
	
	OOGLPushModelView();
	
	OOGLTranslateModelView(make_vector(position.x, position.y, z));
	OOGLMultModelView(OOMatrixForRotationZ(rotation));

	if (texture != nullptr)  texture->apply();	// a message to nil did nothing

	//
	// Body..
	//
	OOGLBEGIN(GL_TRIANGLE_FAN);
		glColor4fv(pointColor[3]);
		glTexCoord2f( 0.25, 0.5);
		glVertex2f(	0.0,		-0.5 * ht);
		
		glColor4fv(pointColor[0]);
		glTexCoord2f( 0.0, 0.5);
		glVertex2f(	-0.5 * wd,	-0.5 * ht);
		
		glColor4fv(pointColor[1]);
		glTexCoord2f( 0.0, 0.0);
		glVertex2f(	-0.5 * wd,	0.5 * ht);
		
		glColor4fv(pointColor[2]);
		glTexCoord2f( 0.25, 0.0);
		glVertex2f(	0.0,		0.5 * ht);
		
		glColor4fv(pointColor[4]);
		glTexCoord2f( 0.5, 0.0);
		glVertex2f(	0.5 * wd,	0.5 * ht);
		
		glColor4fv(pointColor[5]);
		glTexCoord2f( 0.5, 0.5);
		glVertex2f(	0.5 * wd,	-0.5 * ht);
	OOGLEND();
	
	//
	// Eyes
	//
	GLfloat eyeTextureOffset = 0.0;
	switch(eyeFrame)
	{
		case TRUMBLE_EYES_NONE :
		case TRUMBLE_EYES_OPEN :
			eyeTextureOffset = 0.0;	break;
		case TRUMBLE_EYES_SHUT :
			eyeTextureOffset = 0.25; break;
		case TRUMBLE_EYES_WIDE :
			eyeTextureOffset = 0.5;	break;
	}
	
	OOGLTranslateModelView(make_vector(eye_position.x * wd, eye_position.y * ht, 0.0));
	
	OOGL(glColor4fv(colorEyes));
	OOGLBEGIN(GL_QUADS);
		glTexCoord2f( 0.5, eyeTextureOffset);
		glVertex2f(	-0.5 * wd,	0.20 * ht);
		
		glTexCoord2f( 1.0, eyeTextureOffset);
		glVertex2f(	0.5 * wd,	0.20 * ht);
		
		glTexCoord2f( 1.0, eyeTextureOffset + 0.25);
		glVertex2f(	0.5 * wd,	-0.30 * ht);
		
		glTexCoord2f( 0.5, eyeTextureOffset + 0.25);
		glVertex2f(	-0.5 * wd,	-0.30 * ht);
	OOGLEND();
	
	//
	// Mouth
	//
	GLfloat mouthTextureOffset = 0.0;
	switch(mouthFrame)
	{
		case TRUMBLE_MOUTH_POUT :
			mouthTextureOffset = 0.500;	break;
		case TRUMBLE_MOUTH_NONE :
		case TRUMBLE_MOUTH_NORMAL :
			mouthTextureOffset = 0.625;	break;
		case TRUMBLE_MOUTH_GROWL:
			mouthTextureOffset = 0.750;	break;
		case TRUMBLE_MOUTH_SNARL:
			mouthTextureOffset = 0.875;	break;
	}
	
	OOGLTranslateModelView(make_vector(mouth_position.x * wd, mouth_position.y * ht, 0.0));
	
	OOGL(glColor4fv(colorBase));
	OOGLBEGIN(GL_QUADS);
		glTexCoord2f( 0.0, mouthTextureOffset);
		glVertex2f(	-0.25 * wd,	-0.10 * ht);
		
		glTexCoord2f( 0.25, mouthTextureOffset);
		glVertex2f(	0.25 * wd,	-0.10 * ht);
		
		glTexCoord2f( 0.25, mouthTextureOffset + 0.125);
		glVertex2f(	0.25 * wd,	-0.35 * ht);
		
		glTexCoord2f( 0.0, mouthTextureOffset + 0.125);
		glVertex2f(	-0.25 * wd,	-0.35 * ht);
	OOGLEND();	
	
	// finally..
	OOGLPopModelView();
	OOGL(glDisable(GL_TEXTURE_2D));
}

void OOTrumble::updateTrumble(double delta_t)
{
	// player movement
	NSPoint p_mov = NSMakePoint(TRUMBLE_MAX_ROTATIONAL_VELOCITY * (player != nullptr ? player->dialPitch() : 0.0f),	TRUMBLE_MAX_ROTATIONAL_VELOCITY * (player != nullptr ? player->dialRoll() : 0.0f));
	switch ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}))
	{
		GLfloat t;
		case VIEW_AFT:
			p_mov.x = -p_mov.x;
			p_mov.y = -p_mov.y;
			break;
		case VIEW_STARBOARD:
			t = p_mov.x;
			p_mov.x = -p_mov.y;
			p_mov.y = t;
			break;
		case VIEW_PORT:
			t = p_mov.x;
			p_mov.x = p_mov.y;
			p_mov.y = -t;
			break;
		
		default:
			break;
	}
	p_mov.x *= -4.0;
	
	// movement
	//
	GLfloat wd = 0.5 * 96 * size;
	GLfloat ht = 0.5 * 96 * size;
	//
	GLfloat bumpx = 320 * 1.5 - wd;
	GLfloat bumpy = 240 * 1.5 - ht;
	//
	position.x += delta_t * movement.x;
	if ((position.x < -bumpx)||(position.x > bumpx))
	{
		position.x = (position.x < -bumpx)? -bumpx : bumpx;
		randomizeMotionX();
	}	
	position.y += delta_t * (movement.y + p_mov.x);
	if ((position.y < -bumpy)||(position.y > bumpy))
	{
		position.y = (position.y < -bumpy)? -bumpy : bumpy;
		randomizeMotionY();
	}
	
	// rotation
	//
	rotation += delta_t * (rotational_velocity + p_mov.y);
	if (animation != TRUMBLE_ANIM_DIE)
	{
		if (rotation < -TRUMBLE_MAX_ROTATION)
		{
			rotation = -TRUMBLE_MAX_ROTATION;
			rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * 0.5 * (randf() + randf());
		}
		if (rotation > TRUMBLE_MAX_ROTATION)
		{
			rotation = TRUMBLE_MAX_ROTATION;
			rotational_velocity = -TRUMBLE_MAX_ROTATIONAL_VELOCITY * 0.5 * (randf() + randf());
		}
	}
	// growth
	//
	size += delta_t * growth_rate;
	hunger += delta_t * (growth_rate + TRUMBLE_GROWTH_RATE);
	if (size > max_size)	// fully_grown.. stop growing
	{
		size = max_size;
		growth_rate = 0.0;
	}
	calcGrowthRate();
	if (hunger > 0.75)
		growth_rate = 0.0;
	if (hunger > 1.0)
		hunger = 1.0;	// clamp

	// feelings
	//
	GLfloat temp = (player != nullptr ? player->hullHeatLevel() : 0.0f);
	discomfort += delta_t * hunger * 0.02 * (1.0 - hunger);
	if (temp > 0.33)
		discomfort += delta_t * (temp - 0.33) * (temp - 0.33) * 0.05;
	if (discomfort > 1.0)
		discomfort = 1.0;	// clamp
	
	// feeding & reproducing
	//
	// am I really hungry?
	if (hunger > 0.50)
	{
		// consult menu...
		::ShipEntity *selectedCargopod = nil;
		float mostYummy = 0.0;
		std::vector<oo::EntityHold> *cargopods = (player != nullptr ? player->getCargo() : (std::vector<oo::EntityHold> *)nullptr);	// the cargo pods (live: eaten ones are removed)
		NSUInteger i, n_pods = cargopods != nullptr ? cargopods->size() : 0;
		for (i = 0 ; i < n_pods; i++)
		{
			::ShipEntity *cargopod = oo::ToShip((*cargopods)[i].get());
			const std::string cargo_type = (cargopod != nullptr ? cargopod->commodityType() : std::optional<std::string>()).value_or("");	// nil arrived as ""
			float yumminess = (1.0 + randf()) * ((UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr) != nullptr ? UNIVERSE->getCommodityMarket()->trumbleOpinionForGood(cargo_type) : 0.0f);
			if (yumminess > mostYummy)
			{
				selectedCargopod = cargopod;
				mostYummy = yumminess;
			}
		}
		if (selectedCargopod)
		{
			// feed
			float trumbleAppetiteAccumulator = (player != nullptr ? player->trumbleAppetiteAccumulator() : 0.0f);
			
			trumbleAppetiteAccumulator += hunger;
			hunger = 0.0;
			discomfort -= mostYummy * 0.5;
			if (discomfort < 0.0)
				discomfort = 0.0;
			if (trumbleAppetiteAccumulator > 10.0)
			{
				// eaten all of this cargo!
				const std::string eatFormat = OO_DESC("trumbles-eat-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
				const std::string ms = oo::str::formatRuntime(eatFormat,
								{ (UNIVERSE != nullptr ? UNIVERSE->displayNameForCommodity((selectedCargopod != nullptr ? selectedCargopod->commodityType() : std::optional<std::string>()).value_or("")) : std::optional<std::string>()).value_or("(null)") });

				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ms, 4.5);
				if (cargopods != nullptr)  std::erase(*cargopods, static_cast<Entity *>(selectedCargopod));
				trumbleAppetiteAccumulator -= 10.0;
				
				// consider breeding - must be full grown and happy
				if ((size > 0.95)&&(discomfort < 0.25))
				{
					readyToSpawn = YES;
				}
				
				if (player != nullptr)  player->setTrumbleAppetiteAccumulator(trumbleAppetiteAccumulator);
			}
		}
	}
	
	// animations
	//
	switch (animation)
	{
		case TRUMBLE_ANIM_SNARL :
			updateSnarl(delta_t);	break;
		case TRUMBLE_ANIM_SHUDDER :
			updateShudder(delta_t);	break;
		case TRUMBLE_ANIM_STONED :
			updateStoned(delta_t);	break;
		case TRUMBLE_ANIM_DIE :
			updatePop(delta_t);		break;
		case TRUMBLE_ANIM_BLINK :
			updateBlink(delta_t);	break;
		case TRUMBLE_ANIM_PROOT :
			updateProot(delta_t);	break;
		case TRUMBLE_ANIM_SLEEP :
			updateSleep(delta_t);	break;
		case TRUMBLE_ANIM_SPAWN :
			updateSpawn(delta_t);	break;
		case TRUMBLE_ANIM_IDLE :
		default:
			updateIdle(delta_t);	break;
	}
	
	
}

void OOTrumble::updateIdle(double delta_t)
{
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// blink or proot or idle and/or change direction
		actionIdle();
		if (randf() < 0.25)
			actionBlink();
		if (randf() < 0.10)
			randomizeMotionX();
		if (randf() < 0.10)
			randomizeMotionY();
		if (randf() < 0.05)
			actionProot();
		if (randf() < 0.01)
			actionSleep();
		if (randf() < 0.01)
			actionSnarl();
		//
		if (readyToSpawn)
		{
			actionSpawn();
			readyToSpawn = NO;
		}
		//
		if (discomfort > 0.5 + randf())
		{
			actionShudder();
		}
		//
		if (discomfort > 0.96)
		{
			actionPop();
		}
		//
		animation = nextAnimation;
		animationTime = 0.0;
	}
}

void OOTrumble::updateBlink(double delta_t)
{
	eyeFrame = TRUMBLE_EYES_SHUT;
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// blink or proot or idle
		actionIdle();
		if (randf() < 0.05)
			actionBlink();
		if (randf() < 0.1)
			actionProot();
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
	}
}

void OOTrumble::updateSnarl(double delta_t)
{
	int pc = 100 * animationTime / animationDuration;
	if (pc < 25)
	{
		eyeFrame = TRUMBLE_EYES_SHUT;
		mouthFrame = TRUMBLE_MOUTH_GROWL;
	}
	if ((pc >=25)&&(pc < 90))
	{
		double vibr = (pc & 1)? -1.0 : 1.0;
		if (digram[1] & 4)
			position.x += size * vibr * 0.5;
		else
			position.y += size * vibr * 0.5;
		eyeFrame = TRUMBLE_EYES_WIDE;
		if (pc & 2)
			mouthFrame = TRUMBLE_MOUTH_SNARL;
		else
			mouthFrame = TRUMBLE_MOUTH_GROWL;
	}
	if ((pc >=90)&&(pc < 100))
	{
		eyeFrame = TRUMBLE_EYES_WIDE;
		mouthFrame = TRUMBLE_MOUTH_GROWL;
	}
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// blink or idle
		actionIdle();
		if (randf() < 0.1)
			actionBlink();
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
	}
}

void OOTrumble::updateProot(double delta_t)
{
	if (!animationTime)
	{
		animationStage = 0;
	}
	int pc = 100 * animationTime / animationDuration;
	if (pc < 10)
	{
		eyeFrame = TRUMBLE_EYES_SHUT;
		mouthFrame = TRUMBLE_MOUTH_POUT;
	}
	if (pc >=10)
	{
		double vibr = (pc & 2)? -1.0 : 1.0;
		position.x += size * vibr * 0.25;
		eyeFrame = TRUMBLE_EYES_SHUT;
		mouthFrame = TRUMBLE_MOUTH_GROWL;
		if (!animationStage)
		{
			animationStage = 1;
			PlayTrumbleIdle();
		}
	}
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// blink or idle
		actionIdle();
		if (randf() < 0.1)
			actionBlink();
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
	}
}

void OOTrumble::updateShudder(double delta_t)
{
	if (!animationTime)
	{
		eyeFrame = TRUMBLE_EYES_WIDE;
		mouthFrame = TRUMBLE_MOUTH_GROWL;
		PlayTrumbleSqueal();
	}
	int pc = 100 * animationTime / animationDuration;
	if (pc < 10)
	{
		eyeFrame = TRUMBLE_EYES_WIDE;
		mouthFrame = TRUMBLE_MOUTH_GROWL;
	}
	if (pc >= 10)
	{
		double vibr = (pc & 2)? -0.25 : 0.25;
		position.x += size * vibr;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_GROWL;
	}
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// feel better
		discomfort *= 0.9;
		// blink or idle
		actionIdle();
		if (randf() < 0.1)
			actionBlink();
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
	}
}

void OOTrumble::updateStoned(double /*delta_t*/)
{
}

void OOTrumble::updatePop(double delta_t)
{
	if (!animationTime)
	{
		eyeFrame = TRUMBLE_EYES_SHUT;
		mouthFrame = TRUMBLE_MOUTH_GROWL;
		movement.y = (ranrot_rand() & 7);
		if (randf() < 0.5)
			rotational_velocity = 63 + (ranrot_rand() & 127);
		else
			rotational_velocity = -63 - (ranrot_rand() & 127);
		// squeal here!
		PlayTrumbleSqueal();
	}
	float pc = animationTime / animationDuration;
	
	// fading alpha
	colorPoint1[1] *= (1.0 - delta_t);
	colorPoint2[1] *= (1.0 - delta_t);
	colorPoint1[2] *= (1.0 - delta_t);
	colorPoint2[2] *= (1.0 - delta_t);
	colorPoint1[3] = (1.0 - pc);
	colorPoint2[3] = (1.0 - pc);
	colorBase[3] = (1.0 - pc);
	
	// falling
	movement.y -= delta_t * 98.0;
	rotational_velocity *= (1.0 + delta_t);
	
	// shrinking
	size -= delta_t * (1.0 - pc) * size;
	
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// kaputnik!
		if (player != nullptr)  player->removeTrumble(this);
	}
}

void OOTrumble::updateSleep(double delta_t)
{
	if (!animationTime)
	{
		saved_float1 = eye_position.y;
		saved_float2 = mouth_position.y;
	}
	eyeFrame = TRUMBLE_EYES_SHUT;
	int pc = 512 * animationTime / animationDuration;
	if (pc & 16)
	{
		double vibr = (pc & 2)? -0.0025 : 0.0025;
		eye_position.y += size * vibr;
		mouth_position.y += size * vibr * -0.5;
	}
	else
	{
		eye_position.y = saved_float1;
		mouth_position.y = saved_float2;
	}
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// idle or proot
		eye_position.y = saved_float1;
		mouth_position.y = saved_float2;
		actionIdle();
		if (randf() < 0.25)
			actionProot();
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
	}
}

void OOTrumble::updateSpawn(double delta_t)
{
	movement.x *= (1.0 - delta_t);
	movement.y *= (1.0 - delta_t);
	rotation *= (1.0 - delta_t);
	rotational_velocity *= (1.0 - delta_t);
	eyeFrame = TRUMBLE_EYES_WIDE;
	mouthFrame = TRUMBLE_MOUTH_POUT;
	int pc = 256 * animationTime / animationDuration;
	double vibr = (pc & 2)? -0.002 * pc : 0.002 * pc;
	position.x += size * vibr;
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// proot
		eye_position.y = saved_float1;
		mouth_position.y = saved_float2;
		actionProot();
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
		randomizeMotionX();
		if (player != nullptr)  player->addTrumble(this);
	}
}

oo::PList OOTrumble::dictionary()
{
	// (the floats are single reals: they come back as +numberWithFloat:, so the save text is unchanged)
	oo::PList::Dict result;
	result.emplace("digram",				oo::PList(oo::utf16ToUtf8(std::u16string(digram, digram + 2))));
	result.emplace("hunger",				oo::PList::singleReal(hunger));
	result.emplace("discomfort",			oo::PList::singleReal(discomfort));
	result.emplace("size",					oo::PList::singleReal(size));
	result.emplace("growth_rate",			oo::PList::singleReal(growth_rate));
	result.emplace("rotation",				oo::PList::singleReal(rotation));
	result.emplace("rotational_velocity",	oo::PList::singleReal(rotational_velocity));
	result.emplace("position",				oo::PList(cxx_StringFromPoint(position)));
	result.emplace("movement",				oo::PList(cxx_StringFromPoint(movement)));
	return oo::PList(std::move(result));
}

void OOTrumble::setFromDictionary(const oo::PList & dict)
{
	setupForPlayer(player, dict.get<std::string>("digram"));
	hunger =		dict.get<float>("hunger");
	discomfort =	dict.get<float>("discomfort");
	size =			dict.get<float>("size");
	growth_rate =	dict.get<float>("growth_rate");
	rotation =		dict.get<float>("rotation");
	rotational_velocity =	dict.get<float>("rotational_velocity");
	position =	cxx_PointFromString(dict.get<std::string>("position"));
	movement =	cxx_PointFromString(dict.get<std::string>("movement"));
}


// The source and the sounds are C++ since beads oo-9ht.88 and oo-9ht.68 deleted their facades.
// Each static holds one retain for the process, as alloc/init (and -initWithCustomSoundKey:, which
// answered the cached sound retained) gave it; the source is made the first time, so it is there
// whenever the sounds are played.
static OOSoundSource	*sTrumbleSoundSource;
static OOSound			*sTrumbleIdleSound;
static OOSound			*sTrumbleSqealSound;

static void InitTrumbleSounds(void)
{
	if (sTrumbleSoundSource == nullptr)
	{
		sTrumbleSoundSource = oo::makeRef<OOSoundSource>().leakRef();
		sTrumbleIdleSound = oo::retain(OOSoundWithCustomSoundKey("[trumble-idle]"));
		sTrumbleSqealSound = oo::retain(OOSoundWithCustomSoundKey("[trumble-squeal]"));
	}
}


static void PlayTrumbleIdle(void)
{
	if (sTrumbleSoundSource == nullptr)  return;	// a message to nil did nothing
	// Only play idle sound if no trumble is making noise.
	if (!sTrumbleSoundSource->isPlaying())
	{
		// trumble sound from random direction - where's it gone now?
		sTrumbleSoundSource->setPosition(OORandomUnitVector());
		sTrumbleSoundSource->playOOSound(sTrumbleIdleSound);
	}
}


static void PlayTrumbleSqueal(void)
{
	if (sTrumbleSoundSource == nullptr)  return;	// a message to nil did nothing
	// Play squeal sound if no trumble is currently squealing, but trumping idle sound.
	if (!sTrumbleSoundSource->isPlaying() || sTrumbleSoundSource->sound() == sTrumbleIdleSound)
	{
		// trumble sound from random direction - where's it gone now?
		sTrumbleSoundSource->setPosition(OORandomUnitVector());
		sTrumbleSoundSource->playOOSound(sTrumbleSqealSound);
	}
}
