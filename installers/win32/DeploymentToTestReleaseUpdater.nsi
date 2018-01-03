# Installer script for updating Oolite from Deployment to Test Release flavor.
# DeploymentToTestReleaseUpdater.nsi

# Oolite
# Copyright (C) 2004-2018 Giles C Williams and contributors
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.


# When running this updater, the following folder structure must
# exist directly below the updater's folder:
# OoliteRootFolder
# |
# --AddOns
# |   |
# |   --Basic-debug.oxp
# |--oolite.app
#
# Basic-debug.oxp should contain the Debug OXP files, while
# oolite.app should contain only the Test Release executable.
# The updater will pack everything it finds below the folder
# named OoliteRootFolder, so it is important that the folder
# structure be maintained.


SetCompressor LZMA
# -------------------------------------------------------------------------
# Always ensure that these are correct for the version we are updating!
# The parameters must be defined on the command line when calling makensis.
!ifndef OOVERSION
!error "OOVERSION not set - use makensis /DOOVERSION=<Maj.Min> /DOOLITEDEPLOYMENTSIZE=<bytes> /DOOBITNESS=[32|64] DeploymentToTestReleaseUpdater.nsi"
!endif

!ifndef OOLITEDEPLOYMENTSIZE
!error "OOLITEDEPLOYMENTSIZE not set - use makensis /DOOVERSION=<Maj.Min> /DOOLITEDEPLOYMENTSIZE=<bytes> /DOOBITNESS=[32|64]"
!endif

!ifndef OOBITNESS
!error "OOBITNESS not set - use makensis /DOOVERSION=<Maj.Min> /DOOLITEDEPLOYMENTSIZE=<bytes> /DOOBITNESS=[32|64]"
!endif
# -------------------------------------------------------------------------

!define APPNAME "Deployment to Test Release Updater"
!define COMPANYNAME "Oolite"
!define DESCRIPTION "Updater for converting an Oolite Deployment configuration to a Test Release one."

!define VERSIONMAJOR 1
!define VERSIONMINOR 0
!define VERSIONBUILD 0
 
RequestExecutionLevel user ;Require normal user rights on NT6+ (When UAC is turned on)


VIAddVersionKey "ProductName" "Oolite Deployment to Test Release Updater"
VIAddVersionKey "FileDescription" "Oolite Deployment -> Test Release (${OOBITNESS}-bit)"
VIAddVersionKey "LegalCopyright" "© 2003-2018 Giles Williams, Jens Ayton and contributors"
VIAddVersionKey "FileVersion" "1.0.0.0"
VIAddVersionKey "ProductVersion" "${OOVERSION}"
VIProductVersion "1.0.0.0"

 
InstallDir "C:\${COMPANYNAME}"
InstallButtonText "Update"
BrandingText "(C) 2003-2018 Giles Williams, Jens Ayton and contributors"
DirText "This application will update an existing ${OOBITNESS}-bit Oolite v${OOVERSION}$\n\
		Deployment configuration installation to a Test Release$\n\
		type one. Please select the root folder where the existing$\n\
		Oolite v${OOVERSION} Deployment release installation resides, then$\n\
		click Update to proceed."
 
# Updater's title bar
Name "${COMPANYNAME} v${OOVERSION} - ${APPNAME}"
Icon "Oolite.ico"
AutoCloseWindow false
outFile "Oolite-${OOVERSION}-Deployment-to-Test-Release.exe"
 
!include FileFunc.nsh	# for GetSize function
!include LogicLib.nsh	# for If, IfNot etc. constructs
!include MUI.nsh


!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP ".\OoliteInstallerHeaderBitmap_ModernUI.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP ".\OoliteInstallerFinishpageBitmap.bmp"
!define MUI_ICON oolite.ico
!define MUI_PAGE_HEADER_TEXT	"Select Oolite v${OOVERSION} Deployment Root Folder"
!define MUI_PAGE_HEADER_SUBTEXT	""
!define MUI_DIRECTORYPAGE_TEXT_DESTINATION "Oolite v${OOVERSION} Deployment Installation Root Folder"
!define MUI_INSTFILESPAGE_FINISHHEADER_TEXT "Update complete"
!define MUI_INSTFILESPAGE_FINISHHEADER_SUBTEXT "Your installation of Oolite v${OOVERSION}$\n\
												has been updated to Test Release configuration."

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
 
 
function .onInit
	setShellVarContext all
functionEnd

 
section "install"
	# If oolite,exe does not exist where we are being pointed to, abort.
	IfFileExists "$INSTDIR\oolite.app\oolite.exe" ProceedWithUpdate AbortUpdate
	ProceedWithUpdate:
		!insertmacro MUI_HEADER_TEXT	"Updating..." "Please wait while your Oolite v${OOVERSION} installation$\n\
														is being updated to Test Release configuration."
		${GetSize} "$INSTDIR\oolite.app" "/M=oolite.exe /S=0B /G=0" $0 $1 $2
		# If the game executable is not the expected size, abort - we are probably trying to mess with a previous
		# version installation.
		${IfNot} $0 == ${OOLITEDEPLOYMENTSIZE}
			MessageBox MB_OK|MB_ICONEXCLAMATION "Error - Incorrect Oolite version executable detected.$\n\
												Please ensure that you are updating the ${OOBITNESS}-bit$\n\
												Deployment version ${OOVERSION} of the game.$\n$\n\
												Click OK to abort this update."
			Quit
		${EndIf}
		# Backup existing Oolite Deployment executable
		CopyFiles "$INSTDIR\oolite.app\oolite.exe" "$INSTDIR\oolite.app\oolite.exe.dpl."
		setOutPath $INSTDIR
		file /nonfatal /r "OoliteRootFolder\"
		goto EndOfExecutableExistsCheck
	AbortUpdate:
		MessageBox MB_OK|MB_ICONEXCLAMATION \
		"A valid Oolite installation was not found in the folder specified.$\n\
		Please ensure that the correct Oolite install folder is selected for $\n\
		running this updater.$\n$\n\
		Click OK to abort."
		Quit
	EndOfExecutableExistsCheck:
sectionEnd
