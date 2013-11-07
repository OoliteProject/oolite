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
echo "\ttitle = \"Oolite core\";"
echo "\tidentifier = \"org.oolite.oolite\";"
echo "\t"
echo "\tversion = \"$OOLITE_VERSION\";"
echo "\trequired_oolite_version = \"$OOLITE_VERSION\";"
echo "\t"
echo "\tlicense = \"GPL 2+ / CC-BY-NC-SA 3.0 - see LICENSE.TXT for details\";"
echo "\tauthor = \"Giles Williams, Jens Ayton and contributors\";"
echo "\tinformation_url = \"http://www.oolite.org/\";"
echo "}"