SetCompress auto
SetCompressor LZMA
SetCompressorDictSize 32
SetDatablockOptimize on

; The script in its current form must be run through MSYS in order to work as expected, since it depends on
; the environment variables SVNREV, VER and DST, which are expected to be set during build time.
; If generating the installer outside of MSYS, uncomment the lines below and set the constants as required.
; In addition, the form $%A_CONSTANT% will have to be replaced with ${A_CONSTANT} throughout this script.
; Of course, running this script outside of the MSYS environment assumes that all the program files are in
; place, in the [trunk location]/tmp folder, ready to be packaged.
;!define SVNREV '1233'
;!define VER '1.69.2'
;!define DST 'd:\ootrunk\tmp'

!include "MUI.nsh"

OutFile "OoliteInstall-r$%SVNREV%.exe"
BrandingText "(C) 2003-2008 Giles Williams and contributors"
Name "Oolite"
Caption "Oolite v$%VER% SVN Revision $%SVNREV% Setup"
SubCaption 0 " "
SubCaption 1 " "
SubCaption 2 " "
SubCaption 3 " "
SubCaption 4 " "
InstallDirRegKey HKLM Software\Oolite "Install_Dir"
InstallDir $PROGRAMFILES\Oolite
;DirText "Choose a directory to install Oolite"
CRCCheck on
InstallColors /windows
InstProgressFlags smooth
AutoCloseWindow false
SetOverwrite on

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


Function RegSetup
FunctionEnd

Function un.RegSetup
FunctionEnd

Section ""
SetOutPath $INSTDIR

CreateDirectory "$INSTDIR\AddOns"

WriteRegStr HKLM Software\Oolite "Install_Dir" "$INSTDIR"
WriteRegStr HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite DisplayName "Oolite Package"
WriteRegStr HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite UninstallString '"$INSTDIR\UninstOolite.exe"'
WriteUninstaller "$INSTDIR\UninstOolite.exe"

CreateDirectory "$SMPROGRAMS\Oolite"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite.lnk" "$INSTDIR\RunOolite.bat" "" "$INSTDIR\Oolite.ico"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite ReadMe.lnk" "$INSTDIR\Oolite_Readme.txt"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite reference sheet.lnk" "$INSTDIR\OoliteRS.pdf"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite website.lnk" "http://Oolite.aegidian.org/"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Uninstall.lnk" "$INSTDIR\UninstOolite.exe"

File "Oolite.ico"
File /r "$%DST%\*.*"

Call RegSetup

ClearErrors
FileOpen $0 $INSTDIR\RunOolite.bat w
IfErrors doneWriting

FileWrite $0 "@echo off"
FileWriteByte $0 "13"
FileWriteByte $0 "10"

FileWrite $0 "set GNUSTEP_PATH_HANDLING=windows"
FileWriteByte $0 "13"
FileWriteByte $0 "10"

FileWrite $0 "set GNUSTEP_LOCAL_ROOT=$INSTDIR\oolite.app"
FileWriteByte $0 "13"
FileWriteByte $0 "10"

FileWrite $0 "set GNUSTEP_NETWORK_ROOT=$INSTDIR\oolite.app"
FileWriteByte $0 "13"
FileWriteByte $0 "10"

FileWrite $0 "set GNUSTEP_SYSTEM_ROOT=$INSTDIR\oolite.app"
FileWriteByte $0 "13"
FileWriteByte $0 "10"

FileWrite $0 "set HOMEPATH=$INSTDIR\oolite.app"
FileWriteByte $0 "13"
FileWriteByte $0 "10"

FileWrite $0 "oolite.app\oolite.exe %1 %2 %3 %4"
FileWriteByte $0 "13"
FileWriteByte $0 "10"

FileClose $0
doneWriting:

Exec "notepad.exe $INSTDIR/Oolite_Readme.txt"

SectionEnd

Section "Uninstall"
DeleteRegKey HKLM Software\Oolite
DeleteRegKey HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite
Call un.RegSetup

RMDir /r "$INSTDIR\oolite.app\Contents"
RMDir /r "$INSTDIR\oolite.app\GNUstep"
RMDir /r "$INSTDIR\oolite.app\GNUstep"
RMDir /r "$INSTDIR\oolite.app\oolite.app"
RMDir /r "$INSTDIR\oolite.app\Resources"
RMDir /r "$INSTDIR\oolite.app\share"
Delete "$INSTDIR\*.*"
Delete "$INSTDIR\oolite.app\*.*"

RMDir /r "$SMPROGRAMS\Oolite"

SectionEnd
