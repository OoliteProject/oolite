#import <stdint.h>

#ifndef NDEBUG

enum OODebugFlags
{
	DEBUG_LINKED_LISTS			= 0x00000001,
	DEBUG_ENTITIES				= 0x00000002,
	DEBUG_COLLISIONS			= 0x00000004,
	DEBUG_DOCKING				= 0x00000008,
	DEBUG_OCTREE				= 0x00000010,
	DEBUG_OCTREE_TEXT			= 0x00000020,
	DEBUG_BOUNDING_BOXES		= 0x00000040,
	DEBUG_OCTREE_DRAW			= 0x00000080,
	DEBUG_DRAW_NORMALS			= 0x00000100,
	DEBUG_NO_DUST				= 0x00000200,
	DEBUG_NO_SHADER_FALLBACK	= 0x00000400,
	
	// Flag for temporary use, always last in list.
	DEBUG_MISC					= 0x10000000
};
#define DEBUG_ALL					0xffffffff


extern uint32_t gDebugFlags;
extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;

#endif
