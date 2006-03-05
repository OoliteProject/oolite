#!/bin/sh
if [ ! $1 ]
then
   echo "Usage: makebinpkg.sh <releasename>"
   echo
   exit
fi

rm -rf $HOME/oolite-installer
mkdir -p $HOME/oolite-installer
tar cvf ~/oolite-installer/oolite-app.tar oolite.app --exclude .svn

cd SelfContainedInstaller
cp install oolite-update.src README.TXT PLAYING.TXT FAQ.TXT LICENSE.TXT oolite.src ~/oolite-installer
tar cvf ~/oolite-installer/oolite-deps.tar oolite-deps --exclude .svn
echo $1 >~/oolite-installer/release.txt

cd ~/
tar zcvf oolite-$1.x86.tar.gz oolite-installer

