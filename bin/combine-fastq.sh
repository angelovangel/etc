#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 [-o output_dir] [-r|-l] [-n] <path_to_fastq_pass1> [path_to_fastq_pass2 ...]"
    echo "Options:"
    echo "  -o DIR   Output combined directory name (default: combined)"
    echo "  -r       Use rsync to copy files (default)"
    echo "  -l       Use hard links (ln) instead of copying"
    echo "  -n       Dry run (show what would be done without executing)"
    exit 1
}

OUTPUT_DIR="combined"
MODE="rsync"
DRY_RUN="false"

while getopts "o:rln" opt; do
    case "$opt" in
        o) OUTPUT_DIR="$OPTARG" ;;
        r) MODE="rsync" ;;
        l) MODE="ln" ;;
        n) DRY_RUN="true" ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

if [ "$#" -eq 0 ]; then
    usage
fi

process_directory() {
    local sub_dir="$1"
    local target_dir="$2"

    if [ "$DRY_RUN" = "true" ]; then
        echo "  $sub_dir ---> $target_dir"
        return
    fi

    mkdir -p "$target_dir"

    if [ "$MODE" = "rsync" ]; then
        rsync -a --ignore-existing "$sub_dir/" "$target_dir/"
        return
    fi

    for f in "$sub_dir"/*; do
        [ -f "$f" ] || continue
        local target_file="$target_dir/$(basename "$f")"
        if [ ! -e "$target_file" ]; then
            ln "$f" "$target_file"
        fi
    done
}

if [ "$DRY_RUN" = "true" ]; then
    echo "[Dry Run] mkdir -p \"$OUTPUT_DIR\""
else
    mkdir -p "$OUTPUT_DIR"
fi

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
            process_directory "$sub_dir" "$OUTPUT_DIR/$basename_sub_dir"
        fi
    done
done


echo "Done! Files have been combined in $OUTPUT_DIR/"
echo ""
echo "Summary of combined files:"
echo "--------------------------"
# Check if the output directory exists and is not empty before summarizing
if [ "$DRY_RUN" = "true" ]; then
    echo "[Dry Run] Summary of combined files is not available in dry run mode."
else
    if [ -d "$OUTPUT_DIR" ]; then
        find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r target_dir; do
            count=$(find "$target_dir" -type f | wc -l | awk '{print $1}')
            echo "$target_dir: $count file(s)"
        done
    fi
fi
