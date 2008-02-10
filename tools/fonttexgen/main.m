//
//  main.m
//  fonttexgen
//
//  Created by Jens Ayton on 2008-01-27.
//  Copyright Jens Ayton 2008. All rights reserved.
//

#import <Cocoa/Cocoa.h>

int main(int argc, char *argv[])
{
	@try
	{
		return NSApplicationMain(argc,  (const char **) argv);
	}
	@catch (id e)
	{
		NSLog(@"*** Root exception handler: %@: %@", [e name], [e reason]);
	}
	return -1;
}
