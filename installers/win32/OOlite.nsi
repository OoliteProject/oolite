; Include the NSIS logic library. Required for the code that handles 
; adding of the changelog file in the non-snapshot distributions
!include "LogicLib.nsh"

; Include the Sections library, required for being able to provide the 
; Basic-debug.OXP as an optional installation component
!include "Sections.nsh"

; Include the x64 library, required for checking whether the user has
; attempted to run the 64-bit installer flavor under a 32-bit OS
!include "x64.nsh"

; Need to include the versions as we can't pass them in as parameters
; and it's too much work to try to dynamically edit this file
!include /NONFATAL "OoliteVersions.nsh"

!ifndef VER_GITREV
!warning "No GIT Revision supplied"
!define VER_GITREV 0
!endif
!ifndef VERSION
!warning "No Version information supplied"
!define VERSION 0.0.0.0
!endif
; Version number must be of format X.X.X.X.
; We use M.m.R.S:  M-major, m-minor, R-revision, S-subversion
!define VER ${VERSION}
!ifndef DST
!define DST ..\..\oolite.app
!endif
!ifndef OUTDIR
!define OUTDIR .
!endif

!ifndef SNAPSHOT
!define EXTVER ""
!define ADDCHANGELOG 1	; Official distributions go with a changelog file
!else
!define EXTVER "-dev"
!define ADDCHANGELOG 0	; Snapshot distributions do not need changelog
!endif

!ifndef DEPLOYMENT
!define DEBUGOXPINCLUDED 1
!else
!define DEBUGOXPINCLUDED 0
!endif


!include "MUI.nsh"

SetCompress auto
SetCompressor LZMA
SetCompressorDictSize 32
SetDatablockOptimize on
OutFile "${OUTDIR}\OoliteInstall-${VER_MAJ}.${VER_MIN}.${VER_REV}.${VER_GITHASH}${EXTVER}.exe"
BrandingText "(C) 2003-2018 Giles Williams, Jens Ayton and contributors"
Name "Oolite"
Caption "Oolite ${VER}${EXTVER} Setup"
SubCaption 0 " "
SubCaption 1 " "
SubCaption 2 " "
SubCaption 3 " "
SubCaption 4 " "
Icon Oolite.ico
UninstallIcon Oolite.ico
InstallDirRegKey HKLM Software\Oolite "Install_Dir"
InstallDir $INSTDIR	; $INSTDIR is set in .onInit
CRCCheck on
InstallColors /windows
InstProgressFlags smooth
AutoCloseWindow false
SetOverwrite on
RequestExecutionLevel user


VIAddVersionKey "ProductName" "Oolite"
VIAddVersionKey "FileDescription" "A space combat/trading game, inspired by Elite."
VIAddVersionKey "LegalCopyright" "© 2003-2018 Giles Williams, Jens Ayton and contributors"
VIAddVersionKey "FileVersion" "${VER}"
VIAddVersionKey "ProductVersion" "${VER}"
!ifdef SNAPSHOT
VIAddVersionKey "GIT Revision" "${VER_GITHASH}"
!endif
!ifdef BUILDTIME
VIAddVersionKey "Build Time" "${BUILDTIME}"
!endif
VIProductVersion "${VER}"


!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP ".\OoliteInstallerHeaderBitmap_ModernUI.bmp"
!define MUI_HEADERIMAGE_UNBITMAP ".\OoliteInstallerHeaderBitmap_ModernUI.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP ".\OoliteInstallerFinishpageBitmap.bmp"
!define MUI_ICON oolite.ico
!define MUI_UNICON oolite.ico

!insertmacro MUI_PAGE_DIRECTORY
!ifndef DEPLOYMENT
	!insertmacro MUI_PAGE_COMPONENTS
!endif
!insertmacro MUI_PAGE_INSTFILES

; NSIS first runs the finishpage_run macro, then finishpage_showreadme.
; By completely redefining the meaning of the macros, the installer now runs oolite after showing the readme(!)
  !define MUI_FINISHPAGE_RUN_NOTCHECKED 
  !define MUI_FINISHPAGE_RUN_TEXT "Show Readme"
  !define MUI_FINISHPAGE_RUN
  !define MUI_FINISHPAGE_RUN_FUNCTION readMe ; ExecWait!
  
  !define MUI_FINISHPAGE_SHOWREADME_CHECKED
  !define MUI_FINISHPAGE_SHOWREADME_TEXT "Run Oolite"
  !define MUI_FINISHPAGE_SHOWREADME 
  !define MUI_FINISHPAGE_SHOWREADME_FUNCTION firstRun
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

