//
//  HeadUpDisplay.m
//  Oolite
//
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Fri Jul 30 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/
//

#import "HeadUpDisplay.h"
#import "ResourceManager.h"
#import "OpenGLSprite.h"
#import "PlayerEntity.h"
#import "Universe.h"
#import "TextureStore.h"

@implementation HeadUpDisplay

GLfloat red_color[4] =		{1.0, 0.0, 0.0, 1.0};
GLfloat redplus_color[4] =  {1.0, 0.0, 0.5, 1.0};
GLfloat yellow_color[4] =   {1.0, 1.0, 0.0, 1.0};
GLfloat green_color[4] =	{0.0, 1.0, 0.0, 1.0};

float char_widths[128] = {
	6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0,
    6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0,
    3.0, 2.5, 3.0, 4.0, 4.0, 6.0, 5.0, 2.0, 2.5, 3.0, 3.0, 4.5, 2.0, 3.0, 2.0, 3.0,
    4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 2.5, 2.5, 4.5, 4.5, 4.5, 4.5,
    6.5, 4.7, 4.8, 4.9, 4.7, 4.7, 4.5, 4.8, 4.7, 2.0, 3.7, 4.7, 4.5, 5.7, 4.8, 5.0,
    4.7, 5.5, 5.0, 4.7, 4.7, 4.7, 4.7, 6.5, 4.7, 4.7, 4.7, 2.5, 3.0, 2.5, 4.0, 4.5,
    2.0, 3.8, 3.8, 3.8, 3.8, 3.8, 2.4, 3.8, 3.8, 1.7, 1.9, 3.8, 1.7, 5.7, 3.8, 3.9,
    3.8, 3.8, 2.7, 3.8, 2.3, 3.8, 3.8, 4.9, 3.8, 3.8, 3.8, 3.0, 2.0, 3.0, 4.5, 6.0	};

- (id) initWithDictionary:(NSDictionary *) hudinfo;
{
	int i;
	
	self = [super init];
	
	line_width = 1.0;
	
	for (i = 0; i < 360; i++)
		sin_value[i] = sin(i * PI / 180);	// also used by PlanetEntity, but can't hurt to init it here too!
	
	int ch;
    NSMutableDictionary *stringAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSFont fontWithName:@"Helvetica-Bold" size:28], NSFontAttributeName,
        [NSColor blackColor], NSForegroundColorAttributeName, NULL];
	for (ch = 32; ch < 127; ch++)
	{
		unichar	 uch = (unichar) ch;
		NSString* chr = [NSString stringWithCharacters:&uch length:1];
		NSSize strsize = [chr sizeWithAttributes:stringAttributes];
		if ((ch < 48)||(ch > 57))	// exclude the digits which should be fixed width
			char_widths[ch] = strsize.width * .225;
	}
	
//	// init sprites
	compassSprite = [[OpenGLSprite alloc]   initWithImage:[ResourceManager imageNamed:COMPASS_IMAGE inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, COMPASS_SIZE, COMPASS_SIZE)
											size:NSMakeSize(COMPASS_HALF_SIZE, COMPASS_HALF_SIZE)];			// alloc retains
	reddotSprite = [[OpenGLSprite alloc]   initWithImage:[ResourceManager imageNamed:COMPASS_REDDOT_IMAGE inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, COMPASS_DOT_SIZE, COMPASS_DOT_SIZE)
											size:NSMakeSize(COMPASS_HALF_DOT_SIZE, COMPASS_HALF_DOT_SIZE)];	// alloc retains
	greendotSprite = [[OpenGLSprite alloc]   initWithImage:[ResourceManager imageNamed:COMPASS_GREENDOT_IMAGE inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, COMPASS_DOT_SIZE, COMPASS_DOT_SIZE)
											size:NSMakeSize(COMPASS_HALF_DOT_SIZE, COMPASS_HALF_DOT_SIZE)];	// alloc retains
	aegisSprite = [[OpenGLSprite alloc]   initWithImage:[ResourceManager imageNamed:AEGIS_IMAGE inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, 32, 32)
											size:NSMakeSize(32, 32)];	// alloc retains
	NSImage *zoomLevelImage = [ResourceManager imageNamed:ZOOM_LEVELS_IMAGE inFolder:@"Images"];
	int w1 = [zoomLevelImage size].width / SCANNER_ZOOM_LEVELS;
	int h1 = [zoomLevelImage size].height;
	for (i = 0; i < SCANNER_ZOOM_LEVELS; i++)
	{
		zoomLevelSprite[i] = [[OpenGLSprite alloc]   initWithImage:zoomLevelImage
														cropRectangle:NSMakeRect(w1*i, 0, w1, h1)
														size:NSMakeSize(16, 16)];	// alloc retains
	}
	
	// init arrays
	dialArray = [[NSMutableArray alloc] initWithCapacity:16];   // alloc retains
	legendArray = [[NSMutableArray alloc] initWithCapacity:16]; // alloc retains
	
	// populate arrays
	if ([hudinfo objectForKey:DIALS_KEY])
	{
		NSArray *dials = [hudinfo objectForKey:DIALS_KEY];
		for (i = 0; i < [dials count]; i++)
			[self addDial:(NSDictionary *)[dials objectAtIndex:i]];
	}
	if ([hudinfo objectForKey:LEGENDS_KEY])
	{
		NSArray *legends = [hudinfo objectForKey:LEGENDS_KEY];
		for (i = 0; i < [legends count]; i++)
			[self addLegend:(NSDictionary *)[legends objectAtIndex:i]];
	}
	
	last_transmitter = NO_TARGET;
	
	return self;
}

- (void) dealloc
{
	int i;
    if (compassSprite)			[compassSprite release];
    if (greendotSprite)			[greendotSprite release];
    if (reddotSprite)			[reddotSprite release];
    if (aegisSprite)			[aegisSprite release];

	for (i = 0; i < SCANNER_ZOOM_LEVELS; i++) if (zoomLevelSprite[i]) [zoomLevelSprite[i] release];

    if (legendArray)			[legendArray release];
    if (dialArray)				[dialArray release];

    [super dealloc];
}

//------------------------------------------------------------------------------------//

GLuint ascii_texture_name;

- (void) setPlayer:(PlayerEntity *) player_entity
{
	player = player_entity;
	ascii_texture_name = [[[player_entity universe] textureStore] getTextureNameFor:@"asciitext.png"];	// intitalise text texture
}

- (double) scanner_zoom
{
	return scanner_zoom;
}

- (void) setScannerZoom:(double) value
{
	scanner_zoom = value;
}

- (void) addLegend:(NSDictionary *) info
{
	if ([info objectForKey:IMAGE_KEY])
	{
		//NSLog(@"DEBUG adding Legend %@",[info objectForKey:IMAGE_KEY]);
		NSImage			*legendImage = [ResourceManager imageNamed:(NSString *)[info objectForKey:IMAGE_KEY] inFolder:@"Images"];
		NSSize			imageSize = [legendImage size];
		NSSize			spriteSize = imageSize;
		if ([info objectForKey:WIDTH_KEY])
			spriteSize.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
		if ([info objectForKey:HEIGHT_KEY])
			spriteSize.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
		OpenGLSprite *legendSprite = [[OpenGLSprite alloc] initWithImage:legendImage
										cropRectangle:NSMakeRect(0, 0, imageSize.width, imageSize.height) size:spriteSize]; // retained
		NSMutableDictionary *legendDict = [NSMutableDictionary dictionaryWithDictionary:info];
		[legendDict setObject:legendSprite forKey:SPRITE_KEY];
		[legendArray addObject:legendDict];																	
		[legendSprite release];
		return;
	}
	if ([info objectForKey:TEXT_KEY])
	{
		[legendArray addObject:info];
		return;
	}
}

- (void) addDial:(NSDictionary *) info
{
	if ([info objectForKey:SELECTOR_KEY])
	{
		//NSLog(@"DEBUG adding Dial for %@",[info objectForKey:SELECTOR_KEY]);
		SEL _selector = NSSelectorFromString((NSString *)[info objectForKey:SELECTOR_KEY]);
		if ([self respondsToSelector:_selector])
			[dialArray addObject:info];
		//else
		//	NSLog(@"DEBUG HeadUpDisplay does not respond to '%@'",[info objectForKey:SELECTOR_KEY]);
	}
}

