#!/bin/bash
set -euo pipefail

# Configuration
SPLIT_THRESHOLD_BYTES=26214400  # 25 MiB
SPLIT_CHUNK_SIZE="20m"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if file argument provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No map file provided${NC}"
    echo "Usage: $0 <map_file.bsp>"
    echo "Or drag and drop a .bsp file onto this script"
    exit 1
fi

map_file="$1"

# Validate file exists
if [ ! -f "$map_file" ]; then
    echo -e "${RED}Error: File not found: $map_file${NC}"
    exit 1
fi

# Validate file extension
if [[ ! "$map_file" =~ \.bsp$ ]]; then
    echo -e "${RED}Error: File must have .bsp extension${NC}"
    exit 1
fi

# Get absolute path
map_file=$(readlink -f "$map_file")
target_path="${map_file}.bz2"
parts_dir="${target_path}.parts"

# Check if output already exists
if [ -f "$target_path" ] || [ -d "$parts_dir" ]; then
    echo -e "${YELLOW}Warning: Output already exists for $(basename "$map_file")${NC}"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    rm -f "$target_path"
    rm -rf "$parts_dir"
fi

echo -e "${GREEN}Compressing $(basename "$map_file") to bzip2...${NC}"

# Compress the file
bzip2 -ck "$map_file" > "$target_path"
echo -e "${GREEN}✓ Created $target_path${NC}"

# Check file size and split if needed
file_size=$(stat -c%s "$target_path")
echo "Compressed size: $((file_size / 1024 / 1024)) MiB"

if [ "$file_size" -gt "$SPLIT_THRESHOLD_BYTES" ]; then
    echo -e "${YELLOW}File exceeds ${SPLIT_THRESHOLD_BYTES} bytes threshold${NC}"
    echo -e "${GREEN}Splitting into ${SPLIT_CHUNK_SIZE} chunks...${NC}"
    
    mkdir -p "$parts_dir"
    base_name="$(basename "$target_path")"
    
    # Split the file
    split -b "$SPLIT_CHUNK_SIZE" -d -a 3 "$target_path" "$parts_dir/$base_name.part."
    
    # Remove the original compressed file
    rm "$target_path"
    
    # Count and display parts
    part_count=$(find "$parts_dir" -type f | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ Split into $part_count part(s) in $parts_dir${NC}"
    
    # List the parts
    echo "Parts created:"
    ls -lh "$parts_dir"
else
    echo -e "${GREEN}✓ File size is within threshold, no splitting needed${NC}"
fi

echo -e "${GREEN}Done!${NC}"

# Pause if script was double-clicked (not run from terminal)
if [ -t 0 ]; then
    :
else
    read -p "Press Enter to exit..."
fi
