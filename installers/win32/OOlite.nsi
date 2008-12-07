; Need to include the versions as we can't pass them in as parameters
; and it's too much work to try to dynamically edit this file
!include /NONFATAL "OoliteVersions.nsh"

!ifndef SVNREV
!warning "No SVN Revision supplied"
!define SVNREV 0
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
!else
!define EXTVER "-dev"
!endif

!include "MUI.nsh"

SetCompress auto
SetCompressor LZMA
SetCompressorDictSize 32
SetDatablockOptimize on
OutFile "${OUTDIR}\OoliteInstall-${VER}${EXTVER}.exe"
BrandingText "(C) 2003-2008 Giles Williams and contributors"
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
InstallDir $PROGRAMFILES\Oolite
CRCCheck on
InstallColors /windows
InstProgressFlags smooth
AutoCloseWindow false
SetOverwrite on

VIAddVersionKey "ProductName" "Oolite"
VIAddVersionKey "FileDescription" "A space combat/trading game, inspired by Elite."
VIAddVersionKey "LegalCopyright" "© 2003-2008 Giles Williams and contributors"
VIAddVersionKey "FileVersion" "${VER}"
!ifdef SNAPSHOT
VIAddVersionKey "SVN Revision" "${SVNREV}"
!endif
!ifdef BUILDTIME
VIAddVersionKey "Build Time" "${BUILDTIME}"
!endif
VIProductVersion "${VER}"

!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP ".\OoliteInstallerHeaderBitmap_ModernUI.bmp"
!define MUI_HEADERIMAGE_UNBITMAP ".\OoliteInstallerHeaderBitmap_ModernUI.bmp"
!define MUI_ICON oolite.ico
!define MUI_UNICON oolite.ico

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES  
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
 ; 1. Check for multiple running installers
 System::Call 'kernel32::CreateMutexA(i 0, i 0, t "OoliteInstallerMutex") i .r1 ?e'
 Pop $R0
 
 StrCmp $R0 0 +3
   MessageBox MB_OK|MB_ICONEXCLAMATION "Another instance of the Oolite installer is already running."
   Abort

  ; 2. Checks for already-installed versions of Oolite and offers to uninstall
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
  ExecWait '$R0 _?=$INSTDIR'
  IfErrors no_remove_uninstaller
    Delete "$INSTDIR\UninstOolite.exe"
    Goto done
  no_remove_uninstaller:
    MessageBox MB_OK|MB_ICONEXCLAMATION "The Uninstaller did not complete successfully.  Please ensure Oolite was correctly uninstalled then run the installer again."
    Abort
done:
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
CreateDirectory "$INSTDIR\AddOns"

File "Oolite.ico"
File "RunOolite.bat"
File "Oolite_Readme.txt"
File "OoliteRS.pdf"
File /r /x .svn /x *~ "${DST}"

WriteUninstaller "$INSTDIR\UninstOolite.exe"

; Registry entries
WriteRegStr HKLM Software\Oolite "Install_Dir" "$INSTDIR"
WriteRegStr HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite DisplayName "Oolite ${VER}${EXTVER}"
WriteRegStr HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite UninstallString '"$INSTDIR\UninstOolite.exe"'

; Start Menu shortcuts
SetOutPath $INSTDIR
CreateDirectory "$SMPROGRAMS\Oolite"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite.lnk" "$INSTDIR\RunOolite.bat" "" "$INSTDIR\Oolite.ico"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite ReadMe.lnk" "$INSTDIR\Oolite_Readme.txt"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Reference Sheet.lnk" "$INSTDIR\OoliteRS.pdf"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Website.lnk" "http://Oolite.aegidian.org/"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Uninstall.lnk" "$INSTDIR\UninstOolite.exe"

Call RegSetup

Exec "notepad.exe $INSTDIR\Oolite_Readme.txt"

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
RMDir /r "$INSTDIR\oolite.app\GNUstep"
RMDir /r "$INSTDIR\oolite.app\oolite.app"
RMDir /r "$INSTDIR\oolite.app\Resources"
RMDir /r "$INSTDIR\oolite.app\Logs"
Delete "$INSTDIR\*.*"
Delete "$INSTDIR\oolite.app\*.*"

SectionEnd

