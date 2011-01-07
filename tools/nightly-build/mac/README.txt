Running Mac nightly builds:
* Get a Mac, install Xcode, etc.
* Change config/ftp_url to something suitable, and add whatever credentials
  are necessary to config/ftp_credentials (including the appropriate curl
  command line switches, e.g. "-u user:password").
* Set appropriate path and user info in org.oolite.oolite.nightly.plist.
* Copy org.oolite.oolite.nightly.plist to /Library/LaunchAgents, and change
  its owner and group to root:wheel.
* Run this command:
  sudo launchctl load /Library/LaunchAgents/org.oolite.oolite.nightly.plist

To test the build, run ./build-nighly. The code will be checked out
automatically and dependencies will be downloaded.

A directory named "var" will appear alongside the build script when it is
run. This contains a number of log files as well as files tracking build
state. To force a build when the repository has not been updated, delete
the var directory or just var/revision.

BUGS: in true UNIX tradition, this script will blow up in your face if
there's a space in its working path.
