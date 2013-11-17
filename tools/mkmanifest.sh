#! /bin/sh

OOLITE_VERSION_FILE="src/Cocoa/oolite-version.xcconfig"


if [ $# -ge 1 ]; then
    cd $1
    if [ $? ]; then
        exit $?
    fi
fi


# Extract definition of $OOLITE_VERSION from the xcconfig
. $OOLITE_VERSION_FILE

echo "{"
echo "	title = \"Oolite core\";"
echo "	identifier = \"org.oolite.oolite\";"
echo "	"
echo "	version = \"$OOLITE_VERSION\";"
echo "	required_oolite_version = \"$OOLITE_VERSION\";"
echo "	"
echo "	license = \"GPL 2+ / CC-BY-NC-SA 3.0 - see LICENSE.TXT for details\";"
echo "	author = \"Giles Williams, Jens Ayton and contributors\";"
echo "	information_url = \"http://www.oolite.org/\";"
echo "}"
