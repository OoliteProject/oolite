#! /bin/sh

LIBNAME="sparkle"
EXTENSION="zip"


cd ..

# Paths relative to .., i.e. Cocoa-deps.
TEMPDIR="temp-download-$LIBNAME"
TARGETDIR="$LIBNAME"

URLFILE="../URLs/$LIBNAME.url"
VERSIONFILE="$TARGETDIR/current.url"

TEMPFILE="$TEMPDIR/$LIBNAME.$EXTENSION"


DESIREDURL=`head -n 1 $URLFILE`


# Report failure, as an error if there's no existing code but as a warning if there is.
function fail
{
	if [ $LIBRARY_PRESENT -eq 1 ]
	then
		echo "warning: $1, using existing code originating from $CURRENTURL."
		exit 0
	else
		echo "error: $1"
		exit 1
	fi
}


# Determine whether an update is desireable, and whether there's code in place.
if [ -d "$TARGETDIR" ]
then
	LIBRARY_PRESENT=1
	if [ -e $VERSIONFILE ]
	then
		CURRENTURL=`head -n 1 $VERSIONFILE`
		if [ "$DESIREDURL" = "$CURRENTURL" ]
		then
			echo "$LIBNAME is up to date."
			exit 0
		else
			echo "$LIBNAME is out of date."
		fi
	else
		echo "current.url not present, assuming $LIBNAME is out of date."
		CURRENTURL="disk"
	fi
else
	LIBRARY_PRESENT=0
	echo "$LIBNAME not present, initial download needed."
fi


# Clean up temp directory if it's hanging about.
if [ -d "$TEMPDIR" ]
then
	rm -rf "$TEMPDIR"
fi


# Create temp directory.
mkdir "$TEMPDIR"
if [ "$?" -ne "0" ]
then
	echo "error: Could not create temporary directory $TEMPDIR."
	exit 1
fi


# Download $LIBNAME source.
echo "Downloading $LIBNAME source from $DESIREDURL..."
curl -qgsSf -o "$TEMPFILE" "$DESIREDURL"
if [ "$?" -ne "0" ]
then
	fail "could not download $DESIREDURL"
fi


# Expand zip file.
echo "Download complete, expanding archive..."
unzip -q "$TEMPFILE" -d "$TEMPDIR/$LIBNAME"
if [ "$?" -ne "0" ]
then
	fail "could not expand $TEMPFILE into $TEMPDIR"
fi


# Remove tarball.
rm "$TEMPFILE"

# Delete existing code.
rm -rf "$TARGETDIR"


# Move new code into place.
mv $TEMPDIR/$LIBNAME* "$TARGETDIR"
if [ "$?" -ne "0" ]
then
	echo "error: could not move expanded $LIBNAME source into place."
	exit 1
fi

# Note version for future reference.
echo "$DESIREDURL" > "$VERSIONFILE"

# Remove temp directory.
echo "Cleaning up."
rm -rf "$TEMPDIR"

echo "Successfully updated $LIBNAME."
