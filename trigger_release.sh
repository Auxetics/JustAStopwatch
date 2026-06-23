#!/bin/bash
set -e

# Read current version and calculate new version
CURRENT=$(cat version.txt)
NEW_VERSION=$(awk '{printf "%.1f", $1 + 0.1}' version.txt)

# Update version file
echo $NEW_VERSION > version.txt

# Commit the version bump
git commit -am "chore: Bump version to $NEW_VERSION"

# Push the commit to main
git push origin main

# Tag the commit and push the tag to trigger the workflow
git tag "v$NEW_VERSION"
git push origin "v$NEW_VERSION"

echo "Successfully triggered Cross-Platform GitHub Release for v$NEW_VERSION!"
