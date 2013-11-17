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

#import "OOTrumble.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOTexture.h"
#import "ResourceManager.h"
#import "OOSound.h"
#import "OOStringParsing.h"
#import "OOMaths.h"


static void InitTrumbleSounds(void);
static void PlayTrumbleIdle(void);
static void PlayTrumbleSqueal(void);


@implementation OOTrumble

- (id) init
{
	self = [super init];
	
	int i;
	for (i = 0; i < 4; i++)
	{
		colorPoint1[i] = 1.0;
		colorPoint2[i] = 1.0;
	}
	
	return self;
}

- (id) initForPlayer:(PlayerEntity*) p1
{
	self = [super init];
	
	[self setupForPlayer: p1 digram: @"a1"];
	
	return self;
}

- (id) initForPlayer:(PlayerEntity*) p1 digram:(NSString*) digramString
{
	self = [super init];
	
	[self setupForPlayer: p1 digram: digramString];
	
	return self;
}

- (void) setupForPlayer:(PlayerEntity*) p1 digram:(NSString*) digramString
{
	// set digram
	//
	digram[0] = [digramString characterAtIndex:0];
	digram[1] = [digramString characterAtIndex:1];
	
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
	[self randomizeMotionX];
	[self randomizeMotionY];
	
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
	[self calcGrowthRate];
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
	texture = [OOTexture textureWithName:@"trumblekit.png"
								inFolder:@"Textures"
								 options:kOOTextureDefaultOptions | kOOTextureNoShrink
							  anisotropy:0.0f
								 lodBias:kOOTextureDefaultLODBias];
	[texture retain];
	
	InitTrumbleSounds();
	
	readyToSpawn = NO;
}

- (void) dealloc
{
	[texture release];
	
	[super dealloc];
}

- (void) spawnFrom:(OOTrumble*) parentTrumble
{
	if (parentTrumble)
	{
		// mutate..
		unichar mutation1 = ranrot_rand() & ranrot_rand() & ranrot_rand() & 0xff;	// each bit has a 1/8 chance of being set
		unichar mutation2 = ranrot_rand() & ranrot_rand() & ranrot_rand() & 0xff;	// each bit has a 1/8 chance of being set
		unichar* parentdigram = [parentTrumble digram];
		unichar newdigram[2];
		newdigram[0] = parentdigram[0] ^ mutation1;
		newdigram[1] = parentdigram[1] ^ mutation2;
		//
		[self setupForPlayer: player digram: [NSString stringWithCharacters:newdigram length:2]];
		//
		size = [parentTrumble size] * 0.4;
		if (size < 0.5)
			size = 0.5;	// minimum size
		position = [parentTrumble position];
		rotation = [parentTrumble rotation];
		movement = [parentTrumble movement];
		movement.y += 8.0;	// emerge!
	}
	else
	{
		size = 0.5;	// minimum size
		position.x = (ranrot_rand() & 15)* 28 - 210;
		position.y = (ranrot_rand() & 15)* 28 - 210;
		[self randomizeMotionX];
		[self randomizeMotionY];
		rotation = TRUMBLE_MAX_ROTATION * (randf() - randf());
		rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * (randf() - randf());
	}
	hunger = 0.25;
	[self calcGrowthRate];
	discomfort = 0.0;
	[self actionSleep];
}

- (void) calcGrowthRate
{
	float rsize = size / max_size;
	growth_rate = TRUMBLE_GROWTH_RATE * (1.0 - rsize);
}


- (unichar *)	digram
{
	return digram;
}

- (NSPoint)		position
{
	return position;
}

- (NSPoint)		movement
{
	return movement;
}

- (GLfloat)		rotation
{
	return rotation;
}

- (GLfloat)		size
{
	return size;
}

- (GLfloat)		hunger
{
	return hunger;
}

- (GLfloat)		discomfort
{
	return discomfort;
}



