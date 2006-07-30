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
#import "PlayerEntity.h"
#import "PlanetEntity.h"
#import "Universe.h"
#import "TextureStore.h"
#import "OOTrumble.h"
#import "OOColor.h"

static const char *toAscii(unsigned inCodePoint);

@implementation HeadUpDisplay

GLfloat red_color[4] =		{1.0, 0.0, 0.0, 1.0};
GLfloat redplus_color[4] =  {1.0, 0.0, 0.5, 1.0};
GLfloat yellow_color[4] =   {1.0, 1.0, 0.0, 1.0};
GLfloat green_color[4] =	{0.0, 1.0, 0.0, 1.0};
GLfloat darkgreen_color[4] ={0.0, 0.75, 0.0, 1.0};
GLfloat blue_color[4] =		{0.0, 0.0, 1.0, 1.0};

float char_widths[128] = {
	8.000,	7.000,	8.000,	8.000,	7.000,	6.000,	7.000,	6.000,	6.000,	6.000,	6.000,	6.000,	6.000,	6.000,	6.000,	6.000,
	5.000,	6.000,	6.000,	6.000,	6.000,	6.000,	7.500,	8.000,	6.000,	6.000,	6.000,	6.000,	6.000,	6.000,	6.000,	6.000,
	1.750,	2.098,	2.987,	3.504,	3.504,	5.602,	4.550,	1.498,	2.098,	2.098,	2.452,	3.679,	1.750,	2.098,	1.750,	1.750,
	4.000,	4.000,	4.000,	4.000,	4.000,	4.000,	4.000,	4.000,	4.000,	4.000,	2.098,	2.098,	3.679,	3.679,	3.679,	3.848,
	6.143,	4.550,	4.550,	4.550,	4.550,	4.202,	3.848,	4.900,	4.550,	1.750,	3.504,	4.550,	3.848,	5.248,	4.550,	4.900,
	4.202,	4.900,	4.550,	4.202,	3.848,	4.550,	4.202,	5.946,	4.202,	4.202,	3.848,	2.098,	1.750,	2.098,	3.679,	3.504,
	2.098,	3.504,	3.848,	3.504,	3.848,	3.504,	2.098,	3.848,	3.848,	1.750,	1.750,	3.504,	1.750,	5.602,	3.848,	3.848,
	3.848,	3.848,	2.452,	3.504,	2.098,	3.848,	3.504,	4.900,	3.504,	3.504,	3.150,	2.452,	1.763,	2.452,	3.679,	6.000
};