- (void) drawLegends
{
	int i;
	if (!player)
		return;
	z1 = [(MyOpenGLView *)[[player universe] gameView] display_z];
	for (i = 0; i < [legendArray count]; i++)
		[self drawLegend:(NSDictionary *)[legendArray objectAtIndex:i]];
//
checkGLErrors(@"HeadUpDisplay after drawLegends");
//
}

- (void) drawDials
{
	int i;
	if (!player)
		return;
	z1 = [(MyOpenGLView *)[[player universe] gameView] display_z];
	for (i = 0; i < [dialArray count]; i++)
		[self drawHUDItem:(NSDictionary *)[dialArray objectAtIndex:i]];
//
checkGLErrors(@"HeadUpDisplay after drawDials");
//
}


- (void) drawLegend:(NSDictionary *) info
{
	if ([info objectForKey:SPRITE_KEY])
	{
		OpenGLSprite *legendSprite = (OpenGLSprite *)[info objectForKey:SPRITE_KEY];
		int x =		[(NSNumber *)[info objectForKey:X_KEY] intValue];
		int y =		[(NSNumber *)[info objectForKey:Y_KEY] intValue];
		double alpha = [(NSNumber *)[info objectForKey:ALPHA_KEY] doubleValue];
		[legendSprite blitCentredToX:x Y:y Z:z1 Alpha:alpha];
		return;
	}
	if ([info objectForKey:TEXT_KEY])
	{
		NSString*	legendText = (NSString*)[info objectForKey:TEXT_KEY];
		NSSize		siz = NSMakeSize([(NSNumber *)[info objectForKey:WIDTH_KEY] floatValue],[(NSNumber *)[info objectForKey:HEIGHT_KEY] floatValue]);
		double x =		[(NSNumber *)[info objectForKey:X_KEY] doubleValue];
		double y =		[(NSNumber *)[info objectForKey:Y_KEY] doubleValue];
		glColor4f( 0.0, 1.0, 0.0, 1.0);
		drawString( legendText, x, y, z1, siz);
	}
}

- (void) drawHUDItem:(NSDictionary *) info
{
	if ([info objectForKey:SELECTOR_KEY])
	{
		//NSLog(@"DEBUG about to '%@'",[info objectForKey:SELECTOR_KEY]);
		SEL _selector = NSSelectorFromString((NSString *)[info objectForKey:SELECTOR_KEY]);
		if ([self respondsToSelector:_selector])
			[self performSelector:_selector withObject:info];
		else
			NSLog(@"DEBUG HeadUpDisplay does not respond to '%@'",[info objectForKey:SELECTOR_KEY]);
	}
//
checkGLErrors([NSString stringWithFormat:@"HeadUpDisplay after drawHUDItem %@", info]);
//
}

//---------------------------------------------------------------------//

static BOOL hostiles;
- (void) drawScanner:(NSDictionary *) info
{	
    GLfloat scanner_color[4] = { 1.0, 0.0, 0.0, 1.0 };
	
	int x = SCANNER_CENTRE_X;
	int y = SCANNER_CENTRE_Y;
	double alpha = 1.0;
	NSSize siz = NSMakeSize( SCANNER_WIDTH, SCANNER_HEIGHT);
	//
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha = [(NSNumber *)[info objectForKey:ALPHA_KEY] doubleValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] floatValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] floatValue];
	if ([info objectForKey:RGB_COLOR_KEY])
	{
		NSArray*	rgb_array = (NSArray*)[info objectForKey:RGB_COLOR_KEY];
		scanner_color[0] = (GLfloat)[(NSNumber *)[rgb_array objectAtIndex:0] floatValue];
		scanner_color[1] = (GLfloat)[(NSNumber *)[rgb_array objectAtIndex:1] floatValue];
		scanner_color[2] = (GLfloat)[(NSNumber *)[rgb_array objectAtIndex:2] floatValue];
	}
	scanner_color[3] = (GLfloat)alpha;
	
	double z_factor = siz.height / siz.width;	// approx 1/4
	double y_factor = 1.0 - sqrt(z_factor);	// approx 1/2
	
//	NSLog(@"DEBUG z_factor %.2f y_factor %.2f", z_factor, y_factor);

	int i;
    int scanner_cx = x;
	int scanner_cy = y;
	double mass_lock_range2 = 25600.0*25600.0;

	int scanner_scale = SCANNER_MAX_RANGE * 2.5 / siz.width;

	double max_scanner_range2 = SCANNER_SCALE*SCANNER_SCALE*10000.0/(scanner_zoom*scanner_zoom);
	
	BOOL	isHostile = NO;
	BOOL	foundHostiles = NO;
	BOOL	mass_locked = NO;
	
	Vector	position, relativePosition;
	Matrix rotMatrix;
	int flash = ((int)([[player universe] getTime] * 4))&1;

	//
	// use a non-mutable copy so this can't be changed under us.
	//
	Universe*	uni =			[player universe];
	int			ent_count =		uni->n_entities;
	Entity**	uni_entities =	uni->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [uni_entities[i] retain];	// retained
	//
	Entity	*drawthing = nil;
	GLfloat cargo_color[4] = {0.9, 0.9, 0.9, alpha};		// gray
	GLfloat hostile_color[4] = {1.0, 0.25, 0.0, alpha};	// red/orange
	GLfloat neutral_color[4] = {1.0, 1.0, 0.0, alpha};	// yellow
	GLfloat friendly_color[4] = {0.0, 1.0, 0.0, alpha};   // green
	GLfloat missile_color[4] = {0.0, 1.0, 1.0, alpha};	// cyan
	GLfloat police_color1[4] = {0.5, 0.0, 1.0, alpha};		// purpley-blue
	GLfloat police_color2[4] = {1.0, 0.0, 0.5, alpha};		// purpley-red
	GLfloat col[4];								// can be manipulated
    
	position = player->position;
	gl_matrix_into_matrix([player rotationMatrix], rotMatrix);
	
