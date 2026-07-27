#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 [-o output_dir] [-r|-l] <path_to_fastq_pass1> [path_to_fastq_pass2 ...]"
    echo "Options:"
    echo "  -o DIR   Output combined directory name (default: combined)"
    echo "  -r       Use rsync to copy files (default)"
    echo "  -l       Use hard links (ln) instead of copying"
    exit 1
}

OUTPUT_DIR="combined"
MODE="rsync"

while getopts "o:rl" opt; do
    case "$opt" in
        o) OUTPUT_DIR="$OPTARG" ;;
        r) MODE="rsync" ;;
        l) MODE="ln" ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

if [ "$#" -eq 0 ]; then
    usage
fi

mkdir -p "$OUTPUT_DIR"

echo "Combining FASTQ files into '$OUTPUT_DIR' using mode '$MODE'..."

for dir in "$@"; do
    if [ ! -d "$dir" ]; then
        echo "Warning: Directory '$dir' does not exist. Skipping."
        continue
    fi
    
    echo "Processing: $dir"
    
    # Loop through subdirectories (e.g., barcode01, barcode02, unclassified)
    for sub_dir in "$dir"/*; do
        if [ -d "$sub_dir" ]; then
            basename_sub_dir=$(basename "$sub_dir")
            target_dir="$OUTPUT_DIR/$basename_sub_dir"
            
            mkdir -p "$target_dir"
            
            if [ "$MODE" = "rsync" ]; then
                # Use rsync to copy files, ignoring existing files to prevent overwriting
                rsync -a --ignore-existing "$sub_dir/" "$target_dir/"
            elif [ "$MODE" = "ln" ]; then
                # Use hard links (ln), ignoring existing files
                for f in "$sub_dir"/*; do
                    if [ -f "$f" ]; then
                        target_file="$target_dir/$(basename "$f")"
                        if [ ! -e "$target_file" ]; then
                            ln "$f" "$target_file"
                        fi
                    fi
                done
            fi
        fi
    done
done

echo "Done! Files have been combined in $OUTPUT_DIR/"
echo ""
echo "Summary of combined files:"
echo "--------------------------"
# Check if the output directory exists and is not empty before summarizing
if [ -d "$OUTPUT_DIR" ]; then
    find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r target_dir; do
        count=$(find "$target_dir" -type f | wc -l | awk '{print $1}')
        echo "$target_dir: $count file(s)"
    done
fi
