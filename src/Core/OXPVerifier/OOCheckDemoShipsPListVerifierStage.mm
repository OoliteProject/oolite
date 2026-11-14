/*

OOCheckDemoShipsPListVerifierStage.m


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

#import "OOCheckDemoShipsPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "OOFoundationBridge.h"

static const char* const kStageName = "Checking demoships.plist";

@interface OOCheckDemoShipsPListVerifierStage (OOPrivate)

// demoshipsPList is an Array, shipdataPList a Dict.
- (void)runCheckWithDemoShips:(const oo::PList&)demoshipsPList shipData:(const oo::PList&)shipdataPList;

@end

@implementation OOCheckDemoShipsPListVerifierStage

- (id)name // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom(kStageName);
}

- (BOOL)shouldRun
{
    OOFileScannerVerifierStage* fileScanner = nil;

    fileScanner = [[self verifier] fileScannerStage];
    return [fileScanner fileExists:@"demoships.plist"
                          inFolder:@"Config"
                    referencedFrom:nil
                      checkBuiltIn:NO];
}

- (void)run
{
    OOFileScannerVerifierStage* fileScanner = nil;
    oo::PList demoshipsPList;
    oo::PList shipdataPList;

    fileScanner = [[self verifier] fileScannerStage];

    demoshipsPList = oo::PListFrom([fileScanner plistNamed:@"demoships.plist"
                                                  inFolder:@"Config"
                                            referencedFrom:nil
                                              checkBuiltIn:NO]);

    if (demoshipsPList.isNull())
        return;

    // Check that it's an array
    if (!demoshipsPList.isArray()) {
        OOLog(@"verifyOXP.demoshipsPList.notArray", @"%@", @"***** ERROR: demoships.plist is not an array.");
        return;
    }

    shipdataPList = oo::PListFrom([fileScanner plistNamed:@"shipdata.plist"
                                                 inFolder:@"Config"
                                           referencedFrom:nil
                                             checkBuiltIn:NO]);

    if (shipdataPList.isNull())
        return;

    // Check that it's a dictionary
    if (!shipdataPList.isDict()) {
        OOLog(@"verifyOXP.demoshipsPList.notDict", @"%@", @"***** ERROR: shipdata.plist is not a dictionary.");
        return;
    }

    [self runCheckWithDemoShips:demoshipsPList shipData:shipdataPList];
}

@end

@implementation OOCheckDemoShipsPListVerifierStage (OOPrivate)

- (void)runCheckWithDemoShips:(const oo::PList&)demoshipsPList shipData:(const oo::PList&)shipdataPList
{
    for (const oo::PList& entry : *demoshipsPList.getIf<oo::PList::Array>()) {
        // An entry that is not a string is no key of shipdata.plist; "%@" prints the entry itself.
        const std::string* name = entry.getIf<std::string>();
        if (name == nullptr || shipdataPList.find(*name) == nullptr) {
            OOLog(@"verifyOXP.demoshipsPList.unknownShip", @"----- WARNING: demoships.plist entry \"%@\" not found in shipdata.plist.", name != nullptr ? oo::NSStringFrom(*name) : oo::ObjectFromPList(entry));
        }
    }
}

@end

#endif