//	NSLog(@"drawing grid size %.1f x %.1f", siz.width, siz.height);
	
	glColor4fv( scanner_color);
	drawScannerGrid( x, y, z1, siz, [[player universe] viewDir], line_width);
	
	GLfloat off_scope2 = (siz.width > siz.height) ? siz.width * siz.width : siz.height * siz.height;
	
	//
	if ([[player universe] viewDir] != VIEW_DOCKED)
	{
		double upscale = scanner_zoom*1.25/scanner_scale;
		off_scope2 /= upscale * upscale;
		double max_blip = 0.0;
		
		for (i = 0; i < ent_count; i++)  // scanner lollypops
		{
			drawthing = my_entities[i];
			
			int drawClass = drawthing->scan_class;
			if (drawClass == CLASS_PLAYER)	drawClass = CLASS_NO_DRAW;
			
			// consider large bodies for mass_lock
			if (drawthing->isPlanet)
			{
				PlanetEntity* planet = (PlanetEntity *)drawthing;
				double dist =   planet->zero_distance;
				double rad =	planet->collision_radius;
				double factor = ([planet getPlanetType] == PLANET_TYPE_SUN) ? 2.0 : 4.0;
				if (dist < rad*rad*factor)
				{
					mass_locked = YES;
				}
			}
			
			if (drawClass != CLASS_NO_DRAW)
			{
				GLfloat x1,y1,y2;
				float	ms_blip = 0.0;

				if (drawthing->zero_distance <= mass_lock_range2)
				{
					switch (drawClass)
					{
						case CLASS_BUOY :
						case CLASS_ROCK :
						case CLASS_CARGO :
						case CLASS_MINE :
							break;
						case CLASS_THARGOID :
						case CLASS_MISSILE :
						case CLASS_STATION :
						case CLASS_POLICE :
						default :
							mass_locked = YES;
							break;
					}
				}
				
				[player setAlert_flag:ALERT_FLAG_MASS_LOCK :mass_locked];
					
				if ((isnan(drawthing->zero_distance))||(drawthing->zero_distance > max_scanner_range2))
					continue;
				
				// has it sent a recent message
				//
				if (drawthing->isShip) 
					ms_blip = 2.0 * [(ShipEntity *)drawthing message_time];
				if (ms_blip > max_blip)
				{
					max_blip = ms_blip;
					last_transmitter = [drawthing universal_id];
				}
				ms_blip -= floor(ms_blip);
				
				relativePosition = [drawthing relative_position];

				// rotate the view
				mult_vector(&relativePosition, rotMatrix);
				// scale the view
				relativePosition.x *= upscale;	relativePosition.y *= upscale;	relativePosition.z *= upscale;
				
				x1 = relativePosition.x;
				y1 = z_factor * relativePosition.z;
				y2 = y1 + y_factor * relativePosition.y;
				
				isHostile = NO;
				if (drawthing->isShip)
				{
					double wr = [(ShipEntity *)drawthing weapon_range];
					isHostile = (([(ShipEntity *)drawthing hasHostileTarget])&&([(ShipEntity *)drawthing getPrimaryTarget] == player)&&(drawthing->zero_distance < wr*wr));
				}
				
				// position the scanner
				x1 += scanner_cx;   y1 += scanner_cy;   y2 += scanner_cy;
				switch (drawClass)
				{
					case CLASS_ROCK :
					case CLASS_CARGO :
						col[0] = cargo_color[0];	col[1] = cargo_color[1];	col[2] = cargo_color[2];	col[3] = cargo_color[3];
						break;
					case CLASS_THARGOID :
						if (flash)
						{
							col[0] = friendly_color[0];	col[1] = friendly_color[1];	col[2] = friendly_color[2];	col[3] = friendly_color[3];
						}
						else
						{
							col[0] = hostile_color[0];	col[1] = hostile_color[1];	col[2] = hostile_color[2];	col[3] = hostile_color[3];
						}
						foundHostiles = YES;
						break;
					case CLASS_MISSILE :
						col[0] = missile_color[0];	col[1] = missile_color[1];	col[2] = missile_color[2];	col[3] = missile_color[3];
						break;
					case CLASS_STATION :
						col[0] = friendly_color[0];	col[1] = friendly_color[1];	col[2] = friendly_color[2];	col[3] = friendly_color[3];
						break;
					case CLASS_BUOY :
						if (flash)
						{
							col[0] = neutral_color[0];	col[1] = neutral_color[1];	col[2] = neutral_color[2];	col[3] = neutral_color[3];
						}
						else
						{
							col[0] = friendly_color[0];	col[1] = friendly_color[1];	col[2] = friendly_color[2];	col[3] = friendly_color[3];
						}
						break;
					case CLASS_POLICE :
						if ((isHostile)&&(flash))
						{
							col[0] = police_color2[0];	col[1] = police_color2[1];	col[2] = police_color2[2];	col[3] = police_color2[3];
						}
						else
						{
							col[0] = police_color1[0];	col[1] = police_color1[1];	col[2] = police_color1[2];	col[3] = police_color1[3];
						}
						break;
					case CLASS_MINE :
						if (flash)
						{
							col[0] = neutral_color[0];	col[1] = neutral_color[1];	col[2] = neutral_color[2];	col[3] = neutral_color[3];
						}
						else
						{
							col[0] = hostile_color[0];	col[1] = hostile_color[1];	col[2] = hostile_color[2];	col[3] = hostile_color[3];
						}
						break;
					default :
						if (isHostile)
						{
							col[0] = hostile_color[0];	col[1] = hostile_color[1];	col[2] = hostile_color[2];	col[3] = hostile_color[3];
							foundHostiles = YES;
						}
						else
						{
							col[0] = neutral_color[0];	col[1] = neutral_color[1];	col[2] = neutral_color[2];	col[3] = neutral_color[3];
						}
						break;
				}
				if (ms_blip > 0.0)
				{
					drawSpecialOval( x1 - 0.5, y2 + 1.5, z1, NSMakeSize(16.0 * (1.0 - ms_blip), 8.0 * (1.0 - ms_blip)), 30, col);
				}
				if ((drawthing->isParticle)&&(drawClass == CLASS_MINE))
				{
					double r1 = 2.5 + drawthing->collision_radius * upscale;
					double l2 = r1*r1 - relativePosition.y*relativePosition.y;
					double r0 = (l2 > 0)? sqrt(l2): 0;
					if (r0 > 0)
					{
						glColor4f( 1.0, 0.5, 1.0, alpha);
						drawOval( x1  - 0.5, y1 + 1.5, z1, NSMakeSize( r0, r0 * siz.height / siz.width), 20);
					}
					glColor4f( 0.5, 0.0, 1.0, 0.33333 * alpha);
					drawFilledOval( x1  - 0.5, y2 + 1.5, z1, NSMakeSize( r1, r1), 15);
				}
				else
				{
					glBegin(GL_QUADS);
					glColor4fv(col);
					glVertex3f( x1-3, y2, z1);	glVertex3f( x1+2, y2, z1);	glVertex3f( x1+2, y2+3, z1);	glVertex3f( x1-3, y2+3, z1);	
					col[3] *= 0.3333; // one third the alpha
					glColor4fv(col);
					glVertex3f( x1, y1, z1);	glVertex3f( x1+2, y1, z1);	glVertex3f( x1+2, y2, z1);	glVertex3f( x1, y2, z1);
					glEnd();
				}
			}
		}
		//
		[player setAlert_flag:ALERT_FLAG_HOSTILES :foundHostiles];
		//	
		if ((foundHostiles)&&(!hostiles))
		{
			hostiles = YES;
		}
		if ((!foundHostiles)&&(hostiles))
		{
			hostiles = NO;					// there are now no hostiles on scope, relax
		}
	}
	
	//
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release];	//	released

}

- (void) refreshLastTransmitter
{
	Entity* lt = [[player universe] entityForUniversalID:last_transmitter];
	if ((lt == nil)||(!(lt->isShip)))
		return;
	ShipEntity* st = (ShipEntity*)lt;
//	NSLog(@"DEBUG Last Transmitter (%d) == %@ %d", last_transmitter, [st name], [st universal_id]);
	if ([st message_time] <= 0.0)
		[st setMessage_time:2.5];
}

- (void) drawScannerZoomIndicator:(NSDictionary *) info
{	
    int x = ZOOM_INDICATOR_CENTRE_X;
	int y = ZOOM_INDICATOR_CENTRE_Y;
	double alpha = 1.0;
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha = [(NSNumber *)[info objectForKey:ALPHA_KEY] doubleValue];
	int zoom_indicator_cx = x;
	int zoom_indicator_cy = y;
	int zl = scanner_zoom - 1.0;
	if (zl < 0) zl = 0;
	if (zl >= SCANNER_ZOOM_LEVELS) zl = SCANNER_ZOOM_LEVELS - 1;
	[zoomLevelSprite[zl] blitCentredToX:zoom_indicator_cx Y:zoom_indicator_cy Z:z1 Alpha:(zl == 0) ? 0.75 * alpha : alpha];	// vary alpha up if zoomed
}

