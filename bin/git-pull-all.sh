#!/bin/bash

# Start in current directory
BASE_DIR=$(pwd)

# Loop through all directories
for dir in */; do
    if [ -d "$dir/.git" ]; then
        echo ">>> Entering $dir"
        cd "$dir" || continue
        git pull || exit 1
        cd "$BASE_DIR" || exit
    fi
done
