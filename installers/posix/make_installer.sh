#!/bin/sh


# 
# Original by Konstantinos Sykas <ksykas@gmail.com> (26-Mar-2011)
#
#        Type: shell script
#  Parameters: $1 - architecture (i.e. x86 or x86_64)
#              $2 - version with format maj.min.rev.svnrevision (e.g. 1.75.2.4492)
#              $3 - build mode (e.g. release, release-snapshot etc.)
#              $4 - (optional) defines a nightly build. All optional parameters 
#                   must follow after the mandatory parameters
# Description: Wrapper script for "makeself.sh". Prepares a clean build and 
#              generates the tarballs (e.g. docs, icons, libraries) to be 
#              packaged by "makeself.sh".
# 


release_mode=""   # Leave this empty. In the code you should define conditions for values like "-dev", "-test", "-beta", "-rc1", etc.
make_rc=0
build_mode=$3   # Should take [release-deployment, release, release-snapshot]
build_submode=`echo $build_mode | cut -d '-' -f 2 | sed -e s/release/test/`   # Should take [deployment, test, snapshot]
echo $build_mode
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

cpu_architecture=$1
oolite_version_extended=$2
githash=`echo $oolite_version_extended | cut -d '-' -f 3`
if [ "$build_submode" = "snapshot" ]
then
  oolite_version=`echo $oolite_version_extended | awk -F"\." '{print $1"."$2"."$3"."}'`$githash
  if [ "$4" = "nightly" ]
  then
    trunk="-trunk"
    release_mode="-dev"   # This is the only case to define release_mode as "-dev"
    noxterm="--nox11"   # If nightly, do NOT spawn an x11 terminal when installer is started from desktop
  fi    
else
  oolite_version=`echo $oolite_version_extended | awk -F"\." '{print $1"."$2}'`
  ver_rev=`echo $oolite_version_extended | cut -d '.' -f 3`
  if [ $ver_rev -ne 0 ]
  then
    oolite_version=${oolite_version}"."${ver_rev}
  fi
  
  if [ "$build_submode" = "test" ]
  then
    release_mode="-test"   # Here is the right place to define if this is "-test", "-beta", "-rc1", etc.
  fi
fi
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
cat setup.header > ../../${oolite_app}/setup
if [ $trunk ] 
then
  echo "TRUNK=\"$trunk\"" >> ../../${oolite_app}/setup
  echo "UNATTENDED_INSTALLATION=1" >> ../../${oolite_app}/setup
fi
cat setup.body >> ../../${oolite_app}/setup
chmod +x ../../${oolite_app}/setup
cp -p uninstall.source ../../${oolite_app}/.


echo
./makeself.sh ${noxterm} ../../${oolite_app} oolite${trunk}-${oolite_version}${release_mode}.linux-${cpu_architecture}.run "Oolite${trunk} ${oolite_version} " ./setup $oolite_version
ms_rc=$?
if [ $ms_rc -eq 0 ] 
then 
  echo "It is located in the \"installers/posix/\" folder."
fi

exit $ms_rc
