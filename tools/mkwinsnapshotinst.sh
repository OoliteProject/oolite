# Assumed to be running in the root of a working copy (eg trunk, tags/1.64, etc)
# so this script has to be run like: tools/mkwinsnapshotinst.sh

#svn up

export SRC="/c/Program Files/Oolite"
export DST=$GNUSTEP_LOCAL_ROOT/oolite/tmp
export VER=`awk -- '/SoftwareVersion/ { print $2 }' autopackage/default.apspec`
export SVNREV=`svn info . | awk -- '/Revision:/ { print $2 }'`
echo building: $VER from svn revision $SVNREV

if [ -d $DST ]; then
	echo "removing old setup files"
	rm -rf $DST
fi

mkdir $DST
mkdir $DST/oolite.app
mkdir $DST/AddOns

#echo "coping existing installation to setup folder"
#cp "$SRC/"* $DST
#cp -r "$SRC/oolite.app/"* $DST/oolite.app

#echo "cleaning up unwanted files"
#rm $DST/*.txt
#rm $DST/*.exe
#rm $DST/*.bat

#rm $DST/oolite.app/GNUstep/Defaults/.GNUstepDefaults
#rm -rf $DST/oolite.app/oolite-saves/*

echo "making Oolite"
#make clean
#make

echo "copying new build to setup folder"
cp -r oolite.app/* $DST/oolite.app
rm $DST/oolite.app/oolite.exe.a
find $DST -type d -name '.svn' -exec rm -rf {} \;
cp deps/Windows-x86-deps/DLLs/* $DST/oolite.app

echo "making installer"
cd installers/win32

echo Oolite snapshot build of svn revision $SVNREV \(`date -I`\) >$DST/Oolite_Readme.txt
cat Oolite_Readme.txt >>$DST/Oolite_Readme.txt
cp OoliteRS.pdf $DST

"/c/Program Files/NSIS/makensis" OoliteSnapshot.nsi
