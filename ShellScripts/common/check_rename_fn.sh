#!/bin/bash

check_rename() {
    # Checks file exists and optionally renames it
    # First parameter is package name
    # Second parameter is file pattern
    # Third optional parameter is substring to replace in the filename
    if [ -z "$3" ]; then
        fullname=$1
    else
        fullname="${1}_${3}"
    fi
    filename=$(ls $2 2>/dev/null)
    if [ -z "$filename" ]; then
        echo "❌ No file matching $2 found." >&2
        return 1
    fi
    if [ "$3" ]; then
        newname="${filename/$1/$fullname}"
        mv $filename $newname
        filename=$newname
	fi

	echo "${filename}" "${fullname}"
}
