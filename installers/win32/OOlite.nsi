!packhdr "Oolite.dat" "upx.exe --best Oolite.dat"
SetCompress auto
SetCompressor LZMA
SetCompressorDictSize 32
SetDatablockOptimize on
OutFile "OoliteInstall.exe"
BrandingText "Oolite"
Name "Oolite"
Caption "Oolite"
SubCaption 0 " "
SubCaption 1 " "
SubCaption 2 " "
SubCaption 3 " "
SubCaption 4 " "
Icon "Install.ico"
UninstallIcon uninstall.ico
InstallDirRegKey HKLM Software\Oolite "Install_Dir"
InstallDir $PROGRAMFILES\Oolite
DirText "Choose a directory to install Oolite"
CRCCheck on
InstallColors /windows
InstProgressFlags smooth
AutoCloseWindow false
SetOverwrite on

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
CreateShortCut "$SMPROGRAMS\Oolite\Oolite.lnk" "$INSTDIR\RunOolite.bat" "" "$INSTDIR\Jupiter Europa.ico"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite ReadMe.lnk" "$INSTDIR\Oolite_Readme.txt"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite reference sheet.lnk" "$INSTDIR\OoliteRS.pdf"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite website.lnk" "http://Oolite.aegidian.org/"
CreateShortCut "$SMPROGRAMS\Oolite\Oolite Uninstall.lnk" "$INSTDIR\UninstOolite.exe"

File "Jupiter Europa.ico"
File /r "C:\program files\Oolite\*.*"

Call RegSetup

MessageBox MB_OK  "Oolite Package was installed successfully"
SectionEnd

Section "Uninstall"
DeleteRegKey HKLM Software\Oolite
DeleteRegKey HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\Oolite
Call un.RegSetup

RMDir /r "$INSTDIR\oolite.app\Contents"
RMDir /r "$INSTDIR\oolite.app\GNUstep"
RMDir /r "$INSTDIR\oolite.app\Library"
RMDir /r "$INSTDIR\oolite.app\GNUstep"
RMDir /r "$INSTDIR\oolite.app\oolite.app"
RMDir /r "$INSTDIR\oolite.app\Resources"
RMDir /r "$INSTDIR\oolite.app\share"
Delete "$INSTDIR\*.*"
Delete "$INSTDIR\oolite.app\*.*"

RMDir /r "$SMPROGRAMS\Oolite"

SectionEnd

