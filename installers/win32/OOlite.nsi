!ifndef VER
!define VER 1.73-dev
!endif
!ifndef DST
!define DST ..\..\oolite.app
!endif

!include "MUI.nsh"

;!packhdr "Oolite.dat" "upx.exe --best Oolite.dat"
SetCompress auto
SetCompressor LZMA
SetCompressorDictSize 32
SetDatablockOptimize on
OutFile "OoliteInstall-${VER}.exe"
BrandingText "(C) 2003-2008 Giles Williams and contributors"
Name "Oolite"
Caption "Oolite ${VER}"
SubCaption 0 " "
SubCaption 1 " "
SubCaption 2 " "
SubCaption 3 " "
SubCaption 4 " "
Icon Oolite.ico
UninstallIcon Oolite.ico
InstallDirRegKey HKLM Software\Oolite "Install_Dir"
InstallDir $PROGRAMFILES\Oolite
DirText "Choose a directory to install Oolite"
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
WriteRegStr HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite DisplayName "Oolite ${VER}"
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
RMDir /r "$INSTDIR\oolite.app"
RMDir /r "$INSTDIR\Logs"
Delete "$INSTDIR\GNUstep\Library\Caches\Oolite-cache.plist"
RMDir "$INSTDIR\GNUstep\Library\Caches"
RMDir "$INSTDIR\GNUstep\Library"
RMDir "$INSTDIR\GNUstep"
RMDir "$INSTDIR\AddOns"
Delete "$INSTDIR\Oolite.ico"
Delete "$INSTDIR\RunOolite.bat"
Delete "$INSTDIR\Oolite_Readme.txt"
Delete "$INSTDIR\OoliteRS.pdf"
Delete "$INSTDIR\UninstOolite.exe"
RMDir "$INSTDIR"

SectionEnd

