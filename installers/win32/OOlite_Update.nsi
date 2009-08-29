!packhdr "Oolite.dat" "upx.exe --best Oolite.dat"
SetCompress auto
SetCompressor LZMA
SetCompressorDictSize 32
SetDatablockOptimize on

OutFile "OoliteUpdate.exe"
BrandingText "Oolite"
Name "Oolite"
Caption "Oolite"
SubCaption 0 " "
SubCaption 1 " "
SubCaption 2 " "
SubCaption 3 " "
SubCaption 4 " "
Icon "Install.ico"
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
File "C:\program files\Oolite\Oolite_Readme.txt"

SetOutPath "$INSTDIR\oolite.app"
File "C:\program files\Oolite\oolite.app\Oolite.exe"

RMDir /r "$INSTDIR\AddOns\lasercoolant.oxp"

SetOutPath "$INSTDIR\oolite.app\Contents\Resources\Config"
File "C:\Program Files\Oolite\oolite.app\Contents\Resources\Config\keyconfig.plist"
File "C:\Program Files\Oolite\oolite.app\Contents\Resources\Config\shipdata.plist"
File "C:\Program Files\Oolite\oolite.app\Contents\Resources\Config\equipment.plist"

SetOutPath "$INSTDIR\oolite.app\Contents\Resources\AIs"
File "C:\Program Files\Oolite\oolite.app\Contents\Resources\AIs\thargletAI.plist"

Call RegSetup

MessageBox MB_OK  "Oolite Update Package was installed successfully"
SectionEnd

