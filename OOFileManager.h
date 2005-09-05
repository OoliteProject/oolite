#ifdef LOADSAVEGUI
//
// OOFileManager.h
//
// Created for the Oolite-Linux project
// 
// Dylan Smith, 2005-07-02
//
// This extends NSFileManager and adds some methods to insulate the
// main oolite code from the gory details of creating/chdiring to the
// commander save directory.
//
// oolite: (c) 2004 Giles C Williams.
// This work is licensed under the Creative Commons Attribution NonCommercial
// ShareAlike license.
//
#import <Foundation/Foundation.h>

#define SAVEDIR "oolite-saves"

@interface NSFileManager ( OOFileManager )

   - (NSArray *)commanderContents;
   - (BOOL)chdirToDefaultCommanderPath;

@end
#endif

