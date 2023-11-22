#!/bin/bash

# Check for argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

# Change to the directory
cd "$1"

# Check if directory is a git repository
if [ ! -d .git ]; then
    echo "This directory is not a git repository!"
    exit 2
fi

# Function to process files
process_files() {
    git add $@
    git commit -m "Adding batch of files"
    git push
}

# Get list of the latest 20 top-level files/folders beginning with "trans*"
files=( $(ls -td -- trans* | head -n 20) )

# Process files 20 at a time
for ((i=0; i<${#files[@]}; i+=20)); do
    process_files "${files[@]:i:20}"
done

echo "Processing complete!"

