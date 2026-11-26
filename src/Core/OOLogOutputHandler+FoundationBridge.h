/*

OOLogOutputHandler+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; made by bead oo-vjts, Amendment 2 item
18(a)). gnustep-base's NSLog hook (_NSLog_printf_handler, whose type is void (*)(NSString *)),
which OOLogOutputHandlerInit() / OOLogOutputHandlerClose() install and remove through the two C
functions below. It goes with gnustep-base (oo-qps). The Foundation-typed OOLogOutputHandler API
forwarders were removed by oo-vors once every caller moved to the cxx_ API.

Never add Foundation-typed forwarders here. oo-qps (the removal of gnustep-base) deletes this file,
OOLogOutputHandler+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOLogOutputHandler.h.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2013 Jens Ayton (OOLogOutputHandler.h)

*/

// Imported only from the end of OOLogOutputHandler.h (which declares everything used here); never
// import it directly, and never import OOLogOutputHandler.h from it (a cycle).
#ifndef OOLOGOUTPUTHANDLER_FOUNDATIONBRIDGE_H
#define OOLOGOUTPUTHANDLER_FOUNDATIONBRIDGE_H

// gnustep-base's NSLog hook: route NSLog() into the "gnustep" log class. No-ops elsewhere.
void OOLogOutputHandlerInstallNSLogHook(void);
void OOLogOutputHandlerRemoveNSLogHook(void);

#endif // OOLOGOUTPUTHANDLER_FOUNDATIONBRIDGE_H
