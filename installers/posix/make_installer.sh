#!/bin/sh


# 
# Original by Konstantinos Sykas <ksykas@gmail.com> (26-Mar-2011)
#
#        Type: shell script
# Description: Wrapper script for "makeself.sh". Prepares a clean build and 
#              generates the tarballs (e.g. docs, icons, libraries) to be 
#              packaged by "makeself.sh".
# 


make_rc=0
build_mode=$4
if [ "$build_mode" = "release-deployment" ] 
then
  make -f Makefile distclean   # force libraries clean build
else
  make -f Makefile clean
fi
make -f Makefile deps-$build_mode
make_rc=$?
if [ $make_rc -ne 0 ]
then
   exit $make_rc
fi

cpu_architecture=x86
if [ "$1" = "x86_64" ]; then
   cpu_architecture=x86_64
fi
oolite_version=$2
oolite_version_extended=${oolite_version}"."$3
oolite_app=oolite.app
setup_root=${oolite_app}/oolite.installer.tmp


echo
echo "Starting \"makeself\" packager..."
mkdir -p ${setup_root}

echo "Generating version info..."
echo ${oolite_version_extended} > ${setup_root}/release.txt

if [ "$build_mode" != "release-deployment" ]
then
  echo "Packing AddOns..."
  tar zcf ${setup_root}/addons.tar.gz AddOns/ --exclude .svn
fi

echo "Packing desktop menu files..."
cd installers/
tar zcf ../${setup_root}/freedesktop.tar.gz FreeDesktop/ --exclude .svn

echo "Packing $cpu_architecture architecture library dependencies..."
cd ../deps/Linux-deps/${cpu_architecture}/
tar zcf ../../../${setup_root}/oolite.deps.tar.gz lib/ --exclude .svn

echo "Packing documentation..."
cd ../../../Doc/
tar cf ../${setup_root}/oolite.doc.tar AdviceForNewCommanders.pdf OoliteReadMe.pdf OoliteRS.pdf CHANGELOG.TXT
cd ../deps/Linux-deps/
tar rf ../../${setup_root}/oolite.doc.tar README.TXT
gzip ../../${setup_root}/oolite.doc.tar

echo "Packing wrapper scripts and startup README..."
tar zcf ../../${setup_root}/oolite.wrap.tar.gz oolite.src oolite-update.src 

echo "Packing GNUstep DTDs..."
cd ../Cross-platform-deps/
tar zcf ../../${setup_root}/oolite.dtd.tar.gz DTDs --exclude .svn

echo "Copying setup script..."
cd ../../installers/posix/
cp -p setup ../../${oolite_app}/.
cp -p uninstall.source ../../${oolite_app}/.


echo
./makeself.sh ../../${oolite_app} oolite-${oolite_version}.${cpu_architecture}.run "Oolite ${oolite_version} " ./setup $oolite_version
ms_rc=$?
if [ $ms_rc -eq 0 ] 
then 
  echo "It is located in the \"installers/posix/\" folder."
fi

exit $ms_rc
