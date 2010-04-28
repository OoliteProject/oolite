# Assumed to be running in trunk

export SRC="/c/Program Files/Oolite"
export DST=$GNUSTEP_LOCAL_ROOT/oolite/tmp
export VER=`awk -- '/SoftwareVersion/ { print $2 }' installers/autopackage/default.x86.apspec`
echo building: $VER

if [ -d $DST ]; then
	echo "removing old setup files"
	rm -rf $DST
fi

mkdir $DST
mkdir $DST/oolite.app
mkdir $DST/AddOns

echo "coping existing installation to setup folder"
cp "$SRC/"* $DST
cp -r "$SRC/oolite.app/"* $DST/oolite.app

echo "cleaning up unwanted files"
rm $DST/*.txt
rm $DST/*.exe
rm $DST/*.bat

rm -rf $DST/oolite.app/GNUstep/Defaults/.GNUstepDefaults
rm -rf $DST/oolite.app/oolite-saves/*

echo "making Oolite"
make

echo "copying new build to setup folder"
cp -r oolite.app/* $DST/oolite.app
rm $DST/oolite.app/oolite.exe.a

echo "making installer"
cd installers/win32
"/c/Program Files/NSIS/makensis" oolite.nsi
