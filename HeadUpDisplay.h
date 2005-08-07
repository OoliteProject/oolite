//
//  HeadUpDisplay.h
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

#ifdef LINUX
#include "oolite-linux.h"
#else
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#endif

#import <Foundation/Foundation.h>

#import "vector.h"
#import "MyOpenGLView.h"


#define SCANNER_CENTRE_X	0
#define SCANNER_CENTRE_Y	-180
#define SCANNER_SCALE		256
#define SCANNER_WIDTH		288
#define SCANNER_HEIGHT		72

#define SCANNER_MAX_ZOOM			5.0
#define SCANNER_ZOOM_LEVELS			5
#define ZOOM_INDICATOR_CENTRE_X		108
#define ZOOM_INDICATOR_CENTRE_Y		-216
#define ZOOM_LEVELS_IMAGE			@"zoom.png"

#define COMPASS_IMAGE			@"compass.png"
#define COMPASS_CENTRE_X		132
#define COMPASS_CENTRE_Y		-216
#define COMPASS_SIZE			64
#define COMPASS_HALF_SIZE		32
#define COMPASS_REDDOT_IMAGE	@"reddot.png"
#define COMPASS_GREENDOT_IMAGE  @"greendot.png"
#define COMPASS_DOT_SIZE		16
#define COMPASS_HALF_DOT_SIZE	8

#define AEGIS_IMAGE				@"aegis.png"
#define AEGIS_CENTRE_X			-132
#define AEGIS_CENTRE_Y			-216

#define SPEED_BAR_CENTRE_X		200
#define SPEED_BAR_CENTRE_Y		-145
#define SPEED_BAR_WIDTH			80
#define SPEED_BAR_HEIGHT		8
#define SPEED_BAR_DRAW_SURROUND	YES

#define ROLL_BAR_CENTRE_X		200
#define ROLL_BAR_CENTRE_Y		-160
#define ROLL_BAR_WIDTH			80
#define ROLL_BAR_HEIGHT			8
#define ROLL_BAR_DRAW_SURROUND	YES

#define PITCH_BAR_CENTRE_X		200
#define PITCH_BAR_CENTRE_Y		-170
#define PITCH_BAR_WIDTH			80
#define PITCH_BAR_HEIGHT		8
#define PITCH_BAR_DRAW_SURROUND	YES

#define ENERGY_GAUGE_CENTRE_X		200
#define ENERGY_GAUGE_CENTRE_Y		-205
#define ENERGY_GAUGE_WIDTH			80
#define ENERGY_GAUGE_HEIGHT			48
#define ENERGY_GAUGE_DRAW_SURROUND	YES

#define FORWARD_SHIELD_BAR_CENTRE_X			-200
#define FORWARD_SHIELD_BAR_CENTRE_Y			-146
#define FORWARD_SHIELD_BAR_WIDTH			80
#define FORWARD_SHIELD_BAR_HEIGHT			8
#define FORWARD_SHIELD_BAR_DRAW_SURROUND	YES

#define AFT_SHIELD_BAR_CENTRE_X			-200
#define AFT_SHIELD_BAR_CENTRE_Y			-162
#define AFT_SHIELD_BAR_WIDTH			80
#define AFT_SHIELD_BAR_HEIGHT			8
#define AFT_SHIELD_BAR_DRAW_SURROUND	YES

#define FUEL_BAR_CENTRE_X			-200
#define FUEL_BAR_CENTRE_Y			-179
#define FUEL_BAR_WIDTH				80
#define FUEL_BAR_HEIGHT				8

#define CABIN_TEMP_BAR_CENTRE_X		-200
#define CABIN_TEMP_BAR_CENTRE_Y		-189
#define CABIN_TEMP_BAR_WIDTH		80
#define CABIN_TEMP_BAR_HEIGHT		8

#define WEAPON_TEMP_BAR_CENTRE_X	-200
#define WEAPON_TEMP_BAR_CENTRE_Y	-199
#define WEAPON_TEMP_BAR_WIDTH		80
#define WEAPON_TEMP_BAR_HEIGHT		8

#define ALTITUDE_BAR_CENTRE_X		-200
#define ALTITUDE_BAR_CENTRE_Y		-209
#define ALTITUDE_BAR_WIDTH			80
#define ALTITUDE_BAR_HEIGHT			8

#define MISSILES_DISPLAY_X			-228
#define MISSILES_DISPLAY_Y			-224
#define MISSILES_DISPLAY_SPACING	16
#define MISSILE_ICON_HEIGHT			12

#define CLOCK_DISPLAY_X				-44
#define CLOCK_DISPLAY_Y				-234
#define CLOCK_DISPLAY_WIDTH			12
#define CLOCK_DISPLAY_HEIGHT		12

#define FPSINFO_DISPLAY_X			-300
#define FPSINFO_DISPLAY_Y			220
#define FPSINFO_DISPLAY_WIDTH		12
#define FPSINFO_DISPLAY_HEIGHT		12

#define STATUS_LIGHT_CENTRE_X		-108
#define STATUS_LIGHT_CENTRE_Y		-216
#define STATUS_LIGHT_WIDTH			8
#define STATUS_LIGHT_HEIGHT			8

