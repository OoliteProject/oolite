/*

OOJoystickManager.m
By Dylan Smith
modified by Alex Smith

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

#include "OOJoystickManager.h"
#include "oofnd/Log.hpp"
#include "oofnd/Defaults.hpp"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"


namespace {

OOJoystickManager::StickHandlerFactory sStickHandlerFactory = nullptr;
OOJoystickManager *sSharedStickHandler = nullptr;	// never released, as before

}	// namespace


// +sharedStickHandler and +setStickHandlerClass: (moved from the deleted facade, bead oo-9ht.69):
// the class registered is a function that makes the manager; -init's body, init(), runs on the
// new manager as [[class alloc] init] ran it.
OOJoystickManager *OOJoystickManager::sharedStickHandler()
{
	if (sSharedStickHandler == nullptr)
	{
		oo::Ref<OOJoystickManager> handler = (sStickHandlerFactory != nullptr) ? sStickHandlerFactory() : oo::makeRef<OOJoystickManager>();
		handler->init();
		sSharedStickHandler = handler.leakRef();
	}
	return sSharedStickHandler;
}


bool OOJoystickManager::setStickHandlerFactory(StickHandlerFactory factory)
{
	OOCAssert(sStickHandlerFactory == nullptr && sSharedStickHandler == nullptr, "Can't set joystick handler class after joystick handler is initialized.");

	sStickHandlerFactory = factory;
	return true;
}


void OOJoystickManager::init()
{
	{
		// set initial values for stick buttons/axes (NO for buttons,
		// STICK_AXISUNASSIGNED for axes). Caution: calling this again
		// after axes have been assigned will set all the axes to
		// STICK_AXISUNASSIGNED so if there is a need to do something
		// like this, then do it some other way, or change this method
		// so it doesn't do that.
		clearStickStates();
		
		// Make some sensible mappings. This also ensures unassigned
		// axes and buttons are set to unassigned (STICK_NOFUNCTION).
		loadStickSettings();
		invertPitch = false;
		precisionMode = false;
	}
}



NSPoint OOJoystickManager::rollPitchAxis()
{
	return NSMakePoint(getAxisState(AXIS_ROLL), getAxisState(AXIS_PITCH));
}


NSPoint OOJoystickManager::viewAxis()
{
	return NSMakePoint(axstate[AXIS_VIEWX], axstate[AXIS_VIEWY]);
}


bool OOJoystickManager::getButtonState(int function)
{
	return butstate[function];
}


const BOOL *OOJoystickManager::getAllButtonStates()
{
	return butstate;
}

bool OOJoystickManager::isButtonDown(int button, int stickNum)
{
	return true_butstate[stickNum][button];
}

double OOJoystickManager::getAxisState(int function)
{
	if (axstate[function] == STICK_AXISUNASSIGNED)
	{
		return STICK_AXISUNASSIGNED;
	}
	switch (function)
	{
	case AXIS_ROLL:
		if (precisionMode)
		{
			return (roll_profile != nullptr ? roll_profile->value(axstate[function]) : 0.0) / STICK_PRECISIONFAC;
		}
		else
		{
 			return (roll_profile != nullptr ? roll_profile->value(axstate[function]) : 0.0);
		}
	case AXIS_PITCH:
		if (precisionMode)
		{
			return (pitch_profile != nullptr ? pitch_profile->value(axstate[function]) : 0.0) / STICK_PRECISIONFAC;
		}
		else
		{
			return (pitch_profile != nullptr ? pitch_profile->value(axstate[function]) : 0.0);
		}
	case AXIS_YAW:
		if (precisionMode)
		{
			return (yaw_profile != nullptr ? yaw_profile->value(axstate[function]) : 0.0) / STICK_PRECISIONFAC;
		}
		else
		{
			return (yaw_profile != nullptr ? yaw_profile->value(axstate[function]) : 0.0);
		}
	default:
		return axstate[function];
	}
}


double OOJoystickManager::getSensitivity()
{
	return precisionMode ? STICK_PRECISIONFAC : 1.0;
}

void OOJoystickManager::setProfile(OOJoystickAxisProfile *profile, int axis)
{
	switch (axis)
	{
	case AXIS_ROLL:
		roll_profile = oo::Ref<OOJoystickAxisProfile>(profile);
		break;

	case AXIS_PITCH:
		pitch_profile = oo::Ref<OOJoystickAxisProfile>(profile);
		break;

	case AXIS_YAW:
		yaw_profile = oo::Ref<OOJoystickAxisProfile>(profile);
		break;
	}
	return;
}

OOJoystickAxisProfile *OOJoystickManager::getProfileForAxis(int axis)
{
	switch (axis)
	{
	case AXIS_ROLL:
		return roll_profile.get();
	case AXIS_PITCH:
		return pitch_profile.get();
	case AXIS_YAW:
		return yaw_profile.get();
	}
	return nullptr;
}


void OOJoystickManager::saveProfileForAxis(int axis)
{
	oo::Defaults &defaults = oo::Defaults::standard();
	oo::PList::Dict dict;
	OOJoystickAxisProfile *profile;
	OOJoystickStandardAxisProfile *standard_profile;
	OOJoystickSplineAxisProfile *spline_profile;
	std::vector<NSPoint> controlPoints;
	oo::PList::Array points;
	NSPoint point;
	NSUInteger i;
	
	profile = getProfileForAxis(axis);
	if (!profile) return;
	dict["Deadzone"] = oo::PList(profile->deadzone());
	if (dynamic_cast<OOJoystickStandardAxisProfile *>(profile) != nullptr)
	{
		standard_profile = static_cast<OOJoystickStandardAxisProfile *>(profile);
		dict["Type"] = oo::PList("Standard");
		dict["Power"] = oo::PList(standard_profile->power());
		dict["Parameter"] = oo::PList(standard_profile->parameter());
	}
	else if (dynamic_cast<OOJoystickSplineAxisProfile *>(profile) != nullptr)
	{
		spline_profile = static_cast<OOJoystickSplineAxisProfile *>(profile);
		dict["Type"] = oo::PList("Spline");
		controlPoints = spline_profile->controlPoints();
		points.reserve(controlPoints.size());
		for (i = 0; i < controlPoints.size(); i++)
		{
			point = controlPoints[i];
			// +numberWithFloat: as before: single-precision reals, so the defaults file prints them
			// with %.7g (proposed ADR-0043 Amendment 2).
			points.push_back(oo::PList(oo::PList::Array{
				oo::PList::singleReal(static_cast<float>(point.x)),
				oo::PList::singleReal(static_cast<float>(point.y)) }));
		}
		dict["ControlPoints"] = oo::PList(std::move(points));
	}
	else
	{
		dict["Type"] = oo::PList("Standard");
	}
	if (axis == AXIS_ROLL)
	{
		defaults.setObject(std::string(STICK_ROLL_AXIS_PROFILE_SETTING), oo::PList(std::move(dict)));
	}
	else if (axis == AXIS_PITCH)
	{
		defaults.setObject(std::string(STICK_PITCH_AXIS_PROFILE_SETTING), oo::PList(std::move(dict)));
	}
	else if (axis == AXIS_YAW)
	{
		defaults.setObject(std::string(STICK_YAW_AXIS_PROFILE_SETTING), oo::PList(std::move(dict)));
	}
	return;
}



void OOJoystickManager::loadProfileForAxis(int axis)
{
	oo::Defaults &defaults = oo::Defaults::standard();
	oo::PList dict;
	oo::Ref<OOJoystickStandardAxisProfile> standard_profile;
	oo::Ref<OOJoystickSplineAxisProfile> spline_profile;

	if (axis == AXIS_ROLL)
	{
		dict = defaults.object(std::string(STICK_ROLL_AXIS_PROFILE_SETTING));
	}
	else if (axis == AXIS_PITCH)
	{
		dict = defaults.object(std::string(STICK_PITCH_AXIS_PROFILE_SETTING));
	}
	else if (axis == AXIS_YAW)
	{
		dict = defaults.object(std::string(STICK_YAW_AXIS_PROFILE_SETTING));
	}
	else
	{
		return;
	}

	const oo::PList *type = dict.find("Type");
	if (type != nullptr && type->isString() && *type->getIf<std::string>() == "Standard")
	{
		standard_profile = oo::makeRef<OOJoystickStandardAxisProfile>();
		standard_profile->setDeadzone(dict.get<double>("Deadzone"));
		standard_profile->setPower(dict.get<double>("Power"));
		standard_profile->setParameter(dict.get<double>("Parameter"));
		setProfile(standard_profile.get(), axis);
	}
	else if(type != nullptr && type->isString() && *type->getIf<std::string>() == "Spline")
	{
		spline_profile = oo::makeRef<OOJoystickSplineAxisProfile>();
		spline_profile->setDeadzone(dict.get<double>("Deadzone"));
		const oo::PList *points = dict.get<oo::PList::Array>("ControlPoints"), *pointArray;
		NSPoint point;
		NSUInteger i;

		for (i = 0; points != nullptr && i < points->count(); i++)
		{
			pointArray = points->at<oo::PList::Array>(i);
			if (pointArray != nullptr && pointArray->count() >= 2)
			{
				point = NSMakePoint(pointArray->at<float>(0), pointArray->at<float>(1));
				spline_profile->addControl(point);
			}
		}
		setProfile(spline_profile.get(), axis);
	}
	else
	{
		setProfile(oo::makeRef<OOJoystickStandardAxisProfile>().get(), axis);
	}
}

std::vector<std::string> OOJoystickManager::listSticks()
{
	NSUInteger i, stickCount = joystickCount();

	std::vector<std::string> stickList;
	for (i = 0; i < stickCount; i++)
	{
		stickList.push_back(nameOfJoystick(i).value_or(std::string()));	// a nameless stick lists as "", as before
	}
	return stickList;
}


oo::PList OOJoystickManager::axisFunctions()
{
	int i,j;
	oo::PList::Dict fnList;

	// Add axes
	for (i = 0; i < MAX_AXES; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if(axismap[j][i] >= 0)
			{
				oo::PList::Dict fnDict;
				fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(true));
				fnDict[std::string(STICK_NUMBER)] = oo::PList(j);
				fnDict[std::string(STICK_AXBUT)] = oo::PList(i);
				fnList[ENUMKEY(axismap[j][i])] = oo::PList(std::move(fnDict));
			}
		}
	}
	return oo::PList(std::move(fnList));
}


oo::PList OOJoystickManager::buttonFunctions()
{
	int i, j;
	oo::PList::Dict fnList;

	// Add buttons
	for (i = 0; i < MAX_BUTTONS; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if(buttonmap[j][i] >= 0)
			{
				oo::PList::Dict fnDict;
				fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(false));
				fnDict[std::string(STICK_NUMBER)] = oo::PList(j);
				fnDict[std::string(STICK_AXBUT)] = oo::PList(i);
				fnList[ENUMKEY(buttonmap[j][i])] = oo::PList(std::move(fnDict));
			}
		}
	}
	return oo::PList(std::move(fnList));
}


void OOJoystickManager::setFunction(int function, const oo::PList &stickFn)
{
	bool isAxis = stickFn.get<bool>(std::string(STICK_ISAXIS)) ? true : false;
	int stickNum = stickFn.get<int>(std::string(STICK_NUMBER));
	int stickAxBt = stickFn.get<int>(std::string(STICK_AXBUT));

	if (isAxis)
	{
		setFunctionForAxis(stickAxBt,
						function,
						   stickNum);
	}
	else
	{
		setFunctionForButton(stickAxBt,
						  function,
							 stickNum);
	}
}


void OOJoystickManager::setFunctionForAxis(int axis,
                   int function,
                      int stickNum)
{
	OOCParameterAssert(axis < MAX_AXES && stickNum < MAX_STICKS);
	
	int16_t axisvalue = getAxisWithStick(stickNum, axis);
	unsetAxisFunction(function);
	axismap[stickNum][axis] = function;
	
	// initialize the throttle to what it's set to now (or else the
	// commander has to waggle the throttle to wake it up). Other axes
	// set as default.
	if(function == AXIS_THRUST)
	{
		axstate[function] = (float)(65536 - (axisvalue + 32768)) / 65536;
	}
	else
	{
		axstate[function] = (float)axisvalue / STICK_NORMALDIV;
	}
}


void OOJoystickManager::setFunctionForButton(int button,
                     int function,
                        int stickNum)
{
	OOCParameterAssert(button < MAX_BUTTONS && stickNum < MAX_STICKS);
	
	int i, j;
	for (i = 0; i < MAX_BUTTONS; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if (buttonmap[j][i] == function)
			{
				buttonmap[j][i] = STICK_NOFUNCTION;
				break;
			}
		}
	}
	buttonmap[stickNum][button] = function;
}


void OOJoystickManager::unsetAxisFunction(int function)
{
	int i, j;
	for (i = 0; i < MAX_AXES; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if (axismap[j][i] == function)
			{
				axismap[j][i] = STICK_NOFUNCTION;
				axstate[function] = STICK_AXISUNASSIGNED;
				break;
			}
		}
	}
}


void OOJoystickManager::unsetButtonFunction(int function)
{
	int i,j;
	for (i = 0; i < MAX_BUTTONS; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if(buttonmap[j][i] == function)
			{
				buttonmap[j][i] = STICK_NOFUNCTION;
				break;
			}
		}
	}
}


void OOJoystickManager::setDefaultMapping()
{
	// assign the simplest mapping: stick 0 having
	// axis 0/1 being roll/pitch and button 0 being fire, 1 being missile
	// All joysticks should at least have two axes and two buttons.
	axismap[0][0] = AXIS_ROLL;
	axismap[0][1] = AXIS_PITCH;
	buttonmap[0][0] = BUTTON_FIRE;
	buttonmap[0][1] = BUTTON_LAUNCHMISSILE;
}


void OOJoystickManager::clearMappings()
{
	memset(axismap, STICK_NOFUNCTION, sizeof axismap);
	memset(buttonmap, STICK_NOFUNCTION, sizeof buttonmap);
}


void OOJoystickManager::clearStickStates()
{
	int i, j;
	for (i = 0; i < AXIS_end; i++)
	{
		axstate[i] = STICK_AXISUNASSIGNED;
	}
	for (i = 0; i < BUTTON_end; i++)
	{
		butstate[i] = 0;
	}
	for (i = 0; i < MAX_BUTTONS; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			true_butstate[j][i] = false;
		}
	}
}


void OOJoystickManager::clearStickButtonState(int stickButton)
{
	if (stickButton >= 0 && stickButton < BUTTON_end)
	{
		butstate[stickButton] = 0;
	}
}


void OOJoystickManager::setCallback(StickCallback callback,
           char hwflags)
{
	cbCallback = std::move(callback);
	cbHardware = hwflags;
}


void OOJoystickManager::clearCallback()
{
	cbCallback = nullptr;
	cbHardware = 0;
}


void OOJoystickManager::decodeAxisEvent(JoyAxisEvent *evt)
{
	// Which axis moved? Does the value need to be made to fit a
	// certain function? Convert axis value to a double.
	double axisvalue = (double)evt->value;
	
	// First check if there is a callback and...
	if(cbCallback && (cbHardware & HW_AXIS)) 
	{
		// ...then check if axis moved more than AXCBTHRESH - (fix for BUG #17482)
		if(axisvalue > AXCBTHRESH)
		{
			oo::PList::Dict fnDict;
			fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(true));
			fnDict[std::string(STICK_NUMBER)] = oo::PList(static_cast<int>(evt->which));
			fnDict[std::string(STICK_AXBUT)] = oo::PList(static_cast<int>(evt->axis));
			cbHardware = 0;
			const StickCallback callback = cbCallback;	// a copy: the callback may set another
			callback(oo::PList(std::move(fnDict)));
			cbCallback = nullptr;
		}
		
		// we are done.
		return;
	}
	
	// SDL seems to have some bizarre (perhaps a bug) behaviour when
	// events get queued up because the game isn't ready to handle
	// them (perhaps it's loading a commander and initializing the
	// universe, and the main event loop is blocked).
	// What happens is SDL lies about the axis that was triggered. For
	// each queued event it adds 1 to the axis number!! This does
	// not seem to happen with buttons.
	int function;
	if (evt->axis < MAX_AXES)
	{
		function = axismap[evt->which][evt->axis];
	}
	else
	{
		OO_LOG("decodeAxisEvent", "Stick axis out of range - axis was {}", evt->axis);
		return;
	}
	switch (function)
	{
		case STICK_NOFUNCTION:
			// do nothing
			break;
		case AXIS_THRUST:
			// Normalize the thrust setting.
			axstate[function] = (float)(65536 - (axisvalue + 32768)) / 65536;
			break;
		case AXIS_ROLL:
		case AXIS_PITCH:
		case AXIS_YAW:
		case AXIS_VIEWX:
		case AXIS_VIEWY:
			axstate[function] = axisvalue / STICK_NORMALDIV;
			break;
		// TODO AXIS_FIELD_OF_VIEW
		default:
			// set the state with no modification.
			axstate[function] = axisvalue / 32768;         
	}
	if ((function == AXIS_PITCH) && invertPitch) axstate[function] = -1.0*axstate[function];
}


void OOJoystickManager::decodeButtonEvent(JoyButtonEvent *evt)
{
	bool bs = false;
	
	// Is there a callback we need to make?
	if(cbCallback && (cbHardware & HW_BUTTON))
	{
		oo::PList::Dict fnDict;
		fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(false));
		fnDict[std::string(STICK_NUMBER)] = oo::PList(static_cast<int>(evt->which));
		fnDict[std::string(STICK_AXBUT)] = oo::PList(static_cast<int>(evt->button));
		cbHardware = 0;
		const StickCallback callback = cbCallback;	// a copy: the callback may set another
		callback(oo::PList(std::move(fnDict)));
		cbCallback = nullptr;
		
		// we are done.
		return;
	}
	
	// Defensive measure - see comments in the axis handler for why.
	int function;
	if (evt->button < MAX_BUTTONS)
	{
		function = buttonmap[evt->which][evt->button];
	}
	else
	{
		OO_LOG("decodeButtonEvent", "Joystick button out of range: {}", evt->button);
		return;
	}
	if (evt->type == static_cast<SDL_EventType>(JOYBUTTONDOWN))
	{
		bs = true;
		if(function == BUTTON_PRECISION)
			precisionMode = !precisionMode;
	}
	true_butstate[evt->which][evt->button] = bs;
	if (function >= 0)
	{
		butstate[function]=bs;
	}
	
}


void OOJoystickManager::decodeHatEvent(JoyHatEvent *evt)
{
	// HACK: handle this as a set of buttons
	int i;
	JoyButtonEvent btn;

	btn.which = evt->which;
	
	for (i = 0; i < 4; ++i)
	{
		if ((evt->value ^ hatstate[evt->which][evt->hat]) & (1 << i))
		{
			btn.type = (SDL_EventType)((evt->value & (1 << i)) ? JOYBUTTONDOWN : JOYBUTTONUP);
			btn.button = MAX_REAL_BUTTONS + i + evt->which * 4;
			btn.down = (evt->value & (1 << i));
			decodeButtonEvent(&btn);
		}
	}
	
	hatstate[evt->which][evt->hat] = evt->value;
}


NSUInteger OOJoystickManager::joystickCount()
{
	return 0;
}


void OOJoystickManager::saveStickSettings()
{
	oo::Defaults &defaults = oo::Defaults::standard();
	
	defaults.setObject(std::string(AXIS_SETTINGS), axisFunctions());
	defaults.setObject(std::string(BUTTON_SETTINGS), buttonFunctions());
	saveProfileForAxis(AXIS_ROLL);
	saveProfileForAxis(AXIS_PITCH);
	saveProfileForAxis(AXIS_YAW);
	defaults.synchronize();
}


void OOJoystickManager::loadStickSettings()
{
	clearMappings();
	oo::Defaults &defaults = oo::Defaults::standard();
	const oo::PList axisSettings = defaults.object(std::string(AXIS_SETTINGS));
	const oo::PList buttonSettings = defaults.object(std::string(BUTTON_SETTINGS));
	// Keys are visited in byte order (they came in hash order): where two settings claim the
	// same stick axis or button, the last one still wins (proposed ADR-0043).
	if(axisSettings)
	{
		if (const oo::PList::Dict *settings = axisSettings.getIf<oo::PList::Dict>())
		{
			for (const auto &[key, stickFn] : *settings)
			{
				setFunction(oo::str::intValue(key),
						 stickFn);
			}
		}
	}
	if(buttonSettings)
	{
		if (const oo::PList::Dict *settings = buttonSettings.getIf<oo::PList::Dict>())
		{
			for (const auto &[key, stickFn] : *settings)
			{
				setFunction(oo::str::intValue(key),
						 stickFn);
			}
		}
	}
	else
	{
		// Nothing to load - set useful defaults
		setDefaultMapping();
	}
	loadProfileForAxis(AXIS_ROLL);
	loadProfileForAxis(AXIS_PITCH);
	loadProfileForAxis(AXIS_YAW);
}

// These get overidden by subclasses

std::optional<std::string> OOJoystickManager::nameOfJoystick(NSUInteger /*stickNumber*/)
{
	return std::string("Dummy joystick");
}

int16_t OOJoystickManager::getAxisWithStick(NSUInteger /*stickNum*/, NSUInteger /*axisNum*/)
{
	return 0;
}

