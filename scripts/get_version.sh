#!/usr/bin/env bash

# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
ROOT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/../

# Find the current version
CURRENT_VERSION=$(grep -o "version: .*" ${ROOT_DIR}/resources/metabase-plugin.yaml | cut -c 10-)

echo ${CURRENT_VERSION}
