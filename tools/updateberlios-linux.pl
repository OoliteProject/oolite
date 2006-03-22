#!/usr/bin/perl

# This tool is designed to automate the incredibly tedious task of
# updating the berlios.de download pages.
#
# Usage: tools/updateberlios.pl <src|bin|all> <release>
#
# eg.
# tools/updateberlios.pl src 1.65-dev1
# 
# It looks for the autopackage (which gets dropped by makeinstaller
# into the root), and the tarballs in TarballInstallers directory
# (this is where the source packages and tarball installer gets
# deposited). Common functions that access the BerliOS website
# are in UpdateBerlios.pm. This module can be re-used for, say,
# updating the Windows side of berlios.de.
#
# Warning: this is rather quick and dirty. It also only updates x86 for
# binary packages (since that's all we are hosting on berlios at present)
#
# Dylan Smith, 2006-03-16.
# License is the same as Oolite.

use lib "tools";
use UpdateBerlios;
use strict;

my %SRCPAGE=(
      'dev' => 'https://developer.berlios.de/project/admin/editreleases.php?package_id=2804&release_id=7423&group_id=3577',
      'stable' => 'https://developer.berlios.de/project/admin/editreleases.php?package_id=2786&release_id=8856&group_id=3577');

my %BINPAGE=(
      'dev' => 'https://developer.berlios.de/project/admin/editreleases.php?package_id=2803&release_id=7424&group_id=3577',
      'stable' => 'https://developer.berlios.de/project/admin/editreleases.php?package_id=2785&release_id=8855&group_id=3577');

my $berlios=new UpdateBerlios;
my $arg=shift;
my $version=shift;
if(!$arg || !$version)
{
   print("Usage: tools/updateberlios.pl <<src|bin|all> <version>\n");
   exit(255);
}
my $urlkey;
if($version =~ /dev/)
{
   $urlkey='dev';
}
else
{
   $urlkey='stable';
}

# .updateberliosrc should contain username and passwd on separate
# lines
my @login=`cat ~/.berliosrc`;
if(scalar(@login) < 2)
{
   print(".berliosrc must contain a username and passwd on separate lines\n");
   exit(255);
}

$berlios->connect(@login);

if($arg eq "src" || $arg eq "all")
{
   my $srcfile="oolite-$version-src.tar.gz";
   my $datafile="oolite-$version-data.tar.gz";
   
   $berlios->deleteFiles($SRCPAGE{$urlkey});
   $berlios->addFiles($SRCPAGE{$urlkey}, $srcfile, $datafile);
   $berlios->setFileArchitectures($SRCPAGE{$urlkey}, 'any', 'srcgz');

}

if($arg eq "bin" || $arg eq "all")
{
   my $tarball="Oolite-Linux-$version-x86.tar.gz";
   my $package="oolite-$version.x86.package";
   
   $berlios->deleteFiles($BINPAGE{$urlkey});
   $berlios->addFiles($BINPAGE{$urlkey}, $tarball, $package);
   $berlios->setFileArchitectures($BINPAGE{$urlkey}, 'x86', 'other');
}

