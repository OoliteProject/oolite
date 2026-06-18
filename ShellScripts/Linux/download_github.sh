#!/bin/bash
#
# This script downloads the latest release of a project on github.
# The name of the downloaded file is emitted on stdout.
#
# Run with these parameters:
# -o, --owner      The project owner
# -r, --repository The repository name
# -f, --filter     Additional filter to select from provided artifacts
# -O, --outputdir  Destination directory for download
#

# Exit immediately if a command exits with a non-zero status
set -e

# Default value
OUTPUTDIR=.

# parse command line
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--owner)
      OWNER="$2"
      shift # past argument
      shift # past value
      ;;
    -r|--repository)
      REPOSITORY="$2"
      shift # past argument
      shift # past value
      ;;
    -f|--filter)
      FILTER="$2"
      shift # past argument
      shift # past value
      ;;
    -O|--outputdir)
      OUTPUTDIR="$2"
      shift # past argument
      shift # past value
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

if [ "" == "${OWNER}" ]
then
	echo ERROR: OWNER not set. Use --owner
	exit 1
fi
if [ "" == "${REPOSITORY}" ]
then
	echo ERROR: REPOSITORY not set. Use --repository
	exit 1
fi

# --- CONFIGURATION ---
# Replace with the target repository (Format: owner/repo)
REPO="${OWNER}/${REPOSITORY}"

echo "Fetching latest release info for ${REPO}..." >&2
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
RELEASE_JSON=$(curl -s "${API_URL}")

# Check if the repository was found/has releases
if echo "${RELEASE_JSON}" | grep -q "Not Found"; then
    echo "Error: Repository not found or has no public releases at ${API_URL}"
    exit 1
fi

# Extract the download URL
# If 'jq' is installed, we use it (cleaner). Otherwise, we fallback to 'grep/sed'.
if command -v jq &> /dev/null; then
    if [ -n "${FILTER}" ]; then
        DOWNLOAD_URL=$(echo "${RELEASE_JSON}" | jq -r ".assets[] | select(.name | contains(\"${FILTER}\")) | .browser_download_url" | head -n 1)
    else
        DOWNLOAD_URL=$(echo "${RELEASE_JSON}" | jq -r '.assets[0].browser_download_url')
    fi
else
    # Fallback using grep/sed if jq isn't available
    if [ -n "${FILTER}" ]; then
        DOWNLOAD_URL=$(echo "${RELEASE_JSON}" | grep "browser_download_url" | grep "${FILTER}" | head -n 1 | cut -d '"' -f 4)
    else
        DOWNLOAD_URL=$(echo "${RELEASE_JSON}" | grep "browser_download_url" | head -n 1 | cut -d '"' -f 4)
    fi
fi

# Check if a URL was actually found
if [ -z "${DOWNLOAD_URL}" ] || [ "${DOWNLOAD_URL}" == "null" ]; then
    echo "Error: Could not find a matching download URL."
    exit 1
fi

# Extract filename from the URL
FILENAME=$(basename "${DOWNLOAD_URL}")

echo "Downloading latest release: ${FILENAME}..." >&2
curl -L -O --output-dir "${OUTPUTDIR}" "${DOWNLOAD_URL}"

echo "Download finished" >&2
echo "${OUTPUTDIR}/${FILENAME}" 