// AI methods here
- (void) actionIdle
{
	nextAnimation = TRUMBLE_ANIM_IDLE;
	animationDuration = 1.5 + 3.0 * randf();	// time until next animation
}

- (void) actionBlink
{
	nextAnimation = TRUMBLE_ANIM_BLINK;
	animationDuration = 0.5 + 0.5 * randf();	// time until next animation
}

- (void) actionSnarl
{
	nextAnimation = TRUMBLE_ANIM_SNARL;
	animationDuration = 4.0 + 1.0 * randf();	// time until next animation
}

- (void) actionProot
{
	nextAnimation = TRUMBLE_ANIM_PROOT;
	animationDuration = 1.5 + 0.5 * randf();	// time until next animation
}

- (void) actionShudder
{
	nextAnimation = TRUMBLE_ANIM_SHUDDER;
	animationDuration = 2.25 + randf() * 1.5;	// time until next animation
}

- (void) actionStoned
{
	nextAnimation = TRUMBLE_ANIM_STONED;
	animationDuration = 1.5 + randf() * 3.0;	// time until next animation
}

- (void) actionPop
{
	nextAnimation = TRUMBLE_ANIM_DIE;
	animationDuration = 1.5 + randf() * 3.0;	// time until next animation
}

- (void) actionSleep
{
	nextAnimation = TRUMBLE_ANIM_SLEEP;
	animationDuration = 12.0 + 12.0 * randf();	// time until next animation
}

- (void) actionSpawn
{
	nextAnimation = TRUMBLE_ANIM_SPAWN;
	animationDuration = 9.0 + 3.0 * randf();	// time until next animation
}


- (void) randomizeMotionX
{
	movement.x = 36 * (randf() - 0.5);
	movement.x += (movement.x > 0)? 2.0: -2.0;
	rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * (randf() - randf());
}

- (void) randomizeMotionY
{
	movement.y = 36 * (randf() - 0.5);
	movement.y += (movement.y > 0)? 2.0: -2.0;
	rotational_velocity = TRUMBLE_MAX_ROTATIONAL_VELOCITY * (randf() - randf());
}

- (void) drawTrumble:(double) z
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
	[texture apply];
	
	OOGL(glPushMatrix());
	
	OOGL(glTranslatef( position.x, position.y, z));
	OOGL(glRotatef( rotation, 0.0, 0.0, 1.0));

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
	
	OOGL(glTranslatef( eye_position.x * wd, eye_position.y * ht, 0.0));
	
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
	
	OOGL(glTranslatef( mouth_position.x * wd, mouth_position.y * ht, 0.0));
	
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
	OOGL(glPopMatrix());
	OOGL(glDisable(GL_TEXTURE_2D));
}

