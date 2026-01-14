#!/bin/bash

if [ "$GITHUB_ACTIONS" != "true" ]; then
    echo "This script should only be run as part of a GitHub Action"
    exit 1
fi

set -x
set -eu

# Find the Spoons that have been modified
# Uses the CHANGED_DIRS environment variable set by tj-actions/changed-files
if [ -z "${CHANGED_DIRS:-}" ]; then
    echo "CHANGED_DIRS environment variable not set. Was tj-actions/changed-files executed with dir_names: true?"
    exit 1
fi

SPOONS=$(echo "$CHANGED_DIRS" | tr ' ' '\n' | grep "^Source/.*\.spoon$" | sed -e 's#^Source/\(.*\).spoon$#\1#' | sort | uniq)

if [ -z "${SPOONS}" ]; then
    echo "No Spoons modified, skipping docs rebuild"
    exit 0
fi

git config --global user.email "spoonbot@offby1.net"
git config --global user.name "Spoons GitHub Bot"

just

while IFS= read -r SPOON; do
    git add Spoons/${SPOON}.spoon.zip
    git commit -am "Add binary package for ${SPOON}."
done <<<"${SPOONS}"
