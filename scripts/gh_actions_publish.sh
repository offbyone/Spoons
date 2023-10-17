#!/bin/bash

if [ "$GITHUB_ACTIONS" != "true" ]; then
    echo "This script should only be run as part of a GitHub Action"
    exit 1
fi

set -x
set -eu

# Find the Spoons that have been modified
SPOONS=$(cat "${HOME}/files.json" | jq -r -c '.[] | select(contains(".lua"))' | sed -e 's#^Source/\(.*\).spoon/.*#\1#' | sort | uniq)

if [ "${SPOONS}" == "" ]; then
    echo "No Spoons modified, skipping docs rebuild"
    exit 0
fi

git config --global user.email "spoonbot@offby1.net"
git config --global user.name "Spoons GitHub Bot"

while IFS= read -r SPOON ; do
    rm -f Spoons/${SPOON}.spoon.zip
    make
    git add Spoons/${SPOON}.spoon.zip
    git commit -am "Add binary package for ${SPOON}."
done <<< "${SPOONS}"
