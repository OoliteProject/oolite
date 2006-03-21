#!/usr/bin/perl

# This tool is designed to automate the incredibly tedious task of
# updating the berlios.de download pages.
#
# Usage: tools/updateberlios.pl
# 
# It looks for the autopackage (which gets dropped by makeinstaller
# into the root), and the tarballs in TarballInstallers directory
# (this is where the source packages and tarball installer gets
# deposited). Common functions that access the BerliOS website
# are in UpdateBerlios.pm. This module can be re-used for, say,
# updating the Windows side of berlios.de.
#
# Dylan Smith, 2006-03-16.
# License is the same as Oolite.

use lib "tools";
use UpdateBerlios;
use strict;

my $berlios=new UpdateBerlios;

$berlios->connect("user", "passwd");
#$berlios->deleteFiles("https://developer.berlios.de/project/admin/editreleases.php?package_id=2803&release_id=7424&group_id=3577");

#print("Adding files");
#$berlios->addFiles("https://developer.berlios.de/project/admin/editreleases.php?package_id=2803&release_id=7424&group_id=3577", "oolite-1.64-dev1.x86.package", "Oolite-Linux-1.64-dev1-x86.tar.gz");

$berlios->setFileArchitectures("https://developer.berlios.de/project/admin/editreleases.php?package_id=2804&release_id=7423&group_id=3577", 'any', 'srcgz');