- (id) initWithDictionary:(NSDictionary *) hudinfo;
{
	int i;
	BOOL areTrumblesToBeDrawn = NO;
	
	self = [super init];
	
	line_width = 1.0;
	
	setUpSinTable();
			
	// init arrays
	dialArray = [[NSMutableArray alloc] initWithCapacity:16];   // alloc retains
	legendArray = [[NSMutableArray alloc] initWithCapacity:16]; // alloc retains
	
	// populate arrays
	if ([hudinfo objectForKey:DIALS_KEY])
	{
		NSArray *dials = [hudinfo objectForKey:DIALS_KEY];
		for (i = 0; i < [dials count]; i++)
		{
			NSDictionary* dial_info = (NSDictionary *)[dials objectAtIndex:i];
			areTrumblesToBeDrawn |= [(NSString*)[dial_info objectForKey:SELECTOR_KEY] isEqual:@"drawTrumbles:"];
			[self addDial: dial_info];
		}
	}
	if (!areTrumblesToBeDrawn)	// naughty - a hud with no built-in drawTrumbles: - one must be added!
	{
//		NSLog(@"DEBUG 	// naughty - a hud with no built-in drawTrumbles: - one must be added!");
		//
		NSDictionary* trumble_dial_info = [NSDictionary dictionaryWithObjectsAndKeys: @"drawTrumbles:", SELECTOR_KEY, nil];
		[self addDial: trumble_dial_info];
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

- (void) resizeGuis:(NSDictionary*) info
{
	// check for entries in hud plist for comm_log_gui and message_gui
	// resize and reposition them accordingly
	
	if (!player)
		return;
	Universe* universe = [player universe];
	if (!universe)
		return;
	
	GuiDisplayGen* message_gui = [universe message_gui];
	if ((message_gui)&&([info objectForKey:@"message_gui"]))
	{
		NSDictionary* gui_info = (NSDictionary*)[info objectForKey:@"message_gui"];
		Vector pos = [message_gui drawPosition];
		if ([gui_info objectForKey:X_KEY])
			pos.x = [[gui_info objectForKey:X_KEY] floatValue];
		if ([gui_info objectForKey:Y_KEY])
			pos.y = [[gui_info objectForKey:Y_KEY] floatValue];
		[message_gui setDrawPosition:pos];
		NSSize		siz =	[message_gui	size];
		int			rht =	[message_gui	rowHeight];
		NSString*	title =	[message_gui	title];
		if ([gui_info objectForKey:WIDTH_KEY])
			siz.width = [[gui_info objectForKey:WIDTH_KEY] floatValue];
		if ([gui_info objectForKey:HEIGHT_KEY])
			siz.height = [[gui_info objectForKey:HEIGHT_KEY] floatValue];
		if ([gui_info objectForKey:ROW_HEIGHT_KEY])
			rht = [[gui_info objectForKey:ROW_HEIGHT_KEY] intValue];
		if ([gui_info objectForKey:TITLE_KEY])
			title = [NSString stringWithFormat:@"%@", [gui_info objectForKey:TITLE_KEY]];
		[message_gui resizeTo: siz characterHeight: rht Title: title];
		if ([gui_info objectForKey:ALPHA_KEY])
			[message_gui setAlpha: [[gui_info objectForKey:ALPHA_KEY] floatValue]];
		else
			[message_gui setAlpha: 1.0];
		if ([gui_info objectForKey:BACKGROUND_RGBA_KEY])
			[message_gui setBackgroundColor:[OOColor colorFromString:(NSString *)[gui_info objectForKey:BACKGROUND_RGBA_KEY]]];
	}
	
	GuiDisplayGen* comm_log_gui = [universe comm_log_gui];
	if ((comm_log_gui)&&([info objectForKey:@"comm_log_gui"]))
	{
		NSDictionary* gui_info = (NSDictionary*)[info objectForKey:@"comm_log_gui"];
		Vector pos = [comm_log_gui drawPosition];
		if ([gui_info objectForKey:X_KEY])
			pos.x = [[gui_info objectForKey:X_KEY] floatValue];
		if ([gui_info objectForKey:Y_KEY])
			pos.y = [[gui_info objectForKey:Y_KEY] floatValue];
		[comm_log_gui setDrawPosition:pos];
		NSSize		siz =	[comm_log_gui	size];
		int			rht =	[comm_log_gui	rowHeight];
		NSString*	title =	[comm_log_gui	title];
		if ([gui_info objectForKey:WIDTH_KEY])
			siz.width = [[gui_info objectForKey:WIDTH_KEY] floatValue];
		if ([gui_info objectForKey:HEIGHT_KEY])
			siz.height = [[gui_info objectForKey:HEIGHT_KEY] floatValue];
		if ([gui_info objectForKey:ROW_HEIGHT_KEY])
			rht = [[gui_info objectForKey:ROW_HEIGHT_KEY] intValue];
		if ([gui_info objectForKey:TITLE_KEY])
			title = [NSString stringWithFormat:@"%@", [gui_info objectForKey:TITLE_KEY]];
		[comm_log_gui resizeTo: siz characterHeight: rht Title: title];
		if ([gui_info objectForKey:ALPHA_KEY])
			[comm_log_gui setAlpha: [[gui_info objectForKey:ALPHA_KEY] floatValue]];
		else
			[comm_log_gui setAlpha: 1.0];
		if ([gui_info objectForKey:BACKGROUND_RGBA_KEY])
			[comm_log_gui setBackgroundColor:[OOColor colorFromString:(NSString *)[gui_info objectForKey:BACKGROUND_RGBA_KEY]]];
	}
	
	
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
#ifdef GNUSTEP
		SDLImage		*legendImage = [ResourceManager surfaceNamed:(NSString *)[info objectForKey:IMAGE_KEY] inFolder:@"Images"];
#else
		NSImage			*legendImage = [ResourceManager imageNamed:(NSString *)[info objectForKey:IMAGE_KEY] inFolder:@"Images"];
#endif
		NSSize			imageSize = [legendImage size];
		NSSize			spriteSize = imageSize;
		if ([info objectForKey:WIDTH_KEY])
			spriteSize.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
		if ([info objectForKey:HEIGHT_KEY])
			spriteSize.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];
#ifdef GNUSTEP
 		OpenGLSprite *legendSprite = [[OpenGLSprite alloc] initWithSurface:legendImage
 										cropRectangle:NSMakeRect(0, 0, imageSize.width, imageSize.height) size:spriteSize]; // retained
#else
		OpenGLSprite *legendSprite = [[OpenGLSprite alloc] initWithImage:legendImage
										cropRectangle:NSMakeRect(0, 0, imageSize.width, imageSize.height) size:spriteSize]; // retained
#endif
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
	if (([info objectForKey:EQUIPMENT_REQUIRED_KEY])&&
		(![player has_extra_equipment:(NSString *)[info objectForKey:EQUIPMENT_REQUIRED_KEY]]))
		return;
	
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
	
	int i;
    int scanner_cx = x;
	int scanner_cy = y;
	double mass_lock_range2 = 25600.0*25600.0;

	int scanner_scale = SCANNER_MAX_RANGE * 2.5 / siz.width;

	double max_zoomed_range2 = SCANNER_SCALE*SCANNER_SCALE*10000.0/(scanner_zoom*scanner_zoom);
	
	GLfloat	max_zoomed_range = sqrtf(max_zoomed_range2);
	
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
	//
	GLfloat col[4] =	{ 1.0, 1.0, 1.0, 1.0};	// can be manipulated

	position = player->position;
	gl_matrix_into_matrix([player rotationMatrix], rotMatrix);
		
	glColor4fv( scanner_color);
	drawScannerGrid( x, y, z1, siz, [[player universe] viewDir], line_width, scanner_zoom);
	
	GLfloat off_scope2 = (siz.width > siz.height) ? siz.width * siz.width : siz.height * siz.height;
	
	//
	int p_status = player->status;

	if ((p_status == STATUS_IN_FLIGHT)||(p_status == STATUS_AUTOPILOT_ENGAGED)||(p_status == STATUS_LAUNCHING)||(p_status == STATUS_WITCHSPACE_COUNTDOWN))
	{
		double upscale = scanner_zoom*1.25/scanner_scale;
		off_scope2 /= upscale * upscale;
		double max_blip = 0.0;
		
		for (i = 0; i < ent_count; i++)  // scanner lollypops
		{
			drawthing = my_entities[i];
			
			int drawClass = drawthing->scan_class;
			if (drawClass == CLASS_PLAYER)	drawClass = CLASS_NO_DRAW;
			if (drawthing->isShip)
			{
				ShipEntity* ship = (ShipEntity*)drawthing;
				if (ship->cloaking_device_active)	drawClass = CLASS_NO_DRAW;
			}
			
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
						case CLASS_MILITARY :
						case CLASS_WORMHOLE :
						default :
							mass_locked = YES;
							break;
					}
				}
				
				[player setAlert_flag:ALERT_FLAG_MASS_LOCK :mass_locked];
				
				if (isnan(drawthing->zero_distance))
					continue;
				
				// exit if it's too far away
				GLfloat	act_dist = sqrtf(drawthing->zero_distance);
				GLfloat	lim_dist = act_dist - drawthing->collision_radius;
				
				if (lim_dist > max_zoomed_range)
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
				
				relativePosition = drawthing->relative_position;
				Vector rp = relativePosition;
				
				if (act_dist > max_zoomed_range)
					scale_vector(&relativePosition, max_zoomed_range / act_dist);

				// rotate the view
				mult_vector(&relativePosition, rotMatrix);
				// scale the view
				scale_vector(&relativePosition, upscale);
				
				x1 = relativePosition.x;
				y1 = z_factor * relativePosition.z;
				y2 = y1 + y_factor * relativePosition.y;
				
				isHostile = NO;
				if (drawthing->isShip)
				{
					ShipEntity* ship = (ShipEntity *)drawthing;
					double wr = [ship weapon_range];
					isHostile = (([ship hasHostileTarget])&&([ship getPrimaryTarget] == player)&&(drawthing->zero_distance < wr*wr));
					GLfloat* base_col = [ship scannerDisplayColorForShip:player :isHostile :flash];
					col[0] = base_col[0];	col[1] = base_col[1];	col[2] = base_col[2];	col[3] = alpha * base_col[3];
				}
				
				if (drawthing->isWormhole)
				{
					col[0] = blue_color[0];	col[1] = (flash)? 1.0 : blue_color[1];	col[2] = blue_color[2];	col[3] = alpha * blue_color[3];
				}
				
				// position the scanner
				x1 += scanner_cx;   y1 += scanner_cy;   y2 += scanner_cy;
				
				switch (drawClass)
				{
					case CLASS_THARGOID :
						foundHostiles = YES;
						break;
					case CLASS_ROCK :
					case CLASS_CARGO :
					case CLASS_MISSILE :
					case CLASS_STATION :
					case CLASS_BUOY :
					case CLASS_POLICE :
					case CLASS_MILITARY :
					case CLASS_MINE :
					case CLASS_WORMHOLE :
					default :
						if (isHostile)
							foundHostiles = YES;
						break;
				}

				if (drawthing->isShip)
				{
					ShipEntity* ship = (ShipEntity*)drawthing;
					if (ship->collision_radius * upscale > 4.5)
					{
						Vector bounds[6];
//						BoundingBox bb = [ship getBoundingBox];
						BoundingBox bb = ship->totalBoundingBox;
						bounds[0] = ship->v_forward;	scale_vector( &bounds[0], bb.max.z);
						bounds[1] = ship->v_forward;	scale_vector( &bounds[1], bb.min.z);
						bounds[2] = ship->v_right;		scale_vector( &bounds[2], bb.max.x);
						bounds[3] = ship->v_right;		scale_vector( &bounds[3], bb.min.x);
						bounds[4] = ship->v_up;			scale_vector( &bounds[4], bb.max.y);
						bounds[5] = ship->v_up;			scale_vector( &bounds[5], bb.min.y);
						// rotate the view
						int i;
						for (i = 0; i < 6; i++)
						{
							bounds[i].x += rp.x;	bounds[i].y += rp.y;	bounds[i].z += rp.z;
							mult_vector(&bounds[i], rotMatrix);
							scale_vector(&bounds[i], upscale);
							bounds[i] = make_vector( bounds[i].x + scanner_cx, bounds[i].z * z_factor + bounds[i].y * y_factor + scanner_cy, z1 );
						}
						// draw the diamond
						//
						glBegin(GL_QUADS);
						glColor4f(col[0], col[1], col[2], 0.33333 * col[3]);
							glVertex3f( bounds[0].x, bounds[0].y, bounds[0].z);	glVertex3f( bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f( bounds[1].x, bounds[1].y, bounds[1].z);	glVertex3f( bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f( bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f( bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f( bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f( bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f( bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f( bounds[0].x, bounds[0].y, bounds[0].z);
							glVertex3f( bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f( bounds[1].x, bounds[1].y, bounds[1].z);
						glEnd();
					}
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
    GLfloat zoom_color[] = { 1.0f, 0.1f, 0.0f, 1.0f };
	GLfloat x = ZOOM_INDICATOR_CENTRE_X;
	GLfloat y = ZOOM_INDICATOR_CENTRE_Y;
	NSSize siz = NSMakeSize( ZOOM_INDICATOR_WIDTH, ZOOM_INDICATOR_HEIGHT);
	GLfloat alpha = 1.0;
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] floatValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] floatValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha = [(NSNumber *)[info objectForKey:ALPHA_KEY] floatValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] floatValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] floatValue];
	if ([info objectForKey:RGB_COLOR_KEY])
	{
		NSArray*	rgb_array = (NSArray*)[info objectForKey:RGB_COLOR_KEY];
		zoom_color[0] = (GLfloat)[(NSNumber *)[rgb_array objectAtIndex:0] floatValue];
		zoom_color[1] = (GLfloat)[(NSNumber *)[rgb_array objectAtIndex:1] floatValue];
		zoom_color[2] = (GLfloat)[(NSNumber *)[rgb_array objectAtIndex:2] floatValue];
	}
	GLfloat cx = x - 0.3 * siz.width;
	GLfloat cy = y - 0.75 * siz.height;

	int zl = scanner_zoom;
	if (zl < 1) zl = 1;
	if (zl > SCANNER_ZOOM_LEVELS) zl = SCANNER_ZOOM_LEVELS;
	if (zl == 1) alpha *= 0.75;
	zoom_color[3] = (GLfloat)alpha;
	glColor4fv( zoom_color);
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	glBindTexture(GL_TEXTURE_2D, ascii_texture_name);
	glBegin(GL_QUADS);
	drawCharacterQuad( 48 + zl, cx - 0.4 * siz.width, cy, z1, siz);
	drawCharacterQuad( 58, cx, cy, z1, siz);
	drawCharacterQuad( 49, cx + 0.3 * siz.width, cy, z1, siz);
	glEnd();
	glDisable(GL_TEXTURE_2D);
	
}

- (void) drawCompass:(NSDictionary *) info
{	
	NSSize siz = NSMakeSize( COMPASS_HALF_SIZE, COMPASS_HALF_SIZE);
    GLfloat x = COMPASS_CENTRE_X;
	GLfloat y = COMPASS_CENTRE_Y;
	GLfloat alpha = 1.0;
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] floatValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] floatValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] floatValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] floatValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha = [(NSNumber *)[info objectForKey:ALPHA_KEY] floatValue];
	// draw the compass
	Matrix rotMatrix;
	Vector position = player->position;
	gl_matrix_into_matrix([player rotationMatrix], rotMatrix);
	//	
	// new
	GLfloat h1 = siz.height * 0.125;
	GLfloat h3 = siz.height * 0.375;
	GLfloat w1 = siz.width * 0.125;
	GLfloat w3 = siz.width * 0.375;
	glLineWidth( 2.0 * line_width);	// thicker
	glColor4f( 0.0f, 0.0f, 1.0f, alpha);
	drawOval( x, y, z1, siz, 12);	
	glColor4f( 0.0f, 0.0f, 1.0f, 0.5f * alpha);
	glBegin(GL_LINES);
		glVertex3f( x - w1, y, z1);	glVertex3f( x - w3, y, z1);
		glVertex3f( x + w1, y, z1);	glVertex3f( x + w3, y, z1);
		glVertex3f( x, y - h1, z1);	glVertex3f( x, y - h3, z1);
		glVertex3f( x, y + h1, z1);	glVertex3f( x, y + h3, z1);
	glEnd();
	glLineWidth( line_width);	// thinner
	
	//
	PlanetEntity*	the_sun = [[player universe] sun];
	PlanetEntity*	the_planet = [[player universe] planet];
	StationEntity*	the_station = [[player universe] station];
	Entity*			the_target = [player getPrimaryTarget];
	Entity*			the_next_beacon = [[player universe] entityForUniversalID:[player nextBeaconID]];
	int				p_status = player->status;
	if	(((p_status == STATUS_IN_FLIGHT)
		||(p_status == STATUS_AUTOPILOT_ENGAGED)
		||(p_status == STATUS_LAUNCHING)
		||(p_status == STATUS_WITCHSPACE_COUNTDOWN))	// be in the right mode
		&&(the_sun)
		&&(the_planet))									// and be in a system
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
		if (relativePosition.x||relativePosition.y||relativePosition.z)
			relativePosition = unit_vector(&relativePosition);
		else
			relativePosition.z = 1.0;
		relativePosition = unit_vector(&relativePosition);
		relativePosition.x *= siz.width * 0.4;
		relativePosition.y *= siz.height * 0.4;
		relativePosition.x += x;
		relativePosition.y += y;

		if ([player compass_mode] == COMPASS_MODE_BASIC)
		{
			NSSize oldblipsize = NSMakeSize( 6, 6);
			[self drawCompassPlanetBlipAt:relativePosition Size:oldblipsize Alpha:alpha];
		}
		else
		{
			NSSize sz = siz;
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
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
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
	if (([[player universe] viewDir] == VIEW_GUI_DISPLAY)||([[player universe] sun] == nil)||([player checkForAegis] != AEGIS_IN_DOCKING_RANGE))
		return;	// don't draw
	
	NSSize siz = NSMakeSize( AEGIS_WIDTH, AEGIS_HEIGHT);
    int x = AEGIS_CENTRE_X;
	int y = AEGIS_CENTRE_Y;
	GLfloat alpha = 0.5;
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] intValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] intValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha *= [(NSNumber *)[info objectForKey:ALPHA_KEY] floatValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] intValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] intValue];

	// draw the aegis indicator
	//
	GLfloat	w = siz.width / 16.0;
	GLfloat	h = siz.height / 16.0;
	
	GLfloat strip[] = { -7,8, -6,5, 5,8, 3,5, 7,2, 4,2, 6,-1, 4,2, -4,-1, -6,2, -4,-1, -7,-1, -3,-4, -5,-7, 6,-4, 7,-7 };
	
	glColor4f( 0.0f, 1.0f, 0.0f, alpha);
	glBegin(GL_QUAD_STRIP);
	int i;
	for (i = 0; i < 32; i += 2)
		glVertex3f( x + w * strip[i], y - h * strip[i + 1], z1);
	glEnd();
	
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
    float fu = [player dial_fuel];
	float hr = [player dial_hyper_range];
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
	hudDrawBarAt( x, y, z1, siz, fu);
	
	// draw range indicator
	if ((hr > 0)&&(hr <= 1.0))
	{
		glColor4fv((fu < hr)? red_color : green_color);
		hudDrawMarkerAt( x, y, z1, siz, hr);
	}
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

	double temp = [player dial_ship_temperature];
	int flash = (int)([[player universe] getTime] * 4);
	flash &= 1;
	// draw ship_temperature bar
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
				NSObject* miss_icon = [[[player universe] descriptions] objectForKey:miss_roles];
				if (i == [player active_missile])
				{
					glColor4fv(yellow_color);
					glBegin(GL_POLYGON);
					if (miss_icon)
					{
						hudDrawSpecialIconAt( (NSArray*)miss_icon, x + i * sp + 2, y + 1, z1, NSMakeSize( siz.width + 4, siz.height + 4));
					}
					else
					{
						if ([miss_roles hasSuffix:@"MISSILE"])
							hudDrawMissileIconAt( x + i * sp + 2, y + 1, z1, NSMakeSize( siz.width + 4, siz.height + 4));
						if ([miss_roles hasSuffix:@"MINE"])
							hudDrawMineIconAt( x + i * sp + 2, y + 1, z1, NSMakeSize( siz.width + 4, siz.height + 4));
					}
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
				if (miss_icon)
				{
					hudDrawSpecialIconAt( (NSArray*)miss_icon, x + i * sp, y, z1, siz);
				}
				else
				{
					if ([miss_roles hasSuffix:@"MISSILE"])
						hudDrawMissileIconAt( x + i * sp, y, z1, siz);
					if ([miss_roles hasSuffix:@"MINE"])
						hudDrawMineIconAt( x + i * sp, y, z1, siz);
				}
				glEnd();
				if (i != [player active_missile])
				{
					glColor4fv(green_color);
					glBegin(GL_LINE_LOOP);
					if (miss_icon)
					{
						hudDrawSpecialIconAt( (NSArray*)miss_icon, x + i * sp, y, z1, siz);
					}
					else
					{
						if ([miss_roles hasSuffix:@"MISSILE"])
							hudDrawMissileIconAt( x + i * sp, y, z1, siz);
						if ([miss_roles hasSuffix:@"MINE"])
							hudDrawMineIconAt( x + i * sp, y, z1, siz);
					}
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
//	if (([info objectForKey:EQUIPMENT_REQUIRED_KEY])&&
//		(![player has_extra_equipment:(NSString *)[info objectForKey:EQUIPMENT_REQUIRED_KEY]]))
//		return;
//	
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
		if ([[player universe] viewDir] != VIEW_GUI_DISPLAY)
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
				case VIEW_CUSTOM :
					mult_vector_gl_matrix(&rpn, [player customViewMatrix]);
					break;
			}
			rpn.z = 0;	// flatten vector
			if (rpn.x||rpn.y)
			{
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
    Universe* universe = [player universe];
	
	if (![universe displayFPS])
		return;
	
	if ((!player)||(!universe))
		return;
	
	NSString* positionInfo = [universe expressPosition:player->position inCoordinateSystem:@"pwm"];
	
	NSString* collDebugInfo = [NSString stringWithFormat:@"%@ - %@", [player dial_objinfo], [universe collisionDescription]];
	
	int x = FPSINFO_DISPLAY_X;
	int y = FPSINFO_DISPLAY_Y;
	NSSize siz = NSMakeSize( FPSINFO_DISPLAY_WIDTH, FPSINFO_DISPLAY_HEIGHT);
	NSSize siz08 = NSMakeSize( 0.8 * FPSINFO_DISPLAY_WIDTH, 0.8 * FPSINFO_DISPLAY_HEIGHT);
	
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
	drawString( collDebugInfo, x, y - siz.height, z1, siz);
	
	drawString( positionInfo, x, y - 1.8 * siz.height, z1, siz08);
}

- (void) drawScoopStatus:(NSDictionary *) info
{
	NSSize siz = NSMakeSize( SCOOPSTATUS_WIDTH, SCOOPSTATUS_HEIGHT);
    GLfloat x = SCOOPSTATUS_CENTRE_X;
	GLfloat y = SCOOPSTATUS_CENTRE_Y;
	GLfloat alpha = 0.75;
	if ([info objectForKey:X_KEY])
		x =		[(NSNumber *)[info objectForKey:X_KEY] floatValue];
	if ([info objectForKey:Y_KEY])
		y =		[(NSNumber *)[info objectForKey:Y_KEY] floatValue];
	if ([info objectForKey:ALPHA_KEY])
		alpha *= [(NSNumber *)[info objectForKey:ALPHA_KEY] floatValue];
	if ([info objectForKey:WIDTH_KEY])
		siz.width = [(NSNumber *)[info objectForKey:WIDTH_KEY] floatValue];
	if ([info objectForKey:HEIGHT_KEY])
		siz.height = [(NSNumber *)[info objectForKey:HEIGHT_KEY] floatValue];

	GLfloat* s0_color = red_color;
	GLfloat	s1c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s2c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s3c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	int scoop_status = [player dial_fuelscoops_status];
	double t = [[player universe] getTime];
	GLfloat a1 = alpha * 0.5f * (1.0f + sin(t * 8.0f));
	GLfloat a2 = alpha * 0.5f * (1.0f + sin(t * 8.0f - 1.0f));
	GLfloat a3 = alpha * 0.5f * (1.0f + sin(t * 8.0f - 2.0f));
		
	switch (scoop_status)
	{
		case SCOOP_STATUS_NOT_INSTALLED :
			return;	// don't draw
		case SCOOP_STATUS_FULL_HOLD :
			s0_color = darkgreen_color;
			alpha *= 0.75;
			break;
		case SCOOP_STATUS_ACTIVE :
		case SCOOP_STATUS_OKAY :
			s0_color = green_color;
			break;
	}
	int i;
	for (i = 0; i < 3; i++)
	{
		s1c[i] = s0_color[i];
		s2c[i] = s0_color[i];
		s3c[i] = s0_color[i];
	}
	if (scoop_status == SCOOP_STATUS_FULL_HOLD)
	{
		s3c[0] = red_color[0];
		s3c[1] = red_color[1];
		s3c[2] = red_color[2];
	}
	if (scoop_status == SCOOP_STATUS_ACTIVE)
	{
		s1c[3] = alpha * a1;
		s2c[3] = alpha * a2;
		s3c[3] = alpha * a3;
	}
	else
	{
		s1c[3] = alpha;
		s2c[3] = alpha;
		s3c[3] = alpha;
	}
	
	GLfloat w1 = siz.width / 8.0;
	GLfloat w2 = 2.0 * w1;
//	GLfloat w3 = 3.0 * w1;
	GLfloat w4 = 4.0 * w1;
	GLfloat h1 = siz.height / 8.0;
	GLfloat h2 = 2.0 * h1;
	GLfloat h3 = 3.0 * h1;
	GLfloat h4 = 4.0 * h1;
	
	glDisable(GL_TEXTURE_2D);
	glBegin( GL_QUADS);
	// section 1
		glColor4fv( s1c);
		glVertex3f( x, y + h1, z1);	glVertex3f( x - w2, y + h2, z1);	glVertex3f( x, y + h3, z1);	glVertex3f( x + w2, y + h2, z1);
	// section 2
		glColor4fv( s2c);
		glVertex3f( x, y - h1, z1);	glVertex3f( x - w4, y + h1, z1);	glVertex3f( x - w4, y + h2, z1);	glVertex3f( x, y, z1);
		glVertex3f( x, y - h1, z1);	glVertex3f( x + w4, y + h1, z1);	glVertex3f( x + w4, y + h2, z1);	glVertex3f( x, y, z1);
	// section 3
		glColor4fv( s3c);
		glVertex3f( x, y - h4, z1);	glVertex3f( x - w2, y - h2, z1);	glVertex3f( x - w2, y - h1, z1);	glVertex3f( x, y - h2, z1);
		glVertex3f( x, y - h4, z1);	glVertex3f( x + w2, y - h2, z1);	glVertex3f( x + w2, y - h1, z1);	glVertex3f( x, y - h2, z1);
	glEnd();
	
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

- (void) drawTrumbles:(NSDictionary *) info
{	
	if (!player)
		return;
		
	OOTrumble** trumbles = [player trumbleArray];
	int i;
	for (i = [player n_trumbles]; i > 0; i--)
	{
		OOTrumble* trum = trumbles[i - 1];
//		NSPoint trumpos = [trum position];
//		trumpos.x -= 32;
//		trumpos.y += 32;
		
//		[trum updateTrumble:dt];
		[trum drawTrumble: z1];
		
//		glColor4fv(yellow_color);
//		hudDrawSurroundAt(trumpos.x, trumpos.y, z1, NSMakeSize(32, 12));
//		hudDrawBarAt(trumpos.x, trumpos.y + 4, z1, NSMakeSize(32, 4), [trum discomfort]);
//		hudDrawBarAt(trumpos.x, trumpos.y - 4, z1, NSMakeSize(32, 4), [trum hunger]);
	}
}

//---------------------------------------------------------------------//

void hudDrawIndicatorAt( GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width / 2;
		glBegin(GL_QUADS);
			glVertex3f( position, dial_oy, z);
			glVertex3f( position+2, y, z);
			glVertex3f( position, dial_oy+siz.height, z);
			glVertex3f( position-2, y, z);
		glEnd();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height / 2;
		glBegin(GL_QUADS);
			glVertex3f( dial_ox, position, z);
			glVertex3f( x, position+2, z);
			glVertex3f( dial_ox + siz.width, position, z);
			glVertex3f( x, position-2, z);
		glEnd();
	}
}

void hudDrawMarkerAt( GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width - siz.width/2;
		glBegin(GL_QUADS);
			glVertex3f( position+1, dial_oy+1, z);
			glVertex3f( position+1, dial_oy+siz.height-1, z);
			glVertex3f( position-1, dial_oy+siz.height-1, z);
			glVertex3f( position-1, dial_oy+1, z);
		glEnd();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height - siz.height/2;
		glBegin(GL_QUADS);
			glVertex3f( dial_ox+1, position+1, z);
			glVertex3f( dial_ox + siz.width-1, position+1, z);
			glVertex3f( dial_ox + siz.width-1, position-1, z);
			glVertex3f( dial_ox+1, position-1, z);
		glEnd();
	}
}

