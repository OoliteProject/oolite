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
#include <stdlib.h>
#import "OOFileManager.h"

@implementation NSFileManager ( OOFileManager )

- (NSArray *)commanderContents
{
   if([self chdirToDefaultCommanderPath])
   {
      NSArray *contents=[self directoryContentsAtPath: @"."];   
      return contents;
   }
   return nil;
}

- (BOOL)chdirToDefaultCommanderPath
{
   NSString *savedir=
      [NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR];
   if(![self changeCurrentDirectoryPath: savedir])
   {
      // it probably doesn't exist.
      if(![self createDirectoryAtPath: savedir attributes: nil])
      {
         NSLog(@"Unable to create: %@", savedir);
         return NO;
      }
      if(![self changeCurrentDirectoryPath: savedir])
      {
         NSLog(@"Created %@ but couldn't chdir to it", savedir);
         return NO;
      }
   }
   NSLog(@"CWD is %@", savedir);
      
   return YES;
}

@end
