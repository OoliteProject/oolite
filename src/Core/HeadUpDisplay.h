/*

HeadUpDisplay.h

Class handling the player ship’s heads-up display, and 2D drawing functions.

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"

#import "OOTypes.h"
#import "OOMaths.h"
#import "MyOpenGLView.h"

@class OOCrosshairs, OOColor;


#define SCANNER_CENTRE_X	0
#define SCANNER_CENTRE_Y	-180
#define SCANNER_SCALE		256
#define SCANNER_WIDTH		288
#define SCANNER_HEIGHT		72

#define SCANNER_MAX_ZOOM			5.0
#define SCANNER_ZOOM_LEVELS			5
#define ZOOM_INDICATOR_CENTRE_X		108
#define ZOOM_INDICATOR_CENTRE_Y		-216
#define ZOOM_INDICATOR_WIDTH		11.0f
#define ZOOM_INDICATOR_HEIGHT		14.0f
#define ZOOM_LEVELS_IMAGE			@"zoom.png"

#define COMPASS_IMAGE			@"compass.png"
#define COMPASS_CENTRE_X		132
#define COMPASS_CENTRE_Y		-216
#define COMPASS_SIZE			56
#define COMPASS_HALF_SIZE		28
#define COMPASS_REDDOT_IMAGE	@"reddot.png"
#define COMPASS_GREENDOT_IMAGE  @"greendot.png"
#define COMPASS_DOT_SIZE		16
#define COMPASS_HALF_DOT_SIZE	8

#define AEGIS_IMAGE				@"aegis.png"
#define AEGIS_CENTRE_X			-132
#define AEGIS_CENTRE_Y			-216
#define AEGIS_WIDTH				24
#define AEGIS_HEIGHT			24

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
#define MISSILE_ICON_WIDTH			12
#define MISSILE_ICON_HEIGHT			MISSILE_ICON_WIDTH

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

#define SCOOPSTATUS_CENTRE_X		-132
#define SCOOPSTATUS_CENTRE_Y		-152
#define SCOOPSTATUS_WIDTH			16.0
#define SCOOPSTATUS_HEIGHT			16.0

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
#define COLOR_KEY				@"color"
#define N_BARS_KEY				@"n_bars"

#define ROWS_KEY				@"rows"
#define COLUMNS_KEY				@"columns"
#define ROW_HEIGHT_KEY			@"row_height"
#define ROW_START_KEY			@"row_start"
#define TITLE_KEY				@"title"
#define BACKGROUND_RGBA_KEY		@"background_rgba"
#define OVERALL_ALPHA_KEY		@"overall_alpha"

#define Z1						[(MyOpenGLView *)[[player universe] gameView] display_z]

#define ONE_EIGHTH				0.125



@class Entity, PlayerEntity, OpenGLSprite;


@interface HeadUpDisplay: NSObject
{
@private
	NSMutableArray		*legendArray;
	NSMutableArray		*dialArray;
	
	// zoom level
	GLfloat				scanner_zoom;
	
	//where to draw it
	GLfloat				z1;
	GLfloat				line_width;
	
	GLfloat				overallAlpha;
	
	BOOL				reticleTargetSensitive;
	
	int					last_transmitter;
	
	// Crosshairs
	OOCrosshairs		*_crosshairs;
	OOWeaponType		_lastWeaponType;
	GLfloat				_lastOverallAlpha;
	NSDictionary		*_crosshairOverrides;
	OOColor				*_crosshairColor;
	GLfloat				_crosshairScale;
	GLfloat				_crosshairWidth;
}

- (id) initWithDictionary:(NSDictionary *) hudinfo;

- (void) resizeGuis:(NSDictionary*) info;

- (double) scanner_zoom;
- (void) setScannerZoom:(double) value;

- (GLfloat) overallAlpha;
- (void) setOverallAlpha:(GLfloat) newAlphaValue;

- (BOOL) reticleTargetSensitive;
- (void) setReticleTargetSensitive:(BOOL) newReticleTargetSensitiveValue;

- (void) addLegend:(NSDictionary *) info;
- (void) addDial:(NSDictionary *) info;

- (void) renderHUD;

- (void) refreshLastTransmitter;

- (void) setLine_width:(GLfloat) value;
- (GLfloat) line_width;

@end


@interface NSString (OODisplayEncoding)

// Return a C string in the 8-bit encoding used for display.
- (const char *) cStringUsingOoliteEncoding;

// Return a C string in the 8-bit encoding used for display, with substitutions performed.
- (const char *) cStringUsingOoliteEncodingAndRemapping;

@end


void OODrawString(NSString *text, double x, double y, double z, NSSize siz);
void OODrawPlanetInfo(int gov, int eco, int tec, double x, double y, double z, NSSize siz);
NSRect OORectFromString(NSString *text, double x, double y, NSSize siz);