- (void) updateTrumble:(double) delta_t
{
	// player movement
	NSPoint p_mov = NSMakePoint(TRUMBLE_MAX_ROTATIONAL_VELOCITY * [player dialPitch],	TRUMBLE_MAX_ROTATIONAL_VELOCITY * [player dialRoll]);
	switch ([UNIVERSE viewDirection])
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
		[self randomizeMotionX];
	}	
	position.y += delta_t * (movement.y + p_mov.x);
	if ((position.y < -bumpy)||(position.y > bumpy))
	{
		position.y = (position.y < -bumpy)? -bumpy : bumpy;
		[self randomizeMotionY];
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
	[self calcGrowthRate];
	if (hunger > 0.75)
		growth_rate = 0.0;
	if (hunger > 1.0)
		hunger = 1.0;	// clamp

	// feelings
	//
	GLfloat temp = [player hullHeatLevel];
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
		ShipEntity *selectedCargopod = nil;
		float mostYummy = 0.0;
		NSMutableArray *cargopods = [player cargo];	// the cargo pods
		NSUInteger i, n_pods = [cargopods count];
		float foodfactor[17] = { 1.00, 0.25, 0.75, 0.01, 0.95, 1.25, 1.05, 0.00, 0.00, 0.00, 0.00, 0.15, 0.00, 0.00, 0.00, 0.00, 0.00};
		for (i = 0 ; i < n_pods; i++)
		{
			ShipEntity *cargopod = [cargopods objectAtIndex:i];
			OOCommodityType cargo_type = [cargopod commodityType];
			float yumminess = (1.0 + randf()) * foodfactor[cargo_type];
			if (yumminess > mostYummy)
			{
				selectedCargopod = cargopod;
				mostYummy = yumminess;
			}
		}
		if (selectedCargopod)
		{
			// feed
			float trumbleAppetiteAccumulator = [player trumbleAppetiteAccumulator];
			
			trumbleAppetiteAccumulator += hunger;
			hunger = 0.0;
			discomfort -= mostYummy * 0.5;
			if (discomfort < 0.0)
				discomfort = 0.0;
			if (trumbleAppetiteAccumulator > 10.0)
			{
				// eaten all of this cargo!
				NSString* ms = [NSString stringWithFormat:DESC(@"trumbles-eat-@"),
								[UNIVERSE displayNameForCommodity:[selectedCargopod commodityType]]];
				
				[UNIVERSE addMessage: ms forCount: 4.5];
				[cargopods removeObject:selectedCargopod];
				trumbleAppetiteAccumulator -= 10.0;
				
				// consider breeding - must be full grown and happy
				if ((size > 0.95)&&(discomfort < 0.25))
				{
					readyToSpawn = YES;
				}
				
				[player setTrumbleAppetiteAccumulator:trumbleAppetiteAccumulator];
			}
		}
	}
	
	// animations
	//
	switch (animation)
	{
		case TRUMBLE_ANIM_SNARL :
			[self updateSnarl: delta_t];	break;
		case TRUMBLE_ANIM_SHUDDER :
			[self updateShudder: delta_t];	break;
		case TRUMBLE_ANIM_STONED :
			[self updateStoned: delta_t];	break;
		case TRUMBLE_ANIM_DIE :
			[self updatePop: delta_t];		break;
		case TRUMBLE_ANIM_BLINK :
			[self updateBlink: delta_t];	break;
		case TRUMBLE_ANIM_PROOT :
			[self updateProot: delta_t];	break;
		case TRUMBLE_ANIM_SLEEP :
			[self updateSleep: delta_t];	break;
		case TRUMBLE_ANIM_SPAWN :
			[self updateSpawn: delta_t];	break;
		case TRUMBLE_ANIM_IDLE :
		default:
			[self updateIdle: delta_t];	break;
	}
	
	
}

- (void) updateIdle:(double) delta_t
{
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// blink or proot or idle and/or change direction
		[self actionIdle];
		if (randf() < 0.25)
			[self actionBlink];
		if (randf() < 0.10)
			[self randomizeMotionX];
		if (randf() < 0.10)
			[self randomizeMotionY];
		if (randf() < 0.05)
			[self actionProot];
		if (randf() < 0.01)
			[self actionSleep];
		if (randf() < 0.01)
			[self actionSnarl];
		//
		if (readyToSpawn)
		{
			[self actionSpawn];
			readyToSpawn = NO;
		}
		//
		if (discomfort > 0.5 + randf())
		{
			[self actionShudder];
		}
		//
		if (discomfort > 0.96)
		{
			[self actionPop];
		}
		//
		animation = nextAnimation;
		animationTime = 0.0;
	}
}

- (void) updateBlink:(double) delta_t
{
	eyeFrame = TRUMBLE_EYES_SHUT;
	animationTime += delta_t;
	if (animationTime > animationDuration)
	{
		// blink or proot or idle
		[self actionIdle];
		if (randf() < 0.05)
			[self actionBlink];
		if (randf() < 0.1)
			[self actionProot];
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
	}
}

- (void) updateSnarl:(double) delta_t
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
		[self actionIdle];
		if (randf() < 0.1)
			[self actionBlink];
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
	}
}