!ifndef DEPLOYMENT
; Create the main game and Debug OXP sections
Section "Oolite Game" ooGame
SectionIn RO	; The game itself cannot be unselected
SectionEnd

Section "Basic-debug.OXP" ooDebugOXP
; Do not use any of the Debug OXP files when we are building Deployment
SetOutPath $INSTDIR
File /r "..\..\AddOns"
SectionEnd

; Below are the descriptions of the two component sections
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
	!insertmacro MUI_DESCRIPTION_TEXT ${ooGame} "The core game files (required)."
	!insertmacro MUI_DESCRIPTION_TEXT ${ooDebugOXP} "Allows Oolite to communicate with the Debug Console. If you already have a Basic-debug.OXP in your \
													 destination AddOns folder, it will be overwritten."
!insertmacro MUI_FUNCTION_DESCRIPTION_END
!endif

Function .onInit
 ; 1. Check that we are not attempting to run a 64-bit installer on a 32-bit operating system
 ${IfNot} ${RunningX64}
   ${If} ${BUILDHOST_IS64BIT} == "1"
     MessageBox MB_OK|MB_ICONEXCLAMATION \
	 "This application installs the 64-bit version of Oolite and $\n \
	 cannot be run under a 32-bit environment. Click OK to abort $\n \
	 the installation."
	 Abort
   ${EndIf}
 ${EndIf}
 
 ; 2. Get the system drive
 StrCpy $R9 $WINDIR 2
 StrCpy $INSTDIR $R9\Oolite

 ; 3. Check for multiple running installers
 System::Call 'kernel32::CreateMutexA(i 0, i 0, t "OoliteInstallerMutex") i .r1 ?e'
 Pop $R0
 
 StrCmp $R0 0 +3
   MessageBox MB_OK|MB_ICONEXCLAMATION "Another instance of the Oolite installer is already running."
   Abort
   
  ;4a. Skip checks, don't uninstall previous versions. Comment out the following line to re-enable 4b.
  Goto done
  
  ; 4b. Checks for previous versions of Oolite and offers to uninstall
  ReadRegStr $R0 HKLM \
  "Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite" \
  "UninstallString"
  StrCmp $R0 "" done
 
  MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION \
  "Oolite is already installed. $\n$\nClick `OK` to remove the \
  previous version or `Cancel` to cancel this upgrade." \
  IDOK uninst
  Abort
 
;Run the uninstaller
uninst:
  ClearErrors
  ReadRegStr $R1 HKLM "Software\Oolite" Install_Dir
  ExecWait '$R0 _?=$R1'
  IfErrors no_remove_uninstaller
    Delete "$R1\UninstOolite.exe"
    Goto done
  no_remove_uninstaller:
    MessageBox MB_OK|MB_ICONEXCLAMATION "The Uninstaller did not complete successfully.  Please ensure Oolite was correctly uninstalled then run the installer again."
    Abort
done:
FunctionEnd

!ifndef DEPLOYMENT
Function .onSelChange
	${If} ${SectionIsSelected} ${ooDebugOXP}
		!insertmacro SelectSection ${ooDebugOXP}
		!undef DEBUGOXPINCLUDED
		!define DEBUGOXPINCLUDED 1
	${Else}
		!insertmacro UnselectSection ${ooDebugOXP}
		!undef DEBUGOXPINCLUDED
		!define DEBUGOXPINCLUDED 0
	${EndIf}
FunctionEnd
!endif

Function readMe
  ; don't do a thing until the user finishes reading the readme!
  ExecWait "notepad.exe $INSTDIR\Oolite_Readme.txt"
FunctionEnd

Function firstRun
  Exec "$INSTDIR\oolite.app\oolite.exe"
FunctionEnd

Function RegSetup
FunctionEnd

Function un.RegSetup
FunctionEnd

;------------------------------------------------------------
; Installation Section
Section ""
SetOutPath $INSTDIR

; Package files
; Inclusion of the DebugOXP files is handled in the ooDebugOXP section
${If} ${DEBUGOXPINCLUDED} == "0"
	CreateDirectory "$INSTDIR\AddOns"
