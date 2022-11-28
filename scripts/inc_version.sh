#!/usr/bin/env bash

# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
ROOT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/../

# Find the current version
CURRENT_VERSION=$(grep -o "version: .*" ${ROOT_DIR}/resources/metabase-plugin.yaml | cut -c 10-)

# Increment the version
NEW_VERSION=$(echo $CURRENT_VERSION | awk -F. -v OFS=. '{$NF += 1 ; print}')

echo "Incrementing version from ${CURRENT_VERSION} to ${NEW_VERSION}"

# Update the version
FILES=(${ROOT_DIR}/resources/metabase-plugin.yaml ${ROOT_DIR}/project.clj)
for i in ${!FILES[@]}; do
  sed -i "s/${CURRENT_VERSION}/${NEW_VERSION}/g" ${FILES[$i]}
done