void hudDrawBarAt( GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	GLfloat dial_ox =   x - siz.width/2;
	GLfloat dial_oy =   y - siz.height/2;
	if (fabs(siz.width) > fabs(siz.height))
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

void hudDrawSurroundAt( GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat dial_ox = x - siz.width/2;
	GLfloat dial_oy = y - siz.height/2;

	glBegin(GL_LINE_LOOP);
		glVertex3f( dial_ox-2, dial_oy-2, z);
		glVertex3f( dial_ox+siz.width+2, dial_oy-2, z);
		glVertex3f( dial_ox+siz.width+2, dial_oy+siz.height+2, z);
		glVertex3f( dial_ox-2, dial_oy+siz.height+2, z);
	glEnd();
}

void hudDrawSpecialIconAt(NSArray* ptsArray, int x, int y, int z, NSSize siz)
{
	if (!ptsArray)
		return;
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 
	int i = 0;
	int npts = [ptsArray count] & 0xfffe;	// make sure it's an even number
	while (i < npts)
	{
		int x = [(NSNumber*)[ptsArray objectAtIndex:i++] intValue];
		int y = [(NSNumber*)[ptsArray objectAtIndex:i++] intValue];
		glVertex3i( ox + x * w, oy + y * h, z);
	}
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
	ShipEntity* target_ship = (ShipEntity *)target;
	NSString* legal_desc = nil;
	if ((!target)||(!player1))
		return;

	if (target_ship->cloaking_device_active)
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
		
		case CLASS_MILITARY :
		legal_desc = @"Military Vessel";
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
	Vector v1 = vector_up_from_quaternion(back_q);
	Vector p0 = [player1 getViewpointPosition];
	Vector p1 = target->position;
	p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
	double rdist = sqrt(magnitude2(p1));
	double rsize = target->collision_radius;
	
	if (rsize < rdist * ONE_SIXTYFOURTH)
		rsize = rdist * ONE_SIXTYFOURTH;
	
	GLfloat rs0 = rsize;
	//double rs3 = rsize * 0.75;
	GLfloat rs2 = rsize * 0.50;
	//double rs1 = rsize * 0.25;
	
	glPushMatrix();
	//
	// deal with view directions
	Vector view_dir, view_up;
	view_up.x = 0.0;	view_up.y = 1.0;	view_up.z = 0.0;
	switch ([[player1 universe] viewDir])
	{
		default:
		case VIEW_FORWARD :
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = 1.0;
			break;
		case VIEW_AFT :
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
			quaternion_rotate_about_axis( &back_q, v1, PI);
			break;
		case VIEW_PORT :
			view_dir.x = -1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis( &back_q, v1, 0.5 * PI);
			break;
		case VIEW_STARBOARD :
			view_dir.x = 1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis( &back_q, v1, -0.5 * PI);
			break;
		case VIEW_CUSTOM :
			view_dir = [player1 customViewForwardVector];
			view_up = [player1 customViewUpVector];
			back_q = quaternion_multiply( [player1 customViewQuaternion], back_q);
			break;
	}
	gluLookAt(view_dir.x, view_dir.y, view_dir.z, 0.0, 0.0, 0.0, view_up.x, view_up.y, view_up.z);
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
	float range = (sqrtf(target->zero_distance) - target->collision_radius) * 0.001f;
	NSSize textsize = NSMakeSize( rdist * ONE_SIXTYFOURTH, rdist * ONE_SIXTYFOURTH);
	float line_height = rdist * ONE_SIXTYFOURTH;
	NSString*	info1 = [target_ship identFromShip: player1];
	NSString*	info2 = (legal_desc == nil)? [NSString stringWithFormat:@"%0.3f km", range] : [NSString stringWithFormat:@"%0.3f km (%@)", range, legal_desc];
	// no need to set color - tis green already!
	drawString( info1, rs0, 0.5 * rs2, 0, textsize);
	drawString( info2, rs0, 0.5 * rs2 - line_height, 0, textsize);
	
	glPopMatrix();
}

double drawCharacterQuad(int chr, double x, double y, double z, NSSize siz)
{
	if ((chr < 0) || (chr > 127))
		return 0;
	GLfloat texture_x = ONE_SIXTEENTH * (chr & 0x0f);
	GLfloat texture_y = ONE_EIGHTH * (chr >> 4);		// divide by 16 fast
	
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
	const char *string;
	char simple[2] = {0, 0};
	unsigned ch, next, length;
	
//	NSLog(@"DEBUG drawing string (%@) at %.1f, %.1f, %.1f (%.1f x %.1f)", text, x, y, z, siz.width, siz.height);
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	glBindTexture(GL_TEXTURE_2D, ascii_texture_name);

	glBegin(GL_QUADS);
	length = [text length];
	for (i = 0; i < length; i++)
	{
		ch = [text characterAtIndex:i];
		if ((ch & 0xFC00) == 0xD800)
		{
			// This is a high surrogate. NSStrings don’t automagically handle surrogate pairs
			// for us for historical reasons.
			if (i != length - 1)
			{
				// Check if next is a low surrogate
				next = [text characterAtIndex:i + 1];
				if ((next & 0xFC00) == 0xDC00)
				{
					// It is; merge the surrogate pair into a code point in ch and skip
					++i;
					ch = ((ch & 0x03FF) << 10) | (next & 0x03FF);
				}
			}
		}
		
		if (0x7f < ch) string = toAscii(ch);
		else
		{
			// An alternative for tabs would be to round cx up to the next multiple of foo
			if (ch == '\t') ch = ' ';
			simple[0] = ch;
			string = simple;
		}
		
		while (*string)
		{
			assert(!(*string & 0x80));
			cx += drawCharacterQuad(*string++, cx, y, z, siz);
		}
	}
	glEnd();

	glDisable(GL_TEXTURE_2D);
	
}

static const char *toAscii(unsigned inCodePoint)
{
	// Convert some Unicode code points likely(ish) to occur in Roman text to ASCII near equivalents.
	// Doesn’t do characters with diacritics, 'cos there's loads.
	switch (inCodePoint)
	{
		case 0x2018:	// Left single quotation mark
		case 0x2019:	// Right single quotation mark
		case 0x201B:	// Single high-reversed-9 quotation mark
			return "'";
		
		case 0x201A:	// Single low-9 quotation mark
			return ",";
		
		case 0x201C:	// Left double quotation mark
		case 0x201D:	// Right double quotation mark
		case 0x201F:	// Double high-reversed-9 quotation mark
			return "\"";
		
		case 0x201E:	// Double low-9 quotation mark
			return ",,";
		
		case 0x2026:	// Horizontal ellipsis
			return "...";
		
		case 0x2010:	// Hyphen
		case 0x2011:	// Hyphen
		case 0x00AD:	// Soft hyphen
		case 0x2012:	// Figure dash
		case 0x2013:	// En dash
		case 0x00B7:	// Middle dot
			return "-";
		
		case 0x2014:	// Em dash
		case 0x2015:	// Horizontal bar
			return "--";
		
		case 0x2318:	// Place of interest sign (Command key)
			return "(Cmd)";
		
		case 0x2325:	// Option Key
			return "(Option)";
		
		case 0x2303:	// Up arrowhead (Control Key)
			return "(Control)";
		
		// For GrowlTunes:
		case 0x2605:	// Black star
		case 0x272F:	// Pinwheel star
			return "*";
		
		case 0x2606:	// White star
			return "-";
		
		case 0x266D:	// Musical flat sign
			return "b";
		
		case 0x266E:	// Musical natural sign
			return "=";
		
		case 0x266F:	// Musical sharp sign
			return "#";
		
		default:
			return "?";
	}
}

void drawPlanetInfo(int gov, int eco, int tec, double x, double y, double z, NSSize siz)
{
	GLfloat govcol[] = {	0.5, 0.0, 0.7,
							0.7, 0.5, 0.3,
							0.0, 1.0, 0.3,
							1.0, 0.8, 0.1,
							1.0, 0.0, 0.0,
							0.1, 0.5, 1.0,
							0.7, 0.7, 0.7,
							0.7, 1.0, 1.0};

	double cx = x;
	int tl = tec + 1;
	GLfloat ce1 = 1.0 - 0.125 * eco;
	
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	glBindTexture(GL_TEXTURE_2D, ascii_texture_name);

	glBegin(GL_QUADS);
	
	glColor4f( ce1, 1.0, 0.0, 1.0);
	cx += drawCharacterQuad( 23 - eco, cx, y, z, siz);	// characters 16..23 are economy symbols
	glColor3fv(&govcol[gov * 3]);
	cx += drawCharacterQuad( gov, cx, y, z, siz) - 1.0;		// charcters 0..7 are government symbols
	glColor4f(0.5, 1.0, 1.0, 1.0);
	if (tl > 9)
		cx += drawCharacterQuad( 49, cx, y - 2, z, siz) - 2.0;
	cx += drawCharacterQuad( 48 + (tl % 10), cx, y - 2, z, siz);
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

void drawScannerGrid( double x, double y, double z, NSSize siz, int v_dir, GLfloat thickness, double zoom)
{
	GLfloat w1, h1;
	GLfloat ww = 0.5 * siz.width;
	GLfloat hh = 0.5 * siz.height;

	GLfloat w2 = 0.250 * siz.width;
	GLfloat h2 = 0.250 * siz.height;

	GLfloat km_scan = 0.001 * SCANNER_MAX_RANGE / zoom;	// calculate kilometer divisions
	GLfloat hdiv = 0.5 * siz.height / km_scan;
	GLfloat wdiv = 0.25 * siz.width / km_scan;
	
	int i, ii;
	
	if (wdiv < 4.0)
	{
		wdiv *= 2.0;
		ii = 5;
	}
	else
	{
		ii = 1;
	}
	
	glLineWidth(2.0 * thickness);
	
	drawOval( x, y, z, siz, 4);	
	
	glLineWidth(thickness);
	
	glBegin(GL_LINES);
		glVertex3f(x, y - hh, z);	glVertex3f(x, y + hh, z);
		glVertex3f(x - ww, y, z);	glVertex3f(x + ww, y, z);

		for (i = ii; 2.0 * hdiv * i < siz.height; i += ii)
		{
			h1 = i * hdiv;
			w1 = wdiv;
			if (i % 5 == 0)
				w1 = w1 * 2.5;
			if (i % 10 == 0)
				w1 = w1 * 2.0;
			if (w1 > 3.5)	// don't draw tiny marks
			{
				glVertex3f(x - w1, y + h1, z);	glVertex3f(x + w1, y + h1, z);
				glVertex3f(x - w1, y - h1, z);	glVertex3f(x + w1, y - h1, z);
			}
		}

		switch (v_dir)
		{
			case VIEW_BREAK_PATTERN :
			case VIEW_GUI_DISPLAY :
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
	glBegin(GL_LINE_STRIP);
	for (i = 0; i < 360; i += step)
		glVertex3f(x + ww * sin_value[i], y + hh * cos_value[i], z);
	glVertex3f(x, y + hh, z);
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
		glVertex3f(x + ww * sin_value[i], y + hh * cos_value[i], z);
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
		glVertex3f(x + ww * sin_value[i], y + hh * cos_value[i], z);
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
