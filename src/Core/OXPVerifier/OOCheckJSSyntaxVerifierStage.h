/*

OOCheckJSSyntaxVerifierStage.h

OOOXPVerifierStage which checks that JS scripts compile


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

#pragma once

#include "OOFileScannerVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

/*	A leaf of OOFileHandlingVerifierStage. Nothing outside this file names
   it; the verifier makes it from its name (kCxxStages in OOOXPVerifier.mm) and
   holds it.
*/
class OOCheckJSSyntaxVerifierStage : public OOFileHandlingVerifierStage {
 public:
  std::optional<std::string> name() override;
  bool shouldRun() override;
  void run() override;
};

#endif