- (void) drawCompass:(NSDictionary *) info
{	
    int x = COMPASS_CENTRE_X;
	int y = COMPASS_CENTRE_Y;
	double alpha = 1.0;
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha = [(NSNumber *)[info objectForKey:ALPHA_KEY] doubleValue];
	// draw the compass
	Matrix rotMatrix;
	Vector position = player->position;
	gl_matrix_into_matrix([player rotationMatrix], rotMatrix);
	//
	[compassSprite blitCentredToX:x Y:y Z:z1 Alpha:alpha];
	//
	PlanetEntity*	the_sun = [[player universe] sun];
	PlanetEntity*	the_planet = [[player universe] planet];
	StationEntity*	the_station = [[player universe] station];
	Entity*			the_target = [player getPrimaryTarget];
	Entity*			the_next_beacon = [[player universe] entityForUniversalID:[player nextBeaconID]];
	if (([[player universe] viewDir] != VIEW_DOCKED)&&(the_sun)&&(the_planet))
	{
		Vector relativePosition;
		if ([player compass_mode] == COMPASS_MODE_BASIC)
		{
			relativePosition = the_planet->position;
			if (([player checkForAegis] != AEGIS_NONE)&&(the_station))
				relativePosition = the_station->position;
		}
		else
		{
			switch ([player compass_mode])
			{
				case COMPASS_MODE_PLANET:
					relativePosition = the_planet->position;
					break;
				case COMPASS_MODE_STATION:
					relativePosition = the_station->position;
					break;
				case COMPASS_MODE_SUN:
					relativePosition = the_sun->position;
					break;
				case COMPASS_MODE_TARGET:
					if (the_target)
						relativePosition = the_target->position;
					else
					{
						[player setCompass_mode:COMPASS_MODE_PLANET];
						relativePosition = the_planet->position;
					}	
					break;
				case COMPASS_MODE_BEACONS:
					if (the_next_beacon)
						relativePosition = the_next_beacon->position;
					else
					{
						[player setCompass_mode:COMPASS_MODE_PLANET];
						relativePosition = the_planet->position;
					}	
					break;
			}
		}
		// translate the view
		relativePosition.x -= position.x;   relativePosition.y -= position.y;   relativePosition.z -= position.z;
		// rotate the view
		mult_vector(&relativePosition, rotMatrix);
		relativePosition = unit_vector(&relativePosition);
		relativePosition.x *= [compassSprite size].width * 0.4;
		relativePosition.y *= [compassSprite size].height * 0.4;
		relativePosition.x += x;
		relativePosition.y += y;

		if ([player compass_mode] == COMPASS_MODE_BASIC)
		{
			[self drawCompassPlanetBlipAt:relativePosition Alpha:alpha];
		}
		else
		{
			NSSize sz = [compassSprite size];
			sz.width *= 0.2;
			sz.height *= 0.2;
			glLineWidth(2.0);
			switch ([player compass_mode])
			{
				case COMPASS_MODE_PLANET:
					[self drawCompassPlanetBlipAt:relativePosition Size:sz Alpha:alpha];
					break;
				case COMPASS_MODE_STATION:
					[self drawCompassStationBlipAt:relativePosition Size:sz Alpha:alpha];
					break;
				case COMPASS_MODE_SUN:
					[self drawCompassSunBlipAt:relativePosition Size:sz Alpha:alpha];
					break;
				case COMPASS_MODE_TARGET:
					[self drawCompassTargetBlipAt:relativePosition Size:sz Alpha:alpha];
					break;
				case COMPASS_MODE_BEACONS:
					[self drawCompassBeaconBlipAt:relativePosition Size:sz Alpha:alpha];
					drawString(	[NSString stringWithFormat:@"%c", [(ShipEntity*)the_next_beacon beaconChar]],
								x - 2.5 * sz.width, y - 3.0 * sz.height, z1, NSMakeSize(sz.width * 2, sz.height * 2));
					break;
			}
		}
	}
}

- (void) drawCompassPlanetBlipAt:(Vector) relativePosition Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
		[greendotSprite blitCentredToX:relativePosition.x Y:relativePosition.y Z:z1 Alpha:alpha];
	else
		[reddotSprite blitCentredToX:relativePosition.x Y:relativePosition.y Z:z1 Alpha:alpha];
}

- (void) drawCompassPlanetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,0.75 * alpha);
		drawFilledOval( relativePosition.x, relativePosition.y, z1, siz, 30);
		glColor4f(0.0,1.0,0.0,alpha);
		drawOval( relativePosition.x, relativePosition.y, z1, siz, 30);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
		drawOval( relativePosition.x, relativePosition.y, z1, siz, 30);
	}
}

- (void) drawCompassStationBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
//		drawOval( relativePosition.x, relativePosition.y, z1, siz, 90);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
//		drawOval( relativePosition.x, relativePosition.y, z1, siz, 90);
	}
	glBegin(GL_LINE_LOOP);
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glEnd();
}

- (void) drawCompassSunBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	glColor4f(1.0,1.0,0.0,0.75 * alpha);
	drawFilledOval( relativePosition.x, relativePosition.y, z1, siz, 30);
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
		drawOval( relativePosition.x, relativePosition.y, z1, siz, 30);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
		drawOval( relativePosition.x, relativePosition.y, z1, siz, 30);
	}
}

- (void) drawCompassTargetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
	}
	glBegin(GL_LINES);
	glVertex3f(relativePosition.x - siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x + siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y - siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y + siz.height, z1);
	glEnd();
	drawOval( relativePosition.x, relativePosition.y, z1, siz, 30);
}

- (void) drawCompassWitchpointBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
	}
	glBegin(GL_LINES);
	
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x - 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x - 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y, z1);
	
	glVertex3f(relativePosition.x, relativePosition.y, z1);
	glVertex3f(relativePosition.x + 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x + 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glEnd();
}

- (void) drawCompassBeaconBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
	}
	glBegin(GL_LINES);
	
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	
	glEnd();
}

- (void) drawAegis:(NSDictionary *) info
{	
    int x = AEGIS_CENTRE_X;
	int y = AEGIS_CENTRE_Y;
	double alpha = 1.0;
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha = [(NSNumber *)[info objectForKey:ALPHA_KEY] doubleValue];
	// draw the aegis indicator
	//
	if (([[player universe] viewDir] != VIEW_DOCKED)&&([[player universe] sun])&&([player checkForAegis] == AEGIS_IN_DOCKING_RANGE))
		[aegisSprite blitCentredToX:x Y:y Z:z1 Alpha:alpha];
}