- (void) updateProot:(double) delta_t
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
		[self actionIdle];
		if (randf() < 0.1)
			[self actionBlink];
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
	}
}

- (void) updateShudder:(double) delta_t
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
		[self actionIdle];
		if (randf() < 0.1)
			[self actionBlink];
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
	}
}

- (void) updateStoned:(double) delta_t
{
}

- (void) updatePop:(double) delta_t
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
		[player removeTrumble:self];
	}
}

- (void) updateSleep:(double) delta_t
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
		[self actionIdle];
		if (randf() < 0.25)
			[self actionProot];
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
	}
}

- (void) updateSpawn:(double) delta_t
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
		[self actionProot];
		animation = nextAnimation;
		animationTime = 0.0;
		eyeFrame = TRUMBLE_EYES_OPEN;
		mouthFrame = TRUMBLE_MOUTH_NORMAL;
		[self randomizeMotionX];
		[player addTrumble:self];
	}
}

- (NSDictionary*) dictionary
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSString stringWithCharacters:digram length:2],	@"digram",
		[NSNumber numberWithFloat:hunger],					@"hunger",
		[NSNumber numberWithFloat:discomfort],				@"discomfort",
		[NSNumber numberWithFloat:size],					@"size",
		[NSNumber numberWithFloat:growth_rate],				@"growth_rate",
		[NSNumber numberWithFloat:rotation],				@"rotation",
		[NSNumber numberWithFloat:rotational_velocity],		@"rotational_velocity",
		StringFromPoint(position),							@"position",
		StringFromPoint(movement),							@"movement",
		nil];
}

- (void) setFromDictionary:(NSDictionary*) dict
{
	NSString* digramString = (NSString*)[dict objectForKey:@"digram"];
	[self setupForPlayer: player digram: digramString];
	hunger =		[[dict objectForKey: @"hunger"]			floatValue];
	discomfort =	[[dict objectForKey: @"discomfort"]		floatValue];
	size =			[[dict objectForKey: @"size"]			floatValue];
	growth_rate =	[[dict objectForKey: @"growth_rate"]	floatValue];
	rotation =		[[dict objectForKey: @"rotation"]		floatValue];
	rotational_velocity =	[[dict objectForKey: @"rotational_velocity"]	floatValue];
	position =	PointFromString([dict objectForKey: @"position"]);
	movement =	PointFromString([dict objectForKey: @"movement"]);
}

@end


static OOSoundSource	*sTrumbleSoundSource;
static OOSound			*sTrumbleIdleSound;
static OOSound			*sTrumbleSqealSound;

static void InitTrumbleSounds(void)
{
	if (sTrumbleSoundSource == nil)
	{
		sTrumbleSoundSource = [[OOSoundSource alloc] init];
		sTrumbleIdleSound = [[OOSound alloc] initWithCustomSoundKey:@"[trumble-idle]"];
		sTrumbleSqealSound = [[OOSound alloc] initWithCustomSoundKey:@"[trumble-squeal]"];
	}
}


static void PlayTrumbleIdle(void)
{
	// Only play idle sound if no trumble is making noise.
	if (![sTrumbleSoundSource isPlaying])
	{
		// trumble sound from random direction - where's it gone now?
		[sTrumbleSoundSource setPosition:OORandomUnitVector()];
		[sTrumbleSoundSource playSound:sTrumbleIdleSound];
	}
}


static void PlayTrumbleSqueal(void)
{
	// Play squeal sound if no trumble is currently squealing, but trumping idle sound.
	if (![sTrumbleSoundSource isPlaying] || [sTrumbleSoundSource sound] == sTrumbleIdleSound)
	{
		// trumble sound from random direction - where's it gone now?
		[sTrumbleSoundSource setPosition:OORandomUnitVector()];
		[sTrumbleSoundSource playSound:sTrumbleSqealSound];
	}
}
