#include <stdint.h>

enum OODebugFlags
{
	DEBUG_LINKED_LISTS			= 0x00000001,
//	UNUSED						= 0x00000002,
	DEBUG_COLLISIONS			= 0x00000004,
	DEBUG_DOCKING				= 0x00000008,
	DEBUG_OCTREE_LOGGING		= 0x00000010,
//	UNUSED						= 0x00000020,
	DEBUG_BOUNDING_BOXES		= 0x00000040,
	DEBUG_OCTREE_DRAW			= 0x00000080,
	DEBUG_DRAW_NORMALS			= 0x00000100,
	DEBUG_NO_DUST				= 0x00000200,
	DEBUG_NO_SHADER_FALLBACK	= 0x00000400,
	DEBUG_SHADER_VALIDATION		= 0x00000800,
	
	// Flag for temporary use, always last in list.
	DEBUG_MISC					= 0x10000000
};
#define DEBUG_ALL					0xffffffff


#ifndef NDEBUG

extern NSUInteger gDebugFlags;
extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;

#else

#define gDebugFlags (0)

#endif
