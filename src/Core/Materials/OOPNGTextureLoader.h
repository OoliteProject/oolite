/*

OOPNGTextureLoader.h

It's a texture loader. Which loads PNGs.


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

#ifndef OOPNGTEXTURELOADER_H
#define OOPNGTEXTURELOADER_H

#include "png.h"
#include "OOTexture.h"
#include "OOTextureLoader.h"

#include "oofnd/Data.hpp"
#include "oofnd/StdLib.hpp"


/*	Phase 3 (bead oo-z889, proposed ADR-0056 amendments oo-bj8 item 12, oo-vl43 item 4 and oo-zl36):
	a converted leaf, global, over OOTextureLoader, with no facade of its own. Only the loaders'
	factory (OOTextureLoader::loaderWithPath) makes one and queues it on the work manager (the
	loaders' facade was deleted by bead oo-9ht.114).
*/
class OOPNGTextureLoader : public OOTextureLoader
{
public:
	~OOPNGTextureLoader() override;	// was -dealloc

	void loadTexture() override;

	// Internal: for libpng's read callback (was the private -readBytes:count:).
	void readBytes(png_bytep bytes, png_size_t count);

private:
	void doLoadTexture();

	png_structp					png = {};
	png_infop					pngInfo = {};
	png_infop					pngEndInfo = {};
	std::optional<oo::Data>		fileData;
	size_t						length = {};
	size_t						offset = {};
};

#endif	// OOPNGTEXTURELOADER_H
