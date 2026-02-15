#!/bin/bash
# update-rules.sh
# Syncs shared Cursor rules and commands from the cursor-rules repo.
# Place this script in your project's .cursor/ directory and run it to update.
# The script self-updates on each run.

set -e

# Configuration
REPO_URL="git@github.com:UserGeneratedLLC/cursor-rules.git"
FORCE_DELETE_DIRS=("luau" "roblox" "vide")
SELF_UPDATE_FILES=("update-rules.ps1" "update-rules.sh" "update-external.ps1" "update-external.sh")

# Resolve paths: script lives at <project>/.cursor/update-rules.sh
CURSOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="$CURSOR_DIR/rules"
COMMANDS_DIR="$CURSOR_DIR/commands"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Temp directory for clone
TEMP_DIR=$(mktemp -d)
trap 'echo -e "\n${GRAY}Cleaning up...${NC}"; rm -rf "$TEMP_DIR"' EXIT

echo -e "${CYAN}Updating Cursor rules...${NC}"
echo "  Repo: $REPO_URL"
echo "  Target: $CURSOR_DIR"

# Clone repo (shallow)
echo ""
echo -e "${YELLOW}Cloning repository...${NC}"
git clone --depth 1 "$REPO_URL" "$TEMP_DIR"
echo -e "${GREEN}  Done!${NC}"

CLONE_RULES_DIR="$TEMP_DIR/rules"
CLONE_COMMANDS_DIR="$TEMP_DIR/commands"

# --- Rules: Force-delete subdirectories then copy fresh ---
echo ""
echo -e "${YELLOW}Syncing rules (subdirectories)...${NC}"

mkdir -p "$RULES_DIR"

for dir in "${FORCE_DELETE_DIRS[@]}"; do
    target_subdir="$RULES_DIR/$dir"
    source_subdir="$CLONE_RULES_DIR/$dir"

    if [ -d "$target_subdir" ]; then
        echo -e "${GRAY}  Removing $dir/...${NC}"
        rm -rf "$target_subdir"
    fi

    if [ -d "$source_subdir" ]; then
        echo -e "${GRAY}  Copying $dir/...${NC}"
        cp -r "$source_subdir" "$target_subdir"
    fi
done

echo -e "${GREEN}  Done!${NC}"

# --- Rules: Copy root-level files individually (preserves user files) ---
echo ""
echo -e "${YELLOW}Syncing rules (root files)...${NC}"

for file in "$CLONE_RULES_DIR"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        cp -f "$file" "$RULES_DIR/$filename"
        echo -e "${GRAY}  $filename${NC}"
    fi
done

echo -e "${GREEN}  Done!${NC}"

# --- Commands: Copy files individually (no hard deletes, preserves user files) ---
if [ -d "$CLONE_COMMANDS_DIR" ]; then
    echo ""
    echo -e "${YELLOW}Syncing commands...${NC}"

    mkdir -p "$COMMANDS_DIR"

    for file in "$CLONE_COMMANDS_DIR"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            cp -f "$file" "$COMMANDS_DIR/$filename"
            echo -e "${GRAY}  $filename${NC}"
        fi
    done

    echo -e "${GREEN}  Done!${NC}"
fi

# --- Self-update: Copy update-rules scripts from repo root ---
echo ""
echo -e "${YELLOW}Self-updating scripts...${NC}"

for filename in "${SELF_UPDATE_FILES[@]}"; do
    source_file="$TEMP_DIR/$filename"
    if [ -f "$source_file" ]; then
        cp -f "$source_file" "$CURSOR_DIR/$filename"
        echo -e "${GRAY}  $filename${NC}"
    fi
done

echo -e "${GREEN}  Done!${NC}"

echo ""
echo -e "${GREEN}Update completed successfully!${NC}"