- (void) drawSpeedBar:(NSDictionary *) info
{	
    double ds = [player dial_speed];
//	double hs = [player dial_hyper_speed];
	int x = SPEED_BAR_CENTRE_X;
	int y = SPEED_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( SPEED_BAR_WIDTH, SPEED_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	BOOL draw_surround = SPEED_BAR_DRAW_SURROUND;
	if ([info objectForKey:DRAW_SURROUND_KEY])
		draw_surround = [(NSNumber *)[info objectForKey:DRAW_SURROUND_KEY] boolValue];

	if (draw_surround)
	{
		// draw speed surround
		glColor4fv(green_color);
		hudDrawSurroundAt( x, y, z1, siz);
	}
	// draw speed bar
	if (ds > .25)
		glColor4fv(yellow_color);
	if (ds > .80)
		glColor4fv(red_color);
	hudDrawBarAt( x, y, z1, siz, ds);
	
}

- (void) drawRollBar:(NSDictionary *) info
{	
    int x = ROLL_BAR_CENTRE_X;
	int y = ROLL_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( ROLL_BAR_WIDTH, ROLL_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	BOOL draw_surround = ROLL_BAR_DRAW_SURROUND;
	if ([info objectForKey:DRAW_SURROUND_KEY])
		draw_surround = [(NSNumber *)[info objectForKey:DRAW_SURROUND_KEY] boolValue];

	if (draw_surround)
	{
		// draw ROLL surround
		glColor4fv(green_color);
		hudDrawSurroundAt( x, y, z1, siz);
	}
	// draw ROLL bar
	glColor4fv(yellow_color);
	hudDrawIndicatorAt( x, y, z1, siz, [player dial_roll]);
}

- (void) drawPitchBar:(NSDictionary *) info
{	
    int x = PITCH_BAR_CENTRE_X;
	int y = PITCH_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( PITCH_BAR_WIDTH, PITCH_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	BOOL draw_surround = PITCH_BAR_DRAW_SURROUND;
	if ([info objectForKey:DRAW_SURROUND_KEY])
		draw_surround = [(NSNumber *)[info objectForKey:DRAW_SURROUND_KEY] boolValue];

	if (draw_surround)
	{
		// draw PITCH surround
		glColor4fv(green_color);
		hudDrawSurroundAt( x, y, z1, siz);
	}
	// draw PITCH bar
	glColor4fv(yellow_color);
	hudDrawIndicatorAt( x, y, z1, siz, [player dial_pitch]);
}

- (void) drawEnergyGauge:(NSDictionary *) info
{	
	int n_bars = [player dial_max_energy]/64.0;
	if (n_bars < 1)
		n_bars = 1;

    int x = ENERGY_GAUGE_CENTRE_X;
	int y = ENERGY_GAUGE_CENTRE_Y;
	

	NSSize siz = NSMakeSize( ENERGY_GAUGE_WIDTH, ENERGY_GAUGE_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	BOOL draw_surround = ENERGY_GAUGE_DRAW_SURROUND;
	if ([info objectForKey:DRAW_SURROUND_KEY])
		draw_surround = [(NSNumber *)[info objectForKey:DRAW_SURROUND_KEY] boolValue];
	BOOL labelled = YES;
	if ([info objectForKey:LABELLED_KEY])
		labelled = [(NSNumber *)[info objectForKey:LABELLED_KEY] boolValue];
	
	if ([info objectForKey:N_BARS_KEY])
		n_bars = [(NSNumber *)[info objectForKey:N_BARS_KEY] intValue];
		
	if (n_bars > 8)
		labelled = NO;
		
	if (draw_surround)
	{
		// draw energy surround
		glColor4fv(yellow_color);
		hudDrawSurroundAt( x, y, z1, siz);
	}
	// draw energy surround
	glColor4fv(yellow_color);
	hudDrawSurroundAt( x, y, z1, siz);
	// draw energy banks
	{
		int qy = siz.height / n_bars;
		NSSize dial_size = NSMakeSize(siz.width,qy - 2);
		int cy = y - (n_bars - 1) * qy / 2;
		double energy = [player dial_energy]*n_bars;
		[player setAlert_flag:ALERT_FLAG_ENERGY :((energy < 1.0)&&(player->status == STATUS_IN_FLIGHT))];
		int i;
		for (i = 0; i < n_bars; i++)
		{
			glColor4fv(yellow_color);
			if (energy > 1.0)
				hudDrawBarAt( x, cy, z1, dial_size, 1.0);
			if ((energy > 0.0)&&(energy <= 1.0))
				hudDrawBarAt( x, cy, z1, dial_size, energy);
			if (labelled)
			{
				glColor4f( 0.0, 1.0, 0.0, 1.0);
				drawString([NSString stringWithFormat:@"E%x",n_bars - i], x + 0.5 * dial_size.width + 2, cy - 0.5 * qy, z1, NSMakeSize(9, (qy < 18)? qy : 18 ));
			}
			energy -= 1.0;
			cy += qy;
		}
	}

}

- (void) drawForwardShieldBar:(NSDictionary *) info
{	
    int x = FORWARD_SHIELD_BAR_CENTRE_X;
	int y = FORWARD_SHIELD_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( FORWARD_SHIELD_BAR_WIDTH, FORWARD_SHIELD_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	BOOL draw_surround = FORWARD_SHIELD_BAR_DRAW_SURROUND;
	if ([info objectForKey:DRAW_SURROUND_KEY])
		draw_surround = [(NSNumber *)[info objectForKey:DRAW_SURROUND_KEY] boolValue];

	double shield = [player dial_forward_shield];
	if (draw_surround)
	{
		// draw forward_shield surround
		glColor4fv(green_color);
		hudDrawSurroundAt( x, y, z1, siz);
	}
	// draw forward_shield bar
	glColor4fv(green_color);
	if (shield < .80)
		glColor4fv(yellow_color);
	if (shield < .25)
		glColor4fv(red_color);
	hudDrawBarAt( x, y, z1, siz, shield);
}

- (void) drawAftShieldBar:(NSDictionary *) info
{	
    int x = AFT_SHIELD_BAR_CENTRE_X;
	int y = AFT_SHIELD_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( AFT_SHIELD_BAR_WIDTH, AFT_SHIELD_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	BOOL draw_surround = AFT_SHIELD_BAR_DRAW_SURROUND;
	if ([info objectForKey:DRAW_SURROUND_KEY])
		draw_surround = [(NSNumber *)[info objectForKey:DRAW_SURROUND_KEY] boolValue];

	double shield = [player dial_aft_shield];
	if (draw_surround)
	{
		// draw aft_shield surround
		glColor4fv(green_color);
		hudDrawSurroundAt( x, y, z1, siz);
	}
	// draw aft_shield bar
	glColor4fv(green_color);
	if (shield < .80)
		glColor4fv(yellow_color);
	if (shield < .25)
		glColor4fv(red_color);
	hudDrawBarAt( x, y, z1, siz, shield);
}

- (void) drawFuelBar:(NSDictionary *) info
{	
    int x = FUEL_BAR_CENTRE_X;
	int y = FUEL_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( FUEL_BAR_WIDTH, FUEL_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	// draw fuel bar
	glColor4fv(yellow_color);
	hudDrawBarAt( x, y, z1, siz, [player dial_fuel]);
}

- (void) drawCabinTempBar:(NSDictionary *) info
{	
    int x = CABIN_TEMP_BAR_CENTRE_X;
	int y = CABIN_TEMP_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( CABIN_TEMP_BAR_WIDTH, CABIN_TEMP_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	double temp = [player dial_cabin_temp];
	int flash = (int)([[player universe] getTime] * 4);
	flash &= 1;
	// draw cabin_temp bar
	glColor4fv(green_color);
	if (temp > .25)
		glColor4fv(yellow_color);
	if (temp > .80)
		glColor4fv(red_color);
	if ((flash)&&(temp > .90))
		glColor4fv(redplus_color);
	[player setAlert_flag:ALERT_FLAG_TEMP :((temp > .90)&&(player->status == STATUS_IN_FLIGHT))];
	hudDrawBarAt( x, y, z1, siz, temp);
}

- (void) drawWeaponTempBar:(NSDictionary *) info
{	
    int x = WEAPON_TEMP_BAR_CENTRE_X;
	int y = WEAPON_TEMP_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( WEAPON_TEMP_BAR_WIDTH, WEAPON_TEMP_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	double temp = [player dial_weapon_temp];
	// draw weapon_temp bar
	glColor4fv(green_color);
	if (temp > .25)
		glColor4fv(yellow_color);
	if (temp > .80)
		glColor4fv(red_color);
	hudDrawBarAt( x, y, z1, siz, temp);
}

- (void) drawAltitudeBar:(NSDictionary *) info
{	
    int x = ALTITUDE_BAR_CENTRE_X;
	int y = ALTITUDE_BAR_CENTRE_Y;
	NSSize siz = NSMakeSize( ALTITUDE_BAR_WIDTH, ALTITUDE_BAR_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	double alt = [player dial_altitude];
	int flash = (int)([[player universe] getTime] * 4);
	flash &= 1;
	// draw altitude bar
	glColor4fv(green_color);
	if (alt < .75)
		glColor4fv(yellow_color);
	if (alt < .25)
		glColor4fv(red_color);
	if ((flash)&&(alt < .10))
		glColor4fv(redplus_color);
	[player setAlert_flag:ALERT_FLAG_ALT :((alt < .10)&&(player->status == STATUS_IN_FLIGHT))];
	hudDrawBarAt( x, y, z1, siz, alt);
}

- (void) drawMissileDisplay:(NSDictionary *) info
{	
    int x = MISSILES_DISPLAY_X;
	int y = MISSILES_DISPLAY_Y;
	int sp = MISSILES_DISPLAY_SPACING;
	NSSize siz = NSMakeSize( MISSILE_ICON_HEIGHT, MISSILE_ICON_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:SPACING_KEY])
		sp = [(NSNumber *)[info objectForKey:SPACING_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	if (![player dial_ident_engaged])
	{
		int n_mis = [player dial_max_missiles];
		int i;
		for (i = 0; i < n_mis; i++)
		{
			if ([player missile_for_station:i])
			{
				NSString* miss_roles = [[player missile_for_station:i] roles];
				if (i == [player active_missile])
				{
					glColor4fv(yellow_color);
					glBegin(GL_POLYGON);
					if ([miss_roles hasSuffix:@"MISSILE"])
						hudDrawMissileIconAt( x + i * sp + 2, y + 1, z1, NSMakeSize( siz.width + 4, siz.height + 4));
					if ([miss_roles hasSuffix:@"MINE"])
						hudDrawMineIconAt( x + i * sp + 2, y + 1, z1, NSMakeSize( siz.width + 4, siz.height + 4));
					glEnd();
					switch ([player dial_missile_status])
					{
						case MISSILE_STATUS_SAFE :
							glColor4fv(green_color);	break;
						case MISSILE_STATUS_ARMED :
							glColor4fv(yellow_color);	break;
						case MISSILE_STATUS_TARGET_LOCKED :
							glColor4fv(red_color);	break;
					}
				}
				else
				{
					if ([[player missile_for_station:i] getPrimaryTarget])
						glColor4fv(red_color);
					else
						glColor4fv(green_color);
				}
				glBegin(GL_POLYGON);
				if ([miss_roles hasSuffix:@"MISSILE"])
					hudDrawMissileIconAt( x + i * sp, y, z1, siz);
				if ([miss_roles hasSuffix:@"MINE"])
					hudDrawMineIconAt( x + i * sp, y, z1, siz);
//				hudDrawMissileIconAt( x + i * sp, y, z1, siz);
				glEnd();
				if (i != [player active_missile])
				{
					glColor4fv(green_color);
					glBegin(GL_LINE_LOOP);
					if ([miss_roles hasSuffix:@"MISSILE"])
						hudDrawMissileIconAt( x + i * sp, y, z1, siz);
					if ([miss_roles hasSuffix:@"MINE"])
						hudDrawMineIconAt( x + i * sp, y, z1, siz);
//					hudDrawMissileIconAt( x + i * sp, y, z1, siz);
					glEnd();
				}
			}
			else
			{
				glColor4f(0.25, 0.25, 0.25, 0.5);
				glBegin(GL_LINE_LOOP);
				hudDrawMissileIconAt( x + i * sp, y, z1, siz);
				glEnd();
			}
		}
	}
	else
	{
		x -= siz.width;
		y -= siz.height * 0.75;
		siz.width *= 0.80;
		sp *= 0.75;
		switch ([player dial_missile_status])
		{
			case MISSILE_STATUS_SAFE :
				glColor4fv(green_color);	break;
			case MISSILE_STATUS_ARMED :
				glColor4fv(yellow_color);	break;
			case MISSILE_STATUS_TARGET_LOCKED :
				glColor4fv(red_color);	break;
		}
		glBegin(GL_QUADS);
		glVertex3i( x , y, z1);
		glVertex3i( x + siz.width, y, z1);
		glVertex3i( x + siz.width, y + siz.height, z1);
		glVertex3i( x , y + siz.height, z1);
		glEnd();
		glColor4f( 0.0, 1.0, 0.0, 1.0);
		drawString( [player dial_target_name], x + sp, y, z1, NSMakeSize( siz.width, siz.height));
	}
	
}

- (void) drawTargetReticle:(NSDictionary *) info;
{
	// the missile target reticle is an advanced option
	// so we need to check for its extra equipment flag first
	if (([info objectForKey:EQUIPMENT_REQUIRED_KEY])&&
		(![player has_extra_equipment:(NSString *)[info objectForKey:EQUIPMENT_REQUIRED_KEY]]))
		return;
	
	if ([player dial_missile_status] == MISSILE_STATUS_TARGET_LOCKED)
	{
		//Entity *target = [player getPrimaryTarget];
		hudDrawReticleOnTarget( [player getPrimaryTarget], player, z1);
		[self drawDirectionCue:info];
	}
}

- (void) drawStatusLight:(NSDictionary *) info
{
	GLfloat status_color[4] = { 0.25, 0.25, 0.25, 1.0};
	int alert_condition = [player alert_condition];
	double flash_alpha = 0.333 * (2.0 + sin([[player universe] getTime] * 2.5 * alert_condition));
    int x = STATUS_LIGHT_CENTRE_X;
	int y = STATUS_LIGHT_CENTRE_Y;
	NSSize siz = NSMakeSize( STATUS_LIGHT_HEIGHT, STATUS_LIGHT_HEIGHT);
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	//
	switch(alert_condition)
	{
		case ALERT_CONDITION_RED :
//			glColor4fv(red_color);
			status_color[0] = red_color[0];
			status_color[1] = red_color[1];
			status_color[2] = red_color[2];
			break;
		case ALERT_CONDITION_GREEN :
//			glColor4fv(green_color);
			status_color[0] = green_color[0];
			status_color[1] = green_color[1];
			status_color[2] = green_color[2];
			break;
		case ALERT_CONDITION_YELLOW :
//			glColor4fv(yellow_color);
			status_color[0] = yellow_color[0];
			status_color[1] = yellow_color[1];
			status_color[2] = yellow_color[2];
			break;
		default :
		case ALERT_CONDITION_DOCKED :
//			glColor4f( 0.25, 0.25, 0.25, 1.0);
			break;
	}
	status_color[3] = flash_alpha;
	glColor4fv(status_color);
	glBegin(GL_POLYGON);
	hudDrawStatusIconAt( x, y, z1, siz);
	glEnd();
	glColor4f( 0.25, 0.25, 0.25, 1.0);
	glBegin(GL_LINE_LOOP);
	hudDrawStatusIconAt( x, y, z1, siz);
	glEnd();
}

- (void) drawDirectionCue:(NSDictionary *) info
{	
 	// the direction cue is an advanced option
	// so we need to check for its extra equipment flag first
	if (([info objectForKey:EQUIPMENT_REQUIRED_KEY])&&
		(![player has_extra_equipment:(NSString *)[info objectForKey:EQUIPMENT_REQUIRED_KEY]]))
		return;
	
	if ([[player universe] displayGUI])
		return;
	
	if ([player dial_missile_status] == MISSILE_STATUS_TARGET_LOCKED)
	{
		GLfloat clear_color[4] = {0.0, 1.0, 0.0, 0.0};
		Entity *target = [player getPrimaryTarget];
		if (!target)
			return;
		
		// draw the direction cue
		Matrix rotMatrix;
		Vector position = player->position;
		gl_matrix_into_matrix([player rotationMatrix], rotMatrix);
		//
		if ([[player universe] viewDir] != VIEW_DOCKED)
		{
			GLfloat siz1 = CROSSHAIR_SIZE * (1.0 - ONE_EIGHTH);
			GLfloat siz0 = CROSSHAIR_SIZE * ONE_EIGHTH;
			GLfloat siz2 = CROSSHAIR_SIZE * (1.0 + ONE_EIGHTH);
			Vector rpn = target->position;
			// translate the view
			rpn.x -= position.x;   rpn.y -= position.y;   rpn.z -= position.z;
			// rotate the view
			mult_vector(&rpn, rotMatrix);
			switch ([[player universe] viewDir])
			{
				case VIEW_AFT :
					rpn.x = - rpn.x;
					break;
				case VIEW_PORT :
					rpn.x = rpn.z;
					break;
				case VIEW_STARBOARD :
					rpn.x = -rpn.z;
					break;
			}
			rpn.z = 0;	// flatten vector
			rpn = unit_vector(&rpn);
			glBegin(GL_LINES);
				glColor4fv(clear_color);
				glVertex3f( rpn.x * siz1 - rpn.y * siz0, rpn.y * siz1 + rpn.x * siz0, z1);
				glColor4fv(green_color);
				glVertex3f( rpn.x * siz2, rpn.y * siz2, z1);
				glColor4fv(clear_color);
				glVertex3f( rpn.x * siz1 + rpn.y * siz0, rpn.y * siz1 - rpn.x * siz0, z1);
				glColor4fv(green_color);
				glVertex3f( rpn.x * siz2, rpn.y * siz2, z1);
			glEnd();
		}
	}
}

- (void) drawClock:(NSDictionary *) info
{
    int x = CLOCK_DISPLAY_X;
	int y = CLOCK_DISPLAY_Y;
	NSSize siz = NSMakeSize( CLOCK_DISPLAY_WIDTH, CLOCK_DISPLAY_HEIGHT);
	
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	glColor4f( 0.0, 1.0, 0.0, 1.0);
	drawString( [player dial_clock], x, y, z1, siz);
}

- (void) drawFPSInfoCounter:(NSDictionary *) info
{
    if (![[player universe] displayFPS])
		return;
	
	int x = FPSINFO_DISPLAY_X;
	int y = FPSINFO_DISPLAY_Y;
	NSSize siz = NSMakeSize( FPSINFO_DISPLAY_WIDTH, FPSINFO_DISPLAY_HEIGHT);
	
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	glColor4f( 0.0, 1.0, 0.0, 1.0);
	drawString( [player dial_fpsinfo], x, y, z1, siz);
	drawString( [player dial_objinfo], x, y - siz.height, z1, siz);
}

- (void) drawGreenSurround:(NSDictionary *) info
{	
    int x, y;
	NSSize siz;
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	else
		return;
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	else
		return;
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	else
		return;
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	else
		return;

	// draw aft_shield surround
	glColor4fv(green_color);
	hudDrawSurroundAt( x, y, z1, siz);
}

- (void) drawYellowSurround:(NSDictionary *) info
{	
    int x, y;
	NSSize siz;
	if ([info objectForKey:X_KEY])
		x = [(NSNumber *)[info objectForKey:X_KEY] intValue];
	else
		return;
	if ([info objectForKey:Y_KEY])
		y = [(NSNumber *)[info objectForKey:Y_KEY] intValue];
	else
		return;
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	else
		return;
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
	else
		return;

	// draw aft_shield surround
	glColor4fv(yellow_color);
	hudDrawSurroundAt( x, y, z1, siz);
}

- (void) drawCollisionHitIndicator:(NSDictionary *) info
{	
    [player drawCollisionHitIndicator:info depth:z1];
}

//---------------------------------------------------------------------//

void hudDrawIndicatorAt(int x, int y, int z, NSSize siz, double amount)
{
	if (siz.width > siz.height)
	{
		int dial_oy =   y - siz.height/2;
		int position =  x + amount * siz.width / 2;
		glBegin(GL_QUADS);
			glVertex3i( position, dial_oy, z);
			glVertex3i( position+2, y, z);
			glVertex3i( position, dial_oy+siz.height, z);
			glVertex3i( position-2, y, z);
		glEnd();
	}
	else
	{
		int dial_ox =   x - siz.width/2;
		int position =  y + amount * siz.height / 2;
		glBegin(GL_QUADS);
			glVertex3i( dial_ox, position, z);
			glVertex3i( x, position+2, z);
			glVertex3i( dial_ox + siz.width, position, z);
			glVertex3i( x, position-2, z);
		glEnd();
	}
}

void hudDrawBarAt(int x, int y, int z, NSSize siz, double amount)
{
	GLfloat dial_ox =   x - siz.width/2;
	GLfloat dial_oy =   y - siz.height/2;
	if (siz.width > siz.height)
	{
		GLfloat position =  dial_ox + amount * siz.width;
		
		glBegin(GL_QUADS);
			glVertex3f( dial_ox, dial_oy, z);
			glVertex3f( position, dial_oy, z);
			glVertex3f( position, dial_oy+siz.height, z);
			glVertex3f( dial_ox, dial_oy+siz.height, z);
		glEnd();
	}
	else
	{
		GLfloat position =  dial_oy + amount * siz.height;
		
		glBegin(GL_QUADS);
			glVertex3f( dial_ox, dial_oy, z);
			glVertex3f( dial_ox, position, z);
			glVertex3f( dial_ox+siz.width, position, z);
			glVertex3f( dial_ox+siz.width, dial_oy, z);
		glEnd();
	}
}

void hudDrawSurroundAt(int x, int y, int z, NSSize siz)
{
	int dial_ox = x - siz.width/2;
	int dial_oy = y - siz.height/2;

	glBegin(GL_LINE_LOOP);
		glVertex3i( dial_ox-2, dial_oy-2, z);
		glVertex3i( dial_ox+siz.width+2, dial_oy-2, z);
		glVertex3i( dial_ox+siz.width+2, dial_oy+siz.height+2, z);
		glVertex3i( dial_ox-2, dial_oy+siz.height+2, z);
	glEnd();
}

void hudDrawMissileIconAt(int x, int y, int z, NSSize siz)
{
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 

	glVertex3i( ox, oy + 3 * h, z);
	glVertex3i( ox + 2 * w, oy, z);
	glVertex3i( ox + w, oy, z);
	glVertex3i( ox + w, oy - 2 * h, z);
	glVertex3i( ox - w, oy - 2 * h, z);
	glVertex3i( ox - w, oy, z);
	glVertex3i( ox - 2 * w, oy, z);
}

void hudDrawMineIconAt(int x, int y, int z, NSSize siz)
{
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 

	glVertex3i( ox, oy + 2 * h, z);
	glVertex3i( ox + w, oy + h, z);
	glVertex3i( ox + w, oy - h, z);
	glVertex3i( ox, oy - 2 * h, z);
	glVertex3i( ox - w, oy - h, z);
	glVertex3i( ox - w, oy + h, z);
}

void hudDrawStatusIconAt(int x, int y, int z, NSSize siz)
{
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 

	glVertex3i( ox, oy + h, z);
	glVertex3i( ox, oy + 3 * h, z);
	glVertex3i( ox + w, oy + 4 * h, z);
	glVertex3i( ox + 3 * w, oy + 4 * h, z);
	glVertex3i( ox + 4 * w, oy + 3 * h, z);
	glVertex3i( ox + 4 * w, oy + h, z);
	glVertex3i( ox + 3 * w, oy, z);
	glVertex3i( ox + w, oy, z);
}


void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1)
{
	//GLfloat z1 = [(MyOpenGLView *)[[player1 universe] gameView] display_z];
	ShipEntity* target_ship = (ShipEntity *)target;
	NSString* legal_desc = nil;
	if ((!target)||(!player1))
		return;
	switch (target_ship->scan_class)
	{
		case CLASS_NEUTRAL :
		{
			int target_legal = [target_ship legal_status];
			int legal_i = 0;
			if (target_legal > 0)
				legal_i =  (target_legal <= 50) ? 1 : 2;
			legal_desc = [(NSArray *)[[[player1 universe] descriptions] objectForKey:@"legal_status"] objectAtIndex:legal_i];
		}
		break;
	
		case CLASS_THARGOID :
		legal_desc = @"Alien";
		break;
		
		case CLASS_POLICE :
		legal_desc = @"System Vessel";
		break;
		
		default :
		case CLASS_BUOY :
		case CLASS_CARGO :
		case CLASS_ROCK :
		case CLASS_MISSILE :
		case CLASS_NO_DRAW :
		case CLASS_STATION :
		case CLASS_TARGET :
		break;
	}

	
	if ([player1 gui_screen] != GUI_SCREEN_MAIN)	// don't draw on text screens
		return;
	
	if (!target)
		return;
	
	gl_matrix	back_mat;
    Quaternion  back_q = player1->q_rotation;
	back_q.w = -back_q.w;   // invert
	Vector p0 = [player1 getViewpointPosition];
	Vector p1 = target->position;
	p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
	double rdist = sqrt(magnitude2(p1));
	double rsize = target->collision_radius;
	
	if (rsize < rdist * ONE_SIXTYFOURTH)
		rsize = rdist * ONE_SIXTYFOURTH;
	
	double rs0 = rsize;
	//double rs3 = rsize * 0.75;
	double rs2 = rsize * 0.50;
	//double rs1 = rsize * 0.25;
	
	glPushMatrix();
	//
	// deal with view directions
	Vector view_dir;
	switch ([[player1 universe] viewDir])
	{
		case VIEW_FORWARD :
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
			break;
		case VIEW_AFT :
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = 1.0;
			quaternion_rotate_about_axis(&back_q,vector_up_from_quaternion(back_q),PI);
			break;
		case VIEW_PORT :
			view_dir.x = 1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q,vector_up_from_quaternion(back_q),PI/2.0);
			break;
		case VIEW_STARBOARD :
			view_dir.x = -1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q,vector_up_from_quaternion(back_q),-PI/2.0);
			break;
		
		case VIEW_DOCKED :
		case VIEW_BREAK_PATTERN :
		default :
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
			break;
	}
    gluLookAt(0.0, 0.0, 0.0,	view_dir.x, view_dir.y, view_dir.z,	0.0, 1.0, 0.0);
	//
	quaternion_into_gl_matrix(back_q, back_mat);
	//
	// rotate the view
	glMultMatrixf([player1 rotationMatrix]);
	// translate the view
	glTranslatef(p1.x, p1.y, p1.z);
	//rotate to face player1
	glMultMatrixf(back_mat);
	// draw the reticle	
	glColor4fv(green_color);
	glBegin(GL_LINES);
		glVertex2f(rs0,rs2);	glVertex2f(rs0,rs0);
		glVertex2f(rs0,rs0);	glVertex2f(rs2,rs0);

		glVertex2f(rs0,-rs2);	glVertex2f(rs0,-rs0);
		glVertex2f(rs0,-rs0);	glVertex2f(rs2,-rs0);

		glVertex2f(-rs0,rs2);	glVertex2f(-rs0,rs0);
		glVertex2f(-rs0,rs0);	glVertex2f(-rs2,rs0);

		glVertex2f(-rs0,-rs2);	glVertex2f(-rs0,-rs0);
		glVertex2f(-rs0,-rs0);	glVertex2f(-rs2,-rs0);
	
//	NSLog(@"DEBUG rs0 %.3f %.3f",rs0, rs2);
	
	glEnd();
	
	// add text for reticle here
	float range = sqrt(target->zero_distance)/1000;
	NSSize textsize = NSMakeSize( rdist * ONE_SIXTYFOURTH, rdist * ONE_SIXTYFOURTH);
	float line_height = rdist * ONE_SIXTYFOURTH;
	NSString *info1 = [(ShipEntity *)target name];
	NSString *info2 = (legal_desc == nil)? [NSString stringWithFormat:@"%0.3f km", range] : [NSString stringWithFormat:@"%0.3f km (%@)", range, legal_desc];
	// no need to set color - tis green already!
	drawString( info1, rs0, 0.5 * rs2, 0, textsize);
	drawString( info2, rs0, 0.5 * rs2 - line_height, 0, textsize);
	
	glPopMatrix();
}

double drawCharacterQuad(int chr, double x, double y, double z, NSSize siz)
{
	if ((chr < 0) || (chr > 127))
		return 0;
	double texture_x = ONE_SIXTEENTH * (chr & 0x0f);
	double texture_y = ONE_EIGHTH * (chr >> 4);		// divide by 16 fast
	
	glTexCoord2f( texture_x, texture_y + ONE_EIGHTH);
	glVertex3f( x, y, z);
	glTexCoord2f( texture_x + ONE_SIXTEENTH, texture_y + ONE_EIGHTH);
	glVertex3f( x + siz.width, y, z);
	glTexCoord2f( texture_x + ONE_SIXTEENTH, texture_y);
	glVertex3f( x + siz.width, y + siz.height, z);
	glTexCoord2f( texture_x, texture_y);
	glVertex3f( x, y + siz.height, z);

	return siz.width * 0.13 * char_widths[chr];
}

void drawString(NSString *text, double x, double y, double z, NSSize siz)
{
	int i;
	double cx = x;
//	NSLog(@"DEBUG drawing string (%@) at %.1f, %.1f, %.1f (%.1f x %.1f)", text, x, y, z, siz.width, siz.height);
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	glBindTexture(GL_TEXTURE_2D, ascii_texture_name);
//	glColor4f( 0.0, 1.0, 0.0, 1.0);

	glBegin(GL_QUADS);
	for (i = 0; i < [text length]; i++)
	{
		int ch = (int)[text characterAtIndex:i];
		ch = ch & 0x7f;
		cx += drawCharacterQuad( ch, cx, y, z, siz);
	}
	glEnd();

	glDisable(GL_TEXTURE_2D);
		
}

NSRect rectForString(NSString *text, double x, double y, NSSize siz)
{
	int i;
	double w = 0;
	for (i = 0; i < [text length]; i++)
	{
		int ch = (int)[text characterAtIndex:i];
		ch = ch & 0x7f;
		w += siz.width * 0.13 * char_widths[ch];
	}

	return NSMakeRect( x, y, w, siz.height);
}

void drawScannerGrid( double x, double y, double z, NSSize siz, int v_dir, GLfloat thickness)
{
	GLfloat ww = 0.5 * siz.width;
	GLfloat w1 = 0.125 * siz.width;
	GLfloat w2 = 0.250 * siz.width;
//	GLfloat w3 = 0.375 * siz.width;
	GLfloat hh = 0.5 * siz.height;
	GLfloat h1 = 0.125 * siz.height;
	GLfloat h2 = 0.250 * siz.height;
	GLfloat h3 = 0.375 * siz.height;
//	glColor4f( 1.0, 0.0, 0.0, alpha);
	
	glLineWidth(2.0 * thickness);
	
	drawOval( x, y, z, siz, 4);	
	
	glLineWidth(thickness);
	
	glBegin(GL_LINES);
		glVertex3f(x, y - hh, z);	glVertex3f(x, y + hh, z);
		glVertex3f(x - ww, y, z);	glVertex3f(x + ww, y, z);
		glVertex3f(x - w1, y - h1, z);	glVertex3f(x + w1, y - h1, z);
		glVertex3f(x - w1, y - h2, z);	glVertex3f(x + w1, y - h2, z);
		glVertex3f(x - w1, y - h3, z);	glVertex3f(x + w1, y - h3, z);
		glVertex3f(x - w1, y + h1, z);	glVertex3f(x + w1, y + h1, z);
		glVertex3f(x - w1, y + h2, z);	glVertex3f(x + w1, y + h2, z);
		glVertex3f(x - w1, y + h3, z);	glVertex3f(x + w1, y + h3, z);
		switch (v_dir)
		{
			case VIEW_BREAK_PATTERN :
			case VIEW_DOCKED :
			case VIEW_FORWARD :
			case VIEW_NONE :
				glVertex3f( x, y, z); glVertex3f(x - w2, y + hh, z);
				glVertex3f( x, y, z); glVertex3f(x + w2, y + hh, z);
				break;
			case VIEW_AFT :
				glVertex3f( x, y, z); glVertex3f(x - w2, y - hh, z);
				glVertex3f( x, y, z); glVertex3f(x + w2, y - hh, z);
				break;
			case VIEW_PORT :
				glVertex3f( x, y, z); glVertex3f(x - ww, y + h2, z);
				glVertex3f( x, y, z); glVertex3f(x - ww, y - h2, z);
				break;
			case VIEW_STARBOARD :
				glVertex3f( x, y, z); glVertex3f(x + ww, y + h2, z);
				glVertex3f( x, y, z); glVertex3f(x + ww, y - h2, z);
				break;
		}
	glEnd();
}

void drawOval( double x, double y, double z, NSSize siz, int step)
{
	int i;
	GLfloat ww = 0.5 * siz.width;
	GLfloat hh = 0.5 * siz.height;
	glBegin(GL_LINE_LOOP);
	for (i = 0; i < 360; i += step)
		glVertex3f(x + ww * sin_value[i], y + hh * sin_value[(i + 90) % 360], z);
//	glVertex3f(x, y + hh, z);
	glEnd();
	return;
}

void drawFilledOval( double x, double y, double z, NSSize siz, int step)
{
	int i;
	GLfloat ww = 0.5 * siz.width;
	GLfloat hh = 0.5 * siz.height;
	glBegin(GL_TRIANGLE_FAN);
	glVertex3f( x, y, z);
	for (i = 0; i < 360; i += step)
		glVertex3f(x + ww * sin_value[i], y + hh * sin_value[(i + 90) % 360], z);
	glVertex3f(x, y + hh, z);
	glEnd();
	return;
}

void drawSpecialOval( double x, double y, double z, NSSize siz, int step, GLfloat* color4v)
{
	int i;
	GLfloat ww = 0.5 * siz.width;
	GLfloat hh = 0.5 * siz.height;
	glEnable(GL_LINE_SMOOTH);
	glBegin(GL_LINE_LOOP);
	for (i = 0; i < 360; i += step)
	{
		glColor4f( color4v[0], color4v[1], color4v[2], fabs(sin_value[i] * color4v[3]));
		glVertex3f(x + ww * sin_value[i], y + hh * sin_value[(i + 90) % 360], z);
	}
	glEnd();
	return;
}

- (void) setLine_width:(GLfloat) value
{
	line_width = value;
}

- (GLfloat) line_width
{
	return line_width;
}

@end
