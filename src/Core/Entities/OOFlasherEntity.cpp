/*

OOFlasherEntity.m


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

#include "OOFlasherEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOColor.h"
#include "OOJSFlasher.h"

#include "oofnd/PListGet.hpp"


oo::Ref<OOFlasherEntity> OOFlasherEntity::flasherWithDictionary(const oo::PList &dictionary)
{
	const oo::Ref<OOFlasherEntity> flasher = oo::makeRef<OOFlasherEntity>();
	flasher->initWithDictionary(dictionary);
	return flasher;
}


void OOFlasherEntity::initWithDictionary(const oo::PList &dictionary)
{
	float size = dictionary.get<float>("size", 1.0f);
	
	OOLightParticleEntity::initWithDiameter(size);
	// [super initWithDiameter:] could not fail.
	{
		_frequency = dictionary.get<float>("frequency", 1.0f) * 2.0f;
		_phase = dictionary.get<float>("phase", 0.0f);
		_brightfraction = dictionary.get<float>("bright_fraction", 0.5f);

		setUpColors(dictionary.get<oo::PList::Array>("colors"));
		getCurrentColorComponents();
		
		setActive(dictionary.get<bool>("initially_on", YES));
	}
}


void OOFlasherEntity::setUpColors(const oo::PList *colorSpecifiers)
{
	std::vector<oo::Ref<OOColor>> colors;
	if (colorSpecifiers != nullptr)
	{
		for (const oo::PList &specifier : *colorSpecifiers->getIf<oo::PList::Array>())
		{
			colors.emplace_back(OOColor::colorWithDescription(specifier, 0.75f));
		}
	}
	
	_colors = std::move(colors);
}


// The colour at index; null past the end (-objectAtIndex: raised there).
OOColor *OOFlasherEntity::flasherColorAtIndex(NSUInteger index)
{
	return index < _colors.size() ? _colors[index].get() : nullptr;
}


void OOFlasherEntity::getCurrentColorComponents()
{
	setColor(flasherColorAtIndex(_activeColor), _colorComponents[3]);
}


bool OOFlasherEntity::isActive()
{
	return _active;
}


void OOFlasherEntity::setActive(bool active)
{
	_active = !!active;
}


oo::Ref<OOColor> OOFlasherEntity::color()
{
	return OOColor::colorWithRed(_colorComponents[0],
								 _colorComponents[1],
								 _colorComponents[2],
								 _colorComponents[3]);
}


float OOFlasherEntity::frequency()
{
	return _frequency;
}


void OOFlasherEntity::setFrequency(float frequency)
{
	_frequency = frequency;
}


float OOFlasherEntity::phase()
{
	return _phase;
}


void OOFlasherEntity::setPhase(float phase)
{
	_phase = phase;
}


float OOFlasherEntity::fraction()
{
	return _brightfraction;
}


void OOFlasherEntity::setFraction(float fraction)
{
	_brightfraction = fraction;
}


void OOFlasherEntity::update(OOTimeDelta delta_t)
{
	OOLightParticleEntity::update(delta_t);
	
	_time += delta_t;

	if (_frequency != 0)
	{
		float wave = sinf(_frequency * M_PI * (_time + _phase));
		NSUInteger count = _colors.size();
		if (count > 1 && wave < 0) 
		{
			if (!_justSwitched && wave > _wave)	// don't test for wave >= _wave - could give wrong results with very low frequencies
			{
				_justSwitched = YES;
				++_activeColor;
				_activeColor %= count;	//_activeColor = ++_activeColor % count; is potentially undefined operation
				setColor(flasherColorAtIndex(_activeColor));
			}
		}
		else if (_justSwitched)
		{
			_justSwitched = NO;
		}

		float threshold = cosf(_brightfraction * M_PI);
		
		float brightness = _brightfraction;
		if (wave > threshold)
		{
			brightness = _brightfraction + (((1-_brightfraction)/(1-threshold))*(wave-threshold));
		}
		else if (wave < threshold)
		{
			brightness = _brightfraction + ((_brightfraction/(threshold+1))*(wave-threshold));
		}

		_colorComponents[3] = brightness;
		
		_wave = wave;
	}
	else
	{
		_colorComponents[3] = 1.0;
	}
}


void OOFlasherEntity::drawImmediate(bool immediate, bool translucent)
{
	if (_active)
	{
		OOLightParticleEntity::drawImmediate(immediate, translucent);
	}
}


void OOFlasherEntity::drawSubEntityImmediate(bool immediate, bool translucent)
{
	if (_active)
	{
		OOLightParticleEntity::drawSubEntityImmediate(immediate, translucent);
	}
}


bool OOFlasherEntity::isFlasher()
{
	return YES;
}


double OOFlasherEntity::findCollisionRadius()
{
	return diameter() / 2.0;
}


void OOFlasherEntity::rescaleBy(GLfloat factor)
{
	setDiameter(diameter() * factor);
}


void OOFlasherEntity::rescaleBy(GLfloat /*factor*/, bool /*writeToCache*/)
{
	/* Do nothing; this is only needed because of OOEntityWithDrawable
	   implementation requirements */
}


// The binding's bodies (OOJSFlasher.mm), which the façade forwarded to until bead oo-9ht.107.
void OOFlasherEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSFlasherGetJSClass(outClass, outPrototype);
}


std::optional<std::string> OOFlasherEntity::jsClassName()
{
	return ::OOJSFlasherJSClassName();
}


bool OOFlasherEntity::isVisibleToScripts()
{
	return ::OOJSFlasherIsVisibleToScripts();
}