#define HIT_INDICATOR_CENTRE_X		200
#define HIT_INDICATOR_CENTRE_Y		0

#define DIALS_KEY				@"dials"
#define LEGENDS_KEY				@"legends"
#define X_KEY					@"x"
#define Y_KEY					@"y"
#define SPACING_KEY				@"spacing"
#define ALPHA_KEY				@"alpha"
#define SELECTOR_KEY			@"selector"
#define IMAGE_KEY				@"image"
#define WIDTH_KEY				@"width"
#define HEIGHT_KEY				@"height"
#define SPRITE_KEY				@"sprite"
#define DRAW_SURROUND_KEY		@"draw_surround"
#define EQUIPMENT_REQUIRED_KEY	@"equipment_required"
#define LABELLED_KEY			@"labelled"
#define TEXT_KEY				@"text"
#define RGB_COLOR_KEY			@"rgb_color"
#define N_BARS_KEY				@"n_bars"

#define Z1						[(MyOpenGLView *)[[player universe] gameView] display_z]

#define ONE_EIGHTH				0.125
#define ONE_SIXTEENTH			0.0625
#define ONE_SIXTYFOURTH			0.015625



@class Entity, PlayerEntity, OpenGLSprite;

extern int debug;

@interface HeadUpDisplay : NSObject {

	PlayerEntity*   player;

	OpenGLSprite	*compassSprite;
	OpenGLSprite	*aegisSprite;
	
	NSMutableArray  *legendArray;
	NSMutableArray  *dialArray;
	
	// zoom indicators
	OpenGLSprite*   zoomLevelSprite[SCANNER_ZOOM_LEVELS];
	double			scanner_zoom;
	
	//where to draw it
	GLfloat			z1;
	
	GLfloat			line_width;
	
	int				last_transmitter;
	
}

- (void) setPlayer:(PlayerEntity *) player_entity;

- (double) scanner_zoom;
- (void) setScannerZoom:(double) value;

- (void) addLegend:(NSDictionary *) info;
- (void) addDial:(NSDictionary *) info;

- (void) drawLegends;
- (void) drawDials;

- (void) drawLegend:(NSDictionary *) info;
- (void) drawHUDItem:(NSDictionary *) info;

- (void) drawScanner:(NSDictionary *) info;
- (void) refreshLastTransmitter;
- (void) drawScannerZoomIndicator:(NSDictionary *) info;

- (void) drawCompass:(NSDictionary *) info;
- (void) drawCompassPlanetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassStationBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassSunBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassTargetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassWitchpointBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassBeaconBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;

- (void) drawAegis:(NSDictionary *) info;
- (void) drawSpeedBar:(NSDictionary *) info;
- (void) drawRollBar:(NSDictionary *) info;
- (void) drawPitchBar:(NSDictionary *) info;
- (void) drawEnergyGauge:(NSDictionary *) info;
- (void) drawForwardShieldBar:(NSDictionary *) info;
- (void) drawAftShieldBar:(NSDictionary *) info;
- (void) drawFuelBar:(NSDictionary *) info;
- (void) drawCabinTempBar:(NSDictionary *) info;
- (void) drawWeaponTempBar:(NSDictionary *) info;
- (void) drawAltitudeBar:(NSDictionary *) info;
- (void) drawMissileDisplay:(NSDictionary *) info;
- (void) drawTargetReticle:(NSDictionary *) info;
- (void) drawStatusLight:(NSDictionary *) info;
- (void) drawDirectionCue:(NSDictionary *) info;
- (void) drawClock:(NSDictionary *) info;
- (void) drawFPSInfoCounter:(NSDictionary *) info;

- (void) drawGreenSurround:(NSDictionary *) info;
- (void) drawYellowSurround:(NSDictionary *) info;

- (void) drawTrumbles:(NSDictionary *) info;

void hudDrawIndicatorAt(int x, int y, int z, NSSize siz, double amount);
void hudDrawBarAt(int x, int y, int z, NSSize siz, double amount);
void hudDrawSurroundAt(int x, int y, int z, NSSize siz);
void hudDrawSpecialIconAt(NSArray* ptsArray, int x, int y, int z, NSSize siz);
void hudDrawMineIconAt(int x, int y, int z, NSSize siz);
void hudDrawMissileIconAt(int x, int y, int z, NSSize siz);
void hudDrawStatusIconAt(int x, int y, int z, NSSize siz);

void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1);

double drawCharacterQuad(int chr, double x, double y, double z, NSSize siz);
void drawString(NSString *text, double x, double y, double z, NSSize siz);
NSRect rectForString(NSString *text, double x, double y, NSSize siz);

void drawScannerGrid( double x, double y, double z, NSSize siz, int v_dir, GLfloat thickness);
void drawOval( double x, double y, double z, NSSize siz, int step);
void drawFilledOval( double x, double y, double z, NSSize siz, int step);
void drawSpecialOval( double x, double y, double z, NSSize siz, int step, GLfloat* color4v);

- (void) setLine_width:(GLfloat) value;
- (GLfloat) line_width;

@end
