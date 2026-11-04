/*

AIGraphViz.h

GenerateGraphVizForAIStateMachine(), defined in AIGraphViz.mm (DEBUG_GRAPHVIZ
builds only). It is declared here, next to its definition, and uses the C++
types AI.mm holds the state machine in.


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

#if DEBUG_GRAPHVIZ

#include "OOFoundation.h"
#include "oofnd/PList.hpp"

void GenerateGraphVizForAIStateMachine(const oo::PList& stateMachine,
                                       const std::string& smName);

#endif  // DEBUG_GRAPHVIZ
