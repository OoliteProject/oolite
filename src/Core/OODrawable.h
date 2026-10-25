/*

OODrawable.h

Abstract base class for objects which can draw themselves.

C++20 since bead oo-smy, with OOMaterial the Materials module exemplar (proposed ADR-0056,
amendment oo-smy). Global since bead oo-9ht.9 deleted the Objective-C facade (with oo-hahfg, which
moved the entities' drawable to C++, and oo-9ht.132, the OOMesh facade): every drawable
(OOMesh, OOPlanetDrawable, OOSkyDrawable) and every holder is C++.


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OODRAWABLE_H
#define OODRAWABLE_H

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOOpenGL.h"
#include "OOMaths.h"
class Entity;	// Entity.h: the shader binding target (bead oo-9ht.39.6)

#include <vector>
#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"

#include "OOTexture.h"	// allTextures() answers oo::Ref<OOTexture>, which needs the class (bead oo-9ht.99)


class OODrawable : public oo::RefCounted
{
public:
	virtual void renderOpaqueParts();
	virtual void renderTranslucentParts();
	virtual bool hasOpaqueParts();
	virtual bool hasTranslucentParts();

	virtual GLfloat collisionRadius();
	virtual GLfloat maxDrawDistance();

	virtual BoundingBox boundingBox();

	// Passed to all materials.
	virtual void setBindingTarget(Entity *target);

	virtual void dumpSelfState();

	// What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h). None here, as
	// OOObject answered; OOMesh and OOSkyDrawable override it.
	virtual std::optional<std::string> descriptionComponents() const;

	// What "%@" printed for the drawable's facade (bead oo-9ht.9): "<Class 0x...>{components}",
	// the C++ class's name and the drawable's own address.
	std::string description() const;

#ifndef NDEBUG
	virtual std::vector<oo::Ref<OOTexture>> allTextures();
	virtual size_t totalSize();	// Size including dynamic data, not counting textures.

	// The object's own size, which totalSize() starts from (the facade's instance size until bead
	// oo-9ht.9): sizeof the dynamic type, each subclass answering its own.
	virtual size_t objectSize() const	{ return sizeof *this; }
#endif
};


/*	[drawable autorelease], which the deleted facade answered (bead oo-hahfg): keeps the drawable
	until the current autorelease pool drains, so a drawable an entity replaces lives exactly as
	long as its autoreleased object did. Nothing for null.
*/
void OODrawableAutorelease(oo::Ref<OODrawable> drawable);

#endif	// OODRAWABLE_H