${EndIf}
CreateDirectory "$INSTDIR\oolite.app\Logs"
CreateDirectory "$INSTDIR\oolite.app\oolite-saves"
CreateDirectory "$INSTDIR\oolite.app\oolite-saves\snapshots"

File "Oolite.ico"
File "Oolite_Readme.txt"
File "..\..\Doc\OoliteRS.pdf"
File "..\..\Doc\AdviceForNewCommanders.pdf"
File "..\..\Doc\OoliteReadMe.pdf"
${If} ${ADDCHANGELOG} == "1"
  File "..\..\Doc\CHANGELOG.TXT"
${EndIf}
File /r /x .svn /x *~ "${DST}"

WriteUninstaller "$INSTDIR\UninstOolite.exe"

; Registry entries
WriteRegStr HKLM Software\Oolite "Install_Dir" "$INSTDIR"
WriteRegStr HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite DisplayName "Oolite ${VER}${EXTVER}"
WriteRegStr HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite UninstallString '"$INSTDIR\UninstOolite.exe"'

; Start Menu shortcuts
SetOutPath $INSTDIR\oolite.app
CreateDirectory "$SMPROGRAMS\Oolite"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite.lnk" "$INSTDIR\oolite.app\oolite.exe" "" "$INSTDIR\Oolite.ico"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite ReadMe.lnk" "$INSTDIR\OoliteReadMe.pdf"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Reference Sheet.lnk" "$INSTDIR\OoliteRS.pdf"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite - Advice for New Commanders.lnk" "$INSTDIR\AdviceForNewCommanders.pdf"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Uninstall.lnk" "$INSTDIR\UninstOolite.exe"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Website.lnk" "http://oolite.org/" "" "$INSTDIR\Oolite.ico"

CreateShortCut "$SMPROGRAMS\Oolite\Oolite Logs.lnk" "$INSTDIR\oolite.app\Logs"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Screenshots.lnk" "$INSTDIR\oolite.app\oolite-saves\snapshots"
CreateShortCut "$SMPROGRAMS\Oolite\Expansion Packs.lnk" "$INSTDIR\AddOns"

Call RegSetup

SectionEnd


;------------------------------------------------------------
; Uninstaller Section
Section "Uninstall"

; Remove registry entries
DeleteRegKey HKLM Software\Oolite
DeleteRegKey HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite
Call un.RegSetup

; Remove Start Menu entries
RMDir /r "$SMPROGRAMS\Oolite"

; Remove Package files (but leave any generated content behind)
RMDir /r "$INSTDIR\oolite.app\Contents"

; Managed OXZs, if present, must survive the uninstall
IfFileExists "$INSTDIR\oolite.app\GNUstep\Library\ApplicationSupport\Oolite\ManagedAddOns\*.oxz" NoRemoveOXZFolder RemoveOXZFolder
NoRemoveOXZFolder:
RMDir /r "$INSTDIR\oolite.app\GNUstep\Defaults"
RMDir /r "$INSTDIR\oolite.app\GNUstep\Library\Caches"
goto EndOfOXZFolderCheck
RemoveOXZFolder:
RMDir /r "$INSTDIR\oolite.app\GNUstep"
EndOfOXZFolderCheck:

RMDir /r "$INSTDIR\oolite.app\oolite.app"
RMDir /r "$INSTDIR\oolite.app\Resources"
RMDir /r "$INSTDIR\oolite.app\Logs"
Delete "$INSTDIR\Oolite.ico"
Delete "$INSTDIR\Oolite_Readme.txt"
Delete "$INSTDIR\OoliteRS.pdf"
Delete "$INSTDIR\AdviceForNewCommanders.pdf"
Delete "$INSTDIR\OoliteReadMe.pdf"

IfFileExists "$INSTDIR\AddOns\Basic-debug.oxp\*.*"  DebugOXPRemove DebugOXPIgnore
DebugOXPRemove:
RMDIR /r "$INSTDIR\AddOns\Basic-debug.oxp"
DebugOXPIgnore:
; Nothing to do in this case, just continue

IfFileExists "$INSTDIR\CHANGELOG.TXT" ChangelogExists ChangelogDoesNotExist
ChangelogExists:
Delete "$INSTDIR\CHANGELOG.TXT"
ChangelogDoesNotExist:
; Nothing to do in this case, just continue

Delete "$INSTDIR\UninstOolite.exe"
Delete "$INSTDIR\oolite.app\*.*"

SectionEnd

