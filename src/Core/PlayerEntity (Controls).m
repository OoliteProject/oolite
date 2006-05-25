//
//  PlayerEntity (Controls).m
/*
 *
 *  Oolite
 *
 *  Created by Jens Ayton on Fri Dec 02 2005.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004-2005, Giles C Williams and contributors.
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

#import "PlayerEntity.h"
#import "PlayerEntity (Controls).h"
#import "PlayerEntity (Sound).h"

#import "Universe.h"
#import "GameController.h"
#import "AI.h"
#import "MyOpenGLView.h"
#import "OOSound.h"
#import "LoadSave.h"

// TODO: ifdef HAVE_STICK might be better.
#ifdef GNUSTEP
#import "JoystickHandler.h"
#import "PlayerEntity_StickMapper.h"
#else
#import "Groolite.h"
#endif

@implementation PlayerEntity (Controls)

- (void) pollControls:(double) delta_t
{
	MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];
		
	if (gameView)
	{
		// poll the gameView keyboard things
		[self pollApplicationControls]; // quit command-f etc.
		switch (status)
		{
			case	STATUS_WITCHSPACE_COUNTDOWN :
			case	STATUS_IN_FLIGHT :
				[self pollFlightControls:delta_t];
				break;
			
			case	STATUS_DEAD :
				[self pollGameOverControls:delta_t];
				break;
				
			case	STATUS_AUTOPILOT_ENGAGED :
				[self pollAutopilotControls:delta_t];
				break;
				
			case	STATUS_DOCKED :
				[self pollDockedControls:delta_t];
				break;
								
			case	STATUS_START_GAME :
				[self pollDemoControls:delta_t];
				break;
								
			case	STATUS_ESCAPE_SEQUENCE :
			case	STATUS_HANDLING_ERROR :
			default :
				break;
		}
		
		// handle docking music generically
		if (status == STATUS_AUTOPILOT_ENGAGED)
		{
			if (docking_music_on) 
			{
				if (![dockingMusic isPlaying])
					[dockingMusic play];
			}
			else
			{
				if ([dockingMusic isPlaying])
					[dockingMusic stop];
			}
		}
		else
		{
			if ([dockingMusic isPlaying])
				[dockingMusic stop];
		}
		
	}
}

//static BOOL fuel_inject_pressed;
static BOOL jump_pressed;
static BOOL hyperspace_pressed;
static BOOL galhyperspace_pressed;
static BOOL pause_pressed;
static BOOL compass_mode_pressed;
static BOOL next_target_pressed;
static BOOL previous_target_pressed;
static BOOL next_missile_pressed;
static BOOL fire_missile_pressed;
static BOOL target_missile_pressed;
static BOOL ident_pressed;
static BOOL safety_pressed;
static BOOL cloak_pressed;
static BOOL rotateCargo_pressed;
static BOOL autopilot_key_pressed;
static BOOL fast_autopilot_key_pressed;
static BOOL target_autopilot_key_pressed;
static int				saved_view_direction;
static double			saved_script_time;
static NSTimeInterval	time_last_frame;
- (void) pollFlightControls:(double) delta_t
{
	MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];

#ifdef GNUSTEP   
   // DJS: TODO: Sort where SDL keeps its stuff.
   if(!stickHandler)
   {
      stickHandler=[gameView getStickHandler];
   }
   const BOOL *joyButtonState=[stickHandler getAllButtonStates];
#endif
   
    BOOL paused = [[gameView gameController] game_is_paused];
	double speed_delta = 5.0 * thrust;
	
	if (!paused)
	{
		//
		// arrow keys
		//
		if ([universe displayGUI])
			[self pollGuiArrowKeyControls:delta_t];
		else
			[self pollFlightArrowKeyControls:delta_t];
		//
		//  view keys
		//
		[self pollViewControls];
		
		//if (![gameView allowingStringInput])
		if (![universe displayCursor])
		{
			//
#ifdef GNUSTEP
			if ((joyButtonState[BUTTON_FUELINJECT] || [gameView isDown:key_inject_fuel])&&(has_fuel_injection)&&(!hyperspeed_engaged))
#else
			if (([gameView isDown:key_inject_fuel])&&(has_fuel_injection)&&(!hyperspeed_engaged))
#endif
			{
				if ((fuel > 0)&&(!afterburner_engaged))
				{
					[universe addMessage:[universe expandDescription:@"[fuel-inject-on]" forSystem:system_seed] forCount:1.5];
					afterburner_engaged = YES;
					if (!afterburnerSoundLooping)
						[self loopAfterburnerSound];
				}
				else
				{
					if (fuel <= 0.0)
						[universe addMessage:[universe expandDescription:@"[fuel-out]" forSystem:system_seed] forCount:1.5];
				}
				afterburner_engaged = (fuel > 0);
			}
			else
				afterburner_engaged = NO;
			
			if ((!afterburner_engaged)&&(afterburnerSoundLooping))
				[self stopAfterburnerSound];
			//
			
#ifdef GNUSTEP
		 // DJS: Thrust can be an axis or a button. Axis takes precidence.
         double reqSpeed=[stickHandler getAxisState: AXIS_THRUST];
         if(reqSpeed == STICK_AXISUNASSIGNED || [stickHandler getNumSticks] == 0)
         {
            // DJS: original keyboard code 
            if (([gameView isDown:key_increase_speed] || joyButtonState[BUTTON_INCTHRUST])&&(flight_speed < max_flight_speed)&&(!afterburner_engaged))
            {
               if (flight_speed < max_flight_speed)
                  flight_speed += speed_delta * delta_t;
               if (flight_speed > max_flight_speed)
                  flight_speed = max_flight_speed;
            }
            // if (([gameView isDown:key_decrease_speed])&&(!hyperspeed_engaged)&&(!afterburner_engaged))
            // ** tgape ** - decrease obviously means no hyperspeed
            if (([gameView isDown:key_decrease_speed] || joyButtonState[BUTTON_DECTHRUST])&&(!afterburner_engaged))
            {
               if (flight_speed > 0.0)
                  flight_speed -= speed_delta * delta_t;
               if (flight_speed < 0.0)
                  flight_speed = 0.0;
               // ** tgape ** - decrease obviously means no hyperspeed
               hyperspeed_engaged = NO;
            }
         } // DJS: STICK_NOFUNCTION else...a joystick axis is assigned to thrust.
         else
         {
            if(flight_speed < max_flight_speed * reqSpeed)
            {
               flight_speed += speed_delta * delta_t;
            }
            if(flight_speed > max_flight_speed * reqSpeed)
            {
               flight_speed -= speed_delta * delta_t;
            }
         } // DJS: end joystick thrust axis
#else
		 if (([gameView isDown:key_increase_speed])&&(flight_speed < max_flight_speed)&&(!afterburner_engaged))
		 {
			 if (flight_speed < max_flight_speed)
				 flight_speed += speed_delta * delta_t;
			 if (flight_speed > max_flight_speed)
				 flight_speed = max_flight_speed;
		 }
		 // ** tgape ** - decrease obviously means no hyperspeed
		 if (([gameView isDown:key_decrease_speed])&&(!afterburner_engaged))
		 {
			 if (flight_speed > 0.0)
				 flight_speed -= speed_delta * delta_t;
			 if (flight_speed < 0.0)
				 flight_speed = 0.0;
			 // ** tgape ** - decrease obviously means no hyperspeed
			 hyperspeed_engaged = NO;
		 }
#endif
		 
			//
			//  hyperspeed controls
			//
		 
#ifdef GNUSTEP
			if ([gameView isDown:key_jumpdrive] || joyButtonState[BUTTON_HYPERSPEED])		// 'j'
#else
			if ([gameView isDown:key_jumpdrive])		// 'j'	
#endif
			{
				if (!jump_pressed)
				{
					if (!hyperspeed_engaged)
					{
						hyperspeed_locked = [self massLocked];
						hyperspeed_engaged = !hyperspeed_locked;						
						if (hyperspeed_locked)
						{
							if (![universe playCustomSound:@"[jump-mass-locked]"])
								[self boop];
							[universe addMessage:[universe expandDescription:@"[jump-mass-locked]" forSystem:system_seed] forCount:1.5];
						}
					}
					else
					{
						hyperspeed_engaged = NO;
					}
				}
				jump_pressed = YES;
			}
			else
			{
				jump_pressed = NO;
			}
			//
			//  shoot 'a'
			//
#ifdef GNUSTEP
			if ((([gameView isDown:key_fire_lasers])||((mouse_control_on)&&([gameView isDown:gvMouseLeftButton]))||joyButtonState[BUTTON_FIRE])&&(shot_time > weapon_reload_time))
#else
			if ((([gameView isDown:key_fire_lasers])||((mouse_control_on)&&([gameView isDown:gvMouseLeftButton])))&&(shot_time > weapon_reload_time))
#endif
				
			{
				if ([self fireMainWeapon])
				{
					if (target_laser_hit != NO_TARGET)
					{
#ifdef HAVE_SOUND                 
						if (weaponHitSound)
						{
							if ([weaponHitSound isPlaying])
								[weaponHitSound stop];
							[weaponHitSound play];
						}
					}
					else
					{
						if (weaponSound)
						{
							if ([weaponSound isPlaying])
								[weaponSound stop];
							[weaponSound play];
						}
#endif                  
					}
				}
			}
			//
			//  shoot 'm'   // launch missile
			//
#ifdef GNUSTEP
			if ([gameView isDown:key_launch_missile] || joyButtonState[BUTTON_LAUNCHMISSILE])
#else
			if ([gameView isDown:key_launch_missile])				
#endif
			{
				// launch here
				if (!fire_missile_pressed)
				{
					BOOL missile_noise = [[missile_entity[active_missile] roles] hasSuffix:@"MISSILE"];
					if ([self fireMissile])
					{
#ifdef HAVE_SOUND                 
						if (missile_noise)
							[missileSound play];
#endif                  
					}
				}
				fire_missile_pressed = YES;
			}
			else
				fire_missile_pressed = NO;
			//
			//  shoot 'y'   // next missile
			//
#ifdef GNUSTEP		 
			if ([gameView isDown:key_next_missile] || joyButtonState[BUTTON_CYCLEMISSILE])
#else
			if ([gameView isDown:key_next_missile])
#endif				
			{
				if ((!ident_engaged)&&(!next_missile_pressed)&&([self has_extra_equipment:@"EQ_MULTI_TARGET"]))
				{
					[[universe gui] click];
					[self select_next_missile];
				}
				next_missile_pressed = YES;
			}
			else
				next_missile_pressed = NO;
			//
			//	'+' // next target
			//
			if ([gameView isDown:key_next_target])
			{
				if ((!next_target_pressed)&&([self has_extra_equipment:@"EQ_TARGET_MEMORY"]))
				{
					if ([self selectNextTargetFromMemory])
						[[universe gui] click];
					else
					{
						if (![universe playCustomSound:@"[no-target-in-memory]"])
							[self boop];
					}
				}
				next_target_pressed = YES;
			}
			else
				next_target_pressed = NO;
			//
			//	'-' // previous target
			//
			if ([gameView isDown:key_previous_target])
			{
				if ((!previous_target_pressed)&&([self has_extra_equipment:@"EQ_TARGET_MEMORY"]))
				{
					if ([self selectPreviousTargetFromMemory])
						[[universe gui] click];
					else
					{
						if (![universe playCustomSound:@"[no-target-in-memory]"])
							[self boop];
					}
				}
				previous_target_pressed = YES;
			}
			else
				previous_target_pressed = NO;
			//
			//  shoot 'r'   // switch on ident system
			//
#ifdef GNUSTEP
			if ([gameView isDown:key_ident_system] || joyButtonState[BUTTON_ID])
#else
			if ([gameView isDown:key_ident_system])
#endif				
			{
				// ident 'on' here
				if (!ident_pressed)
				{
					missile_status = MISSILE_STATUS_ARMED;
					primaryTarget = NO_TARGET;
					ident_engaged = YES;
					if (![universe playCustomSound:@"[ident-on]"])
						[self beep];
					[universe addMessage:[universe expandDescription:@"[ident-on]" forSystem:system_seed] forCount:2.0];
				}
				ident_pressed = YES;
			}
			else
				ident_pressed = NO;
			//
			//  shoot 't'   // switch on missile targetting
			//
#ifdef GNUSTEP
			if (([gameView isDown:key_target_missile] || joyButtonState[BUTTON_ARMMISSILE])&&(missile_entity[active_missile]))
#else
			if ([gameView isDown:key_target_missile] && missile_entity[active_missile])
#endif				
			{
				// targetting 'on' here
				if (!target_missile_pressed)
				{
					missile_status = MISSILE_STATUS_ARMED;
					if ((ident_engaged) && ([self getPrimaryTarget]))
					{
						if ([[missile_entity[active_missile] roles] hasSuffix:@"MISSILE"])
						{
							missile_status = MISSILE_STATUS_TARGET_LOCKED;
							[missile_entity[active_missile] addTarget:[self getPrimaryTarget]];
							[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[missile-locked-onto-@]" forSystem:system_seed], [(ShipEntity *)[self getPrimaryTarget] identFromShip: self]] forCount:4.5];
							if (![universe playCustomSound:@"[missile-locked-on]"])
								[self beep];
						}
					}
					else
					{
						primaryTarget = NO_TARGET;
						if ([[missile_entity[active_missile] roles] hasSuffix:@"MISSILE"])
						{
							if (missile_entity[active_missile])
								[missile_entity[active_missile] removeTarget:nil];
							[universe addMessage:[universe expandDescription:@"[missile-armed]" forSystem:system_seed] forCount:2.0];
							if (![universe playCustomSound:@"[missile-armed]"])
								[self beep];
						}
					}
					if ([[missile_entity[active_missile] roles] hasSuffix:@"MINE"])
					{
						[universe addMessage:[universe expandDescription:@"[mine-armed]" forSystem:system_seed] forCount:4.5];
						if (![universe playCustomSound:@"[mine-armed]"])
							[self beep];
					}
					ident_engaged = NO;
				}
				target_missile_pressed = YES;
			}
			else
				target_missile_pressed = NO;
			//
			//  shoot 'u'   // disarm missile targetting
			//
#ifdef GNUSTEP
			if ([gameView isDown:key_untarget_missile] || joyButtonState[BUTTON_UNARM])
#else
			if ([gameView isDown:key_untarget_missile])
#endif				
			{
				if (!safety_pressed)
				{
					if (!ident_engaged)
					{
						// targetting 'off' here
						missile_status = MISSILE_STATUS_SAFE;
						primaryTarget = NO_TARGET;
						[self safe_all_missiles];
						if (![universe playCustomSound:@"[missile-safe]"])
							[self boop];
						[universe addMessage:[universe expandDescription:@"[missile-safe]" forSystem:system_seed] forCount:2.0];
					}
					else
					{
						// targetting 'back on' here
						primaryTarget = [missile_entity[active_missile] getPrimaryTargetID];
						missile_status = (primaryTarget != NO_TARGET)? MISSILE_STATUS_TARGET_LOCKED : MISSILE_STATUS_SAFE;
						if (![universe playCustomSound:@"[ident-off]"])
							[self boop];
						[universe addMessage:[universe expandDescription:@"[ident-off]" forSystem:system_seed] forCount:2.0];
					}
					ident_engaged = NO;
				}
				safety_pressed = YES;
			}
			else
				safety_pressed = NO;
			//
			//  shoot 'e'   // ECM
			//
#ifdef GNUSTEP
			if (([gameView isDown:key_ecm] || joyButtonState[BUTTON_ECM])&&(has_ecm))
#else
			if ([gameView isDown:key_ecm] && has_ecm)
#endif				
			{
				if (!ecm_in_operation)
				{
					if ([self fireECM])
					{
						[self playECMSound];
						[universe addMessage:[universe expandDescription:@"[ecm-on]" forSystem:system_seed] forCount:3.0];
					}
				}
			}
			//
			//  shoot 'tab'   // Energy bomb
			//
#ifdef GNUSTEP				
			if (([gameView isDown:key_energy_bomb] || joyButtonState[BUTTON_ENERGYBOMB])&&(has_energy_bomb))
#else			
			if ([gameView isDown:key_energy_bomb] && has_energy_bomb)
#endif				
			{
				// original energy bomb routine
				[self fireEnergyBomb];
				[self remove_extra_equipment:@"EQ_ENERGY_BOMB"];
			}
			//
			//  shoot 'escape'   // Escape pod launch
			//
#ifdef GNUSTEP				
			if (([gameView isDown:key_launch_escapepod] || joyButtonState[BUTTON_ESCAPE])&&(has_escape_pod)&&([universe station]))
#else
			if ([gameView isDown:key_launch_escapepod] && has_escape_pod && [universe station])
#endif				
				
			{
				found_target = [self launchEscapeCapsule];
			}
			//
			//  shoot 'd'   // Dump Cargo
			//
#ifdef GNUSTEP				
			if (([gameView isDown:key_dump_cargo] || joyButtonState[BUTTON_JETTISON])&&([cargo count] > 0))
#else
			if ([gameView isDown:key_dump_cargo] && ([cargo count] > 0))
#endif				
			{
				if ([self dumpCargo] != CARGO_NOT_CARGO)
				{
					if (![universe playCustomSound:@"[cargo-jettisoned]"])
						[self beep];
				}
			}
			//
			//  shoot 'R'   // Rotate Cargo
			//
			if ([gameView isDown:key_rotate_cargo])
			{
				if ((!rotateCargo_pressed)&&([cargo count] > 0))
					[self rotateCargo];
				rotateCargo_pressed = YES;
			}
			else
				rotateCargo_pressed = NO;
			//
			// autopilot 'c'
			//
#ifdef GNUSTEP			
			if ([gameView isDown:key_autopilot] || joyButtonState[BUTTON_DOCKCPU])   // look for the 'c' key
#else
			if ([gameView isDown:key_autopilot])   // look for the 'c' key
#endif				
			{
				if (has_docking_computer && (!autopilot_key_pressed))   // look for the 'c' key
				{
					if ([self checkForAegis] == AEGIS_IN_DOCKING_RANGE)
					{
						primaryTarget = NO_TARGET;
						targetStation = NO_TARGET;
						autopilot_engaged = YES;
						ident_engaged = NO;
						[self safe_all_missiles];
						velocity = make_vector( 0.0f, 0.0f, 0.0f);
						status = STATUS_AUTOPILOT_ENGAGED;
						[shipAI setState:@"GLOBAL"];	// restart the AI
						if (![universe playCustomSound:@"[autopilot-on]"])
							[self beep];
						[universe addMessage:[universe expandDescription:@"[autopilot-on]" forSystem:system_seed] forCount:4.5];
						//
						if (ootunes_on)
						{
							// ootunes - play docking music
							[[universe gameController] playiTunesPlaylist:@"Oolite-Docking"];
							docking_music_on = NO;
						}
						//
						if (afterburner_engaged)
						{
							afterburner_engaged = NO;
							if (afterburnerSoundLooping)
								[self stopAfterburnerSound];
						}
					}
					else
					{
						if (![universe playCustomSound:@"[autopilot-out-of-range]"])
							[self boop];
						[universe addMessage:[universe expandDescription:@"[autopilot-out-of-range]" forSystem:system_seed] forCount:4.5];
					}
				}
				autopilot_key_pressed = YES;
			}
			else
				autopilot_key_pressed = NO;
			//
			// autopilot 'C' - dock with target
			//
			if ([gameView isDown:key_autopilot_target])   // look for the 'C' key
			{
				if (has_docking_computer && (!target_autopilot_key_pressed))
				{
					Entity* primeTarget = [self getPrimaryTarget];
					if ((primeTarget)&&(primeTarget->isStation)&&[primeTarget isKindOfClass:[StationEntity class]])
					{
						targetStation = primaryTarget;
						primaryTarget = NO_TARGET;
						autopilot_engaged = YES;
						ident_engaged = NO;
						[self safe_all_missiles];
						velocity = make_vector( 0.0f, 0.0f, 0.0f);
						status = STATUS_AUTOPILOT_ENGAGED;
						[shipAI setState:@"GLOBAL"];	// restart the AI
						if (![universe playCustomSound:@"[autopilot-on]"])
							[self beep];
						[universe addMessage:[universe expandDescription:@"[autopilot-on]" forSystem:system_seed] forCount:4.5];
						//
						if (ootunes_on)
						{
							// ootunes - play docking music
							[[universe gameController] playiTunesPlaylist:@"Oolite-Docking"];
							docking_music_on = NO;	
						}
						//
						if (afterburner_engaged)
						{
							afterburner_engaged = NO;
							if (afterburnerSoundLooping)
								[self stopAfterburnerSound];
						}
					}
					else
					{
						if (![universe playCustomSound:@"[autopilot-cannot-dock-with-target]"])
							[self boop];
						[universe addMessage:[universe expandDescription:@"Target is not capable of autopilot-docking" forSystem:system_seed] forCount:4.5];
					}
				}
				target_autopilot_key_pressed = YES;
			}
			else
				target_autopilot_key_pressed = NO;
			//
			// autopilot 'D'
			//
#ifdef GNUSTEP				
			if ([gameView isDown:key_autodock] || joyButtonState[BUTTON_DOCKCPUFAST])   // look for the 'D' key
#else
			if ([gameView isDown:key_autodock])   // look for the 'D' key
#endif				
			{
				if (has_docking_computer && (!fast_autopilot_key_pressed))   // look for the 'D' key
				{
					if ([self checkForAegis] == AEGIS_IN_DOCKING_RANGE)
					{
						StationEntity *the_station = [universe station];
						if (the_station)
						{
							if (legal_status > 50)
							{
								status = STATUS_AUTOPILOT_ENGAGED;
								[self interpretAIMessage:@"DOCKING_REFUSED"];
							}
							else
							{
								if (legal_status > 0)
								{
									// there's a slight chance you'll be fined for your past offences when autodocking
									//
									int fine_chance = ranrot_rand() & 0x03ff;	//	0..1023
									int government = 1 + [(NSNumber *)[[universe currentSystemData] objectForKey:KEY_GOVERNMENT] intValue];	// 1..8
									fine_chance /= government;
									if (fine_chance < legal_status)
										[self markForFines];
								}
								ship_clock_adjust = 1200.0;			// 20 minutes penalty to enter dock
								ident_engaged = NO;
								[self safe_all_missiles];
								[universe setViewDirection:VIEW_FORWARD];
								[self enterDock:the_station];
							}
						}
					}
					else
					{
						if (![universe playCustomSound:@"[autopilot-out-of-range]"])
							[self boop];
						[universe addMessage:[universe expandDescription:@"[autopilot-out-of-range]" forSystem:system_seed] forCount:4.5];
					}
				}
				fast_autopilot_key_pressed = YES;
			}
			else
				fast_autopilot_key_pressed = NO;
			//
			// hyperspace 'h'
			//
#ifdef GNUSTEP				
			if ([gameView isDown:key_hyperspace] || joyButtonState[BUTTON_HYPERDRIVE])   // look for the 'h' key
#else
			if ([gameView isDown:key_hyperspace])   // look for the 'h' key
#endif				
			{
				if (!hyperspace_pressed)
				{
					float			dx = target_system_seed.d - galaxy_coordinates.x;
					float			dy = target_system_seed.b - galaxy_coordinates.y;
					double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y); 
					BOOL		jumpOK = YES;
					
					if ((dx == 0)&&(dy == 0))
					{
						if (![universe playCustomSound:@"[witch-no-target]"])
							[self boop];
						[universe clearPreviousMessage];
						[universe addMessage:[universe expandDescription:@"[witch-no-target]" forSystem:system_seed] forCount:3.0];
						jumpOK = NO;
					}
					
					if (10.0 * distance > fuel)
					{
						if (![universe playCustomSound:@"[witch-no-fuel]"])
							[self boop];
						[universe clearPreviousMessage];
						[universe addMessage:[universe expandDescription:@"[witch-no-fuel]" forSystem:system_seed] forCount:3.0];
						jumpOK = NO;
					}
					
					if (status == STATUS_WITCHSPACE_COUNTDOWN)
					{
						// abort!
						if (galactic_witchjump)
							[universe stopCustomSound:@"[galactic-hyperspace-countdown-begun]"];
						else
							[universe stopCustomSound:@"[hyperspace-countdown-begun]"];
						jumpOK = NO;
						galactic_witchjump = NO;
						status = STATUS_IN_FLIGHT;
						if (![universe playCustomSound:@"[hyperspace-countdown-aborted]"])
							[self boop];
						// say it!
						[universe clearPreviousMessage];
						[universe addMessage:[universe expandDescription:@"[witch-user-abort]" forSystem:system_seed] forCount:3.0];
					}
					
					if (jumpOK)
					{
						galactic_witchjump = NO;
						witchspaceCountdown = 15.0;
						status = STATUS_WITCHSPACE_COUNTDOWN;
						if (![universe playCustomSound:@"[hyperspace-countdown-begun]"])
							[self beep];
						// say it!
						[universe clearPreviousMessage];
						[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[witch-to-@-in-f-seconds]" forSystem:system_seed], [universe getSystemName:target_system_seed], witchspaceCountdown] forCount:1.0];
					}
				}
				hyperspace_pressed = YES;
			}
			else
				hyperspace_pressed = NO;
			//
			// Galactic hyperspace 'g'
			//
#ifdef GNUSTEP
			if (([gameView isDown:key_galactic_hyperspace] || joyButtonState[BUTTON_GALACTICDRIVE])&&(has_galactic_hyperdrive))// look for the 'g' key
#else
			if ([gameView isDown:key_galactic_hyperspace] &&(has_galactic_hyperdrive))// look for the 'g' key
#endif				
			{
				if (!galhyperspace_pressed)
				{
					BOOL	jumpOK = YES;
					
					if (status == STATUS_WITCHSPACE_COUNTDOWN)
					{
						// abort!
						if (galactic_witchjump)
							[universe stopCustomSound:@"[galactic-hyperspace-countdown-begun]"];
						else
							[universe stopCustomSound:@"[hyperspace-countdown-begun]"];
						jumpOK = NO;
						galactic_witchjump = NO;
						status = STATUS_IN_FLIGHT;
						if (![universe playCustomSound:@"[hyperspace-countdown-aborted]"])
							[self boop];
						// say it!
						[universe clearPreviousMessage];
						[universe addMessage:[universe expandDescription:@"[witch-user-abort]" forSystem:system_seed] forCount:3.0];
					}
					
					if (jumpOK)
					{
						galactic_witchjump = YES;
						witchspaceCountdown = 15.0;
						status = STATUS_WITCHSPACE_COUNTDOWN;
						if (![universe playCustomSound:@"[galactic-hyperspace-countdown-begun]"])
							if (![universe playCustomSound:@"[hyperspace-countdown-begun]"])
								[self beep];
						// say it!
						[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[witch-galactic-in-f-seconds]" forSystem:system_seed], witchspaceCountdown] forCount:1.0];
					}
				}
				galhyperspace_pressed = YES;
			}
			else
				galhyperspace_pressed = NO;
					//
			//  shoot '0'   // Cloaking Device
			//
#ifdef GNUSTEP			
			if (([gameView isDown:key_cloaking_device] || joyButtonState[BUTTON_CLOAK]) && has_cloaking_device)
#else				
			if ([gameView isDown:key_cloaking_device] && has_cloaking_device)
#endif				
			{
				if (!cloak_pressed)
				{
					if (!cloaking_device_active)
					{
						if ([self activateCloakingDevice])
							[universe addMessage:[universe expandDescription:@"[cloak-on]" forSystem:system_seed] forCount:2];
						else
							[universe addMessage:[universe expandDescription:@"[cloak-low-juice]" forSystem:system_seed] forCount:3];
					}
					else
					{
						[self deactivateCloakingDevice];
						[universe addMessage:[universe expandDescription:@"[cloak-off]" forSystem:system_seed] forCount:2];
					}
					//   
					if (cloaking_device_active)
					{
						if (![universe playCustomSound:@"[cloaking-device-on]"])
							[self beep];
					}
					else
					{
						if (![universe playCustomSound:@"[cloaking-device-off]"])
							[self boop];
					}
				}
				cloak_pressed = YES;
			}
			else
				cloak_pressed = NO;
			
		}

		//
		//  text displays
		//
		[self pollGuiScreenControls];
	}
	else
	{
		// game is paused
		
		// check options menu request
		if ((([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2]))&&(gui_screen != GUI_SCREEN_OPTIONS))
		{
			[gameView clearKeys];
			[self setGuiToLoadSaveScreen];
		}
		//
#ifdef GNUSTEP		
		if (gui_screen == GUI_SCREEN_OPTIONS ||
          gui_screen == GUI_SCREEN_STICKMAPPER)
#else
		if (gui_screen == GUI_SCREEN_OPTIONS)
#endif			
		{
			NSTimeInterval time_this_frame = [NSDate timeIntervalSinceReferenceDate];
			double time_delta = time_this_frame - time_last_frame;
			time_last_frame = time_this_frame;
			if ((time_delta > MINIMUM_GAME_TICK)||(time_delta < 0.0))
				time_delta = MINIMUM_GAME_TICK;		// peg the maximum pause (at 0.5->1.0 seconds) to protect against when the machine sleeps	
			script_time += time_delta;
			[self pollGuiArrowKeyControls:time_delta];
		}

		// look for debugging keys
		if ([gameView isDown:48])// look for the '0' key
		{
			if (!cloak_pressed)
			{
				[universe obj_dump];	// dump objects
				debug = 0;
			}
			cloak_pressed = YES;
		}
		else
			cloak_pressed = NO;
		
		// look for debugging keys
		if ([gameView isDown:'c'])// look for the 'c' key
		{
			debug |= DEBUG_OCTREE;
			[universe addMessage:@"Octree debug ON" forCount:3];
		}

	}
	//
	// Pause game 'p'
	//
	if ([gameView isDown:key_pausebutton])// look for the 'p' key
	{
		if (!pause_pressed)
		{
			if (paused)
			{
				script_time = saved_script_time;
				gui_screen = GUI_SCREEN_MAIN;
				[gameView allowStringInput:NO];
				[universe setDisplayCursor:NO];
				[universe clearPreviousMessage];
				[universe setViewDirection:saved_view_direction];
				[[gameView gameController] unpause_game];
			}
			else
			{
				saved_view_direction = [universe viewDir];
				saved_script_time = script_time;
				[universe addMessage:[universe expandDescription:@"[game-paused]" forSystem:system_seed] forCount:1.0];
				[universe addMessage:[universe expandDescription:@"[game-paused-options]" forSystem:system_seed] forCount:1.0];
				[[gameView gameController] pause_game];
			}
		}
		pause_pressed = YES;
	}
	else
	{
		pause_pressed = NO;
	}
	//
	//
	//
}

static  BOOL	f_key_pressed;
static  BOOL	m_key_pressed;
static  BOOL	taking_snapshot;
- (void) pollApplicationControls
{
   if(!pollControls)
      return;

	// does fullscreen / quit / snapshot
	//
	MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];
	//
	//  command-key controls
	//
	if (([gameView isCommandDown])&&([[gameView gameController] inFullScreenMode]))
	{
		if (([gameView isCommandDown])&&([gameView isDown:102]))   //  command f
		{
			[[gameView gameController] exitFullScreenMode];
			if (mouse_control_on)
				[universe addMessage:[universe expandDescription:@"[mouse-off]" forSystem:system_seed] forCount:3.0];
			mouse_control_on = NO;
		}
		//
		if (([gameView isCommandDown])&&([gameView isDown:113]))   //  command q
		{
			[[gameView gameController] pauseFullScreenModeToPerform:@selector(exitApp) onTarget:[gameView gameController]];
		}
	}

#ifdef WIN32
          // Allow Win32 Quit
          if ( ([gameView isDown:'Q']) )
          {
                  [[gameView gameController] exitApp];
                  exit(0); // Force it
          }
#endif

	//
	// handle pressing Q or [esc] in error-handling mode
	//
	if (status == STATUS_HANDLING_ERROR)
	{
		if ([gameView isDown:113]||[gameView isDown:81]||[gameView isDown:27])   // 'q' | 'Q' | esc
		{
			[[gameView gameController] exitApp];
		}
	}
	
	//
	// dread debugging keypress of fear
	//
	if ([gameView isDown: 64])   // '@'
	{
		NSLog(@"%@ status==%@ guiscreen==%@", self, [self status_string], [self gui_screen_string]);
	}
	
	//
	//  snapshot
	//
	if ([gameView isDown:key_snapshot])   //  '*' key
	{
		if (!taking_snapshot)
		{
			taking_snapshot = YES;
			[gameView snapShot];
		}
	}
	else
	{
		taking_snapshot = NO;
	}
	//
	// FPS display
	//
	if ([gameView isDown:key_show_fps])   //  'F' key
	{
		if (!f_key_pressed)
			[universe setDisplayFPS:![universe displayFPS]];
		f_key_pressed = YES;
	}
	else
	{
		f_key_pressed = NO;
	}
	//
	// Mouse control
	//
	if ([[gameView gameController] inFullScreenMode])
	{
		if ([gameView isDown:key_mouse_control])   //  'M' key
		{
			if (!m_key_pressed)
			{
				mouse_control_on = !mouse_control_on;
				if (mouse_control_on)
				{
					[universe addMessage:[universe expandDescription:@"[mouse-on]" forSystem:system_seed] forCount:3.0];
#ifdef GNUSTEP
					// ensure the keyboard pitch override (intended to lock out the joystick if the
					// player runs to the keyboard) is reset
					keyboardRollPitchOverride = NO;
#endif					
				}
				else
					[universe addMessage:[universe expandDescription:@"[mouse-off]" forSystem:system_seed] forCount:3.0];
			}
			m_key_pressed = YES;
		}
		else
		{
			m_key_pressed = NO;
		}
	}
}

#ifdef GNUSTEP
- (void) pollFlightArrowKeyControls:(double) delta_t
{
	MyOpenGLView	*gameView = (MyOpenGLView *)[universe gameView];
	NSPoint			virtualStick;

   // TODO: Rework who owns the stick.
   if(!stickHandler)
   {
      stickHandler=[gameView getStickHandler];
   }
   numSticks=[stickHandler getNumSticks];

   // DJS: Handle inputs on the joy roll/pitch axis.
   // Mouse control on takes precidence over joysticks.
   // We have to assume the player has a reason for switching mouse
   // control on if they have a joystick - let them do it.
   if(mouse_control_on)
   {
      virtualStick=[gameView virtualJoystickPosition];
	   double sensitivity = 2.0;
	   virtualStick.x *= sensitivity;
	   virtualStick.y *= sensitivity;
   }
   else if(numSticks)
   {
      virtualStick=[stickHandler getRollPitchAxis];
      if(virtualStick.x == STICK_AXISUNASSIGNED ||
         virtualStick.y == STICK_AXISUNASSIGNED)
      {
         // Not assigned - set to zero.
         virtualStick.x=0;
         virtualStick.y=0;
      }
      else if(virtualStick.x != 0 ||
              virtualStick.y != 0)
      {
         // cancel keyboard override, stick has been waggled
         keyboardRollPitchOverride=NO;
      }
   }

	double roll_dampner = ROLL_DAMPING_FACTOR * delta_t;
	double pitch_dampner = PITCH_DAMPING_FACTOR * delta_t;
	
	rolling = NO;
	if (!mouse_control_on )
	{
		if ([gameView isDown:key_roll_left])
		{
         keyboardRollPitchOverride=YES;
			if (flight_roll > 0.0)  flight_roll = 0.0;
			[self decrease_flight_roll:delta_t*roll_delta];
			rolling = YES;
		}
		if ([gameView isDown:key_roll_right])
		{
         keyboardRollPitchOverride=YES;
			if (flight_roll < 0.0)  flight_roll = 0.0;
			[self increase_flight_roll:delta_t*roll_delta];
			rolling = YES;
		}
	}
	if((mouse_control_on || numSticks) && !keyboardRollPitchOverride)
	{
		double stick_roll = max_flight_roll * virtualStick.x;
		if (flight_roll < stick_roll)
		{
			[self increase_flight_roll:delta_t*roll_delta];
			if (flight_roll > stick_roll)
				flight_roll = stick_roll;
		}
		if (flight_roll > stick_roll)
		{
			[self decrease_flight_roll:delta_t*roll_delta];
			if (flight_roll < stick_roll)
				flight_roll = stick_roll;
		}
		rolling = (abs(virtualStick.x) > .10);
	}
	if (!rolling)
	{
		if (flight_roll > 0.0)
		{
			if (flight_roll > roll_dampner)	[self decrease_flight_roll:roll_dampner];
			else	flight_roll = 0.0;
		}
		if (flight_roll < 0.0)
		{
			if (flight_roll < -roll_dampner)   [self increase_flight_roll:roll_dampner];
			else	flight_roll = 0.0;
		}
	}

	pitching = NO;
	if (!mouse_control_on)
	{
		if ([gameView isDown:key_pitch_back])
		{
         keyboardRollPitchOverride=YES;
			if (flight_pitch < 0.0)  flight_pitch = 0.0;
			[self increase_flight_pitch:delta_t*pitch_delta];
			pitching = YES;
		}
		if ([gameView isDown:key_pitch_forward])
		{
         keyboardRollPitchOverride=YES;
			if (flight_pitch > 0.0)  flight_pitch = 0.0;
			[self decrease_flight_pitch:delta_t*pitch_delta];
			pitching = YES;
		}
	}
   if((mouse_control_on || numSticks) && !keyboardRollPitchOverride)
	{
		double stick_pitch = max_flight_pitch * virtualStick.y;
		if (flight_pitch < stick_pitch)
		{
			[self increase_flight_pitch:delta_t*roll_delta];
			if (flight_pitch > stick_pitch)
				flight_pitch = stick_pitch;
		}
		if (flight_pitch > stick_pitch)
		{
			[self decrease_flight_pitch:delta_t*roll_delta];
			if (flight_pitch < stick_pitch)
				flight_pitch = stick_pitch;
		}
		pitching = (abs(virtualStick.x) > .10);
	}
	if (!pitching)
	{
		if (flight_pitch > 0.0)
		{
			if (flight_pitch > pitch_dampner)	[self decrease_flight_pitch:pitch_dampner];
			else	flight_pitch = 0.0;
		}
		if (flight_pitch < 0.0)
		{
			if (flight_pitch < -pitch_dampner)	[self increase_flight_pitch:pitch_dampner];
			else	flight_pitch = 0.0;
		}
	}
}
#else		// ifdef GNUSTEP else
- (void) pollFlightArrowKeyControls:(double) delta_t
{
	MyOpenGLView	*gameView = (MyOpenGLView *)[universe gameView];
	NSPoint			virtualStick =[gameView virtualJoystickPosition];
	double sensitivity = 2.0;
	double keyboard_sensitivity = 1.0;
	virtualStick.x *= sensitivity;
	virtualStick.y *= sensitivity;
	double roll_dampner = ROLL_DAMPING_FACTOR * delta_t;
	double pitch_dampner = PITCH_DAMPING_FACTOR * delta_t;
	
	rolling = NO;
	if (!mouse_control_on)
	{
		if ([gameView isDown:key_roll_left])
		{
			if (flight_roll > 0.0)  flight_roll = 0.0;
			[self decrease_flight_roll:delta_t*roll_delta*keyboard_sensitivity];
			rolling = YES;
		}
		if ([gameView isDown:key_roll_right])
		{
			if (flight_roll < 0.0)  flight_roll = 0.0;
			[self increase_flight_roll:delta_t*roll_delta*keyboard_sensitivity];
			rolling = YES;
		}
	}
	else
	{
		double stick_roll = max_flight_roll * virtualStick.x;
		if (flight_roll < stick_roll)
		{
			[self increase_flight_roll:delta_t*roll_delta];
			if (flight_roll > stick_roll)
				flight_roll = stick_roll;
		}
		if (flight_roll > stick_roll)
		{
			[self decrease_flight_roll:delta_t*roll_delta];
			if (flight_roll < stick_roll)
				flight_roll = stick_roll;
		}
		rolling = (abs(virtualStick.x) > .10);
	}
	if (!rolling)
	{
		if (flight_roll > 0.0)
		{
			if (flight_roll > roll_dampner)	[self decrease_flight_roll:roll_dampner];
			else	flight_roll = 0.0;
		}
		if (flight_roll < 0.0)
		{
			if (flight_roll < -roll_dampner)   [self increase_flight_roll:roll_dampner];
			else	flight_roll = 0.0;
		}
	}
	
	pitching = NO;
	if (!mouse_control_on)
	{
		if ([gameView isDown:key_pitch_back])
		{
			if (flight_pitch < 0.0)  flight_pitch = 0.0;
			[self increase_flight_pitch:delta_t*pitch_delta*keyboard_sensitivity];
			pitching = YES;
		}
		if ([gameView isDown:key_pitch_forward])
		{
			if (flight_pitch > 0.0)  flight_pitch = 0.0;
			[self decrease_flight_pitch:delta_t*pitch_delta*keyboard_sensitivity];
			pitching = YES;
		}
	}
	else
	{
		double stick_pitch = max_flight_pitch * virtualStick.y;
		if (flight_pitch < stick_pitch)
		{
			[self increase_flight_pitch:delta_t*roll_delta];
			if (flight_pitch > stick_pitch)
				flight_pitch = stick_pitch;
		}
		if (flight_pitch > stick_pitch)
		{
			[self decrease_flight_pitch:delta_t*roll_delta];
			if (flight_pitch < stick_pitch)
				flight_pitch = stick_pitch;
		}
		pitching = (abs(virtualStick.x) > .10);
	}
	if (!pitching)
	{
		if (flight_pitch > 0.0)
		{
			if (flight_pitch > pitch_dampner)	[self decrease_flight_pitch:pitch_dampner];
			else	flight_pitch = 0.0;
		}
		if (flight_pitch < 0.0)
		{
			if (flight_pitch < -pitch_dampner)	[self increase_flight_pitch:pitch_dampner];
			else	flight_pitch = 0.0;
		}
	}
}
#endif

static BOOL pling_pressed;
static BOOL cursor_moving;
static BOOL disc_operation_in_progress;
static BOOL switching_resolution;
static BOOL wait_for_key_up;
static int searchStringLength;
static double timeLastKeyPress;
static BOOL upDownKeyPressed;
static BOOL leftRightKeyPressed;
static BOOL volumeControlPressed;
static int oldSelection;
static BOOL selectPressed;
static BOOL queryPressed;

// DJS + aegidian : Moved from the big switch/case block in pollGuiArrowKeyControls
- (BOOL) handleGUIUpDownArrowKeys
         : (GuiDisplayGen *)gui
         : (MyOpenGLView *)gameView
{
	BOOL result = NO;
	BOOL arrow_up = [gameView isDown:gvArrowKeyUp];
	BOOL arrow_down = [gameView isDown:gvArrowKeyDown];
	BOOL mouse_click = [gameView isDown:gvMouseLeftButton];
	//
	if (arrow_down)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
		   if ([gui setNextRow: +1])
			{
				[gui click];
				result = YES;
			}
			timeLastKeyPress = script_time;
		}
	}
	//
	if (arrow_up)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if ([gui setNextRow: -1])
			{
				[gui click];
				result = YES;
			}
			timeLastKeyPress = script_time;
		}
	}
	//
	if (mouse_click)
	{
		if (!upDownKeyPressed)
		{
			int click_row = 0;
			if (universe)
				click_row = universe->cursor_row;
			if ([gui setSelectedRow:click_row])
			{
				result = YES;
			}
		}
	}
	//
	upDownKeyPressed = (arrow_up || arrow_down || mouse_click);
	//
	return result;
}

- (void) pollGuiArrowKeyControls:(double) delta_t
{
	MyOpenGLView*	gameView = (MyOpenGLView *)[universe gameView];
	BOOL			moving = NO;
	double			cursor_speed = 10.0;
	GuiDisplayGen*  gui = [universe gui];
	NSString*		commanderFile;

	// deal with string inputs as necessary
	if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
		[gameView setStringInput: gvStringInputAlpha];
	else if (gui_screen == GUI_SCREEN_SAVE)
		[gameView setStringInput: gvStringInputAll];   
	else
		[gameView allowStringInput: NO];

	switch (gui_screen)
	{
		case	GUI_SCREEN_LONG_RANGE_CHART :
			if ([gameView isDown:key_map_dump])   //  '!' key
			{
				if (!pling_pressed)
					[self starChartDump];
				pling_pressed = YES;
			}
			else
			{
				pling_pressed = NO;
			}
			if ([[gameView typedString] length])
			{
				planetSearchString = [gameView typedString];
				NSPoint search_coords = [universe findSystemCoordinatesWithPrefix:planetSearchString withGalaxySeed:galaxy_seed];
				if ((search_coords.x >= 0.0)&&(search_coords.y >= 0.0))
				{
					moving = ((cursor_coordinates.x != search_coords.x)||(cursor_coordinates.y != search_coords.y));
					cursor_coordinates = search_coords;
				}
				else
				{
					[gameView resetTypedString];
				}
			}
			else
			{
				planetSearchString = nil;
			}
			//
			moving |= (searchStringLength != [[gameView typedString] length]);
			searchStringLength = [[gameView typedString] length];
			//
		case	GUI_SCREEN_SHORT_RANGE_CHART :
			//
			show_info_flag = ([gameView isDown:key_map_info] && ![universe strict]);
			//
			if (status != STATUS_WITCHSPACE_COUNTDOWN)
			{
				if ([gameView isDown:gvMouseLeftButton])
				{
					NSPoint maus = [gameView virtualJoystickPosition];
					if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)
					{
						double		vadjust = 51;
						double		hscale = 4.0 * MAIN_GUI_PIXEL_WIDTH / 256.0;
						double		vscale = 4.0 * MAIN_GUI_PIXEL_HEIGHT / 512.0;
						cursor_coordinates.x = galaxy_coordinates.x + (maus.x * MAIN_GUI_PIXEL_WIDTH) / hscale;
						cursor_coordinates.y = galaxy_coordinates.y + (maus.y * MAIN_GUI_PIXEL_HEIGHT + vadjust) / vscale;
						//NSLog(@"DEBUG mouse (%.3f,%.3f), coordinates (%.3f,%.3f) vadjust %.1f", maus.x, maus.y, cursor_coordinates.x, cursor_coordinates.y, vadjust);
					}
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
					{
						double		vadjust = 211;
						double		hadjust = MAIN_GUI_PIXEL_WIDTH / 2.0;
						double		hscale = MAIN_GUI_PIXEL_WIDTH / 256.0;
						double		vscale = MAIN_GUI_PIXEL_HEIGHT / 512.0;
						cursor_coordinates.x = (maus.x * MAIN_GUI_PIXEL_WIDTH + hadjust)/ hscale;
						cursor_coordinates.y = (maus.y * MAIN_GUI_PIXEL_HEIGHT + vadjust) / vscale;
						//NSLog(@"DEBUG mouse (%.3f,%.3f), coordinates (%.3f,%.3f) vadjust %.1f", maus.x, maus.y, cursor_coordinates.x, cursor_coordinates.y, vadjust);
					}
					[gameView resetTypedString];
					moving = YES;
				}
				if ([gameView isDown:gvMouseDoubleClick])
				{
					[gameView clearMouse];
					[self setGuiToSystemDataScreen];
					[self checkScript];
				}
				if ([gameView isDown:key_map_home])
				{
					[gameView resetTypedString];
					cursor_coordinates = galaxy_coordinates;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyLeft])
				{
					[gameView resetTypedString];
					cursor_coordinates.x -= cursor_speed*delta_t;
					if (cursor_coordinates.x < 0.0) cursor_coordinates.x = 0.0;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyRight])
				{
					[gameView resetTypedString];
					cursor_coordinates.x += cursor_speed*delta_t;
					if (cursor_coordinates.x > 256.0) cursor_coordinates.x = 256.0;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyDown])
				{
					[gameView resetTypedString];
					cursor_coordinates.y += cursor_speed*delta_t*2.0;
					if (cursor_coordinates.y > 256.0) cursor_coordinates.y = 256.0;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyUp])
					{
					[gameView resetTypedString];
					cursor_coordinates.y -= cursor_speed*delta_t*2.0;
					if (cursor_coordinates.y < 0.0) cursor_coordinates.y = 0.0;
					moving = YES;
				}
				if ((cursor_moving)&&(!moving))
				{
					target_system_seed = [universe findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
					cursor_coordinates.x = target_system_seed.d;
					cursor_coordinates.y = target_system_seed.b;
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART) [self setGuiToLongRangeChartScreen];
					if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART) [self setGuiToShortRangeChartScreen];
				}
				cursor_moving = moving;
				if ((cursor_moving)&&(gui_screen == GUI_SCREEN_LONG_RANGE_CHART)) [self setGuiToLongRangeChartScreen]; // update graphics
				if ((cursor_moving)&&(gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)) [self setGuiToShortRangeChartScreen]; // update graphics
			}
			//
		case	GUI_SCREEN_SYSTEM_DATA :
			//
			if ((status == STATUS_DOCKED)&&([gameView isDown:key_contract_info]))  // '?' toggle between maps/info and contract screen
			{
				if (!queryPressed)
				{
					[self setGuiToContractsScreen];
					if ((oldSelection >= [gui selectableRange].location)&&(oldSelection < [gui selectableRange].location + [gui selectableRange].length))
						[gui setSelectedRow:oldSelection];
					[self setGuiToContractsScreen];
				}
				queryPressed = YES;
			}
			else
				queryPressed = NO;
			break;

      // DJS: Farm off load/save screen options to LoadSave.m         
			case GUI_SCREEN_LOAD:
				commanderFile=[self commanderSelector: gui :gameView];
				if(commanderFile)
				{
					[self loadPlayerFromFile: commanderFile];
					[self setGuiToStatusScreen];
				}
				break;
			case GUI_SCREEN_SAVE:
				[self saveCommanderInputHandler: gui :gameView];
				break;
			case GUI_SCREEN_SAVE_OVERWRITE:
				[self overwriteCommanderInputHandler: gui :gameView];
				break;

#ifdef GNUSTEP				
      case GUI_SCREEN_STICKMAPPER:
         [self stickMapperInputHandler: gui view: gameView];
         break;
#endif		  

		case	GUI_SCREEN_OPTIONS :
			{
				int quicksave_row =		GUI_ROW_OPTIONS_QUICKSAVE;
				int save_row =			GUI_ROW_OPTIONS_SAVE;
				int load_row =			GUI_ROW_OPTIONS_LOAD;
				int begin_new_row =	GUI_ROW_OPTIONS_BEGIN_NEW;
				int strict_row =	GUI_ROW_OPTIONS_STRICT;
				int detail_row =	GUI_ROW_OPTIONS_DETAIL;
#ifdef GNUSTEP            
				// quit only appears in GNUstep as users aren't
				// used to Cmd-Q equivs. Same goes for window
				// vs fullscreen.
				int quit_row = GUI_ROW_OPTIONS_QUIT;
				int display_style_row = GUI_ROW_OPTIONS_DISPLAYSTYLE;
				int stickmap_row = GUI_ROW_OPTIONS_STICKMAPPER;				
#else
				// Macintosh only
				int ootunes_row =	GUI_ROW_OPTIONS_OOTUNES;				
				int speech_row =	GUI_ROW_OPTIONS_SPEECH;
				int growl_row =		GUI_ROW_OPTIONS_GROWL;				
#endif      
				int volume_row = GUI_ROW_OPTIONS_VOLUME;      
				int display_row =   GUI_ROW_OPTIONS_DISPLAY;

				GameController  *controller = [universe gameController];
				NSArray *modes = [controller displayModes];
				
				[self handleGUIUpDownArrowKeys: gui :gameView];
				BOOL selectKeyPress = ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]);
				if ([gameView isDown:gvMouseDoubleClick])
					[gameView clearMouse];
				
				if (selectKeyPress)   // 'enter'
				{
					if (([gui selectedRow] == quicksave_row)&&(!disc_operation_in_progress))
					{
						NS_DURING
							disc_operation_in_progress = YES;
							[self quicksavePlayer];
						NS_HANDLER
							NSLog(@"\n\n***** Handling localException: %@ : %@ *****\n\n",[localException name], [localException reason]);
							if ([[localException name] isEqual:@"GameNotSavedException"])	// try saving game instead
							{
								NSLog(@"\n\n***** Trying a normal save instead *****\n\n");
								if ([[universe gameController] inFullScreenMode])
									[[universe gameController] pauseFullScreenModeToPerform:@selector(savePlayer) onTarget:self];
								else
									[self savePlayer];
							}
							else
							{
								[localException raise];
							}
						NS_ENDHANDLER
					}
					if (([gui selectedRow] == save_row)&&(!disc_operation_in_progress))
					{
						disc_operation_in_progress = YES;
#ifdef GNUSTEP
						// for GNUstep it is always preferable to use the OOgui - GNUstep's
						// Load/Save dialog doesn't play well with an SDL window (stacking
						// order always seems to be wrong)
						[self setGuiToSaveCommanderScreen: player_name];
#else
						// for OS X it is preferable to use the Cocoa dialog when in windowed mode.
						if ([[universe gameController] inFullScreenMode])
							[self setGuiToSaveCommanderScreen: player_name];
						else
							[self savePlayer];						
#endif
					}
					if (([gui selectedRow] == load_row)&&(!disc_operation_in_progress))
					{
						disc_operation_in_progress = YES;
#ifdef GNUSTEP
						// see comments above for save player
						[self setGuiToLoadCommanderScreen];  
#else
						if ([[universe gameController] inFullScreenMode])
							[self setGuiToLoadCommanderScreen];
						else
							[self loadPlayer];
#endif
					}
						
#ifdef GNUSTEP						
					if ([gui selectedRow] == stickmap_row)
					{	
						[self setGuiToStickMapperScreen];
					}
#endif
						
					if (([gui selectedRow] == begin_new_row)&&(!disc_operation_in_progress))
					{
						disc_operation_in_progress = YES;
						[universe reinit];
					}
				}
				else
				{
					disc_operation_in_progress = NO;
				}
				
				if (([gui selectedRow] == display_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft]))&&(!switching_resolution))
				{
					int direction = ([gameView isDown:gvArrowKeyRight]) ? 1 : -1;
					int displayModeIndex = [controller indexOfCurrentDisplayMode];
					if (displayModeIndex == NSNotFound)
					{
						NSLog(@"***** couldn't find current display mode switching to basic 640x480");
						displayModeIndex = 0;
					}
					else
					{
						displayModeIndex = displayModeIndex + direction;
						if (displayModeIndex < 0)
							displayModeIndex = [modes count] - 1;
						if (displayModeIndex >= [modes count])
							displayModeIndex = 0;
					}
					NSDictionary	*mode = [modes objectAtIndex:displayModeIndex];
					int modeWidth = [[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
					int modeHeight = [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
					int modeRefresh = [[mode objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
					[controller setDisplayWidth:modeWidth Height:modeHeight Refresh:modeRefresh];
#ifdef GNUSTEP
					// TODO: The gameView for the SDL game currently holds and
					// sets the actual screen resolution (controller just stores
					// it). This probably ought to change.
					[gameView setScreenSize: displayModeIndex]; 
#endif
					NSString *displayModeString = [self screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];
					
					[gui click];
					{
						GuiDisplayGen* gui = [universe gui];
						int display_row =   GUI_ROW_OPTIONS_DISPLAY;
						[gui setText:displayModeString	forRow:display_row  align:GUI_ALIGN_CENTER];
					}
					switching_resolution = YES;
				}
				if ((![gameView isDown:gvArrowKeyRight])&&(![gameView isDown:gvArrowKeyLeft])&&(!selectKeyPress))
					switching_resolution = NO;

#ifndef GNUSTEP				
				if (([gui selectedRow] == speech_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
				{
					GuiDisplayGen* gui = [universe gui];
					if ([gameView isDown:gvArrowKeyRight] != speech_on)
						[gui click];
					speech_on = [gameView isDown:gvArrowKeyRight];
					if (speech_on)
						[gui setText:@" Spoken messages: ON "	forRow:speech_row  align:GUI_ALIGN_CENTER];
					else
						[gui setText:@" Spoken messages: OFF "	forRow:speech_row  align:GUI_ALIGN_CENTER];
				}


				if (([gui selectedRow] == ootunes_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
				{
					GuiDisplayGen* gui = [universe gui];
					if ([gameView isDown:gvArrowKeyRight] != ootunes_on)
						[gui click];
					ootunes_on = [gameView isDown:gvArrowKeyRight];
					if (ootunes_on)
						[gui setText:@" iTunes integration: ON "	forRow:ootunes_row  align:GUI_ALIGN_CENTER];
					else
						[gui setText:@" iTunes integration: OFF "	forRow:ootunes_row  align:GUI_ALIGN_CENTER];
				}
#endif
				if (([gui selectedRow] == volume_row)
					&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft]))
					&&[OOSound respondsToSelector:@selector(masterVolume)])
				{
					if ((!volumeControlPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						BOOL rightKeyDown = [gameView isDown:gvArrowKeyRight];
						BOOL leftKeyDown = [gameView isDown:gvArrowKeyLeft];
						GuiDisplayGen* gui = [universe gui];
						int volume = 100 * [OOSound masterVolume];
						volume += (((rightKeyDown && (volume < 100)) ? 5 : 0) - ((leftKeyDown && (volume > 0)) ? 5 : 0));
						if (volume > 100) volume = 100;
						if (volume < 0) volume = 0;
						[OOSound setMasterVolume: 0.01 * volume];
						[gui click];
						if (volume > 0)
						{
							NSString* v1_string = @"|||||||||||||||||||||||||";
							NSString* v0_string = @".........................";
							v1_string = [v1_string substringToIndex:volume / 5];
							v0_string = [v0_string substringToIndex:20 - volume / 5];
							[gui setText:[NSString stringWithFormat:@" Sound Volume: %@%@ ", v1_string, v0_string]	forRow:volume_row  align:GUI_ALIGN_CENTER];
						}
						else
							[gui setText:@" Sound Volume: MUTE "	forRow:volume_row  align:GUI_ALIGN_CENTER];
						timeLastKeyPress = script_time;
					}
					volumeControlPressed = YES;
				}
				else
					volumeControlPressed = NO;
				
#ifndef GNUSTEP
				if (([gui selectedRow] == growl_row)&&([gameView isDown:gvArrowKeyRight]||[gameView isDown:gvArrowKeyLeft]))
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
						BOOL rightKeyDown = [gameView isDown:gvArrowKeyRight];
						BOOL leftKeyDown = [gameView isDown:gvArrowKeyLeft];
						GuiDisplayGen* gui = [universe gui];
						int growl_min_priority = 3;
						if ([prefs objectForKey:@"groolite-min-priority"])
							growl_min_priority = [prefs integerForKey:@"groolite-min-priority"];
						int new_priority = growl_min_priority;
						if (rightKeyDown)
							new_priority--;
						if (leftKeyDown)
							new_priority++;
						if (new_priority < -2)	// sanity check values -2 .. 3
							new_priority = -2;
						if (new_priority > 3)
							new_priority = 3;
						if (new_priority != growl_min_priority)
						{
							growl_min_priority = new_priority;
							NSString* growl_priority_desc = [Groolite priorityDescription:growl_min_priority];
							[gui setText:[NSString stringWithFormat:@" Show Growl messages: %@ ", growl_priority_desc] forRow:growl_row align:GUI_ALIGN_CENTER];
							[gui click];
							[prefs setInteger:growl_min_priority forKey:@"groolite-min-priority"];
						}
						timeLastKeyPress = script_time;
					}
					leftRightKeyPressed = YES;
				}
				else
					leftRightKeyPressed = NO;
#endif

				if (([gui selectedRow] == detail_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
				{
					GuiDisplayGen* gui = [universe gui];
					if ([gameView isDown:gvArrowKeyRight] != [universe reducedDetail])
						[gui click];
					[universe setReducedDetail:[gameView isDown:gvArrowKeyRight]];
					if ([universe reducedDetail])
						[gui setText:@" Reduced detail: ON "	forRow:detail_row  align:GUI_ALIGN_CENTER];
					else
						[gui setText:@" Reduced detail: OFF "	forRow:detail_row  align:GUI_ALIGN_CENTER];
				}
            
#ifdef GNUSTEP
            // GNUstep only menu quit item
            if (([gui selectedRow] == quit_row) && [gameView isDown:13])
            {
			      [[gameView gameController] exitApp];
            }
            if (([gui selectedRow] == display_style_row) && [gameView isDown: 13])
            {
               [gameView toggleScreenMode];

               // redraw GUI
               [self setGuiToLoadSaveScreen];
            }
#endif              
            // TODO: Investigate why this has to be handled last (if the
            // quit item and this are swapped, the game crashes if
            // strict mode is selected with SIGSEGV in the ObjC runtime
            // system. The stack trace shows it crashes when it hits
            // the if statement, trying to send the message to one of
            // the things contained.
				if (([gui selectedRow] == strict_row)&& selectKeyPress)
				{
					[universe setStrict:![universe strict]];
				}

			}
			break;
		
		case	GUI_SCREEN_EQUIP_SHIP :
			{
				//
				if ([self handleGUIUpDownArrowKeys:gui :gameView])
				{
					[self showInformationForSelectedUpgrade];
				}
				//
				if ([gameView isDown:gvArrowKeyLeft])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_EQUIPMENT_START] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
							[self buySelectedItem];
						}
						timeLastKeyPress = script_time;
					}
				}
				if ([gameView isDown:gvArrowKeyRight])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1];
							[self buySelectedItem];
						}
						timeLastKeyPress = script_time;
					}
				}
				leftRightKeyPressed = [gameView isDown:gvArrowKeyRight]|[gameView isDown:gvArrowKeyLeft];
				
				if ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick])   // 'enter'
				{
					if ([gameView isDown:gvMouseDoubleClick])
					{
						selectPressed = NO;
						[gameView clearMouse];
					}
					if ((!selectPressed)&&([gui selectedRow] > -1))
					{
						[self buySelectedItem];
						selectPressed = YES;
					}
				}
				else
				{
					selectPressed = NO;
				}
			}
			break;

		case	GUI_SCREEN_MARKET :
			if (status == STATUS_DOCKED)
			{
				//
				[self handleGUIUpDownArrowKeys:gui :gameView];
				//
				if (([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])||([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]))
				{
					if ([gameView isDown:gvArrowKeyRight])   // -->
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							//NSLog(@"Try Buying Commodity %d",item);
							if ([self tryBuyingCommodity:item])
								[self setGuiToMarketScreen];
							else
								[self boop];
							wait_for_key_up = YES;
						}
					}
					if ([gameView isDown:gvArrowKeyLeft])   // <--
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							//NSLog(@"Try Selling Commodity %d",item);
							if ([self trySellingCommodity:item])
								[self setGuiToMarketScreen];
							else
								[self boop];
							wait_for_key_up = YES;
						}
					}
					if ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick])   // 'enter'
					{
						if ([gameView isDown:gvMouseDoubleClick])
						{
							wait_for_key_up = NO;
							[gameView clearMouse];
						}
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							int yours =		[(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:item] objectAtIndex:1] intValue];
							//NSLog(@"buy/sell all of item %d (you have %d)",item,yours);
							if ((yours > 0)&&(![self marketFlooded:item]))  // sell all you can
							{
								int i;
								for (i = 0; i < yours; i++)
									[self trySellingCommodity:item];
								//NSLog(@"... you sold %d.", yours);
								[self playInterfaceBeep:kInterfaceBeep_Sell];
								[self setGuiToMarketScreen];
							}
							else			// buy as much as possible
							{
								int amount_bought = 0;
								while ([self tryBuyingCommodity:item])
									amount_bought++;
								//NSLog(@"... you bought %d.", amount_bought);
								[self setGuiToMarketScreen];
								if (amount_bought == 0)
								{
									[self boop];
								}
								else
								{
									[self playInterfaceBeep:kInterfaceBeep_Buy];
								}
							}
							wait_for_key_up = YES;
						}
					}
				}
				else
				{
					wait_for_key_up = NO;
				}
			}
			break;

		case	GUI_SCREEN_CONTRACTS :
			if (status == STATUS_DOCKED)
			{
				//
				if ([self handleGUIUpDownArrowKeys:gui :gameView])
					[self setGuiToContractsScreen];
				//
				if ((status == STATUS_DOCKED)&&([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]))   // 'enter' | doubleclick
				{
					if ([gameView isDown:gvMouseDoubleClick])
						[gameView clearMouse];
					if (!selectPressed)
					{
						if ([self pickFromGuiContractsScreen])
						{
							[self playInterfaceBeep:kInterfaceBeep_Buy];
							[self setGuiToContractsScreen];
						}
						else
						{
							[self boop];
						}
					}
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
				}
				//
				if ([gameView isDown:key_contract_info])   // '?' toggle between contracts screen and map
				{
					if (!queryPressed)
					{
						oldSelection = [gui selectedRow];
						[self highlightSystemFromGuiContractsScreen];
					}
					queryPressed = YES;
				}
				else
					queryPressed = NO;
			}
			break;
		
		case	GUI_SCREEN_REPORT :
			if ([gameView isDown:32])	// spacebar
			{
				[gui click];
				[self setGuiToStatusScreen];
			}
			break;
				
		case	GUI_SCREEN_SHIPYARD :
			{
				GuiDisplayGen* gui = [universe gui];
				//
				if ([self handleGUIUpDownArrowKeys:gui :gameView])
				{
					[self showShipyardInfoForSelection];
				}
				//
				if ([gameView isDown:gvArrowKeyLeft])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_SHIPYARD_START] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_SHIPYARD_START];
							[self buySelectedShip];
						}
						timeLastKeyPress = script_time;
					}
				}
				if ([gameView isDown:gvArrowKeyRight])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
							[self buySelectedShip];
						}
						timeLastKeyPress = script_time;
					}
				}
				leftRightKeyPressed = [gameView isDown:gvArrowKeyRight]|[gameView isDown:gvArrowKeyLeft];
				
				if ([gameView isDown:13])   // 'enter' NOT double-click
				{
					if (!selectPressed)
					{
						// try to buy the ship!
						int money = credits;
						if ([self buySelectedShip])
						{
							if (money == credits)	// we just skipped to another page
							{
								[[universe gui] click];
							}
							else
							{
								[universe removeDemoShips];
								[self setGuiToStatusScreen];
								[self playInterfaceBeep: kInterfaceBeep_Buy];
							}
						}
						else
						{
							[self boop];
						}
					}
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
				}
			}
			break;

	}
	
	//
	// damp any rotations we entered with
	//
	if (flight_roll > 0.0)
	{
		if (flight_roll > delta_t)	[self decrease_flight_roll:delta_t];
		else	flight_roll = 0.0;
	}
	if (flight_roll < 0.0)
	{
		if (flight_roll < -delta_t)   [self increase_flight_roll:delta_t];
		else	flight_roll = 0.0;
	}
	if (flight_pitch > 0.0)
	{
		if (flight_pitch > delta_t)	[self decrease_flight_pitch:delta_t];
		else	flight_pitch = 0.0;
	}
	if (flight_pitch < 0.0)
	{
		if (flight_pitch < -delta_t)	[self increase_flight_pitch:delta_t];
		else	flight_pitch = 0.0;
	}
}

- (void) switchToMainView
{
	gui_screen = GUI_SCREEN_MAIN;
	if (showDemoShips)
	{
		[self setShowDemoShips: NO];
		[universe removeDemoShips];
	}
	[(MyOpenGLView *)[universe gameView] allowStringInput:NO];
	[universe setDisplayCursor:NO];
}

static BOOL zoom_pressed;

- (void) pollViewControls
{
   if(!pollControls)
      return;

	MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];
	//
	//  view keys
	//
	if (([gameView isDown:gvFunctionKey1])||([gameView isDown:gvNumberKey1]))
	{
		if ([universe displayGUI])
			[self switchToMainView];
		[universe setViewDirection:VIEW_FORWARD];
	}
	if (([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2]))
	{
		if ([universe displayGUI])
			[self switchToMainView];
		[universe setViewDirection:VIEW_AFT];
	}
	if (([gameView isDown:gvFunctionKey3])||([gameView isDown:gvNumberKey3]))
	{
		if ([universe displayGUI])
			[self switchToMainView];
		[universe setViewDirection:VIEW_PORT];
	}
	if (([gameView isDown:gvFunctionKey4])||([gameView isDown:gvNumberKey4]))
	{
		if ([universe displayGUI])
			[self switchToMainView];
		[universe setViewDirection:VIEW_STARBOARD];
	}
	//
	// Zoom scanner 'z'
	//
	if ([gameView isDown:key_scanner_zoom] && ([gameView allowingStringInput] == gvStringInputNo)) // look for the 'z' key
	{
		if (!scanner_zoom_rate)
		{
			if ([hud scanner_zoom] < 5.0)
			{
				if (([hud scanner_zoom] > 1.0)||(!zoom_pressed))
					scanner_zoom_rate = SCANNER_ZOOM_RATE_UP;
			}
			else
			{
				if (!zoom_pressed)	// must release and re-press zoom to zoom back down..
					scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
			}
		}
		zoom_pressed = YES;
	}
	else
		zoom_pressed = NO;
	//
	// Unzoom scanner 'Z'
	//
	if ([gameView isDown:key_scanner_unzoom] && ([gameView allowingStringInput] == gvStringInputNo)) // look for the 'Z' key
	{
		if ((!scanner_zoom_rate)&&([hud scanner_zoom] > 1.0))
			scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
	}
	//
	// Compass mode '/'
	//
	if ([gameView isDown:key_next_compass_mode]) // look for the '/' key
	{
		if ((!compass_mode_pressed)&&(compass_mode != COMPASS_MODE_BASIC))
			[self setNextCompassMode];
		compass_mode_pressed = YES;
	}
	else
	{
		compass_mode_pressed = NO;
	}
	//
	//  show comms log '`'
	//
	if ([gameView isDown:key_comms_log])
	{
		[universe showCommsLog: 1.5];
		[hud refreshLastTransmitter];
	}
}

static BOOL switching_chart_screens;
static BOOL switching_status_screens;
static BOOL switching_market_screens;
static BOOL switching_equipship_screens;
- (void) pollGuiScreenControls
{
   if(!pollControls)
      return;

	MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];
	BOOL docked_okay = (status == STATUS_DOCKED);// || ((status == STATUS_COCKPIT_DISPLAY) && (gui_screen == GUI_SCREEN_SHIPYARD));
	//
	//  text displays
	//
	if (([gameView isDown:gvFunctionKey5])||([gameView isDown:gvNumberKey5]))
	{
		if (!switching_status_screens)
		{
			switching_status_screens = YES;
			if ((gui_screen == GUI_SCREEN_STATUS)&&(![universe strict]))
				[self setGuiToManifestScreen];
			else
				[self setGuiToStatusScreen];
			[self checkScript];
		}
	}
	else
	{
		switching_status_screens = NO;
	}
	
	if (([gameView isDown:gvFunctionKey6])||([gameView isDown:gvNumberKey6]))
	{
		if  (!switching_chart_screens)
		{
			switching_chart_screens = YES;
			if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)
				[self setGuiToLongRangeChartScreen];
			else
				[self setGuiToShortRangeChartScreen];
		}
	}
	else
	{
		switching_chart_screens = NO;
	}
	
	if (([gameView isDown:gvFunctionKey7])||([gameView isDown:gvNumberKey7]))
	{
		if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
		{
			[self setGuiToSystemDataScreen];
			[self checkScript];
		}
	}
	
	
	if (docked_okay)
	{
		if ((([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2]))&&(gui_screen != GUI_SCREEN_OPTIONS))
		{
			[gameView clearKeys];
			[self setGuiToLoadSaveScreen];
		}
		//
		if (([gameView isDown:gvFunctionKey3])||([gameView isDown:gvNumberKey3]))
		{
			if (!switching_equipship_screens)
			{
				if (!docked_station)
					docked_station = [universe station];
				if ((gui_screen == GUI_SCREEN_EQUIP_SHIP)&&[docked_station hasShipyard])
				{
					[gameView clearKeys];
					[self setGuiToShipyardScreen:0];
					[[universe gui] setSelectedRow:GUI_ROW_SHIPYARD_START];
					[self showShipyardInfoForSelection];
				}
				else
				{
					[gameView clearKeys];
					[self setGuiToEquipShipScreen:0:-1];
					[[universe gui] setSelectedRow:GUI_ROW_EQUIPMENT_START];
				}
			}
			switching_equipship_screens = YES;
		}
		else
		{
			switching_equipship_screens = NO;
		}
		//
		if (([gameView isDown:gvFunctionKey8])||([gameView isDown:gvNumberKey8]))
		{
			if (!switching_market_screens)
			{
				if ((gui_screen == GUI_SCREEN_MARKET)&&(docked_station == [universe station])&&(![universe strict]))
				{
					[gameView clearKeys];
					[self setGuiToContractsScreen];
					[[universe gui] setSelectedRow:GUI_ROW_PASSENGERS_START];
				}
				else
				{
					[gameView clearKeys];
					[self setGuiToMarketScreen];
					[[universe gui] setSelectedRow:GUI_ROW_MARKET_START];
				}
			}
			switching_market_screens = YES;
		}
		else
		{
			switching_market_screens = NO;
		}
	}
	else
	{
		if (([gameView isDown:gvFunctionKey8])||([gameView isDown:gvNumberKey8]))
		{
			if (!switching_market_screens)
			{
				[self setGuiToMarketScreen];
				[[universe gui] setSelectedRow:GUI_ROW_MARKET_START];
			}
			switching_market_screens = YES;
		}
		else
		{
			switching_market_screens = NO;
		}
	}
}

- (void) pollGameOverControls:(double) delta_t
{
	MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];
	if ([gameView isDown:32])   // look for the spacebar
	{
		[universe displayMessage:@"" forCount:1.0];
		shot_time = 31.0;	// force restart
	}
}

static BOOL toggling_music;
- (void) pollAutopilotControls:(double) delta_t
{
	//
	// controls polled while the autopilot is active
	//

	MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];
	//
	//  view keys
	//
	[self pollViewControls];
	//
	//  text displays
	//
	[self pollGuiScreenControls];
	//
	if ([universe displayGUI])
		[self pollGuiArrowKeyControls:delta_t];
	//
	//
	if ([gameView isDown:key_autopilot])   // look for the 'c' key
	{
		if (has_docking_computer && (!autopilot_key_pressed))   // look for the 'c' key
		{
			[self abortDocking];			// let the station know that you are no longer on approach
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			autopilot_engaged = NO;
			primaryTarget = NO_TARGET;
			status = STATUS_IN_FLIGHT;
			if (![universe playCustomSound:@"[autopilot-off]"])
				[self beep];
			[universe addMessage:[universe expandDescription:@"[autopilot-off]" forSystem:system_seed] forCount:4.5];
			//
			if (ootunes_on)
			{
				// ootunes - play inflight music
				[[universe gameController] playiTunesPlaylist:@"Oolite-Inflight"];
				docking_music_on = NO;
			}
		}
		autopilot_key_pressed = YES;
	}
	else
		autopilot_key_pressed = NO;
	//
	if (([gameView isDown:key_docking_music])&&(!ootunes_on))   // look for the 's' key
	{
		if (!toggling_music)
		{
			docking_music_on = !docking_music_on;
			// set defaults..
			[[NSUserDefaults standardUserDefaults]  setBool:docking_music_on forKey:KEY_DOCKING_MUSIC];
		}
		toggling_music = YES;
	}
	else
	{
		toggling_music = NO;
	}
	//

}

- (void) pollDockedControls:(double) delta_t
{
	if(pollControls)
	{    
		MyOpenGLView  *gameView = (MyOpenGLView *)[universe gameView];
		if (([gameView isDown:gvFunctionKey1])||([gameView isDown:gvNumberKey1]))   // look for the f1 key
		{
			// ensure we've not left keyboard entry on
			[gameView allowStringInput: NO];

			[universe set_up_universe_from_station]; // launch!
			if (!docked_station)
				docked_station = [universe station];
			//NSLog(@"Leaving dock (%@)...%@",docked_station,[docked_station name]);
			[self leaveDock:docked_station];
			[universe setDisplayCursor:NO];
			[self playBreakPattern];
		}    
	}
	//
	//  text displays
	//
	// mission screens
	if (gui_screen == GUI_SCREEN_MISSION)
		[self pollDemoControls: delta_t];
	else
		[self pollGuiScreenControls];	// don't switch away from mission screens
	//
	[self pollGuiArrowKeyControls:delta_t];
	//
}

- (void) pollDemoControls:(double) delta_t
{
	MyOpenGLView*	gameView = (MyOpenGLView *)[universe gameView];
	GuiDisplayGen*	gui = [universe gui];
	
	switch (gui_screen)
	{
		case	GUI_SCREEN_INTRO1 :
			if (!disc_operation_in_progress)
			{
				if (([gameView isDown:121])||([gameView isDown:89]))	//  'yY'
				{
					if (themeMusic)
					{
						[themeMusic stop];
					}
					disc_operation_in_progress = YES;
					[self setStatus:STATUS_DOCKED];
					[universe removeDemoShips];
					[gui setBackgroundImage:nil];
#ifdef GNUSTEP					
					[self setGuiToLoadCommanderScreen];
#else					
					if ([[universe gameController] inFullScreenMode])
						[self setGuiToLoadCommanderScreen];
					else
					{
						[self loadPlayer];
						[self setGuiToStatusScreen];
					}
#endif					
				}
			}
			if (([gameView isDown:110])||([gameView isDown:78]))	//  'nN'
			{
				[self setGuiToIntro2Screen];
			}
			
//			// test exception handling
//			if ([gameView isDown:48])	//  '0'
//			{
//				NSException* myException = [NSException
//					exceptionWithName:	@"OoliteException"
//					reason:				@"Testing: The Foo throggled the Bar!"
//					userInfo:			nil];
//				[myException raise];
//			}
			
			break;

		case	GUI_SCREEN_INTRO2 :
			if ([gameView isDown:32])	//  '<space>'
			{
				[self setStatus: STATUS_DOCKED];
				[universe removeDemoShips];
				[gui setBackgroundImage:nil];
				[self setGuiToStatusScreen];
				if (themeMusic)
				{
					[themeMusic stop];
				}
			}
			if ([gameView isDown:gvArrowKeyLeft])	//  '<--'
			{
				if (!upDownKeyPressed)
					[universe selectIntro2Previous];
			}
			if ([gameView isDown:gvArrowKeyRight])	//  '-->'
			{
				if (!upDownKeyPressed)
					[universe selectIntro2Next];
			}
			upDownKeyPressed = (([gameView isDown:gvArrowKeyLeft])||([gameView isDown:gvArrowKeyRight]));
			break;
			
		case	GUI_SCREEN_MISSION :
			if ([[gui keyForRow:21] isEqual:@"spacebar"])
			{
//				NSLog(@"GUI_SCREEN_MISSION looking for spacebar");
				if ([gameView isDown:32])	//  '<space>'
				{
					[self setStatus:STATUS_DOCKED];
					[universe removeDemoShips];
					[gui setBackgroundImage:nil];
					[self setGuiToStatusScreen];
					if (missionMusic)
					{
						[missionMusic stop];
					}
				}
			}
			else
			{
//				NSLog(@"GUI_SCREEN_MISSION looking for up/down/select");
				if ([gameView isDown:gvArrowKeyDown])
				{
					if ((!upDownKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([gui setSelectedRow:[gui selectedRow] + 1])
						{
							[gui click];
						}
						timeLastKeyPress = script_time;
					}
				}
				if ([gameView isDown:gvArrowKeyUp])
				{
					if ((!upDownKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([gui setSelectedRow:[gui selectedRow] - 1])
						{
							[gui click];
						}
						timeLastKeyPress = script_time;
					}
				}
				upDownKeyPressed = (([gameView isDown:gvArrowKeyUp])||([gameView isDown:gvArrowKeyDown]));
				//
				if ([gameView isDown:13])	//  '<enter/return>'
				{
					if (missionChoice)
						[missionChoice release];
					missionChoice = [[NSString stringWithString:[gui selectedRowKey]] retain];
					//
					[self setStatus:STATUS_DOCKED];
					[universe removeDemoShips];
					[gui setBackgroundImage:nil];
					[self setGuiToStatusScreen];
					if (missionMusic)
					{
						[missionMusic stop];
					}
					//
					[self checkScript];
				}
			}
			break;
	}
	
}

@end